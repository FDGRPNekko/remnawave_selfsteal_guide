# Руководство по развертыванию SelfSteal ноды на Remnawave

Полное пошаговое руководство по развертыванию SelfSteal ноды на платформе Remnawave, включая полный процесс настройки самой платформы Remnawave. Это руководство охватывает предварительные требования, установку, конфигурацию и советы по устранению неполадок для обеспечения плавного и безопасного развертывания.

## 📋 Предварительные требования

- Два отдельных VPS-сервера, соответствующих [системным требованиям](https://remna.st/docs/install/requirements)
- Доменные имена для панели управления и подписок
- Базовые знания работы с Linux и Docker

---

## 🚀 Часть 1: Настройка панели управления Remnawave

### Шаг 0 — Обновление системы и установка необходимых инструментов

```bash
apt update && apt upgrade -y && apt install curl -y
```

### Шаг 1 — Установка Docker

```bash
curl -fsSL https://get.docker.com | sh
```

### Шаг 2 — Загрузка необходимых файлов

```bash
mkdir -p /opt/remnawave && cd /opt/remnawave
curl -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
curl -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample
```

### Шаг 3 — Настройка переменных окружения

```bash
# Генерация JWT секретов
sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env

# Генерация дополнительных секретов
sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

# Обновление пароля PostgreSQL
pw=$(openssl rand -hex 24)
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env
```

**Настройка доменов:**
```bash
nano .env
```

Обновите следующие значения в файле `.env`:
```env
FRONT_END_DOMAIN="panel.yourdomain.com"
SUB_PUBLIC_DOMAIN="sub.yourdomain.com"
```

### Шаг 4 — Запуск стека

```bash
docker compose up -d && docker compose logs -f -t
```

### Шаг 5 — Настройка DNS

Настройте DNS записи для ваших доменов, указав их на IP-адрес вашего сервера.

---

## 🌐 Часть 2: Настройка Caddy (обратный прокси)

### Создание конфигурации Caddy

```bash
mkdir -p /opt/remnawave/caddy && cd /opt/remnawave/caddy
nano Caddyfile
```

**Содержимое Caddyfile:**
```caddy
https://REPLACE_WITH_YOUR_DOMAIN {
    reverse_proxy * http://remnawave:3000
}
:443 {
    tls internal
    respond 204
}

https://SUBSCRIPTION_PAGE_DOMAIN {
    reverse_proxy * http://remnawave-subscription-page:3010
}
```

### Создание docker-compose.yml для Caddy

```bash
nano docker-compose.yml
```

```yaml
services:
    caddy:
        image: caddy:2.9
        container_name: 'caddy'
        hostname: caddy
        restart: always
        ports:
            - '0.0.0.0:443:443'
            - '0.0.0.0:80:80'
        networks:
            - remnawave-network
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - caddy-ssl-data:/data

networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true

volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
```

### Запуск Caddy

```bash
docker compose up -d && docker compose logs -f -t
```

---

## 📄 Часть 3: Страница подписок Remnawave

```bash
mkdir -p /opt/remnawave/subscription && cd /opt/remnawave/subscription
nano docker-compose.yml
```

**Содержимое docker-compose.yml:**
```yaml
services:
    remnawave-subscription-page:
        image: remnawave/subscription-page:latest
        container_name: remnawave-subscription-page
        hostname: remnawave-subscription-page
        restart: always
        environment:
            - REMNAWAVE_PANEL_URL=https://panel.com
            - APP_PORT=3010
            - META_TITLE="Subscription Page Title"
            - META_DESCRIPTION="Subscription Page Description"
        ports:
            - '127.0.0.1:3010:3010'
        networks:
            - remnawave-network

networks:
    remnawave-network:
        driver: bridge
        external: true
```

### Запуск контейнера страницы подписок

```bash
docker compose up -d && docker compose logs -f
```

---

## 🔧 Часть 4: Настройка ноды Remnawave

*Выполняется на втором VPS сервере*

### Базовая настройка

```bash
apt update && apt upgrade -y && apt install curl -y
curl -fsSL https://get.docker.com | sh
```

### Создание рабочей директории

```bash
mkdir -p /opt/remnanode && cd /opt/remnanode
```

### Настройка переменных окружения

```bash
nano .env
```

**Содержимое .env:**
```env
APP_PORT=2222
SSL_CERT=CERT_FROM_MAIN_PANEL
```

### Создание docker-compose.yml

```bash
nano docker-compose.yml
```

**Содержимое docker-compose.yml:**
```yaml
services:
    remnanode:
        container_name: remnanode
        hostname: remnanode
        image: remnawave/node:latest
        restart: always
        network_mode: host
        env_file:
            - .env
```

### Запуск ноды

```bash
docker compose up -d && docker compose logs -f
```

---

## 🛡️ Часть 5: Настройка SelfSteal (SNI)

### Создание рабочей директории

```bash
mkdir -p /opt/selfsteel && cd /opt/selfsteel
nano Caddyfile
```

**Содержимое Caddyfile:**
```caddy
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
```

### Настройка переменных окружения

```bash
nano .env
```

**Содержимое .env:**
```env
SELF_STEAL_DOMAIN=steel.domain.com    # Должен совпадать с XRAY realitySettings.serverNames
SELF_STEAL_PORT=9443                  # Должен совпадать с XRAY realitySettings.dest
```

### Создание docker-compose.yml для SelfSteal

```bash
nano docker-compose.yml
```

```yaml
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ../html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
```

### Создание placeholder сайта

```bash
mkdir -p /opt/html
printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Selfsteal</title><h1>It works.</h1>' > /opt/html/index.html
```

### Запуск SelfSteal

```bash
docker compose up -d && docker compose logs -f -t
```

---

## ⚡ Часть 6: Конфигурация Xray (Reality)

*Обновляется через панель управления*

```json
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "tag": "Shadowsocks",
      "port": 1234,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "tag": "VLESS",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": false,
        "destOverride": [
          "http",
          "tls",
          "quic",
          "fakedns"
        ],
        "metadataOnly": false
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": {
          "header": {
            "type": "none"
          },
          "acceptProxyProtocol": false
        },
        "realitySettings": {
          "dest": "9443",
          "show": false,
          "xver": 0,
          "spiderX": "/",
          "shortIds": [
            "CHANGE_ME_SHORTID"
          ],
          "publicKey": "CHANGE_ME_PUBLIC_KEY",
          "privateKey": "CHANGE_ME_PRIVATE_KEY",
          "fingerprint": "chrome",
          "serverNames": [
            "steel.domen.com"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "DIRECT",
      "protocol": "freedom"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "type": "field",
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "domain": [
          "geosite:private"
        ],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "BLOCK"
      }
    ]
  }
}
```

---

## 🔍 Советы по устранению неполадок

1. **Проверка логов:** Всегда проверяйте логи после запуска контейнеров
2. **Состояние контейнеров:** Убедитесь, что все контейнеры работают (`docker ps`)
3. **Сетевые настройки:** Проверьте, что все сервисы находятся в одной сети
4. **DNS записи:** Убедитесь, что DNS записи propagated правильно

---

## 📝 Примечания

- Shadowsocks inbound является опциональным и может быть удален в будущем
- Все секретные ключи генерируются автоматически для безопасности
- Убедитесь, что порты на сервере открыты и не блокируются фаерволом

Для дополнительной помощи посетите [официальную документацию Remnawave](https://remna.st/docs).
