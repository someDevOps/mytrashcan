#!/usr/bin/env bash
# Установка Remnawave Node + Selfsteal на чистый VPS
# Запуск: sudo bash setup_remnawave_node.sh

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

cat <<'BANNER'
 ██▒   █▓ ██▓    ▓█████ ▒███████▒         ███▄    █  ▒█████  ▓█████▄ ▓█████ 
 ▓██░   █▒▓██▒    ▓█   ▀ ▒ ▒ ▒ ▄▀░        ██ ▀█   █ ▒██▒  ██▒▒██▀ ██▌▓█   ▀ 
 ▓██  █▒░▒██░    ▒███   ░ ▒ ▄▀▒░         ▓██  ▀█ ██▒▒██░  ██▒░██   █▌▒███   
  ▒██ █░░▒██░    ▒▓█  ▄   ▄▀▒   ░        ▓██▒  ▐▌██▒▒██   ██░░▓█▄   ▌▒▓█  ▄ 
   ▒▀█░  ░██████▒░▒████▒▒███████▒ ██▓    ▒██░   ▓██░░ ████▓▒░░▒████▓ ░▒████▒
   ░ ▐░  ░ ▒░▓  ░░░ ▒░ ░░▒▒ ▓░▒░▒ ▒▓▒    ░ ▒░   ▒ ▒ ░ ▒░▒░▒░  ▒▒▓  ▒ ░░ ▒░ ░
   ░ ░░  ░ ░ ▒  ░ ░ ░  ░░░▒ ▒ ░ ▒ ░▒     ░ ░░   ░ ▒░  ░ ▒ ▒░  ░ ▒  ▒  ░ ░  ░
     ░░    ░ ░      ░   ░ ░ ░ ░ ░ ░         ░   ░ ░ ░ ░ ░ ▒   ░ ░  ░    ░   
      ░      ░  ░   ░  ░  ░ ░      ░              ░     ░ ░     ░       ░  ░
     ░                  ░          ░                          ░             
 ██▓ ███▄    █   ██████ ▄▄▄█████▓ ▄▄▄       ██▓     ██▓    ▓█████  ██▀███   
▓██▒ ██ ▀█   █ ▒██    ▒ ▓  ██▒ ▓▒▒████▄    ▓██▒    ▓██▒    ▓█   ▀ ▓██ ▒ ██▒ 
▒██▒▓██  ▀█ ██▒░ ▓██▄   ▒ ▓██░ ▒░▒██  ▀█▄  ▒██░    ▒██░    ▒███   ▓██ ░▄█ ▒ 
░██░▓██▒  ▐▌██▒  ▒   ██▒░ ▓██▓ ░ ░██▄▄▄▄██ ▒██░    ▒██░    ▒▓█  ▄ ▒██▀▀█▄   
░██░▒██░   ▓██░▒██████▒▒  ▒██▒ ░  ▓█   ▓██▒░██████▒░██████▒░▒████▒░██▓ ▒██▒ 
░▓  ░ ▒░   ▒ ▒ ▒ ▒▓▒ ▒ ░  ▒ ░░    ▒▒   ▓▒█░░ ▒░▓  ░░ ▒░▓  ░░░ ▒░ ░░ ▒▓ ░▒▓░ 
 ▒ ░░ ░░   ░ ▒░░ ░▒  ░ ░    ░      ▒   ▒▒ ░░ ░ ▒  ░░ ░ ▒  ░ ░ ░  ░  ░▒ ░ ▒░ 
 ▒ ░   ░   ░ ░ ░  ░  ░    ░        ░   ▒     ░ ░     ░ ░      ░     ░░   ░  
 ░           ░       ░                 ░  ░    ░  ░    ░  ░   ░  ░   ░      
                                                                            
BANNER

if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo bash $0" >&2
  exit 1
fi

get_server_ip() {
  local ip=""
  for iface in eth0 ens3; do
    ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    [[ -n "$ip" ]] && break
  done
  [[ -z "$ip" ]] && ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
  [[ -z "$ip" ]] && ip=$(curl -s -m 5 https://api.ipify.org || true)
  echo "$ip"
}
SERVER_IP=$(get_server_ip)

# --- 1. Обновление пакетов ---
echo
echo -e "${GREEN}[1/6]${NC} Обновление пакетов..."
apt-get update -y -qq >/dev/null
apt-get upgrade -y -qq >/dev/null
apt-get install -y -qq curl ufw >/dev/null

# --- 2. Настройка UFW ---
echo
echo -e "${GREEN}[2/6]${NC} Настройка фаервола (UFW)..."
read -rp "Введите IP мастер-сервера (панели Remnawave, доступ к 2222): " MASTER_IP
while [[ -z "$MASTER_IP" ]]; do
  read -rp "IP не может быть пустым. Введите IP мастер-сервера: " MASTER_IP
done

ufw allow 22/tcp comment 'SSH' >/dev/null
ufw allow 443 comment 'VPN/Reality + Selfsteal' >/dev/null
ufw allow 80/tcp comment 'ACME (Selfsteal SSL)' >/dev/null
ufw allow from "$MASTER_IP" to any port 2222 proto tcp comment "Remnawave Node API ($MASTER_IP)" >/dev/null
ufw --force enable >/dev/null

# --- 3. Установка Docker ---
echo
echo -e "${GREEN}[3/6]${NC} Установка Docker..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh >/dev/null
else
  echo "Docker уже установлен, пропускаем."
fi

# --- 4. Установка Remnawave Node ---
echo
echo -e "${GREEN}[4/6]${NC} Установка Remnawave Node..."
read -rp "Вставьте SECRET_KEY из панели Remnawave: " SECRET_KEY
while [[ -z "$SECRET_KEY" ]]; do
  read -rp "SECRET_KEY не может быть пустым. Вставьте SECRET_KEY: " SECRET_KEY
done

NODE_PORT=2222
mkdir -p /opt/remnanode
cat > /opt/remnanode/docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY="${SECRET_KEY}"
EOF

cd /opt/remnanode
docker compose up -d >/dev/null
sleep 5

# --- 5. Selfsteal (маскировка Reality) ---
echo
echo -e "${GREEN}[5/6]${NC} Установка Selfsteal..."
read -rp "Введите domain для Selfsteal (например vpn.example.com): " SELFSTEAL_DOMAIN
while [[ -z "$SELFSTEAL_DOMAIN" ]]; do
  read -rp "Domain не может быть пустым. Введите domain: " SELFSTEAL_DOMAIN
done

bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) --domain "$SELFSTEAL_DOMAIN" install

# --- 6. Финал ---
echo
echo -e "${GREEN}[6/6]${NC} Готово. Сводка по установке:"
clear
echo "=============================================="
echo "  УСТАНОВКА ЗАВЕРШЕНА"
echo "=============================================="
echo
echo "Remnawave Node:"
echo "  Статус контейнера:"
docker ps --filter name=remnanode --format "    {{.Names}}  {{.Status}}"
echo "  NODE_PORT : $NODE_PORT (доступ только с $MASTER_IP)"
echo "  SECRET_KEY: ${SECRET_KEY:0:4}...${SECRET_KEY: -4} (скрыт)"
echo "  Каталог   : /opt/remnanode"
echo
echo "Selfsteal:"
echo "  Domain    : $SELFSTEAL_DOMAIN"
echo "  Управление: selfsteal status | selfsteal logs | selfsteal restart"
echo
echo "UFW (открытые порты):"
ufw status numbered | sed 's/^/  /'
echo
echo "Дальше в панели Remnawave добавь ноду:"
echo "  IP: $SERVER_IP  PORT: $NODE_PORT  SECRET_KEY: тот же"
echo "  Reality target -> Selfsteal (127.0.0.1:9443 / unix-сокет, см. selfsteal guide)"
echo "=============================================="
