#!/bin/sh
set -eu

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_DIR=/opt/deeplink-broker
STATE_DIR=/var/lib/deeplink-broker
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

if [ ! -f /etc/deeplink-broker.env ]; then
  cp "$SOURCE_DIR/deploy/deeplink-broker.env.example" /etc/deeplink-broker.env
  chmod 600 /etc/deeplink-broker.env
  ADMIN_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
  sed -i "s/replace-with-a-long-random-secret/$ADMIN_TOKEN/" /etc/deeplink-broker.env
  echo "Created /etc/deeplink-broker.env with a random BROKER_ADMIN_TOKEN."
fi

cp "$SOURCE_DIR/deploy/deeplink-broker.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now deeplink-broker
systemctl restart deeplink-broker

echo "Waiting for the Broker health endpoint..."
attempt=0
until curl --fail --silent --show-error http://127.0.0.1:8010/health; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 10 ]; then
    echo "Broker did not become healthy. Inspect it with:"
    echo "  sudo systemctl status deeplink-broker --no-pager"
    echo "  sudo journalctl -u deeplink-broker -n 100 --no-pager"
    exit 1
  fi
  sleep 1
done
echo
echo "Broker is running on http://127.0.0.1:8010."
