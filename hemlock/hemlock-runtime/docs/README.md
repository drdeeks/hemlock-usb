# Hemlock Documentation

## Quick Navigation

### Core Documentation
- **[Main README](../README.md)** - Complete framework overview, quick start, and all commands

### Directory Index
- **[agents/README](../agents/README.md)** - Agent directory structure and lifecycle
- **[lib/README](../lib/README.md)** - Library utilities and shared code
- **[tools/README](../tools/README.md)** - toolkit documentation

### Extended Guides
- **[Backup Protocol](../plugins/backup-protocol/README.md)** - Backup and restore procedures
- **[Tool Enforcement](../plugins/tool-enforcement/)** - Tool usage enforcement rules
- **[Crew Management](../plugins/crews/)** - Crew templates and workflows

## Documentation Standards

All documentation follows these principles:
- **Concise**: Get to the point quickly
- **Actionable**: Include copy-pasteable commands
- **Structured**: Use consistent heading hierarchy
- **Up-to-date**: Reflects current implementation

## Need More Help?

Run the built-in help system:
```bash
./runtime.sh --help
```

## Documentation Requirements

All agents must log and document:
- Every link
- HTML files
- .doc files
- .md files
- Any other file provided by the USER for informational assistance

## Knowledge Base

- Root `knowledge_base/` is read-only (RO)
- Each agent maintains its own `knowledge/` directory
- The root indexer scans all agent `knowledge/` folders
- Deduplication system maintains a unified index

## Toolkit Usage

The agent toolkit is automatically injected into each agent's `tools/` directory. Refer to `TOOLS-GUIDE.md` for usage rules.

## Documentation Requirements

All agents must log and document:
- Every link
- HTML files
- .doc files
- .md files
- Any other file provided by the USER for informational assistance

## Knowledge Base

- Root `knowledge_base/` is read-only (RO)
- Each agent maintains its own `knowledge/` directory
- The root indexer scans all agent `knowledge/` folders
- Deduplication system maintains a unified index

## Toolkit Usage

The agent toolkit is automatically injected into each agent's `tools/` directory. Refer to `TOOLS-GUIDE.md` for usage rules.
