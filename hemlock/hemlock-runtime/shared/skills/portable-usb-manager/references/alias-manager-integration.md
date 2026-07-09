# Alias Manager Integration Patterns

## Overview
This document covers the integration patterns for the universal alias manager wrapper (`am`) that works across all environments.

## Architecture

### Global Candidates Array
```bash
_am_candidates=(
    "${USB_ALIAS_MANAGER:-}"
    "${BASH_SOURCE[0]%/*}/alias_manager.sh"
    "/usr/local/bin/alias_manager.sh"
    "/opt/usb-compute/alias_manager.sh"
)
```
**Key**: Global array scoped to file level so both `_find_alias_manager()` and `am()` can access it for error reporting.

### Finder Function
```bash
_find_alias_manager() {
    local candidates=(
        "${USB_ALIAS_MANAGER:-}"
        "${BASH_SOURCE[0]%/*}/alias_manager.sh"
        "/usr/local/bin/alias_manager.sh"
        "/opt/usb-compute/alias_manager.sh"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}
```
**Pattern**: Local candidates array for search, `${VAR:-}` expansion to avoid unbound variable errors.

### Universal Wrapper
```bash
am() {
    local am_path
    am_path=$(_find_alias_manager)
    if [[ -n "$am_path" ]]; then
        bash "$am_path" "$@"
    else
        echo "alias_manager.sh not found. Searched locations:"
        for c in "${_am_candidates[@]}"; do [[ -n "$c" ]] && echo "  $c"; done
        return 1
    fi
}
```
**Key Patterns**:
1. Delegates to finder function
2. Passes all arguments (`"$@"`) transparently
3. Uses global `_am_candidates` for error reporting with empty filtering

## Alias Definitions
```bash
alias aml='am --list'
alias ama='am --add'
alias amr='am --remove'
alias ams='am --search'
alias ami='am --import'
alias ame='am --export'
alias ammenu='am'
alias alias-location='echo "Alias file: $USB_ALIAS_FILE"'
alias alias-env='echo "USB_PERSISTENT=$IS_USB_PERSISTENT"; echo "Alias file: $USB_ALIAS_FILE"; echo "Manager: $(_find_alias_manager)"'
alias alias-init='mkdir -p "${HOME}/.usb-persistence-marker" && echo "$(pwd)" > "${HOME}/.usb-persistence-path" && echo "Marked $(pwd) as USB persistence root"'
```

## Help Integration
```bash
_syshelp_alias_manager() {
    cat <<'EOF'

  Alias Manager (Universal Portable):
    am                    # Interactive menu
    aml / am --list       # List all aliases
    ama / am --add        # Add alias (ama name "cmd" "desc")
    amr / am --remove     # Remove alias
    ams / am --search     # Search aliases (ams query)
    ami / am --import     # Import from .bashrc
    ame / am --export     # Export aliases (table/csv/json)
    ammenu                # Interactive menu
    alias-location        # Show where aliases are stored
    alias-env             # Show environment detection status
EOF
}
```

## Common Pitfalls & Solutions

### Pitfall 1: Unbound Variable Error
```bash
# WRONG - errors if USB_ALIAS_MANAGER unset
candidates=("${USB_ALIAS_MANAGER}")

# CORRECT - uses parameter expansion
candidates=("${USB_ALIAS_MANAGER:-}")
```

### Pitfall 2: Candidates Array Scope
```bash
# WRONG - local array not accessible in wrapper
_find_alias_manager() {
    local candidates=(...)  # Local!
}
am() {
    # Can't access candidates here
}

# CORRECT - global array for error reporting
_am_candidates=(...)
_find_alias_manager() { local candidates=(...); ... }
am() { ... for c in "${_am_candidates[@]}"; ... }
```

### Pitfall 3: Alias Expansion in Non-Interactive Shells
```bash
# Must enable BEFORE defining aliases
shopt -s expand_aliases

alias am='...'  # Now works in scripts
```

### Pitfall 4: Parsing Order
```bash
# WRONG - alias defined before shopt
alias ama='...'
shopt -s expand_aliases

# CORRECT - shopt first
shopt -s expand_aliases
alias ama='...'
```

### Pitfall 5: Command Substitution in Alias Definition
```bash
# WRONG - $(...) evaluated at alias DEFINITION time
alias alias-env='echo "Manager: $(_find_alias_manager)"'

# CORRECT - escapes the $() for RUNTIME evaluation
alias alias-env='echo "Manager: $(_find_alias_manager)"'
# Note: The $(...) IS expanded at definition but _find_alias_manager is a function call
# Actually this works correctly because the command substitution is in the alias VALUE
# which gets evaluated each time alias runs. But be careful with escaping.
```

## Alias File Format
```
# ~/.bash_aliases_usb format:
alias NAME='COMMAND' # DESCRIPTION
alias gs='git status' # Git status shortcut
alias ll='ls -la' # Long list
```

## Integration with syshelp
```bash
syshelp() {
    cat <<'HELPEOF'
    ...
    Alias Manager (Universal Portable):
      am                    # Interactive menu
      aml / am --list       # List all aliases
      ama / am --add        # Add alias (ama name "cmd" "desc")
      ...
    EOF
}
```

## Testing the Integration

```bash
# Source and test
source bash_enhanced.sh

# Test detection status
alias-env

# Test manager
am --help

# Test CRUD
ama test "echo hi" "test alias"
aml
ams test
amr test

# Import existing
ami ~/.bashrc

# Export
ame json
```