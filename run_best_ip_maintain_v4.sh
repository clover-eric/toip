#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

PID_FILE="scan_v4.pid"
LOG_FILE="scan_v4.log"
DIAG_FILE="speed_diagnostics_v4.csv"
HISTORY_FILE="best_history.csv"
RAW_FILE="result_scan.csv"
BEST_CSV="best.csv"
BEST_TXT="best.txt"
CANDIDATE_CSV="candidate_best.csv"
CANDIDATE_TXT="candidate_best.txt"
SUMMARY_FILE="scan_summary.txt"
CFST_LOG="cfst_replenish_v4.log"
CFST_OUT="result_scan_v4.csv"
REMOTE_BEST_TXT="remote_best.txt"

OPERATOR="${OPERATOR:-CMCC}"
SLA_SPEED_MB="${SLA_SPEED_MB:-20}"
SLA_LATENCY_MS="${SLA_LATENCY_MS:-30}"
REQUIRED_COUNT="${REQUIRED_COUNT:-10}"
TARGET_SPEED_MB="${TARGET_SPEED_MB:-80}"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
MAX_CANDIDATES="${MAX_CANDIDATES:-24}"
CURL_TIME_LIMIT="${CURL_TIME_LIMIT:-12}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-6}"
PER_REQUEST_SLEEP="${PER_REQUEST_SLEEP:-3}"
ROUND_SLEEP="${ROUND_SLEEP:-30}"
DOWNLOAD_BYTES="${DOWNLOAD_BYTES:-5000000}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-24}"
HEALTH_CHECK="${HEALTH_CHECK:-1}"
CFST_REPLENISH="${CFST_REPLENISH:-1}"
CFST_THREADS="${CFST_THREADS:-120}"
CFST_TESTS="${CFST_TESTS:-4}"
CFST_DOWNLOADS="${CFST_DOWNLOADS:-20}"
WORKER_URL="${WORKER_URL:-https://cfip.i3.pub}"

case "$OPERATOR" in
  CMCC|CTCC|CUCC) ;;
  *) OPERATOR="CMCC" ;;
esac

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "v4 already running: pid=$(cat "$PID_FILE")"
  exit 0
fi

cleanup() {
  [[ -n "${CAFFEINATE_PID:-}" ]] && kill "$CAFFEINATE_PID" 2>/dev/null || true
  rm -f "$PID_FILE"
}
trap cleanup EXIT HUP INT TERM
echo $$ > "$PID_FILE"
: > "$LOG_FILE"

if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dims &
  CAFFEINATE_PID="$!"
fi

sync_remote_best() {
  [[ -n "${WORKER_URL:-}" ]] || return 0
  curl -fsSL --connect-timeout 5 --max-time 12 "${WORKER_URL%/}/best.txt" -o "${REMOTE_BEST_TXT}.tmp" 2>/dev/null || return 0
  if [[ -s "${REMOTE_BEST_TXT}.tmp" ]]; then
    mv "${REMOTE_BEST_TXT}.tmp" "$REMOTE_BEST_TXT"
  else
    rm -f "${REMOTE_BEST_TXT}.tmp"
  fi
}

publish_from_history() {
  python3 - "$OPERATOR" "$SLA_LATENCY_MS" "$SLA_SPEED_MB" "$REQUIRED_COUNT" "$TARGET_SPEED_MB" <<'PY'
import csv, math, pathlib, sys, time, os

op = sys.argv[1]
sla_latency = float(sys.argv[2])
sla_speed = float(sys.argv[3])
required = int(sys.argv[4])
target_speed = float(sys.argv[5])
base = pathlib.Path(".")
history = base / "best_history.csv"
best_csv = base / "best.csv"
best_txt = base / "best.txt"
candidate_csv = base / "candidate_best.csv"
candidate_txt = base / "candidate_best.txt"
summary = base / "scan_summary.txt"

fields = ["operator_profile","ip","latency_ms","download_speed_MB_s","packet_loss","colo","hit_level","speed_source","url","http_code","bytes_downloaded","score","last_seen"]
rows = []
if history.exists():
    with history.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if not r:
                continue
            try:
                lat = float(r.get("latency_ms", "999") or 999)
                speed = float(r.get("download_speed_MB_s", "0") or 0)
            except ValueError:
                continue
            if r.get("operator_profile") == op and lat <= sla_latency and speed >= sla_speed:
                r["_lat"] = lat
                r["_speed"] = speed
                rows.append(r)

rows.sort(key=lambda r: (r["_speed"], -r["_lat"]), reverse=True)
chosen = rows[:required]

def write_table(path, selected):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["operator_profile","IP","平均延迟(ms)","下载速度(MB/s)","丢包率","地区码","命中级别","speed_source","测速URL","HTTP状态","下载字节","评分","last_seen"])
        for r in selected:
            lat = float(r.get("latency_ms", "999") or 999)
            speed = float(r.get("download_speed_MB_s", "0") or 0)
            level = "sla_pass"
            if lat <= 30 and speed >= target_speed:
                level = "ideal_target"
            w.writerow([
                r.get("operator_profile", op),
                r.get("ip", ""),
                f"{lat:.2f}",
                f"{speed:.2f}",
                r.get("packet_loss", "0.00"),
                r.get("colo", "N/A"),
                level,
                r.get("speed_source", ""),
                r.get("url", ""),
                r.get("http_code", ""),
                r.get("bytes_downloaded", ""),
                r.get("score", ""),
                r.get("last_seen", ""),
            ])
    os.replace(tmp, path)

def write_txt(path, selected):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        for r in selected:
            f.write(r.get("ip", "") + "\n")
    os.replace(tmp, path)

write_table(candidate_csv, chosen)
write_txt(candidate_txt, chosen)

published = False
if len(chosen) >= required:
    write_table(best_csv, chosen)
    write_txt(best_txt, chosen)
    published = True

best_latency = min((r["_lat"] for r in chosen), default=math.nan)
best_speed = max((r["_speed"] for r in chosen), default=math.nan)
status = "pass" if published else "fail"
summary.write_text("\n".join([
    f"scan_finished_at={time.strftime('%Y-%m-%d %H:%M:%S')}",
    "scan_engine=curl_resolve_v4_sla_maintainer",
    f"operator_profile={op}",
    f"sla_latency_ms={sla_latency:g}",
    f"sla_speed_MB_s={sla_speed:g}",
    f"required_count={required}",
    f"sla_good_count={len(chosen)}",
    f"best_count={len(chosen)}",
    f"sla_status={status}",
    f"target_speed_MB_s={target_speed:g}",
    f"best_latency_ms={best_latency:.2f}" if chosen else "best_latency_ms=N/A",
    f"best_speed_MB_s={best_speed:.2f}" if chosen else "best_speed_MB_s=N/A",
    "published_files=best.csv,best.txt" if published else "published_files=not_updated; candidate_best.csv,candidate_best.txt only",
    "verdict=" + (
        f"v4 已发布 {required} 个 SLA 达标 IP（延迟 <= {sla_latency:g}ms，速度 >= {sla_speed:g} MB/s）。"
        if published else
        f"v4 当前只有 {len(chosen)}/{required} 个 SLA 达标 IP；正式 best.csv/best.txt 暂不伪装成功。"
    ),
]) + "\n", encoding="utf-8")
print(f"sla_good_count={len(chosen)} published={int(published)}")
PY
}

append_history_from_diag() {
  python3 - "$OPERATOR" "$SLA_LATENCY_MS" "$SLA_SPEED_MB" "$TARGET_SPEED_MB" <<'PY'
import csv, pathlib, sys, time

op = sys.argv[1]
sla_latency = float(sys.argv[2])
sla_speed = float(sys.argv[3])
target_speed = float(sys.argv[4])
base = pathlib.Path(".")
diag = base / "speed_diagnostics_v4.csv"
history = base / "best_history.csv"
fields = ["operator_profile","ip","latency_ms","download_speed_MB_s","packet_loss","colo","hit_level","speed_source","url","http_code","bytes_downloaded","score","last_seen"]

hist_rows = []
if history.exists():
    with history.open(encoding="utf-8") as f:
        hist_rows = list(csv.DictReader(f))

new_rows = []
if diag.exists():
    with diag.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            try:
                ip = r["ip"]
                lat = float(r.get("latency_ms", "999") or 999)
                speed = float(r.get("speed_MB_s", "0") or 0)
                http = int(float(r.get("http_code", "0") or 0))
                bytes_downloaded = int(float(r.get("bytes_downloaded", "0") or 0))
            except Exception:
                continue
            force_overwrite = str(r.get("round", "")).lower() == "health"
            valid = http in (200, 206) and bytes_downloaded > 0 and speed > 0
            if lat <= sla_latency and speed >= sla_speed:
                level = "sla_pass"
            elif lat <= 30 and speed >= target_speed:
                level = "ideal_target"
            elif valid:
                level = "usable_below_sla"
            else:
                level = "failed_or_rate_limited"
            source = "parallel_curl_resolve_speed" if valid else ("rate_limited_429" if http == 429 else "parallel_curl_resolve_failed")
            score = speed * 1000 - lat * 10
            new_rows.append({
                "operator_profile": op,
                "ip": ip,
                "latency_ms": f"{lat:.2f}",
                "download_speed_MB_s": f"{speed:.2f}",
                "packet_loss": "0.00",
                "colo": r.get("colo", "N/A") or "N/A",
                "hit_level": level,
                "speed_source": source,
                "url": r.get("url", ""),
                "http_code": str(http),
                "bytes_downloaded": str(bytes_downloaded),
                "score": f"{score:.2f}",
                "last_seen": time.strftime("%Y-%m-%d %H:%M:%S"),
                "_force_overwrite": force_overwrite,
            })

by_key = {}
for r in hist_rows + new_rows:
    key = (r.get("operator_profile", op), r.get("ip", ""))
    if not key[1]:
        continue
    force_overwrite = bool(r.pop("_force_overwrite", False))
    try:
        speed = float(r.get("download_speed_MB_s", "0") or 0)
        lat = float(r.get("latency_ms", "999") or 999)
    except ValueError:
        speed, lat = 0.0, 999.0
    old = by_key.get(key)
    if old is None:
        by_key[key] = r
        continue
    if force_overwrite:
        by_key[key] = r
        continue
    try:
        old_speed = float(old.get("download_speed_MB_s", "0") or 0)
        old_lat = float(old.get("latency_ms", "999") or 999)
    except ValueError:
        old_speed, old_lat = 0.0, 999.0
    if (speed, -lat) > (old_speed, -old_lat):
        by_key[key] = r

all_rows = list(by_key.values())
all_rows.sort(key=lambda r: (r.get("operator_profile", ""), -float(r.get("download_speed_MB_s", "0") or 0), float(r.get("latency_ms", "999") or 999)))
with history.open("w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    w.writerows(all_rows)
print(f"history_rows={len(all_rows)} new_attempts={len(new_rows)}")
PY
}

make_candidates() {
  python3 - "$OPERATOR" "$SLA_LATENCY_MS" "$SLA_SPEED_MB" "$MAX_CANDIDATES" > "$1" <<'PY'
import csv, ipaddress, pathlib, sys

op = sys.argv[1]
sla_latency = float(sys.argv[2])
sla_speed = float(sys.argv[3])
limit = int(sys.argv[4])
base = pathlib.Path(".")
items = {}
seed_order = 0

def seed_bias(ip):
    if ip.startswith("104."):
        return 7000
    if ip.startswith("172.64.") or ip.startswith("172.65.") or ip.startswith("172.66.") or ip.startswith("172.67."):
        return 6500
    if ip.startswith("162.158."):
        return 4500
    if ip.startswith("198.41."):
        return 3500
    return 0

def add(ip, lat, speed=0.0, source="", order=0):
    if not ip or not ip.replace(".", "").isdigit():
        return
    try:
        lat = float(lat)
    except Exception:
        lat = 999.0
    try:
        speed = float(speed)
    except Exception:
        speed = 0.0
    old = items.get(ip)
    score = 0
    if lat <= sla_latency:
        score += 10000
    if speed >= sla_speed:
        score += 5000
    score += max(0, 1000 - lat * 10) + speed * 20
    if source == "history" and not (lat <= sla_latency and speed >= sla_speed):
        score -= 2500
    if source == "remote_best":
        score += 20000
    if source == "ip_seed":
        score += seed_bias(ip) - order * 0.001
    if old is None or score > old[2]:
        items[ip] = (lat, speed, score, source)

for name in ("result_scan.csv", "result_scan_v4.csv"):
    path = base / name
    if path.exists():
        with path.open(encoding="utf-8") as f:
            for r in csv.DictReader(f):
                add(r.get("IP 地址", ""), r.get("平均延迟", "999"), r.get("下载速度(MB/s)", "0"), name)

path = base / "best_history.csv"
if path.exists():
    with path.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r.get("operator_profile") == op:
                add(r.get("ip", ""), r.get("latency_ms", "999"), r.get("download_speed_MB_s", "0"), "history")

path = base / "best.csv"
if path.exists():
    with path.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            add(r.get("IP") or r.get("ip") or "", r.get("平均延迟(ms)") or r.get("latency_ms") or "999", r.get("下载速度(MB/s)") or r.get("download_speed_MB_s") or "0", "best")

path = base / "remote_best.txt"
if path.exists():
    with path.open(encoding="utf-8") as f:
        for line in f:
            ip = line.strip()
            if ip and not ip.startswith("#"):
                add(ip, 1, sla_speed + 1, "remote_best")

sla_ready = sum(1 for lat, speed, score, source in items.values() if lat <= sla_latency and speed >= sla_speed)
if sla_ready < limit:
    path = base / "ip.txt"
    if path.exists():
        with path.open(encoding="utf-8") as f:
            for line in f:
                raw = line.strip()
                if not raw or raw.startswith("#"):
                    continue
                try:
                    net = ipaddress.ip_network(raw, strict=False)
                except ValueError:
                    seed_order += 1
                    add(raw, 999, 0, "ip_seed", seed_order)
                    continue
                if net.version != 4 or net.num_addresses <= 2:
                    continue
                usable = net.num_addresses - 2
                offsets = [
                    max(2, usable // 7),
                    max(2, usable // 5),
                    max(2, usable // 3),
                    max(2, usable // 2),
                    max(2, usable * 2 // 3),
                    max(2, usable * 4 // 5),
                    max(2, usable * 6 // 7),
                ]
                for offset in offsets:
                    try:
                        ip = str(net.network_address + offset)
                    except Exception:
                        continue
                    last_octet = int(ip.rsplit(".", 1)[1])
                    if last_octet < 2 or last_octet > 253:
                        continue
                    seed_order += 1
                    add(ip, 999, 0, "ip_seed", seed_order)

ranked = sorted(items.items(), key=lambda kv: (-kv[1][2], kv[1][0]))
for ip, (lat, speed, score, source) in ranked[:limit]:
    print(f"{ip},{lat:.2f},{speed:.2f},{source}")
PY
}

make_health_candidates() {
  python3 - "$REQUIRED_COUNT" > "$1" <<'PY'
import csv, pathlib, sys

limit = int(sys.argv[1])
path = pathlib.Path("best.csv")
if not path.exists():
    raise SystemExit(0)
count = 0
with path.open(encoding="utf-8") as f:
    for r in csv.DictReader(f):
        ip = r.get("IP") or r.get("ip") or ""
        lat = r.get("平均延迟(ms)") or r.get("latency_ms") or "999"
        speed = r.get("下载速度(MB/s)") or r.get("download_speed_MB_s") or "0"
        if not ip:
            continue
        print(f"{ip},{lat},{speed},best_health_check")
        count += 1
        if count >= limit:
            break
PY
}

test_candidates() {
  local candidate_file="$1"
  local round="$2"
  while IFS=, read -r ip latency old_speed source; do
    [[ -n "${ip:-}" ]] || continue
    python3 - "$DIAG_FILE" "$OPERATOR" "$round" "$ip" "$latency" "$old_speed" "$source" "$DOWNLOAD_BYTES" "$PARALLEL_DOWNLOADS" "$CONNECT_TIMEOUT" "$CURL_TIME_LIMIT" <<'PY'
import concurrent.futures, csv, random, subprocess, sys, time

diag, op, round_id, ip, latency, old_speed, source, download_bytes, parallel, connect_timeout, curl_time_limit = sys.argv[1:]
download_bytes = int(download_bytes)
parallel = int(parallel)
host = "speed.cloudflare.com"
started = int(time.time())

def run_one(idx):
    url = f"https://{host}/__down?bytes={download_bytes}&op={op}&round={round_id}&parallel={parallel}&r={started}_{random.randint(1,999999)}_{idx}"
    cmd = [
        "curl", "-L", "--http1.1",
        "--connect-timeout", str(connect_timeout),
        "--max-time", str(curl_time_limit),
        "--resolve", f"{host}:443:{ip}",
        "-o", "/dev/null", "-sS",
        "-w", "%{http_code},%{size_download},%{time_total},%{speed_download}",
        url,
    ]
    cmd[-2] = "%{http_code},%{size_download},%{time_total},%{speed_download},%{time_connect},%{time_appconnect}"
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    parts = (proc.stdout or "0,0,0,0").split(",")
    try:
        http = int(float(parts[0] or 0))
        size = int(float(parts[1] or 0))
        total = float(parts[2] or 0)
        bps = float(parts[3] or 0)
        connect = float(parts[4] or 0) if len(parts) > 4 else 0.0
        appconnect = float(parts[5] or 0) if len(parts) > 5 else 0.0
    except Exception:
        http, size, total, bps, connect, appconnect = 0, 0, 0.0, 0.0, 0.0, 0.0
    err = (proc.stderr or "").strip().replace(",", ";").replace("\n", " ")[:120]
    return http, size, total, bps, connect, appconnect, err

wall_start = time.monotonic()
with concurrent.futures.ThreadPoolExecutor(max_workers=parallel) as executor:
    rows = list(executor.map(run_one, range(parallel)))
elapsed = max(time.monotonic() - wall_start, 0.001)
ok_rows = [r for r in rows if r[0] in (200, 206) and r[1] > 0]
total_bytes = sum(r[1] for r in ok_rows)
speed = total_bytes / elapsed / 1024 / 1024
connect_samples = [r[4] for r in ok_rows if r[4] > 0] or [r[4] for r in rows if r[4] > 0]
try:
    measured_latency = min(connect_samples) * 1000 if connect_samples else float(latency)
except Exception:
    measured_latency = 999.0
codes = {}
for r in rows:
    codes[r[0]] = codes.get(r[0], 0) + 1
http = 200 if ok_rows else (max(codes, key=codes.get) if codes else 0)
sample_url = f"https://{host}/__down?bytes={download_bytes}&op={op}&round={round_id}&parallel={parallel}"
error = f"parallel={parallel} ok={len(ok_rows)} codes={codes}"
with open(diag, "a", encoding="utf-8", newline="") as f:
    csv.writer(f).writerow([op, round_id, ip, f"{measured_latency:.2f}", source, sample_url, http, total_bytes, f"{elapsed:.3f}", f"{speed:.2f}", error])
print(f"round={round_id} ip={ip} latency={measured_latency:.2f} old_speed={old_speed} source={source} http={http} bytes={total_bytes} speed={speed:.2f}MB/s {error}")
PY
    sleep "$PER_REQUEST_SLEEP"
  done < "$candidate_file"
}

run_cfst_replenish() {
  [[ "$CFST_REPLENISH" == "1" ]] || return 0
  [[ -x "./cfst" ]] || return 0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] cfst replenish started"
  set +e
  ./cfst -f ip.txt -o "$CFST_OUT" -url "https://speed.cloudflare.com/__down?bytes=${DOWNLOAD_BYTES}&op=${OPERATOR}" \
    -n "$CFST_THREADS" -t "$CFST_TESTS" -dn "$CFST_DOWNLOADS" -dt 8 -tl "$SLA_LATENCY_MS" -tlr 0 -sl "$SLA_SPEED_MB" -p "$CFST_DOWNLOADS" \
    > "$CFST_LOG" 2>&1
  local rc=$?
  set -e
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] cfst replenish finished rc=${rc}"
}

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] v4 SLA maintainer started"
  echo "operator=${OPERATOR} sla_latency_ms=${SLA_LATENCY_MS} sla_speed_MB_s=${SLA_SPEED_MB} required=${REQUIRED_COUNT} max_rounds=${MAX_ROUNDS} parallel_downloads=${PARALLEL_DOWNLOADS} health_check=${HEALTH_CHECK}"
  [[ -n "${CAFFEINATE_PID:-}" ]] && echo "caffeinate_pid=${CAFFEINATE_PID}"
  sync_remote_best
  [[ -f "$REMOTE_BEST_TXT" ]] && echo "remote_best_count=$(grep -cve '^[[:space:]]*$' "$REMOTE_BEST_TXT" 2>/dev/null || echo 0)"
  echo "operator_profile,round,ip,latency_ms,candidate_source,url,http_code,bytes_downloaded,time_total,speed_MB_s,error" > "$DIAG_FILE"
  [[ -f "$HISTORY_FILE" ]] || echo "operator_profile,ip,latency_ms,download_speed_MB_s,packet_loss,colo,hit_level,speed_source,url,http_code,bytes_downloaded,score,last_seen" > "$HISTORY_FILE"

  initial="$(publish_from_history)"
  echo "initial_publish_check: ${initial}"
  if echo "$initial" | grep -q "published=1"; then
    if [[ "$HEALTH_CHECK" == "1" ]]; then
      health_file="$(mktemp)"
      make_health_candidates "$health_file"
      if [[ -s "$health_file" ]]; then
        echo "health_check candidates:"
        cat "$health_file"
        test_candidates "$health_file" "health"
        append_history_from_diag
        health_publish="$(publish_from_history)"
        echo "health_check publish_check: ${health_publish}"
        if echo "$health_publish" | grep -q "published=1"; then
          echo "SLA still satisfied after health check; no public replenish needed."
          rm -f "$health_file"
          exit 0
        fi
      fi
      rm -f "$health_file"
    else
      echo "SLA already satisfied; no public scan needed."
      exit 0
    fi
  fi

  round=1
  while [[ "$round" -le "$MAX_ROUNDS" ]]; do
    candidate_file="$(mktemp)"
    make_candidates "$candidate_file"
    if [[ ! -s "$candidate_file" ]]; then
      echo "round=${round} no candidates; running cfst replenish"
      rm -f "$candidate_file"
      run_cfst_replenish
      candidate_file="$(mktemp)"
      make_candidates "$candidate_file"
    fi
    echo "round=${round} candidates:"
    sed -n '1,80p' "$candidate_file"
    test_candidates "$candidate_file" "$round"
    rm -f "$candidate_file"

    append_history_from_diag
    publish_result="$(publish_from_history)"
    echo "round=${round} publish_check: ${publish_result}"
    if echo "$publish_result" | grep -q "published=1"; then
      echo "SLA satisfied in round ${round}"
      break
    fi

    if [[ "$round" -eq 2 ]]; then
      run_cfst_replenish
    fi
    round=$((round + 1))
    [[ "$round" -le "$MAX_ROUNDS" ]] && sleep "$ROUND_SLEEP"
  done

  final="$(publish_from_history)"
  echo "final_publish_check: ${final}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] v4 finished"
  cat "$SUMMARY_FILE"
} >> "$LOG_FILE" 2>&1
