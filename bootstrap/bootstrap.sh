#!/usr/bin/env bash
# ============================================================
# BOOTSTRAP SCRIPT
#
# Назначение:
#   Подготовка чистого Ubuntu Server для работы с IaC.
#
# ЧТО ДЕЛАЕТ:
#   - Обновляет систему
#   - Устанавливает базовые системные пакеты
#   - Устанавливает Git (CLI)
#   - Устанавливает Docker и Docker Compose (официально)
#   - Настраивает пользователя для работы с Docker
#   - Включает базовый firewall (SSH only)
#
# Этот скрипт запускается ОДИН РАЗ на ВМ.
# ============================================================

set -euo pipefail

# ----------------------------
# Проверка запуска с root / sudo
# ----------------------------
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Скрипт должен быть запущен с sudo или от root"
  exit 1
fi

echo "🚀 Starting bootstrap process..."

# ----------------------------
# Определяем пользователя,
# под которым будем работать дальше
# ----------------------------
TARGET_USER="${SUDO_USER:-root}"

echo "👤 Target user: $TARGET_USER"

# ----------------------------
# Обновление системы
# ----------------------------
echo "🔄 Updating system packages..."
apt update
apt upgrade -y

# ----------------------------
# Установка базовых пакетов
# ----------------------------
# ca-certificates  — доверие HTTPS
# curl             — загрузка скриптов и API
# gnupg            — проверка подписей пакетов
# lsb-release      — определение версии Ubuntu
# git              — IaC невозможен без git
# ufw              — базовая защита сервера
echo "📦 Installing base packages..."
apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  ufw

# ----------------------------
# Установка Docker (официальный способ)
# ----------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "🐳 Installing Docker..."
  curl -fsSL https://get.docker.com | sh
else
  echo "ℹ️ Docker already installed — skipping"
fi

# ----------------------------
# Проверка Docker Compose plugin
# ----------------------------
if ! docker compose version >/dev/null 2>&1; then
  echo "❌ Docker Compose plugin not found"
  exit 1
fi

echo "✅ Docker and Docker Compose are installed"

# ----------------------------
# Добавление пользователя в группу docker
# ----------------------------
# Это позволяет работать с docker без sudo
if id "$TARGET_USER" &>/dev/null; then
  if ! groups "$TARGET_USER" | grep -q "\bdocker\b"; then
    echo "👥 Adding user '$TARGET_USER' to docker group..."
    usermod -aG docker "$TARGET_USER"
  else
    echo "ℹ️ User '$TARGET_USER' already in docker group"
  fi
fi

# ----------------------------
# Настройка Firewall (UFW)
# ----------------------------
# ВАЖНО:
#   Мы открываем ТОЛЬКО SSH.
#   HTTP/HTTPS и прочее будет открываться
#   на уровне core-infra (reverse proxy).
echo "🔐 Configuring UFW firewall..."
ufw allow OpenSSH
ufw --force enable

# ----------------------------
# Финал
# ----------------------------
echo "✅ Bootstrap completed successfully!"
echo ""
echo "⚠️  ВАЖНО:"
echo "   - Выйди из SSH-сессии и зайди снова"
echo "   - Это необходимо для применения docker group"
echo ""
