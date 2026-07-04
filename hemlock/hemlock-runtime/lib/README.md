# Library Directory

This directory contains shared libraries and utilities used by the OpenClaw + Hermes framework.

## Structure

```
lib/
├── python/          # Python utilities
├── shell/          # Shell utilities
├── templates/      # Configuration templates
└── README.md       # This file
```

## Python Utilities

Common Python utilities for:
- Configuration management
- Logging
- Error handling
- API clients
- Data processing

## Shell Utilities

Common shell utilities for:
- Docker management
- File operations
- System checks
- Logging

## Configuration Templates

Template files for:
- Agent configurations
- Skill configurations
- Tool configurations
- System configurations

## Using the Library

### Python

Import utilities in your Python code:

```python
from lib.python.config import load_config
from lib.python.logger import setup_logger
```

### Shell

Source utilities in your shell scripts:

```bash
source "$LIB_DIR/shell/utils.sh"
```

## Best Practices

1. **Modularity**: Keep utilities focused and reusable
2. **Documentation**: Document functions and usage
3. **Testing**: Include tests for critical utilities
4. **Error Handling**: Handle errors gracefully
5. **Performance**: Optimize for common use cases