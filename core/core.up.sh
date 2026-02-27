#!/usr/bin/env bash
# ============================================================
# CORE.UP.SH
#
# Назначение:
#   Поднятие "core" инфраструктуры (reverse proxy + gitea)
#   с общей Docker-сетью, чтобы сервисы видели друг друга по имени.
#
# ЧТО ДЕЛАЕТ:
#   - Создаёт Docker network "core" (если её ещё нет)
#   - Поднимает proxy (Caddy)
#   - Поднимает gitea
#
# Запуск:
#   ./core.up.sh
#
# Важно:
#   Скрипт предполагает запуск из папки core/
#   (или сам перейдёт в неё, если запущен откуда угодно).
# ============================================================

set -euo pipefail

echo "🚀 Starting CORE infrastructure up..."

# ----------------------------
# Переходим в папку core (где лежит этот скрипт)
# ----------------------------
# Комментарий:
#   Это делает скрипт устойчивым к запуску "откуда угодно".
cd "$(dirname "$0")"

# ----------------------------
# Загружаем общий core env (не секреты)
# ----------------------------
# Комментарий:
#   .env.core — часть IaC-контракта. Там лежат "константы" core-инфры:
#   имя docker-сети, домены, порты, TZ и т.п.
CORE_ENV_FILE="./.env.core"

if [ -f "$CORE_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$CORE_ENV_FILE"
  set +a
else
  echo "❌ $CORE_ENV_FILE not found. Create it (from .env.example) before running."
  exit 1
fi

# ----------------------------
# Настройка базовых переменных
# ----------------------------
CORE_NETWORK_NAME="${CORE_NETWORK_NAME:-net-core}"

# ----------------------------
# ✅ Проверка наличия Docker
# ----------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker не найден. Сначала запусти bootstrap/bootstrap.sh"
  exit 1
fi

# ----------------------------
# ✅ Проверка наличия Docker Compose plugin
# ----------------------------
if ! docker compose version >/dev/null 2>&1; then
  echo "❌ Docker Compose plugin не найден. Сначала запусти bootstrap/bootstrap.sh"
  exit 1
fi

# ----------------------------
# Создание общей Docker-сети (идемпотентно)
# ----------------------------
# Комментарий:
#   Нам нужна общая сеть, чтобы proxy мог проксировать на gitea:3000 по имени сервиса.
#   Если сеть уже есть — просто пропускаем.
echo "🌐 Checking docker network: ${CORE_NETWORK_NAME}..."
if ! docker network inspect "$CORE_NETWORK_NAME" >/dev/null 2>&1; then
  echo "➕ Creating docker network: ${CORE_NETWORK_NAME}"
  docker network create "$CORE_NETWORK_NAME" >/dev/null
else
  echo "✅ Docker network already exists: ${CORE_NETWORK_NAME}"
fi

# ----------------------------
# ✅ Проверка unbound.conf перед запуском DNS (ARM-safe)
# ----------------------------
echo "🔍 Validating unbound.conf..."

if [ ! -f "./dns/unbound.conf" ]; then
  echo "❌ dns/unbound.conf not found"
  exit 1
fi

# Комментарий:
#   mvance/unbound может не иметь arm64, поэтому валидируем конфиг
#   в универсальном Alpine (multi-arch), установив unbound-tools.
if ! docker run --rm \
  -v "$(pwd)/dns/unbound.conf:/tmp/unbound.conf:ro" \
  alpine:3.20 \
  sh -lc "apk add --no-cache unbound >/dev/null && unbound-checkconf /tmp/unbound.conf" >/dev/null; then
  echo "❌ unbound.conf validation failed"
  exit 1
else
  echo "✅ unbound.conf is valid"
fi

# ----------------------------
# ✅ Fail-fast: проверяем, что DNS порт свободен на хосте
# ----------------------------
echo "🔍 Checking host DNS port availability..."

DNS_HOST_PORT="${DNS_HOST_PORT:-5353}"

echo "   Using DNS_HOST_PORT=${DNS_HOST_PORT}"

check_port_free() {
  local proto="$1"   # tcp | udp
  local port="$2"

  # Предпочтение ss (обычно есть в Ubuntu)
  if command -v ss >/dev/null 2>&1; then
    if ss -lpn 2>/dev/null | grep -E -q "[:.]${port}\s"; then
      echo "❌ Port ${port}/${proto} seems to be in use."
      echo "   Details:"
      ss -lpn 2>/dev/null | grep -E "[:.]${port}\s" || true
      return 1
    fi
    return 0
  fi

  # Fallback: lsof
  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -i "${proto}:${port}" >/dev/null 2>&1; then
      echo "❌ Port ${port}/${proto} is in use."
      echo "   Details:"
      lsof -nP -i "${proto}:${port}" || true
      return 1
    fi
    return 0
  fi

  echo "⚠️  Cannot verify port ${port}/${proto} (no ss/lsof found)."
  return 0
}

if ! check_port_free "tcp" "$DNS_HOST_PORT"; then
  echo "❌ Host port ${DNS_HOST_PORT}/tcp is busy."
  exit 1
fi

if ! check_port_free "udp" "$DNS_HOST_PORT"; then
  echo "❌ Host port ${DNS_HOST_PORT}/udp is busy."
  exit 1
fi

echo "✅ Port ${DNS_HOST_PORT} appears free (TCP/UDP)"

# ----------------------------
# Поднимаем DNS (Unbound)
# ----------------------------
# Комментарий:
#   DNS — базовый инфраструктурный сервис для локальной сети.
#   Он нужен клиентам в LAN, чтобы домены (gitea.egor.lan и т.д.)
#   резолвились в IP хоста, где живёт reverse proxy.
#
#   Контейнерам внутри Docker сети Unbound НЕ обязателен:
#   они используют встроенный Docker DNS.
#
#   Но логически DNS относится к core и удобно поднимать его первым.
echo "🧩 Starting dns (unbound)..."

if [ ! -f "./dns/docker-compose.yml" ]; then
  echo "❌ dns/docker-compose.yml not found"
  exit 1
fi

if [ ! -f "./dns/unbound.conf" ]; then
  echo "❌ dns/unbound.conf not found"
  exit 1
fi

echo "🛠 Building dns image..."
docker compose \
  --env-file "$CORE_ENV_FILE" \
  -f ./dns/docker-compose.yml \
  build

echo "🚀 Bringing up dns..."
docker compose \
  --env-file "$CORE_ENV_FILE" \
  -f ./dns/docker-compose.yml \
  up -d --force-recreate

# ----------------------------
# ✅ Проверка Caddyfile перед запуском proxy
# ----------------------------
echo "🔍 Validating Caddyfile..."

if [ ! -f "./proxy/Caddyfile" ]; then
  echo "❌ proxy/Caddyfile not found"
  exit 1
fi

if ! docker run --rm \
  -e "GITEA_DOMAIN=${GITEA_DOMAIN}" \
  -v "$(pwd)/proxy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.8 \
  caddy validate --config /etc/caddy/Caddyfile >/dev/null; then
  echo "❌ Caddyfile validation failed"
  exit 1
else
  echo "✅ Caddyfile is valid"
fi

# ----------------------------
# Поднимаем proxy
# ----------------------------
# Комментарий:
#   Proxy — это "единственная дверь наружу" для HTTP/HTTPS.
#   Поэтому логично поднимать его первым.
#
#   Флаг --force-recreate используется специально:
#   изменения в сетях Docker (networks) применяются корректно
#   только при пересоздании контейнера.
echo "🧩 Starting proxy..."
docker compose \
  --env-file "$CORE_ENV_FILE" \
  -f ./proxy/docker-compose.yml \
  up -d --force-recreate

# ----------------------------
# Поднимаем gitea
# ----------------------------
# Комментарий:
#   Аналогично proxy — если в docker-compose.yml
#   добавилась или изменилась сеть, контейнер
#   должен быть пересоздан.
#
#   ДАННЫЕ НЕ ТЕРЯЮТСЯ:
#   все данные Gitea хранятся в volumes.
echo "🧩 Starting gitea..."
docker compose \
  --env-file "$CORE_ENV_FILE" \
  --env-file ./gitea/.env \
  -f ./gitea/docker-compose.yml \
  up -d --force-recreate

# ----------------------------
# Финал
# ----------------------------
echo "✅ CORE infrastructure is up!"
echo ""
echo "ℹ️ Следующий шаг:"
echo "   - Запусти ./core.check.sh чтобы проверить сеть и доступность"
echo ""
