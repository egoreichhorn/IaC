#!/usr/bin/env bash
# ============================================================
# CORE.CHECK.SH (IaC)
#
# Назначение:
#   Быстрая диагностика core-инфраструктуры (общий уровень):
#   - существует ли core docker-сеть
#   - запущены ли core контейнеры
#   - подключены ли они к одной сети
#
# Принцип:
#   READ-ONLY: НЕ меняет систему, только проверяет и печатает статус.
#
# Запуск:
#   ./core.check.sh
# ============================================================

set -euo pipefail

print_ok()   { echo "✅ $1"; }
print_warn() { echo "⚠️  $1"; }
print_fail() { echo "❌ $1"; }

echo "🔍 Checking CORE infrastructure..."

# ----------------------------
# Переходим в папку core
# ----------------------------
cd "$(dirname "$0")"

# ----------------------------
# IaC env-файл
# ----------------------------
CORE_ENV_FILE="./.env.core"

if [[ ! -f "$CORE_ENV_FILE" ]]; then
  print_fail ".env.core не найден: ${CORE_ENV_FILE}"
  echo "   Создай core/.env.core и повтори."
  exit 1
fi

print_ok ".env.core: found (${CORE_ENV_FILE})"

# ----------------------------
# Чтение env-значений (без source)
# ----------------------------
get_env_value() {
  local env_file_path="$1"
  local key="$2"

  grep -E "^${key}=" "$env_file_path" 2>/dev/null | tail -n 1 | cut -d'=' -f2- || true
}

# ----------------------------
# Достаём ключевые переменные из .env.core
# ----------------------------
CORE_NETWORK_NAME="$(get_env_value "$CORE_ENV_FILE" "CORE_NETWORK_NAME")"
PROXY_CONTAINER_NAME="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_PROXY")"
GITEA_CONTAINER_NAME="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_GITEA")"
DNS_CONTAINER_NAME="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_DNS")"

# Фоллбеки на случай пустых значений
CORE_NETWORK_NAME="${CORE_NETWORK_NAME:-net-core}"
PROXY_CONTAINER_NAME="${PROXY_CONTAINER_NAME:-core_proxy}"
GITEA_CONTAINER_NAME="${GITEA_CONTAINER_NAME:-core_gitea}"
DNS_CONTAINER_NAME="${DNS_CONTAINER_NAME:-core_dns}"

print_ok "Core network (CORE_NETWORK_NAME): ${CORE_NETWORK_NAME}"
print_ok "Proxy container (DCN_CORE_PROXY): ${PROXY_CONTAINER_NAME}"
print_ok "Gitea container (DCN_CORE_GITEA): ${GITEA_CONTAINER_NAME}"
print_ok "DNS container (DCN_CORE_DNS): ${DNS_CONTAINER_NAME}"

# ----------------------------
# Проверка Docker
# ----------------------------
if ! command -v docker >/dev/null 2>&1; then
  print_fail "Docker не найден. Сначала запусти bootstrap/bootstrap.sh"
  exit 1
fi

echo ""

# ----------------------------
# 1) Проверяем наличие сети
# ----------------------------
echo "1) 🌐 Docker network: ${CORE_NETWORK_NAME}"
if docker network inspect "$CORE_NETWORK_NAME" >/dev/null 2>&1; then
  print_ok "Network exists"
else
  print_fail "Network not found: ${CORE_NETWORK_NAME}"
  echo "   Запусти: ./core.up.sh (он создаст сеть автоматически)"
  exit 1
fi

echo ""

# ----------------------------
# 2) Проверяем, что core контейнеры существуют и запущены
# ----------------------------
echo "2) 🧩 Containers status"

check_container_running() {
  local container_name="$1"

  if ! docker inspect "$container_name" >/dev/null 2>&1; then
    print_fail "Container not found: ${container_name}"
    return 1
  fi

  local is_running
  is_running="$(docker inspect -f '{{.State.Running}}' "$container_name")"

  if [[ "$is_running" == "true" ]]; then
    print_ok "${container_name}: running"
    return 0
  fi

  print_fail "${container_name}: NOT running"
  echo "   Подсказка: docker logs ${container_name} --tail=200"
  return 1
}

HAS_ERRORS="false"

CORE_CONTAINERS=(
  "$PROXY_CONTAINER_NAME"
  "$GITEA_CONTAINER_NAME"
  "$DNS_CONTAINER_NAME"
)

for c in "${CORE_CONTAINERS[@]}"; do
  if ! check_container_running "$c"; then
    HAS_ERRORS="true"
  fi
done

echo ""

# ----------------------------
# 3) Проверяем, что core контейнеры подключены к одной сети
# ----------------------------
echo "3) 🔗 Network attachments"

check_container_in_network() {
  local container_name="$1"
  local network_name="$2"

  local networks
  networks="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{printf "%s\n" $k}}{{end}}' "$container_name")"

  if echo "$networks" | grep -qx "$network_name"; then
    print_ok "${container_name}: connected to ${network_name}"
    return 0
  fi

  print_fail "${container_name}: NOT connected to ${network_name}"
  echo "   Проверь docker-compose.yml: networks + external: true + name: \${CORE_NETWORK_NAME}"
  return 1
}

for c in "${CORE_CONTAINERS[@]}"; do
  if ! check_container_in_network "$c" "$CORE_NETWORK_NAME"; then
    HAS_ERRORS="true"
  fi
done

echo ""

# ----------------------------
# 4) Делегированные сервисные проверки (optional)
# ----------------------------
# Комментарий:
#   По принципу единой ответственности:
#   - core.check.sh делает только общие проверки core-слоя
#   - сервисные проверки живут рядом с сервисами и запускаются отдельно
#   - здесь мы просто оркестрируем запуск (warn + skip если нет файла)
echo "4) 🧪 Delegated service checks (optional)"

run_check_if_exists() {
  local script_path="$1"

  if [[ -x "$script_path" ]]; then
    if "$script_path"; then
      print_ok "Service check passed: ${script_path}"
    else
      print_fail "Service check failed: ${script_path}"
      HAS_ERRORS="true"
    fi
  else
    print_warn "Service check not found or not executable (skip): ${script_path}"
  fi
}

run_check_if_exists "./dns/dns.check.sh"
run_check_if_exists "./proxy/proxy.check.sh"
run_check_if_exists "./gitea/gitea.check.sh"

echo ""

if [[ "$HAS_ERRORS" == "true" ]]; then
  print_fail "CORE checks finished with errors"
  exit 1
fi

print_ok "CORE checks passed!"