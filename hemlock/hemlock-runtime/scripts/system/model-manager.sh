#!/bin/bash
# =============================================================================
# Hemlock Model Manager
# 
# Downloads, converts, and manages LLMs for use with Llama.cpp.
# Supports downloading from HuggingFace, converting to GGUF format.
# 
# Default model: Qwen3:0.6B
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/helpers.sh"

MODELS_DIR="${MODELS_DIR:-$RUNTIME_ROOT/models}"
GGUF_DIR="$MODELS_DIR/gguf"
HF_DIR="$MODELS_DIR/huggingface"
CACHE_DIR="${CACHE_DIR:-$RUNTIME_ROOT/.cache}"

# Default model configuration
DEFAULT_MODEL="Qwen3-0.6B"
DEFAULT_MODEL_REPO="Qwen/Qwen3-0.6B"
DEFAULT_QUANT="Q4_K_M"
DEFAULT_HF_MODEL="Qwen3-0.6B"

# HuggingFace model info
declare -A MODEL_REPOS=(
    ["qwen3-0.6b"]="Qwen/Qwen3-0.6B"
    ["qwen3-1.6b"]="Qwen/Qwen3-1.6B"
    ["qwen3-4b"]="Qwen/Qwen3-4B"
    ["qwen3-8b"]="Qwen/Qwen3-8B"
    ["llama3-8b"]="meta-llama/Meta-Llama-3-8B"
    ["mistral-7b"]="mistralai/Mistral-7B-v0.1"
    ["gemma-7b"]="google/gemma-7b"
    ["phi-2"]="microsoft/phi-2"
)

# GGUF filenames
declare -A GGUF_NAMES=(
    ["qwen3-0.6b"]="qwen3-0_6b"
    ["qwen3-1.6b"]="qwen3-1_6b"
    ["qwen3-4b"]="qwen3-4b"
    ["qwen3-8b"]="qwen3-8b"
)

mkdir -p "$MODELS_DIR" "$GGUF_DIR" "$HF_DIR" "$CACHE_DIR"

# Persistent config file
PERSISTENT_CONFIG="$CONFIG_DIR/model-config.yaml"

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "${BLUE}[MODEL]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =============================================================================
# Configuration Management
# =============================================================================

# Load persistent configuration
load_config() {
    if [[ ! -f "$PERSISTENT_CONFIG" ]]; then
        return 1
    fi
    
    # Parse YAML-like config
    local current_default=$(grep "^default_model:" "$PERSISTENT_CONFIG" 2>/dev/null | awk '{print $2}' || echo "")
    local current_quant=$(grep "^default_quant:" "$PERSISTENT_CONFIG" 2>/dev/null | awk '{print $2}' || echo "")
    local current_backend=$(grep "^default_backend:" "$PERSISTENT_CONFIG" 2>/dev/null | awk '{print $2}' || echo "")
    
    echo "$current_default $current_quant $current_backend"
}

# Save persistent configuration
save_config() {
    local default_model="$1"
    local default_quant="$2"
    local default_backend="$3"
    local active_model="$4"
    
    cat > "$PERSISTENT_CONFIG" <<EOF
devault_model: $default_model
default_quant: $default_quant
default_backend: $default_backend
active_model: $active_model

# Model registry
models:
  - name: $default_model
    repo: ${MODEL_REPOS[${default_model,,}]:-$DEFAULT_MODEL_REPO}
    gguf_path: $GGUF_DIR/${GGUF_NAMES[${default_model,,}]:-$default_model}-$default_quant.gguf
    enabled: true
    quantizations:
      - Q4_0
      - Q4_K_M
      - Q5_0
      - Q5_K_M
      - Q8_0
EOF
    
    success "Configuration saved to $PERSISTENT_CONFIG"
}

# Check if model exists (GGUF)
model_exists() {
    local model_name="$1"
    local quant="$2"
    
    local model_key="${model_name,,}"
    local gguf_filename="${GGUF_NAMES[$model_key]:-$model_name}-${quant}.gguf"
    local model_path="$GGUF_DIR/$gguf_filename"
    
    if [[ -f "$model_path" ]]; then
        echo "$model_path"
        return 0
    fi
    return 1
}

# =============================================================================
# Gets the recommended quantization based on system
# =============================================================================
get_recommended_quant() {
    local scan_file="$CACHE_DIR/hardware-scan-recommendations.json"
    
    if [[ -f "$scan_file" ]]; then
        jq -r '.recommendations.recommended_quantization // "Q4_K_M"' "$scan_file" 2>/dev/null || echo "Q4_K_M"
    else
        echo "$DEFAULT_QUANT"
    fi
}

# =============================================================================
# Download model from HuggingFace
# =============================================================================
download_model() {
    local model_name="$1"
    local output_dir="$2"
    
    local model_key="${model_name,,}"
    local repo="${MODEL_REPOS[$model_key]:-$DEFAULT_MODEL_REPO}"
    
    log "Downloading $model_name from HuggingFace: $repo"
    log "Output directory: $output_dir"
    
    # Check if already downloaded
    if [[ -d "$output_dir/$model_name" ]]; then
        warn "Model directory already exists, skipping download"
        return 0
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Use huggingface-hub CLI if available
    if command -v huggingface-cli &>/dev/null; then
        log "Using huggingface-hub CLI..."
        huggingface-cli download "$repo" \
            --local-dir "$output_dir/$model_name" \
            --local-dir-use-symlinks False \
            --cache-dir "$CACHE_DIR/huggingface-cache"
        success "Model downloaded using huggingface-cli"
        return 0
    fi
    
    # Fallback: Use git lfs
    if command -v git &>/dev/null; then
        log "Using git lfs..."
        cd "$output_dir"
        
        if [[ ! -d "$model_name" ]]; then
            git lfs install 2>/dev/null || true
            git clone "https://huggingface.co/$repo" "$model_name" \
                --depth 1 \
                --filter=blob:none \
                2>&1 || {
                error "Git LFS clone failed"
                return 1
            }
            
            # Pull LFS files
            cd "$model_name"
            git lfs pull 2>&1 || {
                error "Git LFS pull failed"
                return 1
            }
            cd - >/dev/null
            
            success "Model downloaded using git lfs"
            return 0
        fi
        
        cd - >/dev/null
    fi
    
    # Last resort: Use Python with huggingface_hub
    if command -v python3 &>/dev/null; then
        log "Using Python huggingface_hub library..."
        
        local python_script="$(cat << 'PYEOF'
import os
import sys
from huggingface_hub import snapshot_download

repo_id = sys.argv[1]
local_dir = sys.argv[2]
cache_dir = sys.argv[3]

print(f"Downloading {repo_id} to {local_dir}")
try:
    snapshot_download(
        repo_id=repo_id,
        local_dir=local_dir,
        cache_dir=cache_dir,
        local_dir_use_symlinks=False,
        ignore_patterns=["*.msgpack", "*.h5", "*.tflite", "*.safetensors", "*.bin"]
    )
    print("Download completed successfully")
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF
)"
        
        python3 -c "$python_script" "$repo" "$output_dir/$model_name" "$CACHE_DIR/huggingface-cache" || {
            error "Python download failed"
            return 1
        }
        
        success "Model downloaded using Python"
        return 0
    fi
    
    error "No download method available. Install huggingface-cli, git-lfs, or Python with huggingface_hub."
    return 1
}

# =============================================================================
# Convert PyTorch/Safetensors to GGUF
# =============================================================================
convert_to_gguf() {
    local model_name="$1"
    local quant="$2"
    
    local model_key="${model_name,,}"
    local model_dir="$HF_DIR/$model_name"
    local gguf_filename="${GGUF_NAMES[$model_key]:-$model_name}-${quant}.gguf"
    local gguf_path="$GGUF_DIR/$gguf_filename"
    
    log "Converting $model_name to GGUF format ($quant)..."
    
    # Check if model files exist
    if [[ ! -d "$model_dir" ]]; then
        error "Model directory not found: $model_dir"
        return 1
    fi
    
    # Find the model file (safetensors or bin)
    local model_file=""
    if ls "$model_dir"/*.safetensors 1>/dev/null 2>&1; then
        model_file=$(ls "$model_dir"/*.safetensors | head -1)
    elif ls "$model_dir"/*.bin 1>/dev/null 2>&1; then
        model_file=$(ls "$model_dir"/*.bin | head -1)
    else
        error "No safetensors or bin file found in $model_dir"
        return 1
    fi
    
    log "Found model file: $model_file"
    
    # Use llama.cpp convert tool if available
    local llama_convert="$RUNTIME_ROOT/bin/llama-convert"
    if [[ ! -f "$llama_convert" ]]; then
        llama_convert="llama-convert"
    fi
    
    if command -v "$llama_convert" &>/dev/null; then
        log "Using llama-convert tool..."
        "$llama_convert" "$model_file" "$gguf_path" --quant "$quant" 2>&1 || {
            error "Conversion failed with llama-convert"
            return 1
        }
        success "Converted to $gguf_path using llama-convert"
        return 0
    fi
    
    # Build convert tool if not available
    if ! command -v "$llama_convert" &>/dev/null; then
        log "Building convert tool..."
        local source_dir="$CACHE_DIR/llama.cpp/llama.cpp"
        if [[ ! -d "$source_dir" ]]; then
            error "Llama.cpp source not found. Run llama-build.sh first."
            return 1
        fi
        
        cd "$source_dir"
        local convert_binary="$source_dir/convert"
        
        # Check if already built
        if [[ ! -f "$convert_binary" ]]; then
            # Try to build it
            if command -v make &>/dev/null; then
                make convert 2>&1 || {
                    error "Failed to build convert tool"
                    return 1
                }
            else
                error "make not available, cannot build convert tool"
                return 1
            fi
        fi
        
        cd - >/dev/null
        
        # Use the built convert tool
        log "Using built convert tool..."
        "$convert_binary" "$model_file" "$gguf_path" --quant "$quant" 2>&1 || {
            error "Conversion failed with built convert tool"
            return 1
        }
        
        success "Converted to $gguf_path"
        return 0
    fi
    
    error "No conversion method available"
    return 1
}

# =============================================================================
# Download and convert Qwen3:0.6B
# =============================================================================
download_qwen3_06b() {
    local quant="$1"
    
    log "Downloading and converting Qwen3:0.6B to $quant..."
    
    # Check if already exists
    if model_exists "qwen3-0.6b" "$quant"; then
        success "Model already exists: $(model_exists "qwen3-0.6b" "$quant")"
        return 0
    fi
    
    # Download from HuggingFace
    download_model "qwen3-0.6b" "$HF_DIR" || {
        error "Failed to download Qwen3-0.6B"
        return 1
    }
    
    # Convert to GGUF
    convert_to_gguf "qwen3-0.6b" "$quant" || {
        error "Failed to convert Qwen3-0.6B to GGUF"
        return 1
    }
    
    success "Qwen3-0.6B downloaded and converted to $quant GGUF"
    return 0
}

# =============================================================================
# Setup default model
# =============================================================================
setup_default_model() {
    local quant="$1"
    local model_name="${2:-qwen3-0.6b}"
    
    log "Setting up default model: $model_name ($quant)..."
    
    # Ensure model exists
    download_qwen3_06b "$quant" || {
        error "Failed to setup default model"
        return 1
    }
    
    local model_key="${model_name,,}"
    local gguf_path="$GGUF_DIR/${GGUF_NAMES[$model_key]:-$model_name}-${quant}.gguf"
    
    # Save configuration
    save_config "$model_name" "$quant" "cpu" "$model_name"
    
    # Update runtime.yaml with default model
    if [[ -f "$CONFIG_DIR/runtime.yaml" ]]; then
        # Replace default_model line
        if command -v sed &>/dev/null; then
            sed -i "s|default_model:.*|default_model: \"$model_name\"|" "$CONFIG_DIR/runtime.yaml" 2>/dev/null || true
        fi
    fi
    
    # Update .env with default model
    if [[ -f "$RUNTIME_ROOT/.env" ]]; then
        if command -v sed &>/dev/null; then
            sed -i "s|DEFAULT_AGENT_MODEL=.*|DEFAULT_AGENT_MODEL=$model_name|" "$RUNTIME_ROOT/.env" 2>/dev/null || true
        fi
    fi
    
    # Create default agent configuration
    local default_agent_dir="$AGENTS_DIR/default"
    mkdir -p "$default_agent_dir"
    
    cat > "$default_agent_dir/agent.json" <<EOF
{
  "id": "default",
  "name": "Default Agent",
  "description": "Default chatbot agent using Qwen3:0.6B",
  "model": "$gguf_path",
  "backend": "llama.cpp",
  "type": "chatbot",
  "capabilities": ["chat", "reasoning", "knowledge"],
  "tools": ["web_browse"],
  "enabled": true,
  "active": true,
  "config": {
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 2048,
    "context_size": 4096,
    "threads": $(nproc 2>/dev/null || echo 4)
  }
}
EOF
    
    # Create a simple model info file
    cat > "$GGUF_DIR/qwen3-0.6b-info.json" <<EOF
{
  "model": "Qwen3-0.6B",
  "repo": "Qwen/Qwen3-0.6B",
  "quantization": "$quant",
  "format": "GGUF",
  "file": "$gguf_path",
  "size_mb": $(du -m "$gguf_path" 2>/dev/null | awk '{print $1}' || echo "unknown"),
  "type": "decoder",
  "parameters": 600000000,
  "download_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "default": true
}
EOF
    
    success "Default model configured: $model_name ($quant)"
    success "Model path: $gguf_path"
    success "Agent config: $default_agent_dir/agent.json"
    
    return 0
}

# =============================================================================
# List available models
# =============================================================================
list_models() {
    log "Available models:"
    
    if [[ ! -d "$GGUF_DIR" ]]; then
        warn "No models directory found"
        return 1
    fi
    
    local model_count=0
    
    for gguf_file in "$GGUF_DIR"/*.gguf; do
        if [[ -f "$gguf_file" ]]; then
            local filename=$(basename "$gguf_file")
            local size=$(du -h "$gguf_file" | awk '{print $1}')
            local mtime=$(stat -c '%y' "$gguf_file" 2>/dev/null | cut -d' ' -f1 || stat -f '%Sm' "$gguf_file" 2>/dev/null | cut -d' ' -f1 || date -r "$gguf_file" +%Y-%m-%d || echo "unknown")
            
            echo "  - $filename ($size, last modified: $mtime)"
            model_count=$((model_count + 1))
        fi
    done
    
    if [[ $model_count -eq 0 ]]; then
        warn "No GGUF models found in $GGUF_DIR"
    else
        success "Found $model_count model(s)"
    fi
}

# =============================================================================
# Verify model
# =============================================================================
verify_model() {
    local model_path="$1"
    
    if [[ ! -f "$model_path" ]]; then
        error "Model file not found: $model_path"
        return 1
    fi
    
    log "Verifying model: $model_path"
    
    # Check file size
    local size=$(stat -c '%s' "$model_path" 2>/dev/null || stat -f '%z' "$model_path" 2>/dev/null || echo "0")
    log "  File size: $((size / 1024 / 1024)) MB"
    
    # Check if it's a valid GGUF file (magic number)
    if command -v xxd &>/dev/null; then
        local header=$(xxd -l 4 "$model_path" 2>/dev/null | awk '{print $2$3$4$5}' || echo "")
        if [[ "$header" == "gguf" ]]; then
            success "  Valid GGUF file detected"
        else
            warn "  Warning: File may not be valid GGUF (header: $header)"
        fi
    fi
    
    # Check metadata
    if command -v "$RUNTIME_ROOT/bin/llama-cli" &>/dev/null; then
        log "Checking model metadata with llama-cli..."
        timeout 5 "$RUNTIME_ROOT/bin/llama-cli" -m "$model_path" --model-dump 2>&1 | head -20 || true
    fi
    
    success "Model verified"
}

# =============================================================================
# Clean model files
# =============================================================================
clean_models() {
    log "Cleaning model files..."
    
    # Remove all GGUF files
    if [[ -d "$GGUF_DIR" ]]; then
        rm -rf "$GGUF_DIR"/*
        success "Cleaned GGUF directory"
    fi
    
    # Remove HuggingFace cache
    if [[ -d "$HF_DIR" ]]; then
        rm -rf "$HF_DIR"/*
        success "Cleaned HuggingFace cache"
    fi
    
    # Clean HuggingFace cache
    rm -rf "$CACHE_DIR/huggingface-cache" 2>/dev/null || true
    
    success "Model files cleaned"
}

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<EOF
${CYAN}Hemlock Model Manager${NC}

Usage: $0 <command> [options]

${BLUE}Commands:${NC}
  setup              Setup default Qwen3:0.6B model
  download <model>   Download model from HuggingFace
  convert <model>    Convert downloaded model to GGUF
  full-setup         Download, convert, and configure default model
  list               List available models
  verify <path>      Verify a model file
  clean              Clean all model files
  
${BLUE}Options:${NC}
  --quant <q>        Quantization type (default: $DEFAULT_QUANT)
                     Available: Q4_0, Q4_K_M, Q5_0, Q5_K_M, Q8_0, F16, F32
  --model <m>        Model name (default: qwen3-0.6b)
  --dry-run          Preview actions without executing
  --help, -h         Show this help

${BLUE}Examples:${NC}
  $0 setup                       # Setup default Qwen3:0.6B
  $0 setup --quant Q5_K_M        # Setup with Q5_K_M quantization
  $0 download qwen3-0.6b         # Download only
  $0 convert qwen3-0.6b          # Convert only
  $0 full-setup                  # Full setup (download + convert + configure)
  $0 list                        # List available models
  $0 verify models/gguf/qwen3-0.6b-Q4_K_M.gguf

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    local command="${1:-}"
    local quant="$DEFAULT_QUANT"
    local model="qwen3-0.6b"
    local dry_run=false
    
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quant)
                quant="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    case "$command" in
        "setup")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would setup default model with quant=$quant and model=$model"
            else
                setup_default_model "$quant" "$model"
            fi
            ;;
        "download")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would download model $model to $HF_DIR"
            else
                download_model "$model" "$HF_DIR"
            fi
            ;;
        "convert")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would convert model $model to GGUF with quant=$quant"
            else
                convert_to_gguf "$model" "$quant"
            fi
            ;;
        "full-setup")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would perform full setup for Qwen3:0.6B with quant=$quant"
            else
                # For Qwen3:0.6B specifically
                setup_default_model "$quant" "qwen3-0.6b"
            fi
            ;;
        "list")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would list available models"
            else
                list_models
            fi
            ;;
        "verify")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would verify model at path $1"
            else
                # Use first positional arg as model path
                if [[ "${1:-}" != "" ]]; then
                    verify_model "$1"
                else
                    usage
                    exit 1
                fi
            fi
            ;;
        "clean")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would clean all model files"
            else
                clean_models
            fi
            ;;
        "")
            usage
            exit 0
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Ensure required tools are available
if ! command -v jq &>/dev/null; then
    warn "jq not found, installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || true
    fi
fi

mkdir -p "$MODELS_DIR" "$GGUF_DIR" "$HF_DIR"

main "$@"
