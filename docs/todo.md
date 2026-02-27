У меня не работает DNS остановились на том что
при запуске контейнер gitea не поднимается

egor@dockerserver:~/infrastructure/core$ ./core.check.sh
🔍 Checking CORE infrastructure...
✅ .env.core: found (./.env.core)
✅ Core network (CORE_NETWORK_NAME): net-core
✅ Proxy container (DCN_CORE_PROXY): core_proxy
✅ Gitea container (DCN_CORE_GITEA): core_gitea
✅ DNS container (DCN_CORE_DNS): core_dns

1) 🌐 Docker network: net-core
   ✅ Network exists

2) 🧩 Containers status
   ✅ core_proxy: running
   ❌ core_gitea: NOT running
   Подсказка: docker logs core_gitea --tail=200
   ✅ core_dns: running

3) 🔗 Network attachments
   ✅ core_proxy: connected to net-core
   ✅ core_gitea: connected to net-core
   ✅ core_dns: connected to net-core

4) 🧪 Delegated service checks (optional)
   🔍 Checking CORE DNS...
   ✅ DNS container (DCN_CORE_DNS): core_dns
   ✅ DNS host IP (DNS_HOST_IP): 192.168.88.234
   ✅ DNS host port (DNS_HOST_PORT): 5353
   ✅ Local zone (LOCAL_DNS_ZONE): egor.lan
   ✅ Test FQDN: gitea.egor.lan

1) 🧩 Container status: core_dns
   ✅ Container is running

2) 🌐 Port publish check (5353 -> 53/tcp, 53/udp)
   ✅ 53/tcp published: 0.0.0.0:5353
   [::]:5353
   ✅ 53/udp published: 0.0.0.0:5353
   [::]:5353

3) 📡 Local zone resolution via 127.0.0.1:5353
   ❌ Local zone failed: got '' expected '192.168.88.234'
   ❌ Service check failed: ./dns/dns.check.sh
   🔎 Proxy checks started...
   ✅ .env.core: found (../.env.core)
   ✅ Container name (DCN_CORE_PROXY): core_proxy
   ✅ Core network (CORE_NETWORK_NAME): net-core
   ✅ Gitea domain (GITEA_DOMAIN): gitea.egor.lan

✅ Caddyfile: found
🔍 Validating Caddyfile...
{"level":"info","ts":1771185689.3370783,"msg":"using config from file","file":"/etc/caddy/Caddyfile"}
{"level":"info","ts":1771185689.3377323,"msg":"adapted config to JSON","adapter":"caddyfile"}
{"level":"warn","ts":1771185689.3377414,"msg":"Caddyfile input is not formatted; run 'caddy fmt --overwrite' to fix inconsistencies","adapter":"caddyfile","file":"/etc/caddy/Caddyfile","line":2}
{"level":"info","ts":1771185689.3379672,"logger":"tls.cache.maintenance","msg":"started background certificate maintenance","cache":"0x4000137a00"}
{"level":"info","ts":1771185689.3389952,"logger":"http.auto_https","msg":"server is listening only on the HTTPS port but has no TLS connection policies; adding one to enable TLS","server_name":"srv0","https_port":443}
{"level":"info","ts":1771185689.3390067,"logger":"http.auto_https","msg":"enabling automatic HTTP->HTTPS redirects","server_name":"srv0"}
{"level":"info","ts":1771185689.339073,"logger":"tls.cache.maintenance","msg":"stopped background certificate maintenance","cache":"0x4000137a00"}
✅ Caddyfile: valid

🌐 Docker network: net-core
✅ Network exists

📦 Container: core_proxy
✅ Container running

🔌 Network attachment check...
✅ Attached to net-core

🌍 Port 80 listener check...
✅ Port 80 is listening

🌐 HTTP route check (Host: gitea.egor.lan)...
✅ HTTP response status looks OK
⚠️  Response does not look like Gitea (maybe login redirect or other service).
Это не всегда ошибка, но стоит проверить в браузере: http://gitea.egor.lan

✅ Proxy checks finished successfully
✅ Service check passed: ./proxy/proxy.check.sh
🔎 Gitea checks started...
👤 User: egor
📁 Dir:  /home/egor/infrastructure/core

✅ Docker CLI: found (/usr/bin/docker)
✅ Docker version: Docker version 29.2.0, build 0b9d198
✅ Docker Compose plugin: Docker Compose version v5.0.2
✅ curl: found (/usr/bin/curl)

✅ docker-compose.yml: exists (./docker-compose.yml)
✅ .env.core (core infrastructure env): exists (../.env.core)

✅ Container name (DCN_CORE_GITEA): core_gitea
✅ HTTP port (GITEA_HTTP_PORT): 3000
✅ SSH port  (GITEA_SSH_PORT):  2222

✅ docker compose config: valid (with ../.env.core)

✅ Container: exists (core_gitea)
❌ Container status: NOT running
❌ Healthcheck: NOT healthy (status: unhealthy)

❌ HTTP: FAILED (http://localhost:3000/)
⚠️  API healthz: skipped (run with --with-api-check to enable)

✅ Volume gitea_config: app.ini persisted
✅ Volume gitea_data: data directory exists
✅ Volume gitea_data: gitea.db found