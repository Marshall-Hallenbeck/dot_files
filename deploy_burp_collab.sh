#!/usr/bin/env bash
# deploy_burp_collab.sh — Deploy a private Burp Collaborator server
# Originally from @illwill via NetExec Discord, updated for Burp 2026+
#
# The Collaborator server is embedded in burpsuite_pro.jar — no separate
# download exists. No license key is required to run the server.
#
# Prerequisites:
#   - Domain with NS record pointing to this server
#   - Ports 53, 80, 443 free
#
# Usage:
#   sudo ./deploy_burp_collab.sh <domain>
#
# DNS setup required BEFORE running:
#   A     <domain>       → <server-ip>
#   NS    <domain>       → <domain>
#   A     ns1.<domain>   → <server-ip>

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0 <domain>"
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage: sudo $0 <domain>"
  echo ""
  echo "DNS records required (set these BEFORE running):"
  echo "  A     <domain>       → <this-server-ip>"
  echo "  NS    <domain>       → <domain>"
  echo "  A     ns1.<domain>   → <this-server-ip>"
  exit 1
fi

DOMAIN="$1"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
INSTALL_DIR="/opt/burp-collab"
JAR_URL="https://portswigger.net/burp/releases/download?product=pro&type=jar"
JAR_FILE="burpsuite_pro.jar"
SERVICE_NAME="burp-collab"
SERVER_IP=$(curl -s4 ifconfig.me)

echo "==> Server IP: $SERVER_IP"
echo "==> Domain: $DOMAIN"

echo "==> Installing dependencies…"
apt-get update -qq
apt-get install -y openjdk-21-jre-headless certbot wget jq

echo "==> Creating install directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/keys"

echo "==> Downloading Burp Pro JAR (no license needed for Collaborator server)"
wget -qO "$INSTALL_DIR/$JAR_FILE" "$JAR_URL"
chmod 644 "$INSTALL_DIR/$JAR_FILE"

echo "==> Stopping any services on port 80 (for certbot)…"
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

echo "==> Obtaining Let's Encrypt cert for $DOMAIN"
certbot certonly --standalone --non-interactive \
  --agree-tos --email "$EMAIL" \
  -d "$DOMAIN"

echo "==> Converting cert to PKCS8 for Burp Collaborator"
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
  -out "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8"
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$INSTALL_DIR/keys/$DOMAIN.crt"

echo "==> Writing Collaborator config"
cat > "$INSTALL_DIR/collab-config.json" <<EOF
{
  "serverDomain": "$DOMAIN",
  "workerThreads": 10,
  "interactionLimits": {
    "http": 8192,
    "smtp": 8192
  },
  "eventCapture": {
    "localAddress": ["$SERVER_IP", "127.0.0.1"],
    "publicAddress": "$SERVER_IP",
    "http": {
      "ports": 80
    },
    "https": {
      "ports": 443
    },
    "smtp": {
      "ports": [25, 587]
    },
    "smtps": {
      "ports": 465
    },
    "ssl": {
      "certificateFiles": [
        "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8",
        "$INSTALL_DIR/keys/$DOMAIN.crt"
      ]
    }
  },
  "polling": {
    "localAddress": "127.0.0.1",
    "publicAddress": "$SERVER_IP",
    "http": {
      "port": 9090
    },
    "https": {
      "port": 9443
    },
    "ssl": {
      "certificateFiles": [
        "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8",
        "$INSTALL_DIR/keys/$DOMAIN.crt"
      ]
    }
  },
  "dns": {
    "interfaces": [
      {
        "name": "ns1",
        "localAddress": "$SERVER_IP",
        "publicAddress": "$SERVER_IP"
      }
    ],
    "ports": 53
  },
  "logLevel": "INFO"
}
EOF

echo "==> Creating systemd service"
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Burp Collaborator Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar $INSTALL_DIR/$JAR_FILE --collaborator-server --collaborator-config=$INSTALL_DIR/collab-config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creating cert renewal hook"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/burp-collab.sh <<HOOK
#!/bin/bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
  -out "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8"
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$INSTALL_DIR/keys/$DOMAIN.crt"
systemctl restart $SERVICE_NAME
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/burp-collab.sh

echo "==> Enabling and starting $SERVICE_NAME"
systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service

sleep 2
if systemctl is-active --quiet ${SERVICE_NAME}; then
  echo ""
  echo "Burp Collaborator is live!"
  echo "  Domain:        $DOMAIN"
  echo "  Server IP:     $SERVER_IP"
  echo "  Polling HTTP:  http://$SERVER_IP:9090"
  echo "  Polling HTTPS: https://$SERVER_IP:9443"
  echo ""
  echo "Configure in Burp Suite Pro:"
  echo "  Settings → Project → Collaborator → Use private Collaborator server"
  echo "  Server location: $DOMAIN"
  echo "  Polling location: $SERVER_IP:9443"
  echo ""
  echo "DNS records required:"
  echo "  A     $DOMAIN       → $SERVER_IP"
  echo "  NS    $DOMAIN       → $DOMAIN"
  echo "  A     ns1.$DOMAIN   → $SERVER_IP"
else
  echo "ERROR: Service failed to start. Check: journalctl -u $SERVICE_NAME"
  exit 1
fi
