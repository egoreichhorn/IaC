3) core/gitea/README.md
# Gitea (LAN) — core-infra

## Назначение

Этот модуль поднимает Gitea как сервис уровня core-infra
для локальной корпоративной сети (LAN).

На этом этапе:
- доступ по IP + порту (без доменов и HTTPS);
- позже будет добавлен reverse proxy (core/proxy), который даст доменные имена и TLS.

---

## Быстрый старт

### 1) Подготовить конфиг окружения

Скопируй `.env.example` → `.env`:

```bash
cp .env.example .env


В .env обязательно:

выстави SERVER_IP (LAN IP сервера)

проверь GITEA_USER_UID и GITEA_USER_GID

Проверить UID/GID на сервере:

id -u
id -g

2) Запуск
docker compose up -d


Проверка статуса:

docker compose ps
docker logs -n 50 gitea

Доступ
Web UI

Открыть в браузере (с ПК в локальной сети):

http://SERVER_IP:3000

Git по SSH (рекомендуется)

Мы публикуем SSH на порту 2222 (чтобы не конфликтовать с SSH сервера).

Пример клона:

git clone ssh://git@SERVER_IP:2222/<user>/<repo>.git

Остановка и удаление

Остановить:

docker compose down


Удалить контейнеры (данные останутся в volume):

docker compose down


Удалить данные (ОСТОРОЖНО, это удалит репозитории и настройки):

docker volume rm gitea_data

Примечания по архитектуре

Данные Gitea хранятся в Docker volume gitea_data.

Конфиги хранятся в репозитории IaC.

Домен/HTTPS будут добавлены позже через reverse proxy.


---

# Как это применить у тебя прямо сейчас

1) Создай файлы в `core/gitea/` как выше  
2) На сервере (в каталоге `core/gitea`) сделай:

```bash
cp .env.example .env
nano .env


Поставь корректный SERVER_IP и (если нужно) UID/GID.

Запусти:

docker compose up -d


Проверь:

docker compose ps


Открой в браузере:

http://SERVER_IP:3000