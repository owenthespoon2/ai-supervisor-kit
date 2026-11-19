#!/usr/bin/env bash
# Zero-token wait for a long job the SUPERVISOR started (benchmark, rescan, queue drain). Run as ONE
# background command; it prints ONE line and exits. Task sessions never use this: they leave long jobs
# to the supervisor (see protocol/TASK-SESSION.md, "never background-and-wait").
#
#   bash wait-until.sh queue [stall-min]          wait until hooks.queueStatusCommand stops matching hooks.queueBusyPattern
#   bash wait-until.sh pid <pid> [max-min]        wait until a process exits
#   bash wait-until.sh file <path> <regex> [max-min]   wait until a file contains a line matching regex
# Output: DONE ... | STALLED ... | TIMEOUT ...
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cfg() { node "$KIT/runner/kit-config.mjs" "$@"; }
cd "$(cfg --root)" || exit 1
mode="${1:-queue}"; shift
case "$mode" in
  queue)
    Q="$(cfg hooks.queueStatusCommand)"; BUSY="$(cfg hooks.queueBusyPattern)"
    [ -z "$Q" ] && { echo "ERROR no hooks.queueStatusCommand"; exit 2; }
    STALL="${1:-40}"; last=""; same=0
    while true; do
      q=$(bash -c "$Q" 2>/dev/null | head -n 1)
      if ! echo "$q" | grep -Eq "$BUSY"; then echo "DONE queue empty: $q"; exit 0; fi
      if [ "$q" = "$last" ]; then same=$((same+5)); else same=0; last="$q"; fi
      if [ "$same" -ge "$STALL" ]; then echo "STALLED queue unchanged ${STALL}min: $q"; exit 0; fi
      sleep 300
    done ;;
  pid)
    P="$1"; MAX="${2:-600}"; start=$(date +%s)
    while true; do
      if command -v tasklist >/dev/null 2>&1; then tasklist //FI "PID eq $P" 2>/dev/null | grep -q " $P " || { echo "DONE pid $P exited"; exit 0; }
      else kill -0 "$P" 2>/dev/null || { echo "DONE pid $P exited"; exit 0; }; fi
      [ $(( ($(date +%s) - start) / 60 )) -ge "$MAX" ] && { echo "TIMEOUT pid $P still running after ${MAX}min"; exit 0; }
      sleep 60
    done ;;
  file)
    F="$1"; RE="$2"; MAX="${3:-600}"; start=$(date +%s)
    while true; do
      hit=$(grep -E "$RE" "$F" 2>/dev/null | tail -n 1)
      [ -n "$hit" ] && { echo "DONE ${hit:0:300}"; exit 0; }
      [ $(( ($(date +%s) - start) / 60 )) -ge "$MAX" ] && { echo "TIMEOUT no match in $F after ${MAX}min"; exit 0; }
      sleep 60
    done ;;
  *) echo "usage: wait-until.sh queue [stall-min] | pid <pid> [max-min] | file <path> <regex> [max-min]"; exit 2 ;;
esac
