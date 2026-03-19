#!/usr/bin/env bash
# deploy_burp_collab.sh — Deploy a private Burp Collaborator server
# Originally from @illwill via NetExec Discord, updated for Burp 2026+
#
# The Collaborator server is embedded in burpsuite_pro.jar — no separate
# download exists. No license key is required to run the server.
#
# Obtains a wildcard Let's Encrypt cert via DNS-01 challenge so that all
# generated subdomains (*.domain) have valid TLS. Requires a DigitalOcean
# API token for DNS validation (passed via DO_TOKEN env var or prompted).
#
# Prerequisites:
#   - Ports 53, 80, 443 free (stop any DNS/web services first)
#   - DO_TOKEN env var with DigitalOcean API token (for DNS-01 cert challenge)
#
# Usage:
#   sudo DO_TOKEN=dop_v1_xxx ./deploy_burp_collab.sh <domain>
#
# DNS records required BEFORE running (create via DO panel or API):
#   A     <domain>       → <server-ip>
#   NS    <domain>       → <domain>          (REMOVE before first run, restore after)
#   A     ns1.<domain>   → <server-ip>
#
# NOTE: The NS record must be REMOVED before first run so the DNS-01 cert
# challenge can resolve. The script will remind you to restore it after.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo DO_TOKEN=xxx $0 <domain>"
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage: sudo DO_TOKEN=xxx $0 <domain>"
  echo ""
  echo "DNS records required (set BEFORE running):"
  echo "  A     <domain>       → <this-server-ip>"
  echo "  A     ns1.<domain>   → <this-server-ip>"
  echo ""
  echo "  NS record for <domain> must be REMOVED before first run"
  echo "  (so DNS-01 cert challenge can resolve through the registrar)."
  echo "  Restore it after the script completes."
  exit 1
fi

DOMAIN="$1"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
INSTALL_DIR="/opt/burp-collab"
JAR_URL="https://portswigger.net/burp/releases/download?product=pro&type=jar"
JAR_FILE="burpsuite_pro.jar"
SERVICE_NAME="burp-collab"
CERT_NAME="${DOMAIN//./-}-wildcard"
SERVER_IP=$(curl -s4 ifconfig.me)

# DO token — required for DNS-01 wildcard cert
if [ -z "${DO_TOKEN:-}" ]; then
  echo "ERROR: DO_TOKEN env var required for DNS-01 cert challenge."
  echo "Usage: sudo DO_TOKEN=dop_v1_xxx $0 $DOMAIN"
  exit 1
fi

echo "==> Server IP: $SERVER_IP"
echo "==> Domain: $DOMAIN"
echo "==> Cert name: $CERT_NAME"

# ── Dependencies ──────────────────────────────────────────────────────────────

echo "==> Installing dependencies…"
apt-get update -qq
apt-get install -y openjdk-21-jre-headless certbot wget jq openssl

echo "==> Creating install directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/keys"

# ── Burp Pro JAR ──────────────────────────────────────────────────────────────

if [ -f "$INSTALL_DIR/$JAR_FILE" ]; then
  echo "==> Burp Pro JAR already exists, skipping download"
else
  echo "==> Downloading Burp Pro JAR (no license needed for Collaborator server)"
  wget -qO "$INSTALL_DIR/$JAR_FILE" "$JAR_URL"
fi
chmod 644 "$INSTALL_DIR/$JAR_FILE"

# ── Wildcard TLS Certificate ─────────────────────────────────────────────────

echo "==> Stopping any existing Collaborator (freeing ports)…"
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

echo "==> Writing DO API token for DNS-01 challenge"
mkdir -p /root/.secrets
echo "$DO_TOKEN" > /root/.secrets/do-token
chmod 600 /root/.secrets/do-token

# DNS-01 auth hook — creates TXT record via DO API
cat > /tmp/do-dns-auth.sh << 'AUTHSCRIPT'
#!/bin/bash
DO_API_TOKEN=$(cat /root/.secrets/do-token)

# Extract the parent domain (last two labels) and subdomain prefix
PARENT_DOMAIN=$(echo "$CERTBOT_DOMAIN" | grep -oP '[^.]+\.[^.]+$')
SUB=$(echo "$CERTBOT_DOMAIN" | sed "s/\.$PARENT_DOMAIN$//")
if [ "$SUB" = "$PARENT_DOMAIN" ]; then
  RECORD_NAME="_acme-challenge"
else
  RECORD_NAME="_acme-challenge.${SUB}"
fi

curl -s -X POST "https://api.digitalocean.com/v2/domains/${PARENT_DOMAIN}/records" \
  -H "Authorization: Bearer $DO_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"TXT\",\"name\":\"$RECORD_NAME\",\"data\":\"$CERTBOT_VALIDATION\",\"ttl\":60}" > /dev/null

sleep 30
AUTHSCRIPT
chmod +x /tmp/do-dns-auth.sh

# DNS-01 cleanup hook — removes TXT record via DO API
cat > /tmp/do-dns-cleanup.sh << 'CLEANSCRIPT'
#!/bin/bash
DO_API_TOKEN=$(cat /root/.secrets/do-token)

PARENT_DOMAIN=$(echo "$CERTBOT_DOMAIN" | grep -oP '[^.]+\.[^.]+$')

RECORD_IDS=$(curl -s -H "Authorization: Bearer $DO_API_TOKEN" \
  "https://api.digitalocean.com/v2/domains/${PARENT_DOMAIN}/records?per_page=100" | \
  python3 -c "import json,sys; [print(r['id']) for r in json.load(sys.stdin).get('domain_records',[]) if r['type']=='TXT' and '_acme-challenge' in r.get('name','')]" 2>/dev/null)

for rid in $RECORD_IDS; do
  curl -s -X DELETE "https://api.digitalocean.com/v2/domains/${PARENT_DOMAIN}/records/$rid" \
    -H "Authorization: Bearer $DO_API_TOKEN" > /dev/null
done
CLEANSCRIPT
chmod +x /tmp/do-dns-cleanup.sh

echo "==> Requesting wildcard cert for *.$DOMAIN + $DOMAIN (DNS-01 challenge)"
certbot certonly \
  --manual \
  --preferred-challenges dns \
  --manual-auth-hook /tmp/do-dns-auth.sh \
  --manual-cleanup-hook /tmp/do-dns-cleanup.sh \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "*.$DOMAIN" \
  -d "$DOMAIN" \
  --cert-name "$CERT_NAME"

echo "==> Converting cert to PKCS8 for Burp Collaborator"
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in "/etc/letsencrypt/live/$CERT_NAME/privkey.pem" \
  -out "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8"
cp "/etc/letsencrypt/live/$CERT_NAME/fullchain.pem" "$INSTALL_DIR/keys/$DOMAIN.crt"

# ── Collaborator Config ───────────────────────────────────────────────────────

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
    "localAddress": "$SERVER_IP",
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

# ── Systemd Service ───────────────────────────────────────────────────────────

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

# ── Firewall ──────────────────────────────────────────────────────────────────

echo "==> Opening firewall ports"
for port in 53 80/tcp 443/tcp 9090/tcp 9443/tcp 25/tcp 587/tcp 465/tcp; do
  ufw allow "$port" >/dev/null 2>&1 || true
done

# ── Cert Renewal Hook ─────────────────────────────────────────────────────────

echo "==> Creating cert renewal hook"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/burp-collab.sh <<HOOK
#!/bin/bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in "/etc/letsencrypt/live/$CERT_NAME/privkey.pem" \
  -out "$INSTALL_DIR/keys/$DOMAIN.key.pkcs8"
cp "/etc/letsencrypt/live/$CERT_NAME/fullchain.pem" "$INSTALL_DIR/keys/$DOMAIN.crt"
systemctl restart $SERVICE_NAME
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/burp-collab.sh

# ── Start ─────────────────────────────────────────────────────────────────────

echo "==> Disabling systemd-resolved (conflicts with DNS on port 53)"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
if [ ! -f /etc/resolv.conf ] || grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
  rm -f /etc/resolv.conf
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
fi

echo "==> Enabling and starting $SERVICE_NAME"
systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service

sleep 5
if systemctl is-active --quiet ${SERVICE_NAME}; then
  echo ""
  echo "========================================"
  echo " Burp Collaborator is live!"
  echo "========================================"
  echo ""
  echo "  Domain:         $DOMAIN"
  echo "  Server IP:      $SERVER_IP"
  echo "  Polling HTTPS:  https://$DOMAIN:9443"
  echo "  Cert covers:    *.$DOMAIN + $DOMAIN"
  echo "  Cert expires:   $(openssl x509 -enddate -noout -in "$INSTALL_DIR/keys/$DOMAIN.crt" 2>/dev/null | cut -d= -f2)"
  echo ""
  echo "  Burp Suite Pro settings:"
  echo "    Settings → Project → Collaborator"
  echo "    ☑ Use a private Collaborator server"
  echo "    Server location:  $DOMAIN"
  echo "    Polling location: $DOMAIN:9443"
  echo ""
  echo "  IMPORTANT: Restore the NS record for $DOMAIN now!"
  echo "    NS    $DOMAIN  →  $DOMAIN"
  echo ""
else
  echo "ERROR: Service failed to start."
  echo "Check: journalctl -u $SERVICE_NAME --no-pager -n 30"
  exit 1
fi
