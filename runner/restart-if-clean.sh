#!/usr/bin/env bash
# Run the project's restart hook only when no task is mid-edit (hooks.dirtyPaths clean). Prints one line.
# Never restart while a task session is editing: a rebuild from half-written files breaks the live app
# and can confuse the running session.
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cfg() { node "$KIT/runner/kit-config.mjs" "$@"; }
cd "$(cfg --root)" || exit 1
CMD="$(cfg hooks.restartCommand)"
[ -z "$CMD" ] && { echo "RESTART: no hooks.restartCommand configured"; exit 0; }
mapfile -t DIRTY < <(cfg hooks.dirtyPaths)
if [ -n "$(git status --short -- "${DIRTY[@]}" 2>/dev/null)" ]; then
  echo "SKIP: uncommitted task edits in ${DIRTY[*]}"; exit 0
fi
out=$(bash -c "$CMD" 2>&1 | tail -n 3 | tr '\n' ' ')
echo "RESTART requested: ${out:-ok}"
