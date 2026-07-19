FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        iproute2 \
        iptables \
        openconnect \
        procps \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY start-openconnect.sh /usr/local/bin/start-openconnect.sh
COPY openconnect-dns-wrapper.sh /usr/local/bin/openconnect-dns-wrapper.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/start-openconnect.sh \
    /usr/local/bin/openconnect-dns-wrapper.sh \
    /usr/local/bin/healthcheck.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/start-openconnect.sh"]
