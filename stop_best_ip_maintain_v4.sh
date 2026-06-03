#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PID_FILE="scan_v4.pid"
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  sleep 2
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  pkill -P "$pid" 2>/dev/null || true
  echo "stopped pid=$pid"
else
  rm -f "$PID_FILE"
  echo "no running v4 maintainer"
fi
