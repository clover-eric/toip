#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PID_FILE="scan_v4.pid"
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "status=running"
  pid="$(cat "$PID_FILE")"
  if ps -p "$pid" -o pid,etime,state,%cpu,%mem,command >/dev/null 2>&1; then
    ps -p "$pid" -o pid,etime,state,%cpu,%mem,command
  else
    ps w | awk -v pid="$pid" '$1 == pid {print}'
  fi
else
  echo "status=not_running"
fi
echo
echo "sla:"
awk -F, 'NR>1 {total++; if($3+0<=30 && $4+0>=20) good++} END {print "best_good=" good+0 "/" total+0}' best.csv 2>/dev/null || true
awk -F, 'NR>1 {total++; if($3+0<=30 && $4+0>=20) good++} END {print "candidate_good=" good+0 "/" total+0}' candidate_best.csv 2>/dev/null || true
echo
echo "files:"
for f in scan_v4.log speed_diagnostics_v4.csv best_history.csv best.csv best.txt candidate_best.csv candidate_best.txt result_scan_v4.csv cfst_replenish_v4.log scan_summary.txt; do
  [[ -f "$f" ]] && ls -lh "$f" || echo "missing $f"
done
[[ -f scan_summary.txt ]] && { echo; echo "summary:"; cat scan_summary.txt; }
[[ -f best.csv ]] && { echo; echo "best_preview:"; head -n 12 best.csv; }
[[ -f candidate_best.csv ]] && { echo; echo "candidate_preview:"; head -n 12 candidate_best.csv; }
if [[ ! -f result_scan_v4.csv ]] && [[ -f cfst_replenish_v4.log ]]; then
  echo
  echo "cfst_note:"
  echo "result_scan_v4.csv not found; agent will use built-in ip.txt seed fallback on the latest version."
fi
[[ -f scan_v4.log ]] && { echo; echo "log_tail:"; tail -n 80 scan_v4.log; }
exit 0
