#!/usr/bin/env bash
# 一键部署 vue_doubao 静态面板到公网 117.55.234.72:8765
# 运行前请修改下面的变量，或在命令行设置环境变量

set -euo pipefail

HOST="${DEPLOY_HOST:-117.55.234.72}"
PORT="${DEPLOY_PORT:-8765}"
USER="${DEPLOY_USER:-root}"
KEY="${DEPLOY_KEY:-$HOME/.ssh/id_rsa}"
REMOTE_PATH="${DEPLOY_PATH:-/opt/vue_doubao/dist}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

echo "[1/4] 开始构建..."
cd "$SCRIPT_DIR"
npm run build

echo "[2/4] 上传静态文件到服务器..."
SSH_ARGS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh $SSH_ARGS "$USER@$HOST" "mkdir -p $REMOTE_PATH"
scp $SSH_ARGS -r "$DIST_DIR"/* "$USER@$HOST:$REMOTE_PATH/"

echo "[3/4] 在服务器上启动/重启静态服务..."
ssh $SSH_ARGS "$USER@$HOST" "
    pkill -f 'http.server $PORT' 2>/dev/null || true
    pkill -f 'doubao_dashboard_server' 2>/dev/null || true
    sleep 1
    nohup python3 -m http.server $PORT --directory $REMOTE_PATH > /tmp/vue_doubao.log 2>&1 &
"

echo "[4/4] 等待服务启动..."
sleep 2
if curl -s -o /dev/null -w "%{http_code}" "http://$HOST:$PORT/" | grep -q "200"; then
    echo "部署成功: http://$HOST:$PORT/"
else
    echo "部署可能失败，请检查 /tmp/vue_doubao.log"
    exit 1
fi
