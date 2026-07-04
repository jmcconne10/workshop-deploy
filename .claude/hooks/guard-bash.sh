#!/bin/bash
# PreToolUse hook (matcher: Bash)
# Runs before every Bash tool call. Reads the tool call as JSON on stdin.
# Exit 2 = block the command and tell Claude why.
# Exit 0 = allow it to proceed to normal permission evaluation.
#
# This is a backstop, not the primary control. Primary allow/deny/ask rules
# live in .claude/settings.json. This hook catches things a glob pattern
# can't easily express — like "does this path try to leave the repo."

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Block path traversal outside the project directory ---
# Looks for ../.. patterns or absolute paths outside the project root
# targeted by common file-touching commands.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])(\.\./){2,}'; then
  echo "Blocked: command references a path more than one directory above the project root ('../../'). If you need access outside $PROJECT_DIR, ask the user directly rather than reaching for it via a relative path." >&2
  exit 2
fi

# --- Block obviously destructive patterns not already covered by settings.json deny rules ---
DANGEROUS_PATTERNS=(
  'rm -rf /'
  'DROP TABLE'
  'DROP DATABASE'
  ':(){ :|:& };:'      # fork bomb
  'chmod -R 777'
  '> /dev/sda'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qF "$pattern"; then
    echo "Blocked: command matches a known-destructive pattern ('$pattern'). This is not something this project allows an agent to run automatically." >&2
    exit 2
  fi
done

# --- Block reading kubeconfig or cloud credential files via cat/less/etc, not just the Read tool ---
if echo "$COMMAND" | grep -qE '(cat|less|more|head|tail)[[:space:]].*(kubeconfig|\.aws/credentials|\.kube/config|id_rsa|\.pem|\.env)'; then
  echo "Blocked: this command reads a credentials/secrets file via shell, which bypasses the Read-tool deny rules in settings.json. If you need to verify a config value, ask the user to confirm it instead." >&2
  exit 2
fi

exit 0
