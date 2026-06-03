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

## Docker

```sh
git clone https://github.com/clover-eric/toip.git
cd toip
cp .env.example .env
vi .env
docker compose up -d --build
```

## 运营商标识

建议每个检测点设置不同 `SOURCE`，Worker 会用它做三网均衡：

- 移动：`SOURCE=local-cmcc`，`OPERATOR=CMCC`
- 联通：`SOURCE=local-cucc`，`OPERATOR=CUCC`
- 电信：`SOURCE=local-ctcc`，`OPERATOR=CTCC`

Worker 最终只保留 30 个 IP：三大运营商各尽量 10 个，缺口用全局最优补齐。

## 状态

```sh
/opt/toip/status_best_ip_maintain_v4.sh
```

停止：

```sh
/opt/toip/stop_best_ip_maintain_v4.sh
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
SCAN_INTERVAL_SECONDS=7200
SLA_LATENCY_MS=30
SLA_SPEED_MB=20
REQUIRED_COUNT=10
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
