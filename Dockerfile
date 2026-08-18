FROM cloudflare/cloudflared:2026.8.2 AS cloudflared

FROM alpine:edge

# 安装 Nginx、证书以及 Xray
RUN apk add --no-cache \
    nginx \
    ca-certificates \
    curl \
    bash \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    xray

# 从 Cloudflare 官方镜像复制 cloudflared
COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared

COPY start.sh /start.sh

RUN chmod +x /start.sh \
    && mkdir -p /etc/xray \
    && mkdir -p /run/nginx

EXPOSE 8080

CMD ["/start.sh"]
