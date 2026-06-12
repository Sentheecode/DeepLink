#!/bin/sh
set -eu

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_DIR=/opt/deepseekbalance-broker
STATE_DIR=/var/lib/deepseekbalance-broker
SERVICE_USER=deepseekbroker

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root: sudo sh deploy/install_broker_service.sh"
  exit 1
fi

id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
mkdir -p "$INSTALL_DIR" "$STATE_DIR"
cp "$SOURCE_DIR/app.py" "$SOURCE_DIR/admin.py" "$SOURCE_DIR/hermes_bridge.py" "$SOURCE_DIR/requirements.txt" "$INSTALL_DIR/"
python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR"

if [ ! -f /etc/deepseekbalance-broker.env ]; then
  cp "$SOURCE_DIR/deploy/deepseekbalance-broker.env.example" /etc/deepseekbalance-broker.env
  chmod 600 /etc/deepseekbalance-broker.env
  ADMIN_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  sed -i "s/replace-with-a-long-random-secret/$ADMIN_TOKEN/" /etc/deepseekbalance-broker.env
  echo "Created /etc/deepseekbalance-broker.env with a random BROKER_ADMIN_TOKEN."
fi

cp "$SOURCE_DIR/deploy/deepseekbalance-broker.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable deepseekbalance-broker

echo "After editing /etc/deepseekbalance-broker.env, run:"
echo "  sudo systemctl restart deepseekbalance-broker"
echo "  sudo systemctl status deepseekbalance-broker"
