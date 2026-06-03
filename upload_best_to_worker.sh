#!/usr/bin/env bash
set -euo pipefail

worker_url="${WORKER_URL:-}"
upload_token="${UPLOAD_TOKEN:-}"
source_name="${SOURCE:-$(hostname 2>/dev/null || echo unknown)}"
if [[ -f detected_route.env ]]; then
  route_source="$(sed -n 's/^SOURCE=//p' detected_route.env | head -n1)"
  [[ -n "$route_source" ]] && source_name="$route_source"
fi
source_safe="$(printf '%s' "$source_name" | sed 's/[^A-Za-z0-9_.-]/_/g')"

if [[ -z "$worker_url" ]]; then
  echo "upload skipped: WORKER_URL is empty"
  exit 0
fi
if [[ -z "$upload_token" ]]; then
  echo "upload skipped: UPLOAD_TOKEN is empty"
  exit 0
fi
csv_file="best.csv"
txt_file="best.txt"
upload_kind="best"
if [[ ! -s "$csv_file" || ! -s "$txt_file" ]]; then
  if [[ -s candidate_best.csv && -s candidate_best.txt ]]; then
    csv_file="candidate_best.csv"
    txt_file="candidate_best.txt"
    upload_kind="candidate"
  else
    echo "upload skipped: best/candidate files missing"
    exit 1
  fi
fi

worker_url="${worker_url%/}"
common_headers=(-H "X-Upload-Token: ${upload_token}")

echo "uploading ${csv_file} kind=${upload_kind} source=${source_safe}"
curl -fsS --retry 3 --retry-delay 2 \
  -X POST "${worker_url}/api/upload/best.csv?source=${source_safe}" \
  "${common_headers[@]}" \
  -H "Content-Type: text/csv; charset=utf-8" \
  --data-binary @"$csv_file"
echo

echo "uploading ${txt_file} kind=${upload_kind} source=${source_safe}"
curl -fsS --retry 3 --retry-delay 2 \
  -X POST "${worker_url}/api/upload/best.txt?source=${source_safe}" \
  "${common_headers[@]}" \
  -H "Content-Type: text/plain; charset=utf-8" \
  --data-binary @"$txt_file"
echo

echo "upload finished source=${source_safe}"
