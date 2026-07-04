#!/bin/bash
# =============================================================================
# Hemlock System Hardware Scanner
# 
# Scans system for available acceleration capabilities and recommends
# optimal Llama.cpp build configuration.
# 
# Detects: CPU features, NVIDIA CUDA, AMD ROCm, Apple Metal, Vulkan
# 
# Usage: ./hardware-scanner.sh [--dry-run] [--verbose] [--help]
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
CACHE_DIR="${CACHE_DIR:-$RUNTIME_ROOT/.cache}"

# Output file for scan results
SCAN_RESULTS="$CACHE_DIR/hardware-scan.json"

# Options
DRY_RUN=false
VERBOSE=false
HELP=false

mkdir -p "$CACHE_DIR"

# =============================================================================
# OPTION PARSING
# =============================================================================

parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                HELP=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
${CYAN}Hemlock System Hardware Scanner${NC}

Scans system for hardware capabilities and recommends optimal Llama.cpp build.

${BLUE}Usage:${NC}
  $0 [options]

${BLUE}Options:${NC}
  --dry-run    Show what would be detected without writing files
  --verbose    Verbose output
  --help, -h   Show this help

${BLUE}Detects:${NC}
  - Operating System (Linux, macOS, Windows)
  - CPU (cores, threads, AVX/AVX2/AVX512, SSE, NEON)
  - Memory (total, available)
  - NVIDIA CUDA (GPUs, driver, CUDA version)
  - AMD ROCm (GPUs, ROCm version)
  - Apple Metal (Apple Silicon, MPS)
  - Vulkan (version, GPUs)
  - Build Dependencies (git, make, cmake, gcc, clang, python, jq)

${BLUE}Output:${NC}
  - $SCAN_RESULTS (JSON format)
  - ${SCAN_RESULTS%.json}-recommendations.json (recommendations)

${BLUE}Examples:${NC}
  $0                          # Full scan and save results
  $0 --dry-run                # Show detection without saving
  $0 --verbose                # Detailed output

EOF
}

# Parse options early
parse_options "$@"

if [[ "$HELP" == "true" ]]; then
    usage
    exit 0
fi
# Hemlock System Hardware Scanner
# 
# Scans system for available acceleration capabilities and recommends
# optimal Llama.cpp build configuration.
# 
# Detects: CPU features, NVIDIA CUDA, AMD ROCm, Apple Metal, Vulkan
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
CACHE_DIR="${CACHE_DIR:-$RUNTIME_ROOT/.cache}"

# Output file for scan results
SCAN_RESULTS="$CACHE_DIR/hardware-scan.json"

mkdir -p "$CACHE_DIR"

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "${BLUE}[SCAN]${NC} $1"
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
# Detection Functions
# =============================================================================

detect_os() {
    log "Detecting operating system..."
    
    local os_name="unknown"
    local os_version="unknown"
    local architecture="unknown"
    
    # OS detection
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_name="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="macos"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        os_name="windows"
    elif [[ "$OSTYPE" == "msys" ]]; then
        os_name="windows"
    fi
    
    # Architecture
    architecture="$(uname -m 2>/dev/null || echo "unknown")"
    
    # Version
    if [[ "$os_name" == "linux" ]]; then
        if [[ -f /etc/os-release ]]; then
            os_version=$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release 2>/dev/null || echo "unknown")
            os_pretty=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
        fi
    elif [[ "$os_name" == "macos" ]]; then
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        os_pretty="macOS $os_version"
    fi
    
    echo "{\"os\": {\"name\": \"$os_name\", \"version\": \"$os_version\", \"pretty\": \"$os_pretty\", \"architecture\": \"$architecture\"}}"
}

detect_cpu() {
    log "Detecting CPU capabilities..."
    
    local cpu_model="unknown"
    local cpu_cores=0
    local cpu_threads=0
    local has_avx=false
    local has_avx2=false
    local has_avx512=false
    local has_neon=false
    local has_sse=false
    
    # CPU model
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        cpu_model=$(cat /proc/cpuinfo 2>/dev/null | grep -m1 "model name" | cut -d':' -f2 | xargs 2>/dev/null || echo "unknown")
        cpu_cores=$(nproc 2>/dev/null || echo "1")
        cpu_threads=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
        
        # CPU flags
        local cpu_flags=$(cat /proc/cpuinfo 2>/dev/null | grep -m1 "flags" | cut -d':' -f2 | xargs 2>/dev/null || echo "")
        [[ "$cpu_flags" == *"avx"* ]] && has_avx=true
        [[ "$cpu_flags" == *"avx2"* ]] && has_avx2=true
        [[ "$cpu_flags" == *"avx512"* ]] && has_avx512=true
        [[ "$cpu_flags" == *"sse"* ]] && has_sse=true
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
        cpu_threads=$cpu_cores
        
        # Check for Apple Silicon
        if [[ "$architecture" == "arm64" ]]; then
            has_neon=true
        fi
        # Intel Mac
        if [[ "$architecture" == "x86_64" ]]; then
            has_sse=true
            # Check sysctl for AVX
            if sysctl -n machdep.cpu.features 2>/dev/null | grep -q "AVX"; then
                has_avx=true
            fi
            if sysctl -n machdep.cpu.features 2>/dev/null | grep -q "AVX2"; then
                has_avx2=true
            fi
        fi
    fi
    
    # Memory
    local total_mem_kb=0
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        total_mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        total_mem_kb=$(( $(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' || echo "0") * 4096 / 1024 ))
        # Better method on macOS
        total_mem_kb=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
        total_mem_kb=$(( total_mem_kb / 1024 ))
    fi
    local total_mem_gb=$(( total_mem_kb / 1048576 ))
    
    echo "{\"cpu\": {\"model\": \"$cpu_model\", \"cores\": $cpu_cores, \"threads\": $cpu_threads, \"memory_gb\": $total_mem_gb, \"avx\": $has_avx, \"avx2\": $has_avx2, \"avx512\": $has_avx512, \"neon\": $has_neon, \"sse\": $has_sse}}"
}

detect_nvidia() {
    log "Detecting NVIDIA CUDA..."
    
    local has_nvidia=false
    local cuda_version=""
    local driver_version=""
    local gpu_count=0
    local gpu_models=""
    
    if command -v nvidia-smi &>/dev/null; then
        has_nvidia=true
        driver_version=$(nvidia-smi 2>/dev/null | grep "Driver Version" | awk '{print $NF}' | head -1 || echo "unknown")
        cuda_version=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | awk '{print $NF}' | head -1 || echo "unknown")
        gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l || echo "0")
        gpu_models=$(nvidia-smi -L 2>/dev/null | sed 's/.*: //' | paste -sd "," - || echo "")
        
        # Check if CUDA toolkit is installed
        if [[ -d /usr/local/cuda ]]; then
            local toolkit_version=$(cat /usr/local/cuda/version.txt 2>/dev/null | head -1 || echo "unknown")
            if [[ "$cuda_version" == "" && "$toolkit_version" != "" ]]; then
                cuda_version="$toolkit_version"
            fi
        fi
    fi
    
    echo "{\"nvidia\": {\"detected\": $has_nvidia, \"driver_version\": \"$driver_version\", \"cuda_version\": \"$cuda_version\", \"gpu_count\": $gpu_count, \"gpu_models\": \"$gpu_models\"}}"
}

detect_amd() {
    log "Detecting AMD ROCm..."
    
    local has_rocm=false
    local rocm_version=""
    local gpu_count=0
    local gpu_models=""
    
    # Check for ROCm
    if [[ -d /opt/rocm ]]; then
        has_rocm=true
        rocm_version=$(cat /opt/rocm/version 2>/dev/null | head -1 || echo "unknown")
        # Try to detect GPUs
        if command -v rocminfo &>/dev/null; then
            gpu_count=$(rocminfo 2>/dev/null | grep -c "Agent" || echo "0")
            gpu_models=$(rocminfo 2>/dev/null | grep "Marketing Name" | awk -F': ' '{print $2}' | paste -sd "," - || echo "")
        fi
    fi
    
    # Check environment variable
    if [[ "${ROCR_VISIBLE_DEVICES:-}" != "" ]]; then
        has_rocm=true
    fi
    
    echo "{\"amd\": {\"rocm\": {\"detected\": $has_rocm, \"version\": \"$rocm_version\", \"gpu_count\": $gpu_count, \"gpu_models\": \"$gpu_models\"}}}"
}

detect_metal() {
    log "Detecting Apple Metal..."
    
    local has_metal=false
    local metal_device=""
    local has_mps=false
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Check for Metal on macOS
        if sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -qi "Apple"; then
            has_metal=true
            metal_device="Apple Silicon"
            # Check for MPS (Metal Performance Shaders)
            if [[ "$architecture" == "arm64" ]]; then
                has_mps=true
            fi
        elif command -v metalinfo &>/dev/null; then
            has_metal=true
            metal_device=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | awk -F': ' '{print $2}' || echo "unknown")
        fi
    fi
    
    echo "{\"metal\": {\"detected\": $has_metal, \"device\": \"$metal_device\", \"mps\": $has_mps}}"
}

detect_vulkan() {
    log "Detecting Vulkan..."
    
    local has_vulkan=false
    local vulkan_version=""
    local gpu_count=0
    
    if command -v vulkaninfo &>/dev/null; then
        has_vulkan=true
        vulkan_version=$(vulkaninfo 2>/dev/null | grep "Vulkan API" | awk '{print $NF}' | head -1 || echo "unknown")
        gpu_count=$(vulkaninfo 2>/dev/null | grep -c "VkPhysicalDevice" || echo "0")
    fi
    
    echo "{\"vulkan\": {\"detected\": $has_vulkan, \"version\": \"$vulkan_version\", \"gpu_count\": $gpu_count}}"
}

detect_dependencies() {
    log "Detecting build dependencies..."
    
    local has_git=false
    local has_make=false
    local has_cmake=false
    local has_gcc=false
    local has_clang=false
    local has_python=false
    
    command -v git &>/dev/null && has_git=true
    command -v make &>/dev/null && has_make=true
    command -v cmake &>/dev/null && has_cmake=true
    command -v gcc &>/dev/null && has_gcc=true
    command -v clang &>/dev/null && has_clang=true
    command -v python3 &>/dev/null && has_python=true
    
    echo "{\"dependencies\": {\"git\": $has_git, \"make\": $has_make, \"cmake\": $has_cmake, \"gcc\": $has_gcc, \"clang\": $has_clang, \"python\": $has_python}}"
}

# =============================================================================
# Recommendation Engine
# =============================================================================
generate_recommendations() {
    local scan_file="$1"
    
    log "Generating recommendations..."
    
    if [[ ! -f "$scan_file" ]]; then
        error "Scan file not found: $scan_file"
        return 1
    fi
    
    # Read scan results
    local os_name=$(jq -r '.os.name' "$scan_file" 2>/dev/null || echo "unknown")
    local architecture=$(jq -r '.os.architecture' "$scan_file" 2>/dev/null || echo "unknown")
    local has_cuda=$(jq -r '.nvidia.detected' "$scan_file" 2>/dev/null || echo "false")
    local has_rocm=$(jq -r '.amd.rocm.detected' "$scan_file" 2>/dev/null || echo "false")
    local has_metal=$(jq -r '.metal.detected' "$scan_file" 2>/dev/null || echo "false")
    local has_vulkan=$(jq -r '.vulkan.detected' "$scan_file" 2>/dev/null || echo "false")
    local cpu_threads=$(jq -r '.cpu.threads' "$scan_file" 2>/dev/null || echo "1")
    local memory_gb=$(jq -r '.cpu.memory_gb' "$scan_file" 2>/dev/null || echo "0")
    local has_avx=$(jq -r '.cpu.avx' "$scan_file" 2>/dev/null || echo "false")
    local has_avx2=$(jq -r '.cpu.avx2' "$scan_file" 2>/dev/null || echo "false")
    local has_avx512=$(jq -r '.cpu.avx512' "$scan_file" 2>/dev/null || echo "false")
    
    # Determine recommended backend
    local backend="cpu"
    local backend_priority=0
    local backend_reason=""
    
    # Priority: Metal > CUDA > ROCm > Vulkan > CPU
    if [[ "$has_metal" == "true" ]]; then
        backend="metal"
        backend_priority=100
        backend_reason="Apple Metal detected - optimal for macOS"
    elif [[ "$has_cuda" == "true" ]]; then
        backend="cuda"
        backend_priority=90
        backend_reason="NVIDIA CUDA detected - GPU acceleration"
    elif [[ "$has_rocm" == "true" ]]; then
        backend="hip"  # ROCm uses HIP backend in Llama.cpp
        backend_priority=80
        backend_reason="AMD ROCm detected - GPU acceleration"
    elif [[ "$has_vulkan" == "true" ]]; then
        backend="vulkan"
        backend_priority=70
        backend_reason="Vulkan detected - cross-platform GPU"
    fi
    
    # Determine build flags
    local build_flags=""
    local llm_features=""
    
    case "$backend" in
        "metal")
            build_flags="LLAMA_METAL=ON LLAMA_METAL_EMBEDDING=ON"
            llm_features="metal"
            ;;
        "cuda")
            build_flags="LLAMA_CUBLAS=ON LLAMA_CUDA justicia=ON"
            llm_features="cuda,cublas"
            ;;
        "hip")
            build_flags="LLAMA_HIPBLAS=ON LLAMA_HIP=ON"
            llm_features="hip,hipblas"
            ;;
        "vulkan")
            build_flags="LLAMA_VULKAN=ON"
            llm_features="vulkan"
            ;;
        "cpu")
            # Check for AVX2/AVX512 for optimized CPU build
            if [[ "$has_avx512" == "true" ]]; then
                build_flags="LLAMA_AVX512=ON LLAMA_AVX2=ON LLAMA_AVX=ON"
                llm_features="avx512,avx2,avx"
            elif [[ "$has_avx2" == "true" ]]; then
                build_flags="LLAMA_AVX2=ON LLAMA_AVX=ON"
                llm_features="avx2,avx"
            elif [[ "$has_avx" == "true" ]]; then
                build_flags="LLAMA_AVX=ON"
                llm_features="avx"
            else
                build_flags=""
                llm_features="sse42,sse41,ssse3,sse2"
            fi
            ;;
    esac
    
    # Memory recommendation for model loading
    local max_model_size=""
    if [[ $memory_gb -ge 32 ]]; then
        max_model_size="13B-70B"
    elif [[ $memory_gb -ge 16 ]]; then
        max_model_size="7B-13B"
    elif [[ $memory_gb -ge 8 ]]; then
        max_model_size="3B-7B"
    else
        max_model_size="1B-3B"
    fi
    
    #Quantization recommendation based on hardware
    local recommended_quant="Q4_K_M"
    if [[ "$backend" == "metal" || "$backend" == "cuda" ]]; then
        recommended_quant="Q4_K_M"
    else
        recommended_quant="Q4_K_M"
    fi
    
    cat > "${scan_file%.json}-recommendations.json" <<EOF
{
  "recommendations": {
    "backend": "$backend",
    "backend_priority": $backend_priority,
    "backend_reason": "$backend_reason",
    "build_flags": "$build_flags",
    "features": [$(echo "$llm_features" | sed 's/,/","/g')],
    "max_recommended_model": "$max_model_size",
    "recommended_quantization": "$recommended_quant",
    "threads": $cpu_threads,
    "memory_gb": $memory_gb
  },
  "system_config": {
    "llama_cpp_build": {
      "backend": "$backend",
      "cmake_flags": "$build_flags"
    },
    "model_settings": {
      "default_quant": "$recommended_quant",
      "max_model_size": "$max_model_size"
    }
  }
}
EOF
    
    success "Recommendations generated: ${scan_file%.json}-recommendations.json"
    
    # Print summary
    echo ""
    echo "${CYAN}=============================================================================${NC}"
    echo "${CYAN}                         SYSTEM SCAN RESULTS                               ${NC}"
    echo "${CYAN}=============================================================================${NC}"
    echo ""
    echo "  Operating System:  $os_name ($architecture)"
    echo "  Memory:            ${memory_gb}GB"
    echo "  CPU Threads:       $cpu_threads"
    echo "  Features:          $llm_features"
    echo ""
    echo "  NVIDIA CUDA:      $([[ "$has_cuda" == "true" ]] && echo "YES" || echo "NO")"
    echo "  AMD ROCm:         $([[ "$has_rocm" == "true" ]] && echo "YES" || echo "NO")"
    echo "  Apple Metal:      $([[ "$has_metal" == "true" ]] && echo "YES" || echo "NO")"
    echo "  Vulkan:           $([[ "$has_vulkan" == "true" ]] && echo "YES" || echo "NO")"
    echo ""
    echo "${GREEN}=============================================================================${NC}"
    echo "${GREEN}                      RECOMMENDED CONFIGURATION                          ${NC}"
    echo "${GREEN}=============================================================================${NC}"
    echo ""
    echo "  Recommended Backend: $backend"
    echo "  Build Flags:         $build_flags"
    echo "  Reason:              $backend_reason"
    echo "  Recommended Quant:   $recommended_quant"
    echo "  Max Model Size:      $max_model_size"
    echo ""
    echo "${CYAN}=============================================================================${NC}"
}

# =============================================================================
# Save Scan Results
# =============================================================================
save_scan() {
    local results="$1"
    local scan_file="$2"
    
    # Combine all results into single JSON
    echo "{" > "$scan_file"
    echo "$results" | sed 's/^  //' >> "$scan_file.tmp"
    
    # Clean up temporary files
    rm -f "$scan_file.tmp"
    
    # Format with jq if available
    if command -v jq &>/dev/null; then
        jq '.' "$scan_file" > "${scan_file}.tmp" 2>/dev/null && mv "${scan_file}.tmp" "$scan_file" || true
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Starting system hardware scan..."
    echo ""
    
    local results=""
    
    # Run all detection functions
    results+="$(detect_os),"
    results+="$(detect_cpu),"
    results+="$(detect_nvidia),"
    results+="$(detect_amd),"
    results+="$(detect_metal),"
    results+="$(detect_vulkan),"
    results+="$(detect_dependencies)"
    
    # Remove trailing comma and save
    results="${results%,}"
    echo "{" > "$SCAN_RESULTS"
    echo "$results" >> "$SCAN_RESULTS"
    echo "}" >> "$SCAN_RESULTS"
    
    # Format with jq
    if command -v jq &>/dev/null; then
        jq '.' "$SCAN_RESULTS" > "${SCAN_RESULTS}.tmp" 2>/dev/null && mv "${SCAN_RESULTS}.tmp" "$SCAN_RESULTS"
    fi
    
    success "Hardware scan completed: $SCAN_RESULTS"
    
    # Generate recommendations
    generate_recommendations "$SCAN_RESULTS"
}

# Check if jq is available
if ! command -v jq &>/dev/null; then
    warn "jq is not installed. Installing jq for JSON processing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || \
        sudo apt update && sudo apt install -y jq 2>/dev/null || true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || true
    fi
fi

main "$@"
