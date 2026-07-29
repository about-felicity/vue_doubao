#!/usr/bin/env bash
# 一键发布营养健康客户快照，并绑定到 https://1any.top/custombjp/。

set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/about-felicity/vue_doubao.git}"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-1any.top}"
URL_PREFIX="${URL_PREFIX:-/custombjp}"
EXISTING_PREFIX="${EXISTING_PREFIX:-/customXL}"
APP_NAME="${APP_NAME:-vue_doubao_bjp}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/${APP_NAME}}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/nginx.conf}"
BACKUP_DIR="${BACKUP_DIR:-/root/${APP_NAME}_backups}"
RELEASE_ID="$(date +%Y%m%d%H%M%S)"
RELEASE_DIR="${DEPLOY_ROOT}/releases/${RELEASE_ID}"
CURRENT_LINK="${DEPLOY_ROOT}/current"
WORK_DIR="$(mktemp -d)"
BACKUP_FILE=""
CONFIG_CHANGED=0

cleanup() {
  rm -rf -- "${WORK_DIR}"
}

rollback() {
  local exit_code=$?
  trap - ERR
  if (( CONFIG_CHANGED )) && [[ -n "${BACKUP_FILE}" && -f "${BACKUP_FILE}" ]]; then
    echo "部署失败，恢复 Nginx 配置：${BACKUP_FILE}"
    cp -a -- "${BACKUP_FILE}" "${NGINX_CONF}" || true
    nginx -t -c "${NGINX_CONF}" >/dev/null 2>&1 && systemctl reload nginx.service || true
  fi
  exit "${exit_code}"
}

trap cleanup EXIT
trap rollback ERR

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash deploy_custombjp.sh"
  exit 1
fi
if [[ ! "${URL_PREFIX}" =~ ^/[A-Za-z0-9._~-]+$ ]]; then
  echo "URL_PREFIX 必须是类似 /custombjp 的单层安全路径。"
  exit 1
fi
URL_PREFIX="${URL_PREFIX%/}"

for command_name in git nginx systemctl curl python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "缺少命令：${command_name}"
    exit 1
  fi
done
if [[ ! -f "${NGINX_CONF}" ]]; then
  echo "没有找到 Nginx 配置：${NGINX_CONF}"
  exit 1
fi

echo "[1/5] 拉取 ${REPO_URL} (${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${WORK_DIR}/repo"
if [[ ! -f "${WORK_DIR}/repo/dist/index.html" ]]; then
  echo "GitHub 仓库中没有 dist/index.html，请先在本地生成并推送快照。"
  exit 1
fi

echo "[2/5] 发布静态快照..."
install -d -m 0755 "${RELEASE_DIR}"
cp -a "${WORK_DIR}/repo/dist/." "${RELEASE_DIR}/"
ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}.next"
mv -Tf "${CURRENT_LINK}.next" "${CURRENT_LINK}"

echo "[3/5] 写入 ${DOMAIN}${URL_PREFIX}/ 的 Nginx 路径..."
install -d -m 0700 "${BACKUP_DIR}"
BACKUP_FILE="${BACKUP_DIR}/nginx.conf.${RELEASE_ID}.bak"
cp -a -- "${NGINX_CONF}" "${BACKUP_FILE}"

export DOMAIN URL_PREFIX EXISTING_PREFIX NGINX_CONF CURRENT_LINK
python3 <<'PY'
import os
import re
from pathlib import Path

path = Path(os.environ["NGINX_CONF"])
domain = os.environ["DOMAIN"]
prefix = os.environ["URL_PREFIX"]
existing_prefix = os.environ.get("EXISTING_PREFIX", "/customXL").rstrip("/")
static_root = os.environ["CURRENT_LINK"].rstrip("/")
text = path.read_text(encoding="utf-8")

# The existing lock script intentionally allowed only /customXL and returned
# 403 at server-rewrite phase for every other URI. Expand that whitelist before
# adding the new location; location precedence alone cannot bypass a server if.
lock_begin = "        # BEGIN CUSTOMXL ONLY"
lock_end = "        # END CUSTOMXL ONLY"
lock_pattern = rf"\n{re.escape(lock_begin)}.*?{re.escape(lock_end)}\n"
if re.search(lock_pattern, text, flags=re.S):
    allowed = "|".join(
        re.escape(item)
        for item in dict.fromkeys((existing_prefix, prefix))
    )
    lock_block = f"""
{lock_begin}
        # 仅允许两个客户面板路径；其他域名路径继续返回 403。
        if ($uri !~ "^(?:{allowed})(?:/|$)") {{
            return 403;
        }}
{lock_end}
"""
    text = re.sub(lock_pattern, "\n" + lock_block, text, flags=re.S)

begin = "        # BEGIN CUSTOMBJP MANAGED"
end = "        # END CUSTOMBJP MANAGED"
text = re.sub(
    rf"\n{re.escape(begin)}.*?{re.escape(end)}\n",
    "\n",
    text,
    flags=re.S,
)


def closing_brace(source, opening):
    depth = 0
    quote = None
    escaped = False
    comment = False
    for index in range(opening, len(source)):
        char = source[index]
        if comment:
            if char == "\n":
                comment = False
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char == "#":
            comment = True
        elif char in ("'", '"'):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise RuntimeError("Nginx 配置中的大括号不完整。")


matches = []
for match in re.finditer(r"\bserver\s*\{", text):
    opening = text.find("{", match.start())
    closing = closing_brace(text, opening)
    block = text[match.start():closing + 1]
    names = re.findall(r"\bserver_name\s+([^;]+);", block)
    has_domain = any(domain in name.split() for name in names)
    has_https = bool(re.search(r"\blisten\s+(?:\[::\]:)?443(?:\s|;)", block))
    if has_domain and has_https:
        matches.append((opening, closing))

if len(matches) != 1:
    raise RuntimeError(
        f"应当找到 1 个 {domain}:443 server，实际找到 {len(matches)} 个；未写入配置。"
    )

_, closing = matches[0]
managed = f"""
{begin}
        location = {prefix} {{
            return 301 https://$host{prefix}/;
        }}

        location = {prefix}/ {{
            alias {static_root}/index.html;
            default_type text/html;
        }}

        location ^~ {prefix}/dashboard-assets/ {{
            alias {static_root}/dashboard-assets/;
            expires 7d;
            add_header Cache-Control "public, immutable";
        }}
{end}
"""
text = text[:closing] + managed + text[closing:]
path.write_text(text, encoding="utf-8")
PY

CONFIG_CHANGED=1
nginx -t -c "${NGINX_CONF}"

echo "[4/5] 平滑加载 Nginx..."
systemctl reload nginx.service
if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "${DEPLOY_ROOT}" >/dev/null 2>&1 || true
fi

echo "[5/5] 健康检查..."
for _ in {1..15}; do
  if curl --fail --silent --show-error --max-time 5 \
    --noproxy '*' \
    --resolve "${DOMAIN}:443:127.0.0.1" \
    "https://${DOMAIN}${URL_PREFIX}/" >/dev/null; then
    trap - ERR
    echo "部署成功：https://${DOMAIN}${URL_PREFIX}/"
    echo "当前版本：${RELEASE_ID}"
    echo "Nginx 备份：${BACKUP_FILE}"
    exit 0
  fi
  sleep 1
done

echo "Nginx 已加载，但页面健康检查失败。"
echo "静态文件状态："
ls -ldZ "${DEPLOY_ROOT}" "${CURRENT_LINK}" "${CURRENT_LINK}/index.html" 2>/dev/null || true
echo "最近的 Nginx 错误："
tail -n 30 /var/log/nginx/error.log 2>/dev/null || true
false
