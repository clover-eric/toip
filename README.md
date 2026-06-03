# TOIP 检测端

Cloudflare 优选 IP 本地检测端。适配 OpenWrt、软路由、NAS、Linux、macOS、Docker。安装后自动定时检测、自动上传到 Worker，24 小时稳定运行。

## 一键安装

```sh
curl -fsSL https://raw.githubusercontent.com/clover-eric/toip/main/install.sh | sh
```

国内网络优先用加速入口：

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/install.sh | sh
```

指定检测点运营商：

```sh
SOURCE=local-cmcc OPERATOR=CMCC sh -c "$(curl -fsSL https://raw.githubusercontent.com/clover-eric/toip/main/install.sh)"
```

国内网络指定运营商：

```sh
SOURCE=local-cmcc OPERATOR=CMCC sh -c "$(curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/install.sh)"
```

默认已经内置：

```env
WORKER_URL=https://cfip.i3.pub
UPLOAD_TOKEN=ChangeMeUpload2026!
```

安装脚本内部会自动尝试 `gh-proxy.com`、`ghfast.top` 和 GitHub 直连，源码包和 `cfst` 下载都会自动切换可用源。

如果旧安装卡在 GitHub 下载，按 `Ctrl+C` 停掉后重跑国内加速命令即可。

## Docker

```sh
git clone https://github.com/clover-eric/toip.git
cd toip
cp .env.example .env
vi .env
docker compose up -d --build
```

## 运营商识别

默认启用自动识别出口运营商路线：

```env
AUTO_OPERATOR=1
SOURCE=gl-mt3000
```

检测前会识别公网出口 ASN，并自动写入：

```sh
/opt/toip/detected_route.env
```

例如双 WAN 路由器切到电信出口，会自动变成：

```env
OPERATOR=CTCC
SOURCE=gl-mt3000-ctcc
```

切到移动出口，会自动变成：

```env
OPERATOR=CMCC
SOURCE=gl-mt3000-cmcc
```

如需手动固定路线，关闭自动识别：

```env
AUTO_OPERATOR=0
SOURCE=local-ctcc
OPERATOR=CTCC
```

Worker 最终只保留 30 个 IP：三大运营商各尽量 10 个，缺口用全局最优补齐。

## 日常命令

以下命令以 OpenWrt / 软路由安装路径 `/opt/toip` 为例。

查看服务状态：

```sh
/etc/init.d/toip-agent status
```

查看检测状态、候选文件、摘要和日志尾部：

```sh
/opt/toip/status_best_ip_maintain_v4.sh
```

实时看检测日志：

```sh
tail -f /opt/toip/scan_v4.log
```

重启检测服务：

```sh
/etc/init.d/toip-agent restart
```

停止检测服务，并清理残留测速子进程：

```sh
/etc/init.d/toip-agent stop
/opt/toip/stop_best_ip_maintain_v4.sh
```

手动上传当前结果到 Worker：

```sh
cd /opt/toip
./upload_best_to_worker.sh
```

查看自动识别到的出口路线：

```sh
cat /opt/toip/detected_route.env
```

清空本机历史后重测：

```sh
cd /opt/toip
rm -f best_history.csv best.csv best.txt candidate_best.csv candidate_best.txt speed_diagnostics_v4.csv scan_summary.txt detected_route.env
/etc/init.d/toip-agent restart
tail -f /opt/toip/scan_v4.log
```

双 WAN 切线后重测：

```sh
cd /opt/toip
rm -f best_history.csv best.csv best.txt candidate_best.csv candidate_best.txt speed_diagnostics_v4.csv scan_summary.txt detected_route.env
/etc/init.d/toip-agent restart
tail -f /opt/toip/scan_v4.log
```

确认日志开头的路线识别：

```text
route_OPERATOR=CTCC
route_SOURCE=gl-mt3000-ctcc
route_ROUTE_ASN=AS4134
route_ROUTE_ORG=Chinanet
```

## 升级

OpenWrt / 软路由直接更新脚本：

```sh
cd /opt/toip

/etc/init.d/toip-agent stop
./stop_best_ip_maintain_v4.sh

curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/run_best_ip_maintain_v4.sh -o run_best_ip_maintain_v4.sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/upload_best_to_worker.sh -o upload_best_to_worker.sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/status_best_ip_maintain_v4.sh -o status_best_ip_maintain_v4.sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/clover-eric/toip/main/stop_best_ip_maintain_v4.sh -o stop_best_ip_maintain_v4.sh
chmod +x *.sh

grep -q '^AUTO_OPERATOR=' .env && sed -i 's/^AUTO_OPERATOR=.*/AUTO_OPERATOR=1/' .env || echo 'AUTO_OPERATOR=1' >> .env
sed -i 's/^SOURCE=.*/SOURCE=gl-mt3000/' .env

rm -f best_history.csv best.csv best.txt candidate_best.csv candidate_best.txt speed_diagnostics_v4.csv scan_summary.txt detected_route.env

/etc/init.d/toip-agent start
tail -f /opt/toip/scan_v4.log
```

如果加速地址缓存旧文件，用 GitHub 原链替换 `gh-proxy.com` 这一层：

```sh
curl -fsSL https://raw.githubusercontent.com/clover-eric/toip/main/run_best_ip_maintain_v4.sh -o run_best_ip_maintain_v4.sh
```

## 配置

安装后修改：

```sh
/opt/toip/.env
```

常用项：

```env
WORKER_URL=https://cfip.i3.pub
UPLOAD_TOKEN=ChangeMeUpload2026!
SOURCE=local-cmcc
OPERATOR=CMCC
AUTO_OPERATOR=1
SCAN_INTERVAL_SECONDS=7200
SLA_LATENCY_MS=30
SLA_SPEED_MB=20
REQUIRED_COUNT=10
MAX_CANDIDATES=48
QUICK_PROBE=1
FULL_CANDIDATES=20
```

修改后重启服务：

OpenWrt：

```sh
/etc/init.d/toip-agent restart
```

Linux：

```sh
systemctl restart toip-agent
```

Docker：

```sh
docker compose restart
```

## Worker 清库

如果 Worker 端 IP 库被旧运营商标签污染，可以清空 Worker IP 库后重新上传。

```sh
curl -fsS -X POST https://cfip.i3.pub/api/admin/reset-library \
  -H 'X-Upload-Token: ChangeMeUpload2026!'
```

清库后验证：

```sh
curl -i https://cfip.i3.pub/best.txt
```

正常应返回 `404`，之后等待检测端重新上传。
