#!/usr/bin/env bash
# Remnawave Node + SelfSteal
# FreezeDev — https://github.com/FDGRPNekko

set -euo pipefail

NODE_DIR=/opt/remnanode
STEAL_DIR=/opt/selfsteal
HTML_DIR=/opt/html

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
D='\033[0;90m'
N='\033[0m'
B='\033[1m'

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${R}запусти от root: sudo bash $0${N}"
    exit 1
  fi
}

pause() {
  echo
  read -rp "enter чтобы продолжить... " _
}

ask() {
  local p=$1 d=${2:-} a
  if [[ -n $d ]]; then
    read -rp "$p [$d]: " a
    echo "${a:-$d}"
  else
    read -rp "$p: " a
    echo "$a"
  fi
}

yn() {
  local p=$1 d=${2:-n} a
  while true; do
    read -rp "$p (y/n) [$d]: " a
    a=${a:-$d}
    case ${a,,} in
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
    esac
    echo "y или n"
  done
}

have_docker() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

ensure_docker() {
  if have_docker; then
    echo -e "${G}docker уже есть${N}"
    return
  fi
  echo -e "${Y}ставлю docker...${N}"
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates >/dev/null
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker >/dev/null 2>&1 || true
  if ! have_docker; then
    echo -e "${R}docker не встал, разберись руками${N}"
    exit 1
  fi
  echo -e "${G}docker ок${N}"
}

node_up() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx remnanode
}

steal_up() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx caddy-remnawave
}

node_installed() {
  [[ -f $NODE_DIR/docker-compose.yml ]] || node_up
}

steal_installed() {
  [[ -f $STEAL_DIR/docker-compose.yml ]] || steal_up
}

cpu_n() { nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo; }

ram_info() {
  local t u
  t=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
  u=$(awk '/MemAvailable/ {printf "%.1f", ($2)/1024/1024}' /proc/meminfo)
  echo "${t}G total / ${u}G free"
}

st_badge() {
  if $1; then echo -e "${G}online${N}"; else echo -e "${R}offline${N}"; fi
}

header() {
  clear
  echo -e "${C}╔══════════════════════════════════════════╗${N}"
  echo -e "${C}║${N}  ${B}Remnawave · Node + SelfSteal${N}           ${C}║${N}"
  echo -e "${C}║${N}  ${D}FreezeDev  github.com/FDGRPNekko${N}       ${C}║${N}"
  echo -e "${C}╚══════════════════════════════════════════╝${N}"
  echo
  echo -e "  cpu:  ${B}$(cpu_n)${N} ядер"
  echo -e "  ram:  ${B}$(ram_info)${N}"
  echo -e "  node: $(st_badge node_up)   selfsteal: $(st_badge steal_up)"
  echo
}

# --- node ---

write_node_compose() {
  local port=$1 key=$2
  mkdir -p "$NODE_DIR"
  # multiline ключ (сертификат) → yaml literal, однострочный — в кавычках
  if printf '%s' "$key" | grep -q $'\n'; then
    {
      echo "services:"
      echo "  remnanode:"
      echo "    container_name: remnanode"
      echo "    hostname: remnanode"
      echo "    image: remnawave/node:latest"
      echo "    restart: always"
      echo "    network_mode: host"
      echo "    environment:"
      echo "      NODE_PORT: \"${port}\""
      echo "      SECRET_KEY: |"
      printf '%s\n' "$key" | sed 's/^/        /'
    } >"$NODE_DIR/docker-compose.yml"
  else
    local esc=${key//\\/\\\\}
    esc=${esc//\"/\\\"}
    cat >"$NODE_DIR/docker-compose.yml" <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=${port}
      - SECRET_KEY="${esc}"
EOF
  fi
}

paste_compose() {
  local dest=$1
  echo
  echo -e "${Y}вставь docker-compose.yml целиком, потом Ctrl+D${N}"
  echo "----------------------------------------"
  mkdir -p "$(dirname "$dest")"
  if ! cat >"$dest"; then
    echo -e "${R}не записалось${N}"
    return 1
  fi
  if [[ ! -s $dest ]]; then
    echo -e "${R}пусто, отмена${N}"
    rm -f "$dest"
    return 1
  fi
  echo "----------------------------------------"
  echo -e "${G}записал $dest${N}"
}

read_secret() {
  echo
  echo -e "${D}вставь SECRET_KEY с панели, потом Ctrl+D${N}"
  echo "----------------------------------------"
  local key
  key=$(cat)
  echo "----------------------------------------"
  key=$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  printf '%s' "$key"
}

start_node() {
  cd "$NODE_DIR"
  docker compose pull
  docker compose up -d
  sleep 2
  if node_up; then
    echo
    echo -e "${G}нода поднялась${N}"
    docker compose ps
  else
    echo -e "${Y}контейнер не в online, логи:${N}"
    docker compose logs --tail=40 || true
  fi
}

install_node() {
  header
  echo -e "${B}установка ноды${N}"
  echo
  ensure_docker

  if node_installed && ! yn "нода уже есть, переустановить?" n; then
    return
  fi

  local port
  port=$(ask "порт ноды (NODE_PORT)" "2222")
  if ! [[ $port =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
    echo -e "${R}кривой порт${N}"
    pause
    return
  fi

  echo
  echo "как кинуть конфиг:"
  echo "  1) секретный ключ с панели"
  echo "  2) целиком docker-compose из Remnawave"
  local m
  m=$(ask "выбор" "1")

  case $m in
    2)
      paste_compose "$NODE_DIR/docker-compose.yml" || { pause; return; }
      # если в compose другой порт — подкрутим под то что ввели
      if grep -q 'NODE_PORT=' "$NODE_DIR/docker-compose.yml"; then
        sed -i -E "s/NODE_PORT=[0-9]+/NODE_PORT=${port}/" "$NODE_DIR/docker-compose.yml"
      fi
      ;;
    *)
      local key
      key=$(read_secret)
      if [[ -z $key ]]; then
        echo -e "${R}без ключа никак${N}"
        pause
        return
      fi
      write_node_compose "$port" "$key"
      ;;
  esac

  echo
  start_node
  echo
  echo -e "порт: ${B}${port}${N}  ·  dir: ${B}${NODE_DIR}${N}"
  echo -e "${D}в фаерволе NODE_PORT лучше открыть только под IP панели${N}"
  pause
}

nuke_node() {
  header
  echo -e "${B}снос ноды${N}"
  if ! node_installed; then
    echo "нечего сносить"
    pause
    return
  fi
  yn "точно снести remnanode?" n || { pause; return; }
  if [[ -f $NODE_DIR/docker-compose.yml ]]; then
    (cd "$NODE_DIR" && docker compose down --rmi local 2>/dev/null) || true
  fi
  docker rm -f remnanode 2>/dev/null || true
  rm -rf "$NODE_DIR"
  echo -e "${G}ноды больше нет${N}"
  pause
}

# --- selfsteal ---

write_steal_files() {
  local domain=$1 sport=$2
  mkdir -p "$STEAL_DIR/logs"

  cat >"$STEAL_DIR/.env" <<EOF
SELF_STEAL_DOMAIN=${domain}
SELF_STEAL_PORT=${sport}
EOF

  cat >"$STEAL_DIR/Caddyfile" <<'EOF'
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
EOF

  cat >"$STEAL_DIR/docker-compose.yml" <<EOF
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ${HTML_DIR}:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
EOF
}

make_stub() {
  mkdir -p "$HTML_DIR"
  cat >"$HTML_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Welcome</title>
<style>
  body{margin:0;min-height:100vh;display:grid;place-items:center;
       font:16px/1.5 system-ui,sans-serif;background:#0f1115;color:#e8eaed}
  main{max-width:36rem;padding:2rem;text-align:center}
  h1{font-weight:600;margin:0 0 .5rem}
  p{opacity:.7;margin:0}
</style>
</head>
<body>
<main>
  <h1>It works</h1>
  <p>Server is up.</p>
</main>
</body>
</html>
HTML
  echo -e "${G}заглушка → ${HTML_DIR}/index.html${N}"
}

wait_cert() {
  local domain=$1
  echo
  echo -e "${Y}жду сертификат для ${domain}...${N}"
  echo -e "${D}dns A → этот сервер, порт 80 снаружи должен быть живой${N}"
  echo

  local i=0 max=90 hit=0 logs
  while ((i < max)); do
    logs=$(docker logs caddy-remnawave 2>&1 || true)
    if echo "$logs" | grep -qiE 'certificate obtained successfully|successfully obtained certificate|obtained certificate'; then
      hit=1
      break
    fi
    # caddy 2 иногда так
    if echo "$logs" | grep -F "$domain" | grep -qiE 'serving|tls|certificate' \
      && ! echo "$logs" | grep -qiE 'error obtaining|challenge failed|timeout'; then
      if echo "$logs" | grep -qi 'certificate'; then
        hit=1
        break
      fi
    fi
    printf "\r  ждём... %ss   " "$((i * 2))"
    sleep 2
    i=$((i + 1))
  done
  echo

  if ((hit)); then
    echo -e "${G}сертификат успешно получен${N}"
    return 0
  fi

  echo -e "${Y}за $((max * 2))с в логах не поймал успех${N}"
  echo "хвост логов:"
  docker logs --tail=30 caddy-remnawave 2>&1 || true
  yn "пойти в меню всё равно?" y
}

install_steal() {
  header
  echo -e "${B}установка SelfSteal${N}"
  echo
  ensure_docker

  if steal_installed && ! yn "selfsteal уже стоит, переустановить?" n; then
    return
  fi

  local domain sport
  domain=$(ask "домен для selfsteal")
  if [[ -z $domain ]]; then
    echo -e "${R}домен обязателен${N}"
    pause
    return
  fi
  # прибьём схему если влепили
  domain=${domain#https://}
  domain=${domain#http://}
  domain=${domain%%/*}

  sport=$(ask "порт selfsteal (reality dest)" "9443")
  if ! [[ $sport =~ ^[0-9]+$ ]] || ((sport < 1 || sport > 65535)); then
    echo -e "${R}кривой порт${N}"
    pause
    return
  fi

  echo
  if yn "создать заглушку в ${HTML_DIR}?" y; then
    make_stub
  else
    mkdir -p "$HTML_DIR"
    if [[ ! -f $HTML_DIR/index.html ]]; then
      echo -e "${Y}${HTML_DIR} пустой — кинь туда свой сайт сам${N}"
    fi
  fi

  write_steal_files "$domain" "$sport"

  cd "$STEAL_DIR"
  docker compose pull
  docker compose up -d
  sleep 2

  if steal_up; then
    echo -e "${G}caddy-remnawave запущен${N}"
  else
    echo -e "${R}не поднялся, логи:${N}"
    docker compose logs --tail=40 || true
    pause
    return
  fi

  wait_cert "$domain" || true

  echo
  echo -e "domain: ${B}${domain}${N}"
  echo -e "port:   ${B}${sport}${N}  (в realitySettings.dest)"
  echo -e "sni:    ${B}${domain}${N}  (в realitySettings.serverNames)"
  echo -e "dir:    ${B}${STEAL_DIR}${N}"
  pause
}

nuke_steal() {
  header
  echo -e "${B}снос SelfSteal${N}"
  if ! steal_installed; then
    echo "нечего сносить"
    pause
    return
  fi
  yn "точно снести selfsteal (caddy)?" n || { pause; return; }
  if [[ -f $STEAL_DIR/docker-compose.yml ]]; then
    (cd "$STEAL_DIR" && docker compose down -v 2>/dev/null) || true
  fi
  docker rm -f caddy-remnawave 2>/dev/null || true
  rm -rf "$STEAL_DIR"
  if [[ -d $HTML_DIR ]] && yn "заодно снести ${HTML_DIR}?" n; then
    rm -rf "$HTML_DIR"
  fi
  echo -e "${G}selfsteal снесён${N}"
  pause
}

install_all() {
  install_node
  if ! node_up && ! yn "нода не online — всё равно ставить selfsteal?" n; then
    return
  fi
  install_steal
}

# --- menu ---

menu() {
  while true; do
    header
    echo "  1) поставить всё (нода + selfsteal)"
    echo "  2) только ноду"
    echo "  3) только selfsteal"
    echo
    if node_installed; then
      echo -e "  4) ${R}снести ноду${N}"
    else
      echo -e "  4) ${D}снести ноду (нет)${N}"
    fi
    if steal_installed; then
      echo -e "  5) ${R}снести selfsteal${N}"
    else
      echo -e "  5) ${D}снести selfsteal (нет)${N}"
    fi
    echo
    echo "  6) логи ноды"
    echo "  7) логи selfsteal"
    echo "  0) выход"
    echo
    local c
    c=$(ask "выбор" "1")
    case $c in
      1) install_all ;;
      2) install_node ;;
      3) install_steal ;;
      4) nuke_node ;;
      5) nuke_steal ;;
      6)
        header
        if [[ -f $NODE_DIR/docker-compose.yml ]]; then
          (cd "$NODE_DIR" && docker compose logs --tail=80 -t) || true
        else
          echo "ноды нет"
        fi
        pause
        ;;
      7)
        header
        if steal_up; then
          docker logs --tail=80 -t caddy-remnawave 2>&1 || true
        else
          echo "selfsteal не запущен"
        fi
        pause
        ;;
      0|q|Q) echo; exit 0 ;;
      *) echo "нет такого"; sleep 1 ;;
    esac
  done
}

need_root
menu
