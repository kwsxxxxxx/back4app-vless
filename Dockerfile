FROM cloudflare/cloudflared:latest AS cloudflared

FROM alpine:edge

RUN apk add --no-cache \
    nginx \
    ca-certificates \
    bash \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    xray

COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared

COPY start.sh /start.sh

RUN chmod +x /start.sh \
    && mkdir -p /etc/xray \
    && mkdir -p /run/nginx

EXPOSE 8080

CMD ["/start.sh"]
