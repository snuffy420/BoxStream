#!/usr/bin/env bash
# Box://Stream Helper installer for a fresh Ubuntu server (Oracle Cloud Free Tier, 22.04/24.04).
# Installs ffmpeg, the helper service and Caddy (automatic HTTPS), opens ports 80/443 in the
# server's firewall, and prints the address and pairing code to enter in Box://Stream.
# Also open TCP 80 and 443 in the Oracle subnet's security list (see the guide).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== Swap (helps a 1 GB server)"
if [ ! -f /swapfile ]; then
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile && echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
fi

echo "== Packages"
export DEBIAN_FRONTEND=noninteractive
# A fresh server runs its own updates at first boot: wait for them instead of failing.
apt() { sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=1200 "$@"; }
apt update -qq
apt install -y -qq ffmpeg python3 curl debian-keyring debian-archive-keyring apt-transport-https gnupg iptables-persistent >/dev/null
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -qq && apt install -y -qq caddy >/dev/null
fi

echo "== Helper"
sudo install -m 755 "$HERE/boxstream_helper.py" /usr/local/bin/boxstream_helper.py
if [ ! -f /etc/boxstream-helper.json ]; then
  TOKEN="$(python3 -c "import secrets; print(''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(8)))")"
  echo "{\"token\": \"$TOKEN\", \"port\": 8090}" | sudo tee /etc/boxstream-helper.json >/dev/null
  sudo chmod 640 /etc/boxstream-helper.json
fi
TOKEN="$(python3 -c 'import json;print(json.load(open("/etc/boxstream-helper.json"))["token"])' 2>/dev/null || sudo python3 -c 'import json;print(json.load(open("/etc/boxstream-helper.json"))["token"])')"
sudo tee /etc/systemd/system/boxstream-helper.service >/dev/null <<'UNIT'
[Unit]
Description=Box://Stream Helper
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/boxstream_helper.py
Restart=always
User=root
Nice=5

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now boxstream-helper >/dev/null
sudo systemctl restart boxstream-helper

echo "== HTTPS"
IP="$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"
HOST="$(echo "$IP" | tr . -).sslip.io"
sudo tee /etc/caddy/Caddyfile >/dev/null <<CADDY
$HOST {
    reverse_proxy 127.0.0.1:8090 {
        flush_interval -1
    }
}
CADDY
for port in 80 443; do
  sudo iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 5 -p tcp --dport $port -j ACCEPT
done
sudo netfilter-persistent save >/dev/null 2>&1 || true
sudo systemctl restart caddy

echo
echo "Box://Stream Helper is installed."
echo "  Address:      https://$HOST"
echo "  Pairing code: $TOKEN"
echo "Enter both in Box://Stream: Settings > Helper."
