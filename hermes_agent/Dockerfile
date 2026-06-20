ARG BUILD_VERSION=0.1.3
ARG BUILD_ARCH=amd64

FROM nousresearch/hermes-agent:main

ARG BUILD_VERSION=0.1.3
ARG BUILD_ARCH=amd64
ARG TARGETARCH

ENV HERMES_HOME=/config/.hermes

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx jq curl iproute2 git python3 && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/nginx

RUN git clone https://github.com/nesquena/hermes-webui.git /hermes-webui && \
    cd /hermes-webui && \
    python3 bootstrap.py || true

RUN ARCH="$(echo ${TARGETARCH:-$(dpkg --print-architecture)} | sed 's|arm64|aarch64|;s|arm/v7|armhf|;s|armv7|armhf|;s|amd64|x86_64|')" && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ARCH}" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

COPY render_nginx.py /render_nginx.py
COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
COPY landing.html.tpl /etc/nginx/landing.html.tpl
COPY run.sh /run.sh
RUN chmod a+x /run.sh /render_nginx.py

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}"

ENTRYPOINT ["/init", "/run.sh"]
