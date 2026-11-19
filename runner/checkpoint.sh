#!/usr/bin/env bash
# One-call supervisor checkpoint. Produces everything a checkpoint needs in ONE tool call (zero model
# tokens to produce, a few hundred to read): last task record with effective cost, git state, queue,
# gated restart, and (with --check) the project's health/accuracy summary.
# Usage (from the project root, or set KIT_PROJECT): bash <kit>/runner/checkpoint.sh [--check] [--no-restart]
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cfg() { node "$KIT/runner/kit-config.mjs" "$@"; }
cd "$(cfg --root)" || exit 1
DATA="$(cfg dataDir data/overnight)"
echo "time $(date +%H:%M)"
if [ -f "$DATA/runs.jsonl" ]; then
  grep '"type":"task"' "$DATA/runs.jsonl" | tail -n 1 | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{if(!s.trim())return console.log('no task records yet');const r=JSON.parse(s);const t=r.tokens||{};const eff=r.effective??Math.round(0.1*(t.cacheRead||0)+(t.input||0)+1.25*(t.cacheWrite||0)+5*(t.output||0));console.log('task',r.taskId,r.status,(r.model||'')+'/'+(r.effort||''),r.minutes+'min','calls',r.toolCalls,'eff',eff,'perCall',t.cacheRead&&r.toolCalls?Math.round(t.cacheRead/r.toolCalls):'','protected',(r.protectedTouched||[]).length)})"
  grep '"type":"run"' "$DATA/runs.jsonl" | tail -n 1 | cut -c1-300
else
  echo "no runs.jsonl yet"
fi
git log --oneline -1
mapfile -t DIRTY < <(cfg hooks.dirtyPaths)
echo "dirty (${DIRTY[*]}): $(git status --short -- "${DIRTY[@]}" 2>/dev/null | wc -l)"
Q="$(cfg hooks.queueStatusCommand)"
[ -n "$Q" ] && echo "queue $(bash -c "$Q" 2>&1 | head -n 1)"
case " $* " in *" --no-restart "*) ;; *) bash "$KIT/runner/restart-if-clean.sh" ;; esac
case " $* " in *" --check "*)
  C="$(cfg hooks.checkCommand)"
  if [ -n "$C" ]; then
    sleep "$(cfg hooks.checkDelaySeconds 60)"
    # Retry while the app rebuilds; print only the first 800 chars (counts, not ids).
    for i in $(seq 1 30); do out=$(bash -c "$C" 2>/dev/null) && [ -n "$out" ] && break; sleep 10; done
    echo "check ${out:0:800}"
  else echo "check: no hooks.checkCommand configured"; fi ;;
esac
