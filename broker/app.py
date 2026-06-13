import asyncio
import base64
import hashlib
import html
import json
import os
import secrets
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import Depends, FastAPI, Form, Header, HTTPException, Response
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse, RedirectResponse
from pydantic import BaseModel, Field


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return utc_now().isoformat()


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()

def password_hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), 210_000).hex()


BROKER_ADMIN_TOKEN = os.environ.get("BROKER_ADMIN_TOKEN") or os.environ.get("BROKER_TOKEN", "")
RPC_TIMEOUT_SECONDS = float(os.environ.get("RPC_TIMEOUT_SECONDS", "180"))
BROKER_PUBLIC_URL = os.environ.get("BROKER_PUBLIC_URL", "http://127.0.0.1:8010").rstrip("/")
BASE_DIR = Path(__file__).resolve().parent
DATABASE_PATH = Path(os.environ.get("BROKER_DB_PATH", BASE_DIR / "broker.db"))

app = FastAPI(title="DeepSeekBalance Agent Broker", version="0.2.0")


@contextmanager
def database():
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def configure_database(path: Path = DATABASE_PATH) -> None:
    global DATABASE_PATH
    DATABASE_PATH = path
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with database() as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                username TEXT UNIQUE,
                display_name TEXT NOT NULL,
                access_token_hash TEXT NOT NULL UNIQUE,
                password_salt TEXT,
                password_hash TEXT,
                email TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                disabled INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS invites (
                token_hash TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                owner_id TEXT,
                display_name TEXT,
                expires_at TEXT NOT NULL,
                consumed_at TEXT,
                FOREIGN KEY(owner_id) REFERENCES users(id)
            );
            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                owner_id TEXT NOT NULL,
                name TEXT NOT NULL,
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                node_token_hash TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL,
                last_seen_at TEXT,
                disabled INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(owner_id) REFERENCES users(id)
            );
            CREATE INDEX IF NOT EXISTS devices_owner_idx ON devices(owner_id);
            CREATE TABLE IF NOT EXISTS agents (
                id TEXT PRIMARY KEY,
                device_id TEXT NOT NULL,
                owner_id TEXT NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL DEFAULT 'hermes',
                endpoint TEXT,
                version TEXT,
                status TEXT NOT NULL DEFAULT 'online',
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                skills_json TEXT NOT NULL DEFAULT '[]',
                profile_json TEXT NOT NULL DEFAULT '{}',
                last_seen_at TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(device_id) REFERENCES devices(id),
                FOREIGN KEY(owner_id) REFERENCES users(id)
            );
            CREATE INDEX IF NOT EXISTS agents_device_idx ON agents(device_id);
            CREATE INDEX IF NOT EXISTS agents_owner_idx ON agents(owner_id);
            CREATE TABLE IF NOT EXISTS audit_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                actor_type TEXT NOT NULL,
                actor_id TEXT,
                action TEXT NOT NULL,
                target_type TEXT,
                target_id TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS rpc_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                method TEXT NOT NULL,
                ok INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(owner_id) REFERENCES users(id)
            );
            CREATE INDEX IF NOT EXISTS rpc_owner_idx ON rpc_events(owner_id);
            CREATE TABLE IF NOT EXISTS runtime_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        columns = {row["name"] for row in db.execute("PRAGMA table_info(users)").fetchall()}
        for name, definition in (
            ("username", "TEXT"),
            ("password_salt", "TEXT"),
            ("password_hash", "TEXT"),
            ("email", "TEXT NOT NULL DEFAULT ''"),
        ):
            if name not in columns:
                db.execute(f"ALTER TABLE users ADD COLUMN {name} {definition}")
        db.execute("CREATE UNIQUE INDEX IF NOT EXISTS users_username_idx ON users(username)")
        dev_columns = {row["name"] for row in db.execute("PRAGMA table_info(devices)").fetchall()}
        for name, definition in (("endpoint", "TEXT"),):
            if name not in dev_columns:
                db.execute(f"ALTER TABLE devices ADD COLUMN {name} {definition}")
        agent_cols = {row["name"] for row in db.execute("PRAGMA table_info(agents)").fetchall()}
        for name, definition in (("profile_json", "TEXT NOT NULL DEFAULT '{}'"),):
            if name not in agent_cols:
                db.execute(f"ALTER TABLE agents ADD COLUMN {name} {definition}")
        for key, value in (
            ("node_enrollment_minutes", "15"),
            ("online_timeout_seconds", "75"),
            ("default_hermes_url", "http://127.0.0.1:8642"),
        ):
            db.execute(
                "INSERT OR IGNORE INTO runtime_settings(key, value, updated_at) VALUES (?, ?, ?)",
                (key, value, iso_now()),
            )


configure_database()


class NodeRegistration(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=128)
    endpoint: str | None = Field(default=None, max_length=512)
    capabilities: list[str] = Field(default_factory=list)


class DeviceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    endpoint: str | None = Field(default=None, max_length=512)


class AgentRegistration(BaseModel):
    id: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=128)
    kind: str = Field(default="hermes", max_length=64)
    endpoint: str | None = Field(default=None, max_length=512)
    version: str | None = Field(default=None, max_length=32)
    status: str = Field(default="online", max_length=16)
    capabilities: list[str] = Field(default_factory=list)
    skills: list[dict[str, Any]] = Field(default_factory=list)


class EnrollmentConsumption(BaseModel):
    token: str = Field(min_length=1, max_length=256)
    device_id: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=128)


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=8, max_length=256)


class RegisterRequest(BaseModel):
    username: str = Field(pattern=r"^[a-zA-Z0-9._-]{3,64}$", min_length=3, max_length=64)
    email: str = Field(min_length=5, max_length=256)
    password: str = Field(min_length=8, max_length=256)


class AdminUserCreate(BaseModel):
    username: str = Field(pattern=r"^[a-zA-Z0-9._-]{3,64}$")
    display_name: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=12, max_length=256)


class RPCRequest(BaseModel):
    method: str = Field(min_length=1, max_length=128)
    params: dict[str, Any] = Field(default_factory=dict)


class Command(BaseModel):
    id: str
    method: str
    params: dict[str, Any]
    created_at: datetime


class CommandResult(BaseModel):
    ok: bool
    data: Any = None
    error: str | None = None


@dataclass(frozen=True)
class AdminIdentity:
    pass


@dataclass(frozen=True)
class UserIdentity:
    id: str
    display_name: str


@dataclass(frozen=True)
class NodeIdentity:
    device_id: str
    owner_id: str


class NodeState:
    def __init__(self, registration: NodeRegistration, owner_id: str) -> None:
        self.registration = registration
        self.owner_id = owner_id
        self.last_seen_at = utc_now()
        self.commands: asyncio.Queue[Command] = asyncio.Queue()


nodes: dict[str, NodeState] = {}
pending_results: dict[str, asyncio.Future[CommandResult]] = {}
state_lock = asyncio.Lock()


def bearer_token(authorization: str | None) -> str:
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="invalid bearer token")
    return authorization.removeprefix("Bearer ")


def require_admin(authorization: str | None = Header(default=None)) -> AdminIdentity:
    if authorization is None:
        raise HTTPException(
            status_code=401,
            detail="admin authentication required",
            headers={"WWW-Authenticate": 'Basic realm="DeepSeekBalance Control Plane"'},
        )
    if authorization and authorization.startswith("Basic "):
        try:
            decoded = base64.b64decode(authorization.removeprefix("Basic ")).decode()
            username, token = decoded.split(":", 1)
        except (ValueError, UnicodeDecodeError):
            username, token = "", ""
        if username == "admin" and BROKER_ADMIN_TOKEN and secrets.compare_digest(token, BROKER_ADMIN_TOKEN):
            return AdminIdentity()
        raise HTTPException(
            status_code=401,
            detail="invalid admin token",
            headers={"WWW-Authenticate": 'Basic realm="DeepSeekBalance Control Plane"'},
        )
    token = bearer_token(authorization)
    if not BROKER_ADMIN_TOKEN or not secrets.compare_digest(token, BROKER_ADMIN_TOKEN):
        raise HTTPException(status_code=401, detail="invalid admin token")
    return AdminIdentity()


def require_user_token(token: str) -> UserIdentity:
    with database() as db:
        row = db.execute(
            "SELECT id, display_name FROM users WHERE access_token_hash = ? AND disabled = 0",
            (token_hash(token),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="invalid user token")
    return UserIdentity(id=row["id"], display_name=row["display_name"])


def require_user(authorization: str | None = Header(default=None)) -> UserIdentity:
    return require_user_token(bearer_token(authorization))


def require_node_token(token: str) -> NodeIdentity:
    with database() as db:
        row = db.execute(
            "SELECT id, owner_id FROM devices WHERE node_token_hash = ? AND disabled = 0",
            (token_hash(token),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="invalid node token")
    return NodeIdentity(device_id=row["id"], owner_id=row["owner_id"])


def require_node(authorization: str | None = Header(default=None)) -> NodeIdentity:
    return require_node_token(bearer_token(authorization))


def assert_node_device(device_id: str, identity: NodeIdentity) -> None:
    if identity.device_id != device_id:
        raise HTTPException(status_code=403, detail="node token does not belong to this device")


def find_active_invite(raw_token: str, kind: str) -> sqlite3.Row:
    with database() as db:
        row = db.execute(
            """
            SELECT * FROM invites
            WHERE token_hash = ? AND kind = ? AND consumed_at IS NULL AND expires_at > ?
            """,
            (token_hash(raw_token), kind, iso_now()),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="pairing code is invalid or expired")
    return row


def audit(actor_type: str, actor_id: str | None, action: str, target_type: str, target_id: str) -> None:
    with database() as db:
        db.execute(
            """
            INSERT INTO audit_events(actor_type, actor_id, action, target_type, target_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (actor_type, actor_id, action, target_type, target_id, iso_now()),
        )


def record_rpc(owner_id: str, device_id: str, method: str, ok: bool) -> None:
    with database() as db:
        db.execute(
            "INSERT INTO rpc_events(owner_id, device_id, method, ok, created_at) VALUES (?, ?, ?, ?, ?)",
            (owner_id, device_id, method, int(ok), iso_now()),
        )


def runtime_setting(key: str, default: str) -> str:
    with database() as db:
        row = db.execute("SELECT value FROM runtime_settings WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default


def set_runtime_setting(key: str, value: str) -> None:
    with database() as db:
        db.execute(
            """
            INSERT INTO runtime_settings(key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            (key, value, iso_now()),
        )


@app.get("/health")
async def health() -> dict[str, Any]:
    timeout = int(runtime_setting("online_timeout_seconds", "75"))
    cutoff = utc_now() - timedelta(seconds=timeout)
    online = sum(1 for n in nodes.values() if n.last_seen_at and n.last_seen_at > cutoff)
    return {"ok": True, "online_nodes": online, "time": utc_now(), "version": app.version}


@app.post("/v1/admin/users")
def create_user_account(
    request: AdminUserCreate,
    _: AdminIdentity = Depends(require_admin),
) -> dict[str, Any]:
    user_id = str(uuid4())
    salt = secrets.token_hex(16)
    initial_token_hash = token_hash(secrets.token_urlsafe(48))
    with database() as db:
        try:
            db.execute(
                """
                INSERT INTO users(
                    id, username, display_name, access_token_hash, password_salt, password_hash, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    request.username.lower(),
                    request.display_name.strip(),
                    initial_token_hash,
                    salt,
                    password_hash(request.password, salt),
                    iso_now(),
                ),
            )
        except sqlite3.IntegrityError as exc:
            raise HTTPException(status_code=409, detail="username already exists") from exc
    audit("admin", None, "create_user", "user", user_id)
    return {"user_id": user_id, "username": request.username.lower(), "display_name": request.display_name}


@app.post("/v1/auth/register")
def register(request: RegisterRequest) -> dict[str, Any]:
    user_id = str(uuid4())
    salt = secrets.token_hex(16)
    access_token = secrets.token_urlsafe(48)
    with database() as db:
        try:
            db.execute(
                """
                INSERT INTO users(
                    id, username, display_name, access_token_hash,
                    password_salt, password_hash, email, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    request.username.lower(),
                    request.username,
                    token_hash(access_token),
                    salt,
                    password_hash(request.password, salt),
                    request.email,
                    iso_now(),
                ),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="用户名已存在")
    audit("user", user_id, "register", "user", user_id)
    return {
        "access_token": access_token,
        "user_id": user_id,
        "display_name": request.username,
    }


@app.post("/v1/auth/login")
def login(request: LoginRequest) -> dict[str, Any]:
    with database() as db:
        row = db.execute(
            """
            SELECT id, display_name, password_salt, password_hash FROM users
            WHERE username = ? AND disabled = 0
            """,
            (request.username.lower(),),
        ).fetchone()
        if row is None or not row["password_salt"] or not secrets.compare_digest(
            password_hash(request.password, row["password_salt"]), row["password_hash"]
        ):
            raise HTTPException(status_code=401, detail="用户名或密码错误")
        access_token = secrets.token_urlsafe(48)
        db.execute(
            "UPDATE users SET access_token_hash = ? WHERE id = ?",
            (token_hash(access_token), row["id"]),
        )
    audit("user", row["id"], "login", "user", row["id"])
    return {
        "access_token": access_token,
        "user_id": row["id"],
        "display_name": row["display_name"],
    }


@app.get("/v1/me")
def current_user(user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    usage = user_usage(user)
    return {"id": user.id, "display_name": user.display_name, **usage}


@app.get("/v1/me/usage")
def user_usage(user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    # Re-read the user so a disabled account cannot keep using an in-memory identity.
    with database() as db:
        active = db.execute("SELECT 1 FROM users WHERE id = ? AND disabled = 0", (user.id,)).fetchone()
        if active is None:
            raise HTTPException(status_code=401, detail="user is disabled")
        row = db.execute(
            """
            SELECT COUNT(*) AS rpc_count,
                   COALESCE(SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END), 0) AS successful_rpc_count
            FROM rpc_events WHERE owner_id = ?
            """,
            (user.id,),
        ).fetchone()
        device_count = db.execute(
            "SELECT COUNT(*) AS count FROM devices WHERE owner_id = ? AND disabled = 0",
            (user.id,),
        ).fetchone()["count"]
    return {
        "rpc_count": row["rpc_count"],
        "successful_rpc_count": row["successful_rpc_count"],
        "device_count": device_count,
    }


@app.post("/v1/enrollments")
def create_enrollment(user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    raw_token = secrets.token_urlsafe(32)
    expires_at = utc_now() + timedelta(minutes=int(runtime_setting("node_enrollment_minutes", "15")))
    with database() as db:
        db.execute(
            """
            INSERT INTO invites(token_hash, kind, owner_id, expires_at)
            VALUES (?, 'node', ?, ?)
            """,
            (token_hash(raw_token), user.id, expires_at.isoformat()),
        )
    audit("user", user.id, "create_node_enrollment", "invite", token_hash(raw_token)[:12])
    return {
        "token": raw_token,
        "url": f"{BROKER_PUBLIC_URL}/channel/{raw_token}",
        "expires_at": expires_at,
    }


def consume_enrollment(token: str, registration: NodeRegistration) -> dict[str, Any]:
    node_token = secrets.token_urlsafe(48)
    with database() as db:
        # Check and consume within a single transaction to prevent race conditions
        row = db.execute(
            "SELECT owner_id FROM invites WHERE token_hash = ? AND kind = 'node' AND consumed_at IS NULL AND (expires_at IS NULL OR expires_at > ?)",
            (token_hash(token), iso_now()),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="enrollment token is invalid or already consumed")
        db.execute(
            """
            INSERT INTO devices(
                id, owner_id, name, capabilities_json, endpoint, node_token_hash, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                registration.device_id,
                row["owner_id"],
                registration.name,
                "[]",
                registration.endpoint,
                token_hash(node_token),
                iso_now(),
            ),
        )
        db.execute(
            "UPDATE invites SET consumed_at = ? WHERE token_hash = ?",
            (iso_now(), token_hash(token)),
        )
    audit("node", registration.device_id, "enroll_device", "device", registration.device_id)
    return {"node_token": node_token, "device_id": registration.device_id}


@app.get("/channel/hermes_bridge.py")
async def download_bridge() -> FileResponse:
    return FileResponse(BASE_DIR / "hermes_bridge.py", media_type="text/x-python")


@app.get("/channel/{token}", response_class=PlainTextResponse)
async def channel_instructions(token: str) -> str:
    find_active_invite(token, "node")
    return f"""# DeepLink Agent Channel

This one-time link belongs to one user and expires after 15 minutes.

Install and start the channel:

curl -fsSL {BROKER_PUBLIC_URL}/channel/{token}/install.sh | sh
"""


@app.get("/channel/{token}/install.sh", response_class=PlainTextResponse)
async def channel_installer(token: str) -> str:
    find_active_invite(token, "node")
    return installer_script(token)


@app.post("/v1/enrollments/consume")
def consume_enrollment_request(request: EnrollmentConsumption) -> dict[str, Any]:
    return consume_enrollment(
        request.token,
        NodeRegistration(device_id=request.device_id, name=request.name),
    )


def installer_script(enrollment_token: str) -> str:
    return f"""#!/bin/sh
set -eu

BROKER_URL='{BROKER_PUBLIC_URL}'
ENROLLMENT_TOKEN='{enrollment_token}'
INSTALL_DIR="${{HOME}}/.deeplink-channel"
DEVICE_NAME="${{DEVICE_NAME:-$(hostname)}}"
DEFAULT_HOST="localhost"
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  DEFAULT_HOST="127.0.0.1"
fi
HERMES_URL="${{HERMES_URL:-http://$DEFAULT_HOST:8642}}"
HERMES_KEY="${{HERMES_KEY:-}}"
HERMES_ENV="${{HERMES_ENV:-$HOME/.hermes/.env}}"
if [ -z "$HERMES_KEY" ] && [ -f "$HERMES_ENV" ]; then
  set -a
  . "$HERMES_ENV"
  set +a
  HERMES_KEY="${{API_SERVER_KEY:-}}"
fi

mkdir -p "$INSTALL_DIR"
echo "Checking Broker: $BROKER_URL"
curl -fsSL "$BROKER_URL/health" >/dev/null
echo "Checking Hermes: $HERMES_URL"
if [ -n "$HERMES_KEY" ]; then
  curl -fsSL -H "Authorization: Bearer $HERMES_KEY" "$HERMES_URL/api/sessions" >/dev/null
else
  curl -fsSL "$HERMES_URL/api/sessions" >/dev/null
fi
curl -fsSL "$BROKER_URL/channel/hermes_bridge.py" -o "$INSTALL_DIR/hermes_bridge.py"
python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install --quiet 'httpx>=0.28,<1'

DEVICE_ID="$("$INSTALL_DIR/.venv/bin/python" -c 'import uuid; print(uuid.uuid4())')"
ENROLLMENT_BODY="$("$INSTALL_DIR/.venv/bin/python" -c 'import json,sys; print(json.dumps({{"token":sys.argv[1],"device_id":sys.argv[2],"name":sys.argv[3]}}))' "$ENROLLMENT_TOKEN" "$DEVICE_ID" "$DEVICE_NAME")"
ENROLLMENT_RESULT="$(curl -fsSL -X POST "$BROKER_URL/v1/enrollments/consume" -H 'Content-Type: application/json' --data-binary "$ENROLLMENT_BODY")"
BROKER_TOKEN="$("$INSTALL_DIR/.venv/bin/python" -c 'import json,sys; print(json.loads(sys.argv[1])["node_token"])' "$ENROLLMENT_RESULT")"

cat > "$INSTALL_DIR/channel.env" <<EOF
BROKER_URL=$BROKER_URL
BROKER_TOKEN=$BROKER_TOKEN
DEVICE_ID=$DEVICE_ID
DEVICE_NAME=$DEVICE_NAME
HERMES_URL=$HERMES_URL
HERMES_KEY=$HERMES_KEY
EOF
chmod 600 "$INSTALL_DIR/channel.env"

echo "Verifying Channel registration..."
env BROKER_URL="$BROKER_URL" BROKER_TOKEN="$BROKER_TOKEN" DEVICE_ID="$DEVICE_ID" \
  DEVICE_NAME="$DEVICE_NAME" HERMES_URL="$HERMES_URL" HERMES_KEY="$HERMES_KEY" \
  CHANNEL_CHECK_ONLY=1 "$INSTALL_DIR/.venv/bin/python" -u "$INSTALL_DIR/hermes_bridge.py" --check

if [ "$(uname -s)" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.deeplink.channel.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.deeplink.channel</string>
<key>ProgramArguments</key><array>
<string>$INSTALL_DIR/.venv/bin/python</string><string>-u</string><string>$INSTALL_DIR/hermes_bridge.py</string>
</array>
<key>EnvironmentVariables</key><dict>
<key>BROKER_URL</key><string>$BROKER_URL</string>
<key>BROKER_TOKEN</key><string>$BROKER_TOKEN</string>
<key>DEVICE_ID</key><string>$DEVICE_ID</string>
<key>DEVICE_NAME</key><string>$DEVICE_NAME</string>
<key>HERMES_URL</key><string>$HERMES_URL</string>
<key>HERMES_KEY</key><string>$HERMES_KEY</string>
</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$INSTALL_DIR/channel.log</string>
<key>StandardErrorPath</key><string>$INSTALL_DIR/channel-error.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/com.deeplink.channel" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
else
  SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_DIR/deeplink-channel.service" <<EOF
[Unit]
Description=DeepLink Agent Channel
After=network-online.target

[Service]
EnvironmentFile=$INSTALL_DIR/channel.env
ExecStart=$INSTALL_DIR/.venv/bin/python -u $INSTALL_DIR/hermes_bridge.py
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now deeplink-channel
fi

sleep 2
echo "DeepLink Agent Channel installed and connected: $DEVICE_NAME"
echo "Diagnostics: $INSTALL_DIR/channel-error.log"
"""


@app.post("/v1/nodes/register")
async def register_node(
    registration: NodeRegistration,
    identity: NodeIdentity = Depends(require_node),
) -> dict[str, Any]:
    assert_node_device(registration.device_id, identity)
    async with state_lock:
        nodes[registration.device_id] = NodeState(registration, identity.owner_id)
    with database() as db:
        db.execute(
            """
            UPDATE devices SET name = ?, capabilities_json = ?, endpoint = ?, last_seen_at = ?
            WHERE id = ? AND owner_id = ?
            """,
            (registration.name, json.dumps(registration.capabilities), registration.endpoint, iso_now(), registration.device_id, identity.owner_id),
        )
    return {"ok": True}


@app.post("/v1/nodes/{device_id}/heartbeat")
async def heartbeat(device_id: str, identity: NodeIdentity = Depends(require_node)) -> dict[str, Any]:
    assert_node_device(device_id, identity)
    node = nodes.get(device_id)
    if node is None:
        raise HTTPException(status_code=404, detail="device is not registered")
    node.last_seen_at = utc_now()
    with database() as db:
        db.execute("UPDATE devices SET last_seen_at = ? WHERE id = ?", (iso_now(), device_id))
    return {"ok": True}


@app.get("/v1/devices")
def list_devices(user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    now = utc_now()
    with database() as db:
        rows = db.execute(
            "SELECT id, name, endpoint, last_seen_at FROM devices WHERE owner_id = ? AND disabled = 0",
            (user.id,),
        ).fetchall()
    data = []
    for row in rows:
        node = nodes.get(row["id"])
        last_seen = node.last_seen_at if node else (
            datetime.fromisoformat(row["last_seen_at"]) if row["last_seen_at"] else None
        )
        is_online = bool(
            last_seen
            and (now - last_seen).total_seconds() < int(runtime_setting("online_timeout_seconds", "75"))
        )
        with database() as db:
            agent_rows = db.execute(
                "SELECT id, name, kind, status, version FROM agents WHERE device_id = ? AND owner_id = ? AND status != 'offline'",
                (row["id"], user.id),
            ).fetchall()
        agents_list = [{"id": a["id"], "name": a["name"], "kind": a["kind"], "status": a["status"], "version": a["version"]} for a in agent_rows]
        data.append(
            {
                "id": row["id"],
                "name": row["name"],
                "kind": "brokerRelay",
                "endpoint": row["endpoint"],
                "isOnline": is_online,
                "agentCount": len(agents_list),
                "agents": agents_list,
                "lastSeenAt": last_seen,
            }
        )
    return {"data": data}


@app.delete("/v1/devices/{device_id}")
def delete_device(device_id: str, user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    with database() as db:
        cursor = db.execute(
            "UPDATE devices SET disabled = 1 WHERE id = ? AND owner_id = ? AND disabled = 0",
            (device_id, user.id),
        )
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="device not found")
    nodes.pop(device_id, None)
    audit("user", user.id, "revoke_device", "device", device_id)
    return {"ok": True}


@app.get("/v1/devices/{device_id}/agents")
def list_agents(device_id: str, user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    now = utc_now()
    timeout = int(runtime_setting("online_timeout_seconds", "75"))
    cutoff = now - timedelta(seconds=timeout) if timeout else now
    with database() as db:
        rows = db.execute(
            "SELECT id, device_id, name, kind, endpoint, version, status, capabilities_json, skills_json, profile_json, last_seen_at, created_at FROM agents WHERE device_id = ? AND owner_id = ? ORDER BY kind, name",
            (device_id, user.id),
        ).fetchall()
    data = []
    for row in rows:
        last_seen = datetime.fromisoformat(row["last_seen_at"]) if row["last_seen_at"] else None
        data.append({
            "id": row["id"],
            "deviceId": row["device_id"],
            "name": row["name"],
            "kind": row["kind"],
            "endpoint": row["endpoint"],
            "version": row["version"],
            "status": row["status"],
            "isOnline": bool(last_seen and (now - last_seen).total_seconds() < timeout) if timeout else True,
            "capabilities": json.loads(row["capabilities_json"] or "[]"),
            "skills": json.loads(row["skills_json"] or "[]"),
            "profile": json.loads(row["profile_json"] or "{}"),
            "lastSeenAt": last_seen,
        })
    return {"data": data}


@app.post("/v1/agents/register")
def register_agent(registration: AgentRegistration, identity: NodeIdentity = Depends(require_node)) -> dict[str, Any]:
    assert_node_device(registration.id, identity)
    with database() as db:
        db.execute(
            """INSERT OR REPLACE INTO agents(id, device_id, owner_id, name, kind, endpoint, version, status, capabilities_json, skills_json, last_seen_at, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT created_at FROM agents WHERE id = ?), ?))""",
            (
                registration.id,
                identity.device_id,
                identity.owner_id,
                registration.name,
                registration.kind,
                registration.endpoint,
                registration.version,
                registration.status,
                json.dumps(registration.capabilities),
                json.dumps(registration.skills),
                iso_now(),
                registration.id,
                iso_now(),
            ),
        )
    audit("node", registration.id, "register_agent", "agent", registration.id)
    return {"ok": True}


@app.post("/v1/agents/{agent_id}/heartbeat")
def agent_heartbeat(agent_id: str, identity: NodeIdentity = Depends(require_node)) -> dict[str, Any]:
    with database() as db:
        row = db.execute("SELECT device_id FROM agents WHERE id = ? AND owner_id = ?", (agent_id, identity.owner_id)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="agent not found")
        assert_node_device(agent_id, identity)
        db.execute("UPDATE agents SET last_seen_at = ? WHERE id = ?", (iso_now(), agent_id))
    return {"ok": True}


@app.put("/v1/devices/{device_id}")
def update_device(device_id: str, body: DeviceUpdate, user: UserIdentity = Depends(require_user)) -> dict[str, Any]:
    with database() as db:
        updates: list[str] = []
        params: list[Any] = []
        if body.name is not None:
            updates.append("name = ?")
            params.append(body.name)
        if body.endpoint is not None:
            updates.append("endpoint = ?")
            params.append(body.endpoint)
        if not updates:
            raise HTTPException(status_code=400, detail="no fields to update")
        params.extend([device_id, user.id])
        cursor = db.execute(
            f"UPDATE devices SET {', '.join(updates)} WHERE id = ? AND owner_id = ? AND disabled = 0",
            params,
        )
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="device not found")
    audit("user", user.id, "update_device", "device", device_id)
    return {"ok": True}


@app.post("/v1/admin/users/{user_id}/disabled")
def set_user_disabled(
    user_id: str,
    disabled: bool = True,
    _: AdminIdentity = Depends(require_admin),
) -> dict[str, Any]:
    with database() as db:
        cursor = db.execute("UPDATE users SET disabled = ? WHERE id = ?", (int(disabled), user_id))
        db.execute("UPDATE devices SET disabled = ? WHERE owner_id = ?", (int(disabled), user_id))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="user not found")
    if disabled:
        for device_id, node in list(nodes.items()):
            if node.owner_id == user_id:
                nodes.pop(device_id, None)
    audit("admin", None, "disable_user" if disabled else "enable_user", "user", user_id)
    return {"ok": True, "disabled": disabled}


@app.get("/v1/nodes/{device_id}/commands/next", response_model=None)
async def next_command(
    device_id: str,
    identity: NodeIdentity = Depends(require_node),
    timeout: float = 25,
) -> Response | Command:
    assert_node_device(device_id, identity)
    node = nodes.get(device_id)
    if node is None:
        raise HTTPException(status_code=404, detail="device is not registered")
    node.last_seen_at = utc_now()
    try:
        return await asyncio.wait_for(node.commands.get(), timeout=min(max(timeout, 1), 30))
    except asyncio.TimeoutError:
        return Response(status_code=204)


@app.post("/v1/nodes/{device_id}/commands/{command_id}/result")
async def submit_result(
    device_id: str,
    command_id: str,
    result: CommandResult,
    identity: NodeIdentity = Depends(require_node),
) -> dict[str, Any]:
    assert_node_device(device_id, identity)
    node = nodes.get(device_id)
    if node is None:
        raise HTTPException(status_code=404, detail="device is not registered")
    node.last_seen_at = utc_now()
    future = pending_results.pop(command_id, None)
    if future is None:
        raise HTTPException(status_code=404, detail="command is no longer pending")
    if not future.done():
        future.set_result(result)
    return {"ok": True}


@app.post("/v1/rpc/{device_id}")
async def rpc(
    device_id: str,
    request: RPCRequest,
    user: UserIdentity = Depends(require_user),
) -> CommandResult:
    node = nodes.get(device_id)
    if node is None or node.owner_id != user.id:
        raise HTTPException(status_code=404, detail="device is not registered")
    if (utc_now() - node.last_seen_at).total_seconds() >= int(runtime_setting("online_timeout_seconds", "75")):
        raise HTTPException(status_code=503, detail="device is offline")

    command = Command(id=str(uuid4()), method=request.method, params=request.params, created_at=utc_now())
    result_future: asyncio.Future[CommandResult] = asyncio.get_running_loop().create_future()
    pending_results[command.id] = result_future
    await node.commands.put(command)

    try:
        result = await asyncio.wait_for(result_future, timeout=RPC_TIMEOUT_SECONDS)
    except asyncio.TimeoutError as exc:
        pending_results.pop(command.id, None)
        record_rpc(user.id, device_id, request.method, False)
        raise HTTPException(status_code=504, detail="node response timed out") from exc

    if not result.ok:
        record_rpc(user.id, device_id, request.method, False)
        raise HTTPException(status_code=502, detail=result.error or "node command failed")
    record_rpc(user.id, device_id, request.method, True)
    return result


def admin_page(online_count: int = 0, message: str = "") -> str:
    with database() as db:
        users = db.execute(
            """
            SELECT u.id, u.username, u.display_name, u.created_at, u.disabled,
                   COUNT(DISTINCT d.id) AS devices,
                   COUNT(DISTINCT r.id) AS rpc_count
            FROM users u
            LEFT JOIN devices d ON d.owner_id = u.id AND d.disabled = 0
            LEFT JOIN rpc_events r ON r.owner_id = u.id
            GROUP BY u.id ORDER BY u.created_at DESC
            """
        ).fetchall()
        events = db.execute(
            "SELECT * FROM audit_events ORDER BY id DESC LIMIT 30"
        ).fetchall()
    user_rows = "".join(
        f"""<tr><td>{html.escape(row['username'] or '')}</td><td>{html.escape(row['display_name'])}</td><td>{row['devices']}</td>
        <td>{row['rpc_count']}</td><td>{'停用' if row['disabled'] else '正常'}</td>
        <td><form method="post" action="/admin/users/{row['id']}/toggle">
        <button>{'启用' if row['disabled'] else '停用'}</button></form></td></tr>"""
        for row in users
    ) or '<tr><td colspan="6">还没有用户</td></tr>'
    event_rows = "".join(
        f"<tr><td>{row['created_at'][:19]}</td><td>{html.escape(row['action'])}</td>"
        f"<td>{html.escape(row['target_type'] or '')}: {html.escape(row['target_id'] or '')}</td></tr>"
        for row in events
    ) or '<tr><td colspan="3">还没有审计记录</td></tr>'
    return f"""<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DeepSeekBalance Control Plane</title><style>
:root{{--ink:#13221c;--green:#147d59;--paper:#f4f1e8;--card:#fffdf7}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--paper);color:var(--ink);font:15px -apple-system,BlinkMacSystemFont,sans-serif}}
main{{max-width:1100px;margin:auto;padding:36px 20px}} header{{display:flex;justify-content:space-between;align-items:end;margin-bottom:24px}}
h1{{font:700 34px Georgia,serif;margin:0}} .badge{{background:#d8eadf;color:var(--green);padding:7px 12px;border-radius:99px}}
section{{background:var(--card);padding:22px;border:1px solid #ddd7c8;border-radius:18px;margin:18px 0;box-shadow:0 12px 30px #263b3020}}
form{{display:flex;gap:8px;align-items:center}} input,button{{padding:10px 13px;border-radius:9px;border:1px solid #cfc8b8}}
button{{background:var(--green);color:white;border:0;cursor:pointer}} table{{width:100%;border-collapse:collapse}} td,th{{padding:11px;border-bottom:1px solid #e7e1d5;text-align:left}}
.qr{{width:240px;display:block;margin:16px 0;image-rendering:pixelated}} code{{display:block;overflow-wrap:anywhere;color:#536057}}
</style></head><body><main><header><div><h1>Agent Control Plane</h1><p>用户、设备、配对与中继运行状态</p></div><span class="badge">{online_count} 个在线 Agent</span></header>
{f'<section>{html.escape(message)}</section>' if message else ''}
<section><h2>创建用户</h2><form method="post" action="/admin/users"><input name="username" placeholder="登录名" required><input name="display_name" placeholder="显示名称" required><input name="password" type="password" placeholder="初始密码（至少 12 位）" required><button>创建账号</button></form></section>
<section><h2>用户</h2><table><thead><tr><th>登录名</th><th>名称</th><th>设备</th><th>RPC</th><th>状态</th><th>操作</th></tr></thead><tbody>{user_rows}</tbody></table></section>
<section><h2>最近审计</h2><table><thead><tr><th>时间</th><th>动作</th><th>目标</th></tr></thead><tbody>{event_rows}</tbody></table></section>
</main></body></html>"""


@app.get("/admin", response_class=HTMLResponse)
def admin_dashboard(_: AdminIdentity = Depends(require_admin)) -> str:
    timeout = int(runtime_setting("online_timeout_seconds", "75"))
    cutoff = utc_now() - timedelta(seconds=timeout)
    online = sum(1 for n in nodes.values() if n.last_seen_at and n.last_seen_at > cutoff)
    return admin_page(online)


@app.post("/admin/users", response_class=HTMLResponse)
def admin_create_user(
    username: str = Form(...),
    display_name: str = Form(...),
    password: str = Form(...),
    admin: AdminIdentity = Depends(require_admin),
) -> str:
    result = create_user_account(
        AdminUserCreate(username=username, display_name=display_name, password=password),
        admin,
    )
    return admin_page(message=f"账号 {result['username']} 已创建。")


@app.post("/admin/users/{user_id}/toggle")
def admin_toggle_user(user_id: str, admin: AdminIdentity = Depends(require_admin)) -> RedirectResponse:
    with database() as db:
        row = db.execute("SELECT disabled FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="user not found")
    set_user_disabled(user_id, not bool(row["disabled"]), admin)
    return RedirectResponse("/admin", status_code=303)
