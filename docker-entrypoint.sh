#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  exec "$@"
fi

workdir="${TOCF_WORKDIR:-/data}"
mkdir -p "$workdir"

for file in run_best_ip_maintain_v4.sh status_best_ip_maintain_v4.sh stop_best_ip_maintain_v4.sh upload_best_to_worker.sh router_agent_24h.sh ip.txt ipv6.txt; do
  cp "/opt/tocf/$file" "$workdir/$file"
done

ln -sf /usr/local/bin/cfst "$workdir/cfst"
chmod +x "$workdir"/*.sh "$workdir/cfst"

cd "$workdir"
exec ./router_agent_24h.sh
