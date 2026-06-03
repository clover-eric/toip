#!/usr/bin/env bash
set -euo pipefail

worker_url="${WORKER_URL:-}"
upload_token="${UPLOAD_TOKEN:-}"
source_name="${SOURCE:-$(hostname 2>/dev/null || echo unknown)}"
source_safe="$(printf '%s' "$source_name" | sed 's/[^A-Za-z0-9_.-]/_/g')"

if [[ -z "$worker_url" ]]; then
  echo "upload skipped: WORKER_URL is empty"
  exit 0
fi
if [[ -z "$upload_token" ]]; then
  echo "upload skipped: UPLOAD_TOKEN is empty"
  exit 0
fi
if [[ ! -s best.csv || ! -s best.txt ]]; then
  echo "upload skipped: best.csv/best.txt missing"
  exit 1
fi

worker_url="${worker_url%/}"
common_headers=(-H "X-Upload-Token: ${upload_token}")

echo "uploading best.csv source=${source_safe}"
curl -fsS --retry 3 --retry-delay 2 \
  -X POST "${worker_url}/api/upload/best.csv?source=${source_safe}" \
  "${common_headers[@]}" \
  -H "Content-Type: text/csv; charset=utf-8" \
  --data-binary @best.csv
echo

echo "uploading best.txt source=${source_safe}"
curl -fsS --retry 3 --retry-delay 2 \
  -X POST "${worker_url}/api/upload/best.txt?source=${source_safe}" \
  "${common_headers[@]}" \
  -H "Content-Type: text/plain; charset=utf-8" \
  --data-binary @best.txt
echo

echo "upload finished source=${source_safe}"
