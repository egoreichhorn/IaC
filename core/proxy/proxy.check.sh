#!/usr/bin/env bash
# ============================================================
# PROXY.CHECK.SH (IaC)
#
# Назначение:
#   Проверить работоспособность core reverse proxy (Caddy)
#   и доступность маршрута до Gitea через домен.
#
# Что проверяет:
#   1) Docker установлен и доступен
#   2) Загружен core env: ../.env.core (IaC контракт)
#   3) Docker network (CORE_NETWORK_NAME) существует
#   4) Контейнер proxy (DCN_CORE_PROXY) запущен и подключён к сети
#   5) Порт 80 слушается на хосте
#   6) Caddyfile валиден (fail-fast)
#   7) HTTP-ответ по домену (Host header) отдаётся и похож на Gitea
#
# Запуск:
#   ./proxy.check.sh
#
# Важно:
#   Скрипт предполагает запуск из core/proxy/ (или сам перейдёт).
# ============================================================

set -euo pipefail

print_ok()   { echo "✅ $1"; }
print_warn() { echo "⚠️  $1"; }
print_fail() { echo "❌ $1"; }

echo "🔎 Proxy checks started..."

# ----------------------------
# Переходим в папку proxy
# ----------------------------
cd "$(dirname "$0")"

# ----------------------------
# Базовая проверка Docker
# ----------------------------
if ! command -v docker >/dev/null 2>&1; then
  print_fail "Docker не найден"
  exit 1
fi

# ----------------------------
# IaC env-файл на уровне core/
# ----------------------------
CORE_ENV_FILE="../.env.core"

if [[ ! -f "$CORE_ENV_FILE" ]]; then
  print_fail "${CORE_ENV_FILE} не найден"
  echo "   Создай core/.env.core (на основе .env.example) и повтори."
  exit 1
fi

print_ok ".env.core: found (${CORE_ENV_FILE})"

# ------------------------------------------------------------
# Читатель env-значений (не source)
#
# Почему так:
# - source может вести себя по-разному в разных shell
# - нам нужна предсказуемость и read-only разбор KEY=VALUE
# - это ближе к IaC (явные контракты, без побочных эффектов)
# ------------------------------------------------------------
get_env_value() {
  local env_file_path="$1"
  local key="$2"

  grep -E "^${key}=" "$env_file_path" 2>/dev/null | tail -n 1 | cut -d'=' -f2- || true
}

# ----------------------------
# Читаем параметры из core/.env.core
# ----------------------------
# Комментарий:
#   Контейнерные имена теперь задаются через env, поэтому check не должен хардкодить их.
PROXY_CONTAINER_NAME="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_PROXY")"
CORE_NETWORK_NAME="$(get_env_value "$CORE_ENV_FILE" "CORE_NETWORK_NAME")"
GITEA_DOMAIN="$(get_env_value "$CORE_ENV_FILE" "GITEA_DOMAIN")"

# Фоллбеки на случай отсутствующих переменных
PROXY_CONTAINER_NAME="${PROXY_CONTAINER_NAME:-core-proxy}"
CORE_NETWORK_NAME="${CORE_NETWORK_NAME:-net-core}"
GITEA_DOMAIN="${GITEA_DOMAIN:-gitea.egor.lan}"

print_ok "Container name (DCN_CORE_PROXY): ${PROXY_CONTAINER_NAME}"
print_ok "Core network (CORE_NETWORK_NAME): ${CORE_NETWORK_NAME}"
print_ok "Gitea domain (GITEA_DOMAIN): ${GITEA_DOMAIN}"

echo ""

# ----------------------------
# Проверка Caddyfile
# ----------------------------
if [[ ! -f "./Caddyfile" ]]; then
  print_fail "Caddyfile не найден: $(pwd)/Caddyfile"
  exit 1
fi

print_ok "Caddyfile: found"

# Комментарий:
#   Мы валидируем Caddyfile через отдельный контейнер caddy:2.8
#   чтобы не зависеть от того, поднят ли уже core-proxy контейнер.
echo "🔍 Validating Caddyfile..."
if docker run --rm \
  -e "GITEA_DOMAIN=${GITEA_DOMAIN}" \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.8 \
  caddy validate --config /etc/caddy/Caddyfile > /dev/null; then
  print_ok "Caddyfile: valid"
else
  print_fail "Caddyfile validation failed"
  exit 1
fi

echo ""

# ----------------------------
# Проверка docker network
# ----------------------------
echo "🌐 Docker network: ${CORE_NETWORK_NAME}"
if docker network inspect "$CORE_NETWORK_NAME" >/dev/null 2>&1; then
  print_ok "Network exists"
else
  print_fail "Network not found: ${CORE_NETWORK_NAME}"
  echo "   Запусти core/core.up.sh (он создаёт сеть автоматически)."
  exit 1
fi

echo ""

# ----------------------------
# Проверка контейнера proxy
# ----------------------------
echo "📦 Container: ${PROXY_CONTAINER_NAME}"
if docker inspect "$PROXY_CONTAINER_NAME" >/dev/null 2>&1; then
  PROXY_STATE="$(docker inspect -f '{{.State.Status}}' "$PROXY_CONTAINER_NAME")"
  if [[ "$PROXY_STATE" == "running" ]]; then
    print_ok "Container running"
  else
    print_fail "Container is not running (state: ${PROXY_STATE})"
    echo "   Подсказка: docker logs ${PROXY_CONTAINER_NAME} --tail=200"
    exit 1
  fi
else
  print_fail "Container not found: ${PROXY_CONTAINER_NAME}"
  echo "   Запусти: (из core/) ./core.up.sh"
  exit 1
fi

echo ""

# ----------------------------
# Проверка подключения контейнера к сети
# ----------------------------
# Комментарий:
#   Нам важно, чтобы proxy был подключён к CORE_NETWORK_NAME,
#   иначе он не сможет ходить на gitea по имени (gitea:3000).
echo "🔌 Network attachment check..."
NETWORKS_LIST="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{printf "%s\n" $k}}{{end}}' "$PROXY_CONTAINER_NAME")"

if echo "$NETWORKS_LIST" | grep -qx "$CORE_NETWORK_NAME"; then
  print_ok "Attached to ${CORE_NETWORK_NAME}"
else
  print_fail "Not attached to ${CORE_NETWORK_NAME}"
  echo "   Проверь proxy/docker-compose.yml networks и перезапусти core.up.sh"
  exit 1
fi

echo ""

# ----------------------------
# Проверка, что порт 80 слушается на хосте
# ----------------------------
echo "🌍 Port 80 listener check..."
if command -v ss >/dev/null 2>&1; then
  if ss -lnt | grep -q ':80 '; then
    print_ok "Port 80 is listening"
  else
    print_fail "Port 80 is NOT listening"
    echo "   Возможно proxy не пробросил порт или порт занят другим сервисом."
    exit 1
  fi
else
  # fallback (если ss отсутствует)
  if docker port "$PROXY_CONTAINER_NAME" 80/tcp | grep -q '0.0.0.0:80'; then
    print_ok "Port 80 is published (docker port)"
  else
    print_fail "Port 80 publish check failed"
    exit 1
  fi
fi

echo ""

# ----------------------------
# Проверка HTTP-ответа через домен (Host header)
# ----------------------------
# Комментарий:
#   На сервере домен может НЕ резолвиться (hosts/DNS обычно на клиенте).
#   Поэтому мы проверяем корректность роутинга через Host header:
#   запрос идёт на localhost:80, но с Host: ${GITEA_DOMAIN}.
echo "🌐 HTTP route check (Host: ${GITEA_DOMAIN})..."

HTTP_HEADERS="$(curl -sSI -H "Host: ${GITEA_DOMAIN}" "http://127.0.0.1/" || true)"

if echo "$HTTP_HEADERS" | grep -qiE '^(HTTP/).* (200|302|303|307|308)'; then
  print_ok "HTTP response status looks OK"
else
  print_fail "Unexpected HTTP status"
  echo "$HTTP_HEADERS" | head -n 10
  exit 1
fi

# Частичная “сигнатура” Gitea (не жёстко, но полезно)
if echo "$HTTP_HEADERS" | grep -qiE 'set-cookie:.*i_like_gitea|server:.*gitea'; then
  print_ok "Looks like Gitea behind proxy"
else
  print_warn "Response does not look like Gitea (maybe login redirect or other service)."
  echo "   Это не всегда ошибка, но стоит проверить в браузере: http://${GITEA_DOMAIN}"
fi

echo ""
print_ok "Proxy checks finished successfully"
