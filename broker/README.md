# DeepSeekBalance Cloud Control Plane

This directory contains the server used by the iOS app and Agent channels. It is more than a message broker:

- user identity and authorization
- username/password login and one-time Agent pairing
- user-owned device registry
- Agent RPC relay
- audit log and per-user RPC usage
- administrator web console
- SQLite persistence and production service files

## Security Model

There are three separate credentials:

1. `BROKER_ADMIN_TOKEN`: generated on the server and used only by the administrator.
2. User password: stored only as a PBKDF2 salted hash. Login issues a rotating access token stored in iOS Keychain.
3. Node token: issued once to an Agent installer and restricted to one device.

Users cannot see or invoke another user's devices. Disabling a user immediately invalidates their user token. Removing a device invalidates its node token.

## Deploy On Ubuntu/Debian

Copy the `broker` directory to the server, then:

```bash
cd broker
sudo apt update
sudo apt install -y python3 python3-venv nginx certbot
sudo sh deploy/install_broker_service.sh
sudo nano /etc/deepseekbalance-broker.env
sudo systemctl restart deepseekbalance-broker
sudo systemctl status deepseekbalance-broker --no-pager
curl http://127.0.0.1:8000/health
```

The installer automatically generates a random `BROKER_ADMIN_TOKEN`. View it only when needed:

```bash
sudo grep '^BROKER_ADMIN_TOKEN=' /etc/deepseekbalance-broker.env
```

Do not give this token to users.

## HTTPS For The Public IP

The production URL must use HTTPS. Let's Encrypt supports publicly trusted IP certificates and users do not install certificates.

```bash
sudo mkdir -p /var/www/certbot
sudo cp deploy/nginx-http-bootstrap.conf /etc/nginx/conf.d/deepseekbalance-broker.conf
sudo nginx -t
sudo systemctl reload nginx

sudo certbot certonly \
  --webroot -w /var/www/certbot \
  --cert-name broker-ip \
  --ip-address 139.224.211.170 \
  --required-profile shortlived

sudo cp deploy/nginx-ip-https.conf /etc/nginx/conf.d/deepseekbalance-broker.conf
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --deploy-hook "systemctl reload nginx"
```

Set `BROKER_PUBLIC_URL=https://139.224.211.170` in `/etc/deepseekbalance-broker.env`, then restart the service.

## Administrator Console

Open:

```text
https://139.224.211.170/admin
```

The browser will ask for Basic Auth:

- username: `admin`
- password: the server's `BROKER_ADMIN_TOKEN`

The console can create user accounts, show users/devices/RPC usage, disable users, and inspect recent audit events.

You can also create a user from the command line. If `--password` is omitted, a random initial password is generated:

```bash
cd /opt/deepseekbalance-broker
set -a
. /etc/deepseekbalance-broker.env
set +a
./.venv/bin/python admin.py create-user --username trial-user --name "Trial User"
```

## User Flow

1. Administrator creates a user account and securely sends its initial credentials.
2. User opens Settings and logs in before configuring any services.
3. The App stores the returned private access token in Keychain.
4. User opens Agent devices and taps `Generate Agent pairing QR`.
5. The Agent computer opens the link and runs the displayed installer command.
6. The Agent appears only in that user's device list.

## Operations

```bash
sudo journalctl -u deepseekbalance-broker -f
sudo systemctl restart deepseekbalance-broker
sudo systemctl stop deepseekbalance-broker
sudo sqlite3 /var/lib/deepseekbalance-broker/control-plane.db '.tables'
sudo cp /var/lib/deepseekbalance-broker/control-plane.db /root/control-plane-backup.db
```

Run exactly one Uvicorn worker. Online presence, pending commands, and results currently live in memory. Before horizontal scaling, move those three runtime concerns to Redis and migrate persistent tables from SQLite to PostgreSQL.

## Commercialization Boundary

This version is suitable for controlled public trials on one server. Before paid production, add:

- Apple/email login and account recovery
- subscription and entitlement service
- PostgreSQL migrations and encrypted backups
- Redis-backed relay and multiple Broker instances
- per-plan quotas and abuse detection
- structured logs, metrics, alerting, privacy policy, and data deletion workflow
