#!/bin/sh

set -u

# ==========================================================
# Back4app VLESS + WS
# Cloudflare Quick Tunnel / Named Tunnel 双模式
# ==========================================================

UUID="${UUID:-}"
PORT="${PORT:-8080}"
WS_PATH="${WS_PATH:-/vless}"

TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"
CF_HOST="${CF_HOST:-}"
CF_PROTOCOL="${CF_PROTOCOL:-auto}"

XRAY_PORT="10000"


# ==========================================================
# 基础检查
# ==========================================================

if [ -z "$UUID" ]; then
    echo ""
    echo "===================================================="
    echo " ERROR：没有设置 UUID"
    echo ""
    echo " Back4app → Settings → Environment Variables"
    echo ""
    echo " UUID = 你的UUID"
    echo "===================================================="
    echo ""
    exit 1
fi


# WS_PATH 自动补 /
case "$WS_PATH" in
    /*)
        ;;
    *)
        WS_PATH="/$WS_PATH"
        ;;
esac


echo ""
echo "===================================================="
echo "      Back4app VLESS + Cloudflare Tunnel"
echo "===================================================="
echo ""
echo "UUID      : $UUID"
echo "PORT      : $PORT"
echo "WS PATH   : $WS_PATH"
echo "XRAY PORT : $XRAY_PORT"
echo ""


# ==========================================================
# 判断隧道模式
# ==========================================================

if [ -n "$TUNNEL_TOKEN" ]; then

    TUNNEL_MODE="NAMED"

    echo "Tunnel Mode : 固定隧道 / Named Tunnel"

    if [ -n "$CF_HOST" ]; then
        echo "CF HOST     : $CF_HOST"
    else
        echo "CF HOST     : 未设置"
    fi

else

    TUNNEL_MODE="QUICK"

    echo "Tunnel Mode : 临时隧道 / Quick Tunnel"

fi


echo "===================================================="
echo ""


# ==========================================================
# 创建 Xray 配置
# ==========================================================

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
    }
  ]
}
EOF


# ==========================================================
# 创建 Nginx 配置
# ==========================================================

mkdir -p /run/nginx


cat > /etc/nginx/http.d/default.conf <<EOF
server {

    listen ${PORT};

    server_name _;


    # --------------------------
    # 健康检查
    # --------------------------

    location = / {

        default_type text/plain;

        return 200 "Back4app VLESS is running\n";
    }


    # --------------------------
    # VLESS WebSocket
    # --------------------------

    location ${WS_PATH} {

        proxy_pass http://127.0.0.1:${XRAY_PORT};

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;

        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;

        proxy_set_header X-Real-IP \$remote_addr;

        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_read_timeout 3600s;

        proxy_send_timeout 3600s;
    }
}
EOF


# ==========================================================
# 启动 Xray
# ==========================================================

echo ""
echo "[1/3] 启动 Xray..."

xray run -config /etc/xray/config.json &

XRAY_PID=$!


sleep 1


# ==========================================================
# 启动 Nginx
# ==========================================================

echo "[2/3] 启动 Nginx..."

nginx -g "daemon off;" &

NGINX_PID=$!


sleep 2


# ==========================================================
# 固定 Tunnel
# ==========================================================

run_named_tunnel() {

    echo ""
    echo "===================================================="
    echo "       启动 Cloudflare 固定 Tunnel"
    echo "===================================================="
    echo ""

    if [ -n "$CF_HOST" ]; then

        ENCODED_PATH="$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')"

        echo "固定域名："
        echo "$CF_HOST"

        echo ""

        echo "===================================================="
        echo "                 VLESS 固定节点"
        echo "===================================================="
        echo ""

        echo "vless://${UUID}@${CF_HOST}:443?encryption=none&security=tls&type=ws&host=${CF_HOST}&sni=${CF_HOST}&path=${ENCODED_PATH}#Back4app-CF-Fixed"

        echo ""
        echo "===================================================="
        echo ""

    else

        echo ""
        echo "警告：已经设置 TUNNEL_TOKEN"
        echo "但没有设置 CF_HOST"
        echo ""
        echo "固定 Tunnel 仍然可以启动，"
        echo "但无法自动生成 VLESS 分享链接。"
        echo ""

    fi


    while true
    do

        echo ""
        echo "正在连接 Cloudflare Named Tunnel..."
        echo ""


        cloudflared tunnel \
            --no-autoupdate \
            --protocol "$CF_PROTOCOL" \
            run \
            --token "$TUNNEL_TOKEN"


        EXIT_CODE=$?

        echo ""
        echo "Cloudflared 已停止。"
        echo "Exit Code: $EXIT_CODE"
        echo ""
        echo "5 秒后自动重新连接..."
        echo ""

        sleep 5

    done
}


# ==========================================================
# 临时 Tunnel
# ==========================================================

run_quick_tunnel() {

    while true
    do

        QUICK_LOG="/tmp/cloudflared-quick.log"

        rm -f "$QUICK_LOG"

        touch "$QUICK_LOG"


        echo ""
        echo "===================================================="
        echo "       启动 Cloudflare 临时 Tunnel"
        echo "===================================================="
        echo ""


        cloudflared tunnel \
            --no-autoupdate \
            --url "http://127.0.0.1:${PORT}" \
            2>&1 | tee "$QUICK_LOG" &


        QUICK_PID=$!


        # ==================================================
        # 等待 Cloudflare 返回随机域名
        # ==================================================

        QUICK_URL=""

        COUNT=0


        while [ "$COUNT" -lt 60 ]
        do

            QUICK_URL="$(grep -Eo 'https://[-a-zA-Z0-9]+\.trycloudflare\.com' "$QUICK_LOG" 2>/dev/null | head -n 1 || true)"


            if [ -n "$QUICK_URL" ]; then
                break
            fi


            COUNT=$((COUNT + 1))

            sleep 1

        done


        # ==================================================
        # 成功获取域名
        # ==================================================

        if [ -n "$QUICK_URL" ]; then

            QUICK_HOST="${QUICK_URL#https://}"

            ENCODED_PATH="$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')"


            echo ""
            echo ""
            echo "===================================================="
            echo "       Cloudflare Quick Tunnel 创建成功"
            echo "===================================================="
            echo ""

            echo "临时域名："
            echo "$QUICK_HOST"

            echo ""

            echo "UUID："
            echo "$UUID"

            echo ""

            echo "WS Path："
            echo "$WS_PATH"

            echo ""

            echo "===================================================="
            echo "                 VLESS 临时节点"
            echo "===================================================="
            echo ""

            echo "vless://${UUID}@${QUICK_HOST}:443?encryption=none&security=tls&type=ws&host=${QUICK_HOST}&sni=${QUICK_HOST}&path=${ENCODED_PATH}#Back4app-CF-Quick"

            echo ""
            echo "===================================================="
            echo ""
            echo "直接复制上面的 vless:// 链接导入客户端"
            echo ""
            echo "注意：临时 Tunnel 重启后域名可能变化。"
            echo ""

        else

            echo ""
            echo "===================================================="
            echo "没有获取到 trycloudflare.com 临时域名"
            echo "===================================================="
            echo ""

        fi


        # ==================================================
        # 等待 cloudflared
        # ==================================================

        wait "$QUICK_PID"

        EXIT_CODE=$?


        echo ""
        echo "===================================================="
        echo "Cloudflare Quick Tunnel 已断开"
        echo "Exit Code: $EXIT_CODE"
        echo ""
        echo "5 秒后自动重新创建临时 Tunnel..."
        echo "===================================================="
        echo ""


        sleep 5

    done
}


# ==========================================================
# 根据环境变量选择模式
# ==========================================================

echo ""
echo "[3/3] 启动 Cloudflare Tunnel..."
echo ""


if [ "$TUNNEL_MODE" = "NAMED" ]; then

    run_named_tunnel &

    CF_WRAPPER_PID=$!

else

    run_quick_tunnel &

    CF_WRAPPER_PID=$!

fi


# ==========================================================
# 主进程监控
# ==========================================================

cleanup() {

    echo ""
    echo "正在停止服务..."

    kill "$XRAY_PID" 2>/dev/null || true

    kill "$NGINX_PID" 2>/dev/null || true

    kill "$CF_WRAPPER_PID" 2>/dev/null || true

    exit 0
}


trap cleanup INT TERM


while true
do

    if ! kill -0 "$XRAY_PID" 2>/dev/null; then

        echo ""
        echo "ERROR：Xray 已停止"
        echo ""

        exit 1
    fi


    if ! kill -0 "$NGINX_PID" 2>/dev/null; then

        echo ""
        echo "ERROR：Nginx 已停止"
        echo ""

        exit 1
    fi


    if ! kill -0 "$CF_WRAPPER_PID" 2>/dev/null; then

        echo ""
        echo "ERROR：Cloudflare Tunnel 管理进程已停止"
        echo ""

        exit 1
    fi


    sleep 10

done
