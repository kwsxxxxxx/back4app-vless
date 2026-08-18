#!/bin/sh

set -eu

# ==========================================
# Back4app VLESS + WS + Cloudflare Quick Tunnel
# ==========================================

UUID="${UUID:-}"
PORT="${PORT:-8080}"

XRAY_PORT="10000"
WS_PATH="/vless"

# ==========================================
# 检查 UUID
# ==========================================

if [ -z "$UUID" ]; then
    echo ""
    echo "=============================================="
    echo " ERROR: 没有设置 UUID"
    echo " 请在 Back4app Environment Variables 添加："
    echo ""
    echo " UUID=你的UUID"
    echo "=============================================="
    echo ""
    exit 1
fi


echo ""
echo "=============================================="
echo " Back4app VLESS 正在启动"
echo "=============================================="
echo "UUID      : $UUID"
echo "WS Path   : $WS_PATH"
echo "PORT      : $PORT"
echo "XRAY PORT : $XRAY_PORT"
echo "=============================================="
echo ""


# ==========================================
# 生成 Xray 配置
# ==========================================

mkdir -p /etc/xray

cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": ${XRAY_PORT},
      "protocol": "vless",

      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],

        "decryption": "none"
      },

      "streamSettings": {
        "network": "ws",

        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],

  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },

    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF


# ==========================================
# 生成 Nginx 配置
# ==========================================

mkdir -p /run/nginx

cat > /etc/nginx/http.d/default.conf <<EOF
server {

    listen ${PORT};

    server_name _;


    # 健康检查页面
    location = / {

        default_type text/plain;

        return 200 "Back4app VLESS is running\n";
    }


    # VLESS WebSocket
    location ${WS_PATH} {

        proxy_pass http://127.0.0.1:${XRAY_PORT};

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;

        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;

        proxy_set_header X-Real-IP \$remote_addr;

        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF


# ==========================================
# 启动 Xray
# ==========================================

echo "启动 Xray..."

xray run -config /etc/xray/config.json &

XRAY_PID=$!


# ==========================================
# 启动 Nginx
# ==========================================

echo "启动 Nginx..."

nginx -g "daemon off;" &

NGINX_PID=$!


sleep 2


# ==========================================
# 启动 Cloudflare Quick Tunnel
# ==========================================

echo ""
echo "正在连接 Cloudflare Quick Tunnel..."
echo ""

rm -f /tmp/cloudflared.log


cloudflared tunnel \
    --url "http://127.0.0.1:${PORT}" \
    2>&1 | tee /tmp/cloudflared.log &

CF_PID=$!


# ==========================================
# 获取 trycloudflare.com 域名
# ==========================================

CF_URL=""

COUNT=0

while [ "$COUNT" -lt 40 ]; do

    CF_URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -n 1 || true)"

    if [ -n "$CF_URL" ]; then
        break
    fi

    COUNT=$((COUNT + 1))

    sleep 1

done


# ==========================================
# 自动生成 VLESS 节点
# ==========================================

if [ -n "$CF_URL" ]; then

    CF_HOST="${CF_URL#https://}"

    echo ""
    echo ""
    echo "========================================================"
    echo "       Cloudflare Quick Tunnel 创建成功"
    echo "========================================================"
    echo ""
    echo "CF域名："
    echo "$CF_HOST"
    echo ""
    echo "UUID："
    echo "$UUID"
    echo ""
    echo "WebSocket Path："
    echo "$WS_PATH"
    echo ""
    echo "========================================================"
    echo "                    VLESS 节点"
    echo "========================================================"
    echo ""

    echo "vless://${UUID}@${CF_HOST}:443?encryption=none&security=tls&type=ws&host=${CF_HOST}&sni=${CF_HOST}&path=%2Fvless#Back4app-CF"

    echo ""
    echo "========================================================"
    echo "直接复制上面的 vless:// 链接导入客户端"
    echo "========================================================"
    echo ""

else

    echo ""
    echo "========================================================"
    echo "没有获取到 Cloudflare 临时域名"
    echo ""
    echo "请查看 Cloudflared 日志"
    echo "========================================================"
    echo ""

fi


# ==========================================
# 监控进程
# ==========================================

trap 'kill $XRAY_PID $NGINX_PID $CF_PID 2>/dev/null || true' INT TERM


while true; do

    if ! kill -0 "$XRAY_PID" 2>/dev/null; then

        echo "Xray 已停止"

        exit 1
    fi


    if ! kill -0 "$NGINX_PID" 2>/dev/null; then

        echo "Nginx 已停止"

        exit 1
    fi


    if ! kill -0 "$CF_PID" 2>/dev/null; then

        echo "Cloudflared 已停止"

        exit 1
    fi


    sleep 5

done
