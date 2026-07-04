#!/bin/bash
# PostToolUse hook (matcher: Write|Edit)
# Runs after Claude writes or edits a file.
# 1. Auto-formats the file so style is never something the model has to
#    hold in its head or burn tokens discussing (priority: token efficiency).
# 2. Scans the new content for patterns that look like hardcoded secrets
#    and surfaces a warning back to Claude via additionalContext.
#
# This does not block anything (PostToolUse can't undo a completed write),
# it corrects/flags after the fact. Prevention of secret exposure lives in
# the PreToolUse guard and the Read/Edit deny rules in settings.json.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Auto-format by file type (only runs if the formatter is installed) ---
case "$FILE_PATH" in
  *.py)
    command -v black >/dev/null 2>&1 && black --quiet "$FILE_PATH" 2>/dev/null
    ;;
  *.yaml|*.yml)
    command -v yamllint >/dev/null 2>&1 && yamllint -f parsable "$FILE_PATH" >/dev/null 2>&1
    ;;
  *.json)
    command -v jq >/dev/null 2>&1 && jq . "$FILE_PATH" > /tmp/_fmt.$$ 2>/dev/null && mv /tmp/_fmt.$$ "$FILE_PATH"
    ;;
esac

# --- Lightweight secret scan on the file just written ---
WARNINGS=""
if grep -qEi "(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*['\"][^'\"]{6,}['\"]" "$FILE_PATH" 2>/dev/null; then
  WARNINGS="Possible hardcoded credential-like string found in $FILE_PATH. Move it to an environment variable or a value pulled from a secret store, not committed to the repo."
fi

if [ -n "$WARNINGS" ]; then
  printf '%s\n' "{\"hookSpecificOutput\": {\"hookEventName\": \"PostToolUse\", \"additionalContext\": \"$WARNINGS\"}}"
fi

exit 0
