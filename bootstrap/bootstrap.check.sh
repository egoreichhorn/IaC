#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BOOTSTRAP CHECK
#
# Назначение:
#   Проверяет, что сервер подготовлен для IaC после bootstrap.sh
#
# Принцип:
#   READ-ONLY: НЕ меняет систему, только проверяет и печатает статус.
#
# Опционально:
#   --with-pull-test  -> выполнит docker run hello-world (требует доступ в сеть)
# ============================================================

WITH_PULL_TEST="false"
for arg in "$@"; do
  if [[ "$arg" == "--with-pull-test" ]]; then
    WITH_PULL_TEST="true"
  fi
done

print_ok()   { echo "✅ $1"; }
print_warn() { echo "⚠️  $1"; }
print_fail() { echo "❌ $1"; }

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

check_group_contains() {
  local group="$1"
  local title="$2"

  if groups | grep -q "\b${group}\b"; then
    print_ok "$title: user is in '$group' group"
    return 0
  fi

  print_fail "$title: user is NOT in '$group' group (re-login required?)"
  return 1
}

check_systemd_active() {
  local service="$1"
  local title="$2"

  if systemctl is-active --quiet "$service"; then
    print_ok "$title: active"
    return 0
  fi

  print_fail "$title: NOT active"
  return 1
}

echo "🔎 Bootstrap checks started..."
echo "👤 User: $(whoami)"
echo ""

HAS_ERRORS="false"

# 1) Git
if ! check_cmd "git" "Git CLI"; then
  HAS_ERRORS="true"
else
  print_ok "Git version: $(git --version)"
fi
echo ""

# 2) Docker
if ! check_cmd "docker" "Docker CLI"; then
  HAS_ERRORS="true"
else
  print_ok "Docker version: $(docker --version)"
fi

# docker group
if ! check_group_contains "docker" "Docker permissions"; then
  HAS_ERRORS="true"
fi

# docker daemon
if ! check_systemd_active "docker" "Docker daemon"; then
  HAS_ERRORS="true"
fi

# docker compose
if docker compose version >/dev/null 2>&1; then
  print_ok "Docker Compose plugin: $(docker compose version)"
else
  print_fail "Docker Compose plugin: not available (docker compose version failed)"
  HAS_ERRORS="true"
fi

# docker ps (permission test)
if docker ps >/dev/null 2>&1; then
  print_ok "Docker access: docker ps works without sudo"
else
  print_fail "Docker access: docker ps failed (permission denied?)"
  HAS_ERRORS="true"
fi

echo ""

# 3) UFW (может быть не установлен/не включен — но bootstrap должен был)
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS="$(sudo ufw status 2>/dev/null | head -n 1 || true)"
  if echo "$UFW_STATUS" | grep -qi "active"; then
    print_ok "UFW: active"
  else
    print_warn "UFW: not active (status: ${UFW_STATUS:-unknown})"
  fi
else
  print_warn "UFW: not installed"
fi

echo ""

# 4) Optional: hello-world pull/run test
if [[ "$WITH_PULL_TEST" == "true" ]]; then
  echo "🐳 Running docker hello-world (requires network access)..."
  if docker run --rm hello-world >/dev/null 2>&1; then
    print_ok "hello-world: success"
  else
    print_fail "hello-world: failed (no network? docker issues?)"
    HAS_ERRORS="true"
  fi
else
  print_warn "hello-world: skipped (run with --with-pull-test to enable)"
fi

echo ""
if [[ "$HAS_ERRORS" == "true" ]]; then
  print_fail "Bootstrap checks finished with errors"
  exit 1
fi

print_ok "Bootstrap checks finished successfully"
