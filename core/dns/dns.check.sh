#!/usr/bin/env bash
# ============================================================
# DNS.CHECK.SH (IaC)
#
# Назначение:
#   Проверка корректной работы core DNS (Unbound)
#
# Проверяет:
#   - Контейнер существует и запущен
#   - Порт 53 опубликован (TCP/UDP) для этого контейнера
#   - Локальная зона резолвится (через published host port)
#   - Внешний форвардинг работает
#
# Запуск:
#   ./dns/dns.check.sh
# ============================================================

set -euo pipefail

print_ok()   { echo "✅ $1"; }
print_warn() { echo "⚠️  $1"; }
print_fail() { echo "❌ $1"; }

echo "🔍 Checking CORE DNS..."

cd "$(dirname "$0")/.."

CORE_ENV_FILE="./.env.core"

if [[ ! -f "$CORE_ENV_FILE" ]]; then
  print_fail ".env.core not found: ${CORE_ENV_FILE}"
  exit 1
fi

# Чтение env-значений (без source) — IaC стиль
get_env_value() {
  local env_file_path="$1"
  local key="$2"
  grep -E "^${key}=" "$env_file_path" 2>/dev/null | tail -n 1 | cut -d'=' -f2- || true
}

# Базовые зависимости
if ! command -v docker >/dev/null 2>&1; then
  print_fail "Docker CLI not found"
  exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
  print_fail "dig not found (install dnsutils: sudo apt-get update && sudo apt-get install -y dnsutils)"
  exit 1
fi

DNS_CONTAINER="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_DNS")"
DNS_IP="$(get_env_value "$CORE_ENV_FILE" "DNS_HOST_IP")"
DNS_PORT="$(get_env_value "$CORE_ENV_FILE" "DNS_HOST_PORT")"
LAN_ZONE="$(get_env_value "$CORE_ENV_FILE" "LOCAL_DNS_ZONE")"

DNS_CONTAINER="${DNS_CONTAINER:-core_dns}"
DNS_IP="${DNS_IP:-127.0.0.1}"
DNS_PORT="${DNS_PORT:-53}"
LAN_ZONE="${LAN_ZONE:-egor.lan}"

GITEA_FQDN="gitea.${LAN_ZONE}"

print_ok "DNS container (DCN_CORE_DNS): ${DNS_CONTAINER}"
print_ok "DNS host IP (DNS_HOST_IP): ${DNS_IP}"
print_ok "DNS host port (DNS_HOST_PORT): ${DNS_PORT}"
print_ok "Local zone (LOCAL_DNS_ZONE): ${LAN_ZONE}"
print_ok "Test FQDN: ${GITEA_FQDN}"
echo ""

# 1) Контейнер существует и запущен
echo "1) 🧩 Container status: ${DNS_CONTAINER}"

if ! docker inspect "$DNS_CONTAINER" >/dev/null 2>&1; then
  print_fail "Container not found: ${DNS_CONTAINER}"
  exit 1
fi

IS_RUNNING="$(docker inspect -f '{{.State.Running}}' "$DNS_CONTAINER")"
if [[ "$IS_RUNNING" != "true" ]]; then
  print_fail "Container is NOT running"
  echo "   Tip: docker logs ${DNS_CONTAINER} --tail=200"
  exit 1
fi

print_ok "Container is running"
echo ""

# 2) Порт опубликован (точечно для контейнера)
echo "2) 🌐 Port publish check (${DNS_PORT} -> 53/tcp, 53/udp)"

PORT_TCP="$(docker port "$DNS_CONTAINER" 53/tcp 2>/dev/null || true)"
PORT_UDP="$(docker port "$DNS_CONTAINER" 53/udp 2>/dev/null || true)"

if [[ -z "$PORT_TCP" ]]; then
  print_fail "53/tcp is NOT published for ${DNS_CONTAINER}"
  exit 1
fi
print_ok "53/tcp published: ${PORT_TCP}"

if [[ -z "$PORT_UDP" ]]; then
  print_fail "53/udp is NOT published for ${DNS_CONTAINER}"
  exit 1
fi
print_ok "53/udp published: ${PORT_UDP}"
echo ""

# 3) Локальная зона через localhost + published port
echo "3) 📡 Local zone resolution via 127.0.0.1:${DNS_PORT}"

ANS_LOCAL="$(dig @127.0.0.1 -p "${DNS_PORT}" "$GITEA_FQDN" +short || true)"
if echo "$ANS_LOCAL" | grep -qx "$DNS_IP"; then
  print_ok "Local zone resolves: ${GITEA_FQDN} -> ${DNS_IP}"
else
  print_fail "Local zone failed: got '${ANS_LOCAL}' expected '${DNS_IP}'"
  exit 1
fi
echo ""

# 4) Форвардинг наружу
echo "4) 🌍 Forward resolution (google.com) via 127.0.0.1:${DNS_PORT}"

ANS_FWD="$(dig @127.0.0.1 -p "${DNS_PORT}" google.com +short | head -n 1 || true)"
if echo "$ANS_FWD" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  print_ok "Forwarding works (example: ${ANS_FWD})"
else
  print_fail "Forwarding failed (got '${ANS_FWD}')"
  exit 1
fi
echo ""

# 5) Проверка с LAN IP (как будут обращаться клиенты)
echo "5) 📡 LAN resolution via ${DNS_IP}:${DNS_PORT}"

ANS_LAN="$(dig @"$DNS_IP" -p "${DNS_PORT}" "$GITEA_FQDN" +short || true)"
if echo "$ANS_LAN" | grep -qx "$DNS_IP"; then
  print_ok "LAN resolution works: ${GITEA_FQDN} -> ${DNS_IP}"
else
  print_fail "LAN resolution failed: got '${ANS_LAN}' expected '${DNS_IP}'"
  exit 1
fi

echo ""
print_ok "DNS check completed successfully!"