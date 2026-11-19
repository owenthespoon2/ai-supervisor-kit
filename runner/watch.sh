#!/usr/bin/env bash
# Supervisor watcher for run-board.ps1. Costs ZERO model tokens while it runs (plain shell loop).
# Run it from the supervisor chat as ONE background command; it prints ONE line and exits only when
# something needs attention, so the chat is woken rarely:
#   RUN_FINISHED   the runner wrote its end-of-run record          (normal wake: verify the whole batch)
#   TASK_PROBLEM   a task ended failed / blocked / incomplete
#   TOKEN_ALERT    the current task passed the token threshold
#   STALLED        the live log has not changed for STALL_MIN minutes
#   RUNNER_GONE    the runner process disappeared without an end record
#   CHECKPOINT id  a task named in WAKE_ON finished (use sparingly: every wake re-reads the whole chat)
# Usage (from the project root, or set KIT_PROJECT):
#   bash <kit>/runner/watch.sh <runner-pid> [token-threshold] [stall-minutes] [WAKE_ON ids,comma,separated]
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cfg() { node "$KIT/runner/kit-config.mjs" "$@"; }
cd "$(cfg --root)" || exit 2
DATA="$(cfg dataDir data/overnight)"
PID="$1"
TOKEN_LIMIT="${2:-$(cfg watch.tokenLimit 6000000)}"
STALL_MIN="${3:-$(cfg watch.stallMinutes 45)}"
WAKE_ON="${4:-}"
RUNS="$DATA/runs.jsonl"
STATUS="$DATA/status.json"
seen=$( [ -f "$RUNS" ] && wc -l < "$RUNS" || echo 0 )

alive() {
  [ -z "$PID" ] && return 0
  if command -v tasklist >/dev/null 2>&1; then tasklist //FI "PID eq $PID" 2>/dev/null | grep -q " $PID "
  else kill -0 "$PID" 2>/dev/null; fi
}
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

while true; do
  n=$( [ -f "$RUNS" ] && wc -l < "$RUNS" || echo 0 )
  if [ "$n" -gt "$seen" ]; then
    new=$(tail -n $((n - seen)) "$RUNS")
    seen=$n
    if echo "$new" | grep -q '"type":"run"'; then
      echo "RUN_FINISHED $(echo "$new" | grep '"type":"run"' | cut -c1-400)"; exit 0
    fi
    bad=$(echo "$new" | grep '"type":"task"' | grep -v '"status":"done"' | head -n 1)
    if [ -n "$bad" ]; then echo "TASK_PROBLEM $(echo "$bad" | cut -c1-400)"; exit 0; fi
    for id in $(echo "$WAKE_ON" | tr ',' ' '); do
      hit=$(echo "$new" | grep "\"taskId\":\"$id\"" | grep '"status":"done"' | head -n 1)
      if [ -n "$hit" ]; then echo "CHECKPOINT $id done: $(echo "$hit" | cut -c1-300)"; exit 0; fi
    done
  fi

  if [ -f "$STATUS" ] && grep -q '"state":  *"running"' "$STATUS"; then
    tok=$(grep -o '"tokens":  *[0-9.]*' "$STATUS" | grep -o '[0-9]*' | head -n 1)
    task=$(grep -o '"taskId":  *"[^"]*"' "$STATUS" | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -n "$tok" ] && [ "$tok" -gt "$TOKEN_LIMIT" ]; then
      echo "TOKEN_ALERT task=$task tokens=$tok limit=$TOKEN_LIMIT"; exit 0
    fi
  fi

  log=$(ls -t "$DATA"/logs/*.log 2>/dev/null | head -n 1)
  if [ -n "$log" ]; then
    age=$(( ( $(date +%s) - $(mtime "$log") ) / 60 ))
    # A runner waiting for a usage reset is quiet on purpose; it writes a heartbeat to status.json instead.
    if [ "$age" -ge "$STALL_MIN" ] && ! grep -q 'waiting-for-usage-reset' "$STATUS" 2>/dev/null; then
      echo "STALLED log=$log idle_minutes=$age"; exit 0
    fi
  fi

  if ! alive; then echo "RUNNER_GONE pid=$PID (no end-of-run record)"; exit 0; fi
  sleep 30
done
