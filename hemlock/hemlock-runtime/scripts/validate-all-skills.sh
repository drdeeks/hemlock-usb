#!/bin/bash
# =============================================================================
# Validate All Skills Script
# Generates a report on all skills meeting OpenClaw and Hermes requirements
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# On the host tree the seed lives at shared/skills (in-container it is seeded
# to $RUNTIME_ROOT/skills). Fall back so the report works in both places.
if [[ ! -d "$SKILLS_DIR" && -d "$SCRIPT_DIR/../shared/skills" ]]; then
    SKILLS_DIR="$(cd "$SCRIPT_DIR/../shared/skills" && pwd)"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Output report file
REPORT_FILE="$SKILLS_DIR/SKILLS_VALIDATION_REPORT.md"

# Header
echo "# Skills Validation Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Generated:** $(date)" >> "$REPORT_FILE"
echo "**Purpose:** Validate all skills in \`$SKILLS_DIR/\` meet OpenClaw and Hermes requirements" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Validation Criteria
echo "## Validation Criteria" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### Hermes Requirements" >> "$REPORT_FILE"
echo "- Must have \`SKILL.md\` file" >> "$REPORT_FILE"
echo "- Must have YAML frontmatter (\`---\`)" >> "$REPORT_FILE"
echo "- Must have \`name:\` field" >> "$REPORT_FILE"
echo "- Must have \`description:\` field" >> "$REPORT_FILE"
echo "- Must have \`version:\` field (recommended)" >> "$REPORT_FILE"
echo "- Must have \`hermes:\` metadata (recommended)" >> "$REPORT_FILE"
echo "- Must have \`tags:\` (recommended)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "### OpenClaw Requirements" >> "$REPORT_FILE"
echo "- Must have proper YAML structure" >> "$REPORT_FILE"
echo "- Must have \`metadata:\` section" >> "$REPORT_FILE"
echo "- Must have \`openclaw:\` metadata (recommended)" >> "$REPORT_FILE"
echo "- Must have \`requires:\` for dependencies (recommended)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## Skills Status" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Table header
echo "| Skill Name | Status | FM | N | D | V | M | H | OC | T | A |" >> "$REPORT_FILE"
echo "|------------|--------|----|---|---|---|---|---|----|---|---|" >> "$REPORT_FILE"

# Initialize counters
total=0
valid=0
warning=0
invalid=0

# Process each skill directory
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    
    # Skip non-skill directories
    [[ "$skill_name" =~ ^\.|README|MANIFEST|APPROVED|VALIDATION|SKILL\.md$ ]] && continue
    
    if [[ -d "$skill_dir" ]] && [[ -f "$skill_dir/SKILL.md" ]]; then
        total=$((total+1))
        
        # Check for YAML frontmatter
        has_frontmatter=$(head -1 "$skill_dir/SKILL.md" 2>/dev/null | grep -c '^---$' || echo 0)
        
        # Check for required fields
        has_name=$(grep -c '^name:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_desc=$(grep -c '^description:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_version=$(grep -c '^version:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_metadata=$(grep -c '^metadata:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_hermes=$(grep -c 'hermes:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_openclaw=$(grep -c 'openclaw:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_tags=$(grep -c 'tags:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        has_author=$(grep -c '^author:' "$skill_dir/SKILL.md" 2>/dev/null || echo 0)
        
        # Determine status
        if [[ "$has_frontmatter" -eq 0 ]] || [[ "$has_name" -eq 0 ]] || [[ "$has_desc" -eq 0 ]]; then
            status="INVALID"
            invalid=$((invalid+1))
        elif [[ "$has_version" -eq 0 ]] || [[ "$has_metadata" -eq 0 ]]; then
            status="WARNING"
            warning=$((warning+1))
        else
            status="VALID"
            valid=$((valid+1))
        fi
        
        # Format boolean values
        fmt() { [[ "$1" -gt 0 ]] && echo "Yes" || echo "No"; }
        
        printf "| %-30s | %-8s | %-3s | %-3s | %-3s | %-3s | %-3s | %-3s | %-3s | %-3s | %-3s |\n" \
            "$skill_name" "$status" \
            "$(fmt $has_frontmatter)" \
            "$(fmt $has_name)" \
            "$(fmt $has_desc)" \
            "$(fmt $has_version)" \
            "$(fmt $has_metadata)" \
            "$(fmt $has_hermes)" \
            "$(fmt $has_openclaw)" \
            "$(fmt $has_tags)" \
            "$(fmt $has_author)" >> "$REPORT_FILE"
    fi
done

echo "" >> "$REPORT_FILE"

# Summary
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- **Total Skills:** $total" >> "$REPORT_FILE"
echo "- **Valid:** $valid" >> "$REPORT_FILE"
echo "- **Warning:** $warning" >> "$REPORT_FILE"
echo "- **Invalid:** $invalid" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

#legend
echo "## Legend" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Column | Description | Required |" >> "$REPORT_FILE"
echo "|--------|-------------|----------|" >> "$REPORT_FILE"
echo "| Skill Name | Name of the skill | - |" >> "$REPORT_FILE"
echo "| Status | Overall validation status | - |" >> "$REPORT_FILE"
echo "| FM | Frontmatter present | Yes |" >> "$REPORT_FILE"
echo "| N | Name field present | Yes |" >> "$REPORT_FILE"
echo "| D | Description field present | Yes |" >> "$REPORT_FILE"
echo "| V | Version field present | Recommended |" >> "$REPORT_FILE"
echo "| M | Metadata section present | Recommended |" >> "$REPORT_FILE"
echo "| H | Hermes metadata present | Recommended |" >> "$REPORT_FILE"
echo "| OC | OpenClaw metadata present | Recommended |" >> "$REPORT_FILE"
echo "| T | Tags present | Recommended |" >> "$REPORT_FILE"
echo "| A | Author field present | Recommended |" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Status Definitions
echo "## Status Definitions" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- **VALID**: Meets all required criteria (FM, N, D). Optional criteria may be missing." >> "$REPORT_FILE"
echo "- **WARNING**: Meets required criteria but missing important optional fields (V, M)." >> "$REPORT_FILE"
echo "- **INVALID**: Missing required criteria. Must be fixed." >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## Validation Script Usage" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "\`\`\`bash" >> "$REPORT_FILE"
echo "# Validate all skills" >> "$REPORT_FILE"
echo "./scripts/skills-install.sh --validate-all" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "# Validate a specific skill" >> "$REPORT_FILE"
echo "./scripts/skills-install.sh --validate <agent_id> <skill_name>" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "# Install skills for an agent" >> "$REPORT_FILE"
echo "./scripts/skills-install.sh <agent_id> <skill_name>" >> "$REPORT_FILE"
echo "\`\`\`" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

log "Skills validation report generated: $REPORT_FILE"
log "Total: $total | Valid: $valid | Warning: $warning | Invalid: $invalid"

# Also output to console
success "Validation Complete!"
echo "Total: $total | Valid: $valid | Warning: $warning | Invalid: $invalid"

if [[ "$invalid" -gt 0 ]]; then
    warn "Some skills have validation issues. See $REPORT_FILE for details."
fi
