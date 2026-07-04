# projects/ — the agent's working directories

One subdirectory per project the agent works on. Each project dir is a git repo
(daily auto-commit watcher + rollback via tools/rollback.sh). Empty in the template;
created as the agent takes on work.
