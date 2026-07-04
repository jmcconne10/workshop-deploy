#!/bin/bash
# Stop hook
# Runs when Claude is about to end its turn.
# Exit 2 = tell Claude to keep working (e.g. "tests are failing, fix them").
# Exit 0 = let Claude stop.
#
# This is the deterministic backstop for "definition of done" — it does not
# depend on the model remembering to run tests before declaring victory.
#
# IMPORTANT: stop_hook_active prevents an infinite loop. If this hook already
# forced Claude to continue once for this stop event, let it stop the second
# time even if tests still fail, rather than looping forever.

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

# --- Adjust this block per project. workshop-deploy uses pytest + helm lint. ---
FAILURES=""

if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || find . -maxdepth 2 -name "test_*.py" 2>/dev/null | grep -q .; then
  if command -v pytest >/dev/null 2>&1; then
    if ! pytest -q 2>&1 | tail -30 > /tmp/_pytest_out.$$; then
      FAILURES="${FAILURES}pytest failed:\n$(cat /tmp/_pytest_out.$$)\n\n"
    fi
    rm -f /tmp/_pytest_out.$$
  fi
fi

if find . -maxdepth 3 -name "Chart.yaml" 2>/dev/null | grep -q .; then
  if command -v helm >/dev/null 2>&1; then
    for chart in $(find . -maxdepth 3 -name "Chart.yaml" -exec dirname {} \;); do
      if ! helm lint "$chart" >/tmp/_helm_out.$$ 2>&1; then
        FAILURES="${FAILURES}helm lint failed for $chart:\n$(cat /tmp/_helm_out.$$)\n\n"
      fi
      rm -f /tmp/_helm_out.$$
    done
  fi
fi

if [ -n "$FAILURES" ]; then
  REASON=$(printf '%s' "$FAILURES" | head -c 1500)
  printf '%s\n' "{\"decision\": \"block\", \"reason\": \"Tests/lint are failing. Fix them before finishing:\n\n${REASON}\"}"
  exit 0
fi

exit 0
