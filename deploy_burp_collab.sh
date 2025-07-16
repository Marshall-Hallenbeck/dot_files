#!/usr/bin/env bash
# provided by @illwill via NetExec Discord
# deploy_burp_collab.sh
# Usage: sudo ./deploy_burp_collab.sh your.dns.name

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0 <domain>"
  exit 1
fi

DOMAIN="$1"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
INSTALL_DIR="/opt/burp-collab"
JAR_URL="https://portswigger.net/burp/releases/download?product=collaborator&version=2025.6.3&type=Jar"
JAR_FILE="burp-collaborator.jar"
SERVICE_NAME="burp-collab"

echo "==> Installing dependencies…"
apt-get update -qq
apt-get install -y openjdk-17-jre-headless certbot wget jq

echo "==> Creating install directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
chown root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

echo "==> Obtaining Let's Encrypt cert for $DOMAIN"
certbot certonly --standalone --non-interactive \
  --agree-tos --email "$EMAIL" \
  -d "$DOMAIN"

echo "==> Downloading Burp Collaborator JAR"
wget -qO "$INSTALL_DIR/$JAR_FILE" "$JAR_URL"
chmod +x "$INSTALL_DIR/$JAR_FILE"

echo "==> Writing config JSON"
cat > "$INSTALL_DIR/collab-config.json" <<EOF
{
  "domain":    "$DOMAIN",
  "httpPort":  80,
  "httpsPort": 443,
  "tlsCertFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
  "tlsKeyFile":  "/etc/letsencrypt/live/$DOMAIN/privkey.pem",
  "logFile":   "/var/log/burp-collab.log",
  "logLevel":  "INFO"
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
ExecStart=/usr/bin/java -jar $INSTALL_DIR/$JAR_FILE --config-file $INSTALL_DIR/collab-config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "==> Enabling and starting $SERVICE_NAME"
systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service

echo " Deployment done. Burp Collaborator is live at https://$DOMAIN"