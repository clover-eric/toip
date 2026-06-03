FROM alpine:3.20

ARG TARGETARCH
ARG TARGETVARIANT
ARG CFST_VERSION=2.3.5

RUN apk add --no-cache bash curl ca-certificates python3 coreutils tzdata

WORKDIR /opt/tocf

COPY run_best_ip_maintain_v4.sh status_best_ip_maintain_v4.sh stop_best_ip_maintain_v4.sh ./
COPY router_agent_24h.sh upload_best_to_worker.sh docker-entrypoint.sh ./
COPY ip.txt ipv6.txt ./

RUN chmod +x /opt/tocf/*.sh && \
    set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64*) cfst_arch="linux_amd64" ;; \
      arm64*) cfst_arch="linux_arm64" ;; \
      armv6*) cfst_arch="linux_armv6" ;; \
      armv7*) cfst_arch="linux_armv7" ;; \
      arm*) cfst_arch="linux_armv7" ;; \
      386*) cfst_arch="linux_386" ;; \
      *) echo "unsupported arch: ${TARGETARCH}${TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v${CFST_VERSION}/cfst_${cfst_arch}.tar.gz" -o /tmp/cfst.tar.gz; \
    tar -xzf /tmp/cfst.tar.gz -C /tmp; \
    mv /tmp/cfst /usr/local/bin/cfst; \
    chmod +x /usr/local/bin/cfst; \
    rm -rf /tmp/cfst.tar.gz /tmp/ip.txt /tmp/ipv6.txt /tmp/LICENSE /tmp/README.md

ENV TOCF_WORKDIR=/data \
    OPERATOR=CMCC \
    SOURCE=local-cmcc \
    WORKER_URL=https://cfip.i3.pub \
    SCAN_INTERVAL_SECONDS=7200 \
    HEALTH_CHECK=1 \
    CFST_REPLENISH=1 \
    MAX_ROUNDS=3 \
    MAX_CANDIDATES=24 \
    PARALLEL_DOWNLOADS=24

VOLUME ["/data"]

ENTRYPOINT ["/opt/tocf/docker-entrypoint.sh"]
