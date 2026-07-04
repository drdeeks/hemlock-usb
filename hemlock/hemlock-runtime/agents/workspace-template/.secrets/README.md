# .secrets/ — encrypted secrets ONLY (the one 700-permission dir)

Secrets live here as ENCRYPTED JSON managed exclusively by tools/secret.sh —
never piped in, never stored or read in plain text, never committed. Agents may
know WHICH secrets exist, never their values. The owner can always view and
manage their own secrets through secret.sh. This is the only directory in the
workspace allowed restrictive permissions.
