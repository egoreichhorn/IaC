#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GITEA CHECK (IaC)
#
# Назначение:
#   Проверяет, что Gitea поднята корректно в рамках core-инфраструктуры:
#   - compose валиден (с учётом env-файла core/.env.core)
#   - контейнер запущен и healthy
#   - HTTP доступен на localhost:${GITEA_HTTP_PORT}
#   - данные и конфиги сохранены в volumes (gitea_data, gitea_config)
#
# Принцип:
#   READ-ONLY: НЕ меняет систему, только проверяет и печатает статус.
#
# Опционально:
#   --with-ssh-check  -> проверит, что порт SSH слушается на хосте (GITEA_SSH_PORT)
#   --with-api-check  -> проверит /api/healthz (если endpoint доступен)
# ============================================================

WITH_SSH_CHECK="false"
WITH_API_CHECK="false"

for arg in "$@"; do
  if [[ "$arg" == "--with-ssh-check" ]]; then
    WITH_SSH_CHECK="true"
  fi
  if [[ "$arg" == "--with-api-check" ]]; then
    WITH_API_CHECK="true"
  fi
done

print_ok()   { echo "✅ $1"; }
print_warn() { echo "⚠️  $1"; }
print_fail() { echo "❌ $1"; }

HAS_ERRORS="false"

check_cmd() {
  local cmd="$1"
  local title="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    print_ok "$title: found ($(command -v "$cmd"))"
    return 0
  fi

  print_fail "$title: not found"
  return 1
}

check_file_exists() {
  local path="$1"
  local title="$2"

  if [[ -f "$path" ]]; then
    print_ok "$title: exists ($path)"
    return 0
  fi

  print_fail "$title: missing ($path)"
  return 1
}

check_container_exists() {
  local name="$1"
  local title="$2"

  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    print_ok "$title: exists ($name)"
    return 0
  fi

  print_fail "$title: not found ($name)"
  return 1
}

check_container_running() {
  local name="$1"
  local title="$2"

  if docker ps --format '{{.Names}}' | grep -qx "$name"; then
    print_ok "$title: running"
    return 0
  fi

  print_fail "$title: NOT running"
  return 1
}

check_container_healthy() {
  local name="$1"
  local title="$2"

  # Если healthcheck не задан, поле будет пустым -> предупредим
  local status
  status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null || true)"

  if [[ -z "${status:-}" ]]; then
    print_warn "$title: no healthcheck configured"
    return 0
  fi

  if [[ "$status" == "healthy" ]]; then
    print_ok "$title: healthy"
    return 0
  fi

  print_fail "$title: NOT healthy (status: ${status})"
  return 1
}

check_http() {
  local url="$1"
  local title="$2"

  if curl -sf "$url" >/dev/null 2>&1; then
    print_ok "$title: OK ($url)"
    return 0
  fi

  print_fail "$title: FAILED ($url)"
  return 1
}

get_env_value() {
  # ------------------------------------------------------------
  # Читает значение KEY из указанного env-файла
  #
  # Почему так:
  # - мы используем единый IaC env-файл core/.env.core
  # - gitea.check.sh должен проверять систему в том же контексте,
  #   что и core.up.sh (иначе проверки будут "в вакууме")
  # ------------------------------------------------------------
  local env_file_path="$1"
  local key="$2"

  # Берём последнюю встреченную строку KEY=... (на случай дублей)
  grep -E "^${key}=" "$env_file_path" 2>/dev/null | tail -n 1 | cut -d'=' -f2- || true
}

echo "🔎 Gitea checks started..."
echo "👤 User: $(whoami)"
echo "📁 Dir:  $(pwd)"
echo ""

# ------------------------------------------------------------
# Переходим в директорию скрипта (core/gitea)
# ------------------------------------------------------------
cd "$(dirname "$0")"

# ------------------------------------------------------------
# IaC env-файл на уровне core/
# ------------------------------------------------------------
# Комментарий:
#   У тебя единый env-файл для core-инфраструктуры.
#   Он лежит в директории core/ рядом с core.up.sh
CORE_ENV_FILE="../.env.core"

# 1) Базовые зависимости
if ! check_cmd "docker" "Docker CLI"; then
  HAS_ERRORS="true"
else
  print_ok "Docker version: $(docker --version)"
fi

if docker compose version >/dev/null 2>&1; then
  print_ok "Docker Compose plugin: $(docker compose version)"
else
  print_fail "Docker Compose plugin: not available (docker compose version failed)"
  HAS_ERRORS="true"
fi

if ! check_cmd "curl" "curl"; then
  HAS_ERRORS="true"
fi

echo ""

# 2) Проверка файлов
if ! check_file_exists "./docker-compose.yml" "docker-compose.yml"; then
  HAS_ERRORS="true"
fi

# Комментарий:
#   Раньше скрипт ожидал локальный ./ .env, но теперь у нас IaC-источник один — core/.env.core.
if ! check_file_exists "$CORE_ENV_FILE" ".env.core (core infrastructure env)"; then
  HAS_ERRORS="true"
fi

echo ""

# 3) Читаем параметры из core/.env.core
# Комментарий:
#   Важно: имя контейнера больше не "gitea", а берётся из DCN_CORE_GITEA.
GITEA_CONTAINER_NAME="$(get_env_value "$CORE_ENV_FILE" "DCN_CORE_GITEA")"
GITEA_HTTP_PORT="$(get_env_value "$CORE_ENV_FILE" "GITEA_HTTP_PORT")"
GITEA_SSH_PORT="$(get_env_value "$CORE_ENV_FILE" "GITEA_SSH_PORT")"

# Фоллбеки (на случай если переменная отсутствует в env)
GITEA_CONTAINER_NAME="${GITEA_CONTAINER_NAME:-gitea}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-2222}"

print_ok "Container name (DCN_CORE_GITEA): ${GITEA_CONTAINER_NAME}"
print_ok "HTTP port (GITEA_HTTP_PORT): ${GITEA_HTTP_PORT}"
print_ok "SSH port  (GITEA_SSH_PORT):  ${GITEA_SSH_PORT}"

echo ""

# 4) Проверка валидности compose (с учётом env-файла)
# Комментарий:
#   Это критично: иначе ${...} в compose не подставятся, и проверка будет ложной.
if docker compose --env-file "$CORE_ENV_FILE" config >/dev/null 2>&1; then
  print_ok "docker compose config: valid (with ${CORE_ENV_FILE})"
else
  print_fail "docker compose config: invalid (check yaml and env vars in ${CORE_ENV_FILE})"
  HAS_ERRORS="true"
fi

echo ""

# 5) Контейнер
if check_container_exists "$GITEA_CONTAINER_NAME" "Container"; then
  if ! check_container_running "$GITEA_CONTAINER_NAME" "Container status"; then
    HAS_ERRORS="true"
  fi

  if ! check_container_healthy "$GITEA_CONTAINER_NAME" "Healthcheck"; then
    HAS_ERRORS="true"
  fi
else
  HAS_ERRORS="true"
fi

echo ""

# 6) HTTP доступность (по localhost на сервере)
if ! check_http "http://localhost:${GITEA_HTTP_PORT}/" "HTTP"; then
  HAS_ERRORS="true"
fi

# Optional: API healthcheck (если endpoint доступен)
if [[ "$WITH_API_CHECK" == "true" ]]; then
  if check_http "http://localhost:${GITEA_HTTP_PORT}/api/healthz" "API healthz"; then
    :
  else
    # Не делаем фаталом: на разных версиях/конфигах может отличаться
    print_warn "API healthz: endpoint may be unavailable on this setup"
  fi
else
  print_warn "API healthz: skipped (run with --with-api-check to enable)"
fi

echo ""

# 7) Проверка volumes (критично)
# Комментарий:
#   Мы проверяем именно именованные volumes, которые ты зафиксировал через name:
#   - gitea_config должен содержать app.ini
#   - gitea_data должен содержать data/
if docker volume inspect gitea_config >/dev/null 2>&1; then
  if docker run --rm -v gitea_config:/etc alpine test -f /etc/app.ini >/dev/null 2>&1; then
    print_ok "Volume gitea_config: app.ini persisted"
  else
    print_fail "Volume gitea_config: app.ini NOT found (install wizard will appear)"
    HAS_ERRORS="true"
  fi
else
  print_fail "Volume gitea_config: missing (docker volume inspect failed)"
  HAS_ERRORS="true"
fi

if docker volume inspect gitea_data >/dev/null 2>&1; then
  if docker run --rm -v gitea_data:/data alpine test -d /data/data >/dev/null 2>&1; then
    print_ok "Volume gitea_data: data directory exists"
  else
    print_fail "Volume gitea_data: data directory missing"
    HAS_ERRORS="true"
  fi

  if docker run --rm -v gitea_data:/data alpine test -f /data/data/gitea.db >/dev/null 2>&1; then
    print_ok "Volume gitea_data: gitea.db found"
  else
    print_warn "Volume gitea_data: gitea.db not found (DB might be external or path differs)"
  fi
else
  print_fail "Volume gitea_data: missing (docker volume inspect failed)"
  HAS_ERRORS="true"
fi

echo ""

# 8) Optional: SSH port listening check on host
if [[ "$WITH_SSH_CHECK" == "true" ]]; then
  if command -v ss >/dev/null 2>&1; then
    if ss -lnt | grep -Eq "[:.]${GITEA_SSH_PORT}\s"; then
      print_ok "SSH port: listening on ${GITEA_SSH_PORT}"
    else
      print_fail "SSH port: NOT listening on ${GITEA_SSH_PORT}"
      HAS_ERRORS="true"
    fi
  else
    print_warn "SSH port: skipped (ss not installed)"
  fi
else
  print_warn "SSH port: skipped (run with --with-ssh-check to enable)"
fi

echo ""
if [[ "$HAS_ERRORS" == "true" ]]; then
  print_fail "Gitea checks finished with errors"
  exit 1
fi

print_ok "Gitea checks finished successfully"
