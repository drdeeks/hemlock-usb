## Tar Archiving Best Practices for USB Deployment

### Exclusion Patterns (in order)
```bash
tar -czf package.tar.gz \
  --exclude=.git \
  --exclude=node_modules \
  --exclude=scripts/scripts \
  --exclude=*.pyc \
  --exclude=*.log \
  --exclude=*.tgz \
  --exclude=*.tar.gz \
  --exclude=*.zip \
  -C /staging/project .
```

### Common Pitfalls
| Issue | Cause | Fix |
|-------|-------|-----|
| Missing root files | Tar from wrong directory | Use `-C /staging project` not `-C /staging/project .` |
| Prefix issues | Archive has wrong root | Use `--transform=s,^,project/,` |
| Duplicate files | Nested directories excluded | Exclude `scripts/scripts` and inner project |
| Archive too large | `.git` or `node_modules` included | Always exclude first |

### Verification Checklist
```bash
# Verify archive structure
tar -tzf package.tar.gz | head -20  # Should show project/ prefix
tar -tzf package.tar.gz | grep -c "project/"  # All entries should have prefix
tar -tzf package.tar.gz | grep ".git"  # Should be 0
```

