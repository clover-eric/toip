#!/usr/bin/env bash
set -euo pipefail

interval="${SCAN_INTERVAL_SECONDS:-7200}"
run_on_start="${RUN_ON_START:-1}"
upload_after_scan="${UPLOAD_AFTER_SCAN:-1}"

stop_requested=0
trap 'stop_requested=1; ./stop_best_ip_maintain_v4.sh >/dev/null 2>&1 || true' INT TERM

run_once() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] tocf agent scan started"
  ./run_best_ip_maintain_v4.sh || echo "[$(date '+%Y-%m-%d %H:%M:%S')] scan failed rc=$?"
  ./status_best_ip_maintain_v4.sh || true
  if [[ "$upload_after_scan" == "1" ]]; then
    ./upload_best_to_worker.sh || echo "[$(date '+%Y-%m-%d %H:%M:%S')] upload failed rc=$?"
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] tocf agent round finished"
}

if [[ "$run_on_start" == "1" ]]; then
  run_once
fi

while [[ "$stop_requested" -eq 0 ]]; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] sleeping ${interval}s"
  sleep "$interval" || true
  [[ "$stop_requested" -eq 1 ]] && break
  run_once
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] tocf agent stopped"
