import asyncio
import os
import tempfile
import unittest
from base64 import b64encode
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("BROKER_ADMIN_TOKEN", "test-admin-token")
os.environ.setdefault("BROKER_PUBLIC_URL", "https://broker.example.com")

import app as broker
from fastapi.testclient import TestClient


class BrokerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        broker.configure_database(Path(self.temp_dir.name) / "broker.db")
        broker.nodes.clear()
        broker.pending_results.clear()

    async def asyncTearDown(self) -> None:
        self.temp_dir.cleanup()

    async def test_password_login_returns_user_session(self) -> None:
        created = broker.create_user_account(
            broker.AdminUserCreate(username="alice", display_name="Alice", password="correct-horse-battery"),
            broker.AdminIdentity(),
        )

        session = broker.login(broker.LoginRequest(username="alice", password="correct-horse-battery"))

        self.assertEqual(session["display_name"], "Alice")
        self.assertEqual(session["user_id"], created["user_id"])
        self.assertEqual(broker.require_user_token(session["access_token"]).id, created["user_id"])

    async def test_password_login_rejects_wrong_password(self) -> None:
        broker.create_user_account(
            broker.AdminUserCreate(username="alice", display_name="Alice", password="correct-horse-battery"),
            broker.AdminIdentity(),
        )

        with self.assertRaises(broker.HTTPException) as context:
            broker.login(broker.LoginRequest(username="alice", password="wrong-password"))
        self.assertEqual(context.exception.status_code, 401)

    async def test_registration_returns_usable_user_session(self) -> None:
        session = broker.register(
            broker.RegisterRequest(
                username="new-user",
                email="new-user@example.com",
                password="registration-password",
            )
        )

        self.assertEqual(session["display_name"], "new-user")
        self.assertEqual(broker.require_user_token(session["access_token"]).id, session["user_id"])

    async def test_database_configuration_is_idempotent(self) -> None:
        database_path = Path(self.temp_dir.name) / "broker.db"

        broker.configure_database(database_path)
        broker.configure_database(database_path)

        with broker.database() as db:
            columns = {row["name"] for row in db.execute("PRAGMA table_info(users)").fetchall()}
        self.assertIn("email", columns)

    async def test_runtime_policy_is_stored_in_database(self) -> None:
        broker.set_runtime_setting("node_enrollment_minutes", "30")
        alice = self._create_user("Alice")

        enrollment = broker.create_enrollment(alice)

        remaining = enrollment["expires_at"] - broker.utc_now()
        self.assertGreater(remaining.total_seconds(), 29 * 60)

    async def test_users_only_see_their_own_devices(self) -> None:
        alice = self._create_user("Alice")
        bob = self._create_user("Bob")
        enrollment = broker.create_enrollment(alice)
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
        )
        await broker.register_node(
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
            broker.require_node_token(node_session["node_token"]),
        )

        self.assertEqual(len(broker.list_devices(alice)["data"]), 1)
        self.assertEqual(broker.list_devices(bob)["data"], [])

    async def test_node_token_cannot_control_another_device(self) -> None:
        alice = self._create_user("Alice")
        first = broker.create_enrollment(alice)
        second = broker.create_enrollment(alice)
        first_node = broker.consume_enrollment(
            first["token"],
            broker.NodeRegistration(device_id="first", name="First"),
        )
        broker.consume_enrollment(
            second["token"],
            broker.NodeRegistration(device_id="second", name="Second"),
        )
        identity = broker.require_node_token(first_node["node_token"])

        with self.assertRaises(broker.HTTPException) as context:
            await broker.heartbeat("second", identity)
        self.assertEqual(context.exception.status_code, 403)

    async def test_rpc_round_trip(self) -> None:
        user = self._create_user("Alice")
        enrollment = broker.create_enrollment(user)
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="test-node", name="Test Node"),
        )
        node_identity = broker.require_node_token(node_session["node_token"])
        await broker.register_node(
            broker.NodeRegistration(device_id="test-node", name="Test Node"),
            node_identity,
        )

        rpc_task = asyncio.create_task(
            broker.rpc("test-node", broker.RPCRequest(method="list_sessions", params={}), user)
        )
        command = await broker.next_command("test-node", node_identity, timeout=1)

        self.assertEqual(command.method, "list_sessions")
        await broker.submit_result(
            "test-node",
            command.id,
            broker.CommandResult(ok=True, data={"data": []}),
            node_identity,
        )
        result = await rpc_task
        self.assertTrue(result.ok)
        self.assertEqual(broker.user_usage(user)["rpc_count"], 1)

    async def test_repeated_node_registration_preserves_pending_command_queue(self) -> None:
        user = self._create_user("Alice")
        enrollment = broker.create_enrollment(user)
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="test-node", name="Test Node"),
        )
        identity = broker.require_node_token(node_session["node_token"])
        registration = broker.NodeRegistration(device_id="test-node", name="Test Node")
        await broker.register_node(registration, identity)
        original_queue = broker.nodes["test-node"].commands

        await broker.register_node(registration, identity)

        self.assertIs(broker.nodes["test-node"].commands, original_queue)

    async def test_node_can_register_agent_belonging_to_its_device(self) -> None:
        user = self._create_user("Alice")
        enrollment = broker.create_enrollment(user)
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
        )
        node_identity = broker.require_node_token(node_session["node_token"])

        broker.register_agent(
            broker.AgentRegistration(id="alice-mac-hermes", name="Hermes", version="1.2.3"),
            node_identity,
        )
        broker.agent_heartbeat("alice-mac-hermes", node_identity)

        devices = broker.list_devices(user)["data"]
        self.assertEqual(devices[0]["agentCount"], 1)
        self.assertEqual(devices[0]["agents"][0]["id"], "alice-mac-hermes")
        self.assertTrue(devices[0]["agents"][0]["isOnline"])

    async def test_rpc_rejects_agent_from_another_device_and_routes_selected_agent(self) -> None:
        user = self._create_user("Alice")
        first = broker.create_enrollment(user)
        second = broker.create_enrollment(user)
        first_session = broker.consume_enrollment(
            first["token"],
            broker.NodeRegistration(device_id="first", name="First"),
        )
        second_session = broker.consume_enrollment(
            second["token"],
            broker.NodeRegistration(device_id="second", name="Second"),
        )
        first_identity = broker.require_node_token(first_session["node_token"])
        second_identity = broker.require_node_token(second_session["node_token"])
        await broker.register_node(broker.NodeRegistration(device_id="first", name="First"), first_identity)
        await broker.register_node(broker.NodeRegistration(device_id="second", name="Second"), second_identity)
        broker.register_agent(broker.AgentRegistration(id="first-hermes", name="Hermes"), first_identity)
        broker.register_agent(broker.AgentRegistration(id="second-hermes", name="Hermes"), second_identity)

        with self.assertRaises(broker.HTTPException) as context:
            await broker.rpc(
                "first",
                broker.RPCRequest(method="list_sessions", params={}, agent_id="second-hermes"),
                user,
            )
        self.assertEqual(context.exception.status_code, 404)

        rpc_task = asyncio.create_task(
            broker.rpc(
                "first",
                broker.RPCRequest(method="list_sessions", params={}, agent_id="first-hermes"),
                user,
            )
        )
        command = await broker.next_command("first", first_identity, timeout=1)
        self.assertEqual(command.agent_id, "first-hermes")
        await broker.submit_result(
            "first",
            command.id,
            broker.CommandResult(ok=True, data={"data": []}),
            first_identity,
        )
        self.assertTrue((await rpc_task).ok)

    async def test_node_cannot_take_over_agent_registered_to_another_device(self) -> None:
        user = self._create_user("Alice")
        first = broker.create_enrollment(user)
        second = broker.create_enrollment(user)
        first_session = broker.consume_enrollment(
            first["token"],
            broker.NodeRegistration(device_id="first", name="First"),
        )
        second_session = broker.consume_enrollment(
            second["token"],
            broker.NodeRegistration(device_id="second", name="Second"),
        )
        first_identity = broker.require_node_token(first_session["node_token"])
        second_identity = broker.require_node_token(second_session["node_token"])
        broker.register_agent(broker.AgentRegistration(id="shared-agent", name="First Agent"), first_identity)

        with self.assertRaises(broker.HTTPException) as context:
            broker.register_agent(
                broker.AgentRegistration(id="shared-agent", name="Hijacked Agent"),
                second_identity,
            )

        self.assertEqual(context.exception.status_code, 403)

    async def test_empty_command_poll_handles_python_310_asyncio_timeout(self) -> None:
        class LegacyAsyncioTimeoutError(Exception):
            pass

        class EmptyQueue:
            async def get(self) -> None:
                raise LegacyAsyncioTimeoutError

        user = self._create_user("Alice")
        enrollment = broker.create_enrollment(user)
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="test-node", name="Test Node"),
        )
        node_identity = broker.require_node_token(node_session["node_token"])
        await broker.register_node(
            broker.NodeRegistration(device_id="test-node", name="Test Node"),
            node_identity,
        )
        broker.nodes["test-node"].commands = EmptyQueue()

        with patch.object(broker.asyncio, "TimeoutError", LegacyAsyncioTimeoutError):
            response = await broker.next_command("test-node", node_identity, timeout=1)

        self.assertEqual(response.status_code, 204)

    async def test_user_can_revoke_own_device(self) -> None:
        alice = self._create_user("Alice")
        enrollment = broker.create_enrollment(alice)
        broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
        )

        broker.delete_device("alice-mac", alice)

        self.assertEqual(broker.list_devices(alice)["data"], [])

    async def test_user_cannot_revoke_another_users_device(self) -> None:
        alice = self._create_user("Alice")
        bob = self._create_user("Bob")
        enrollment = broker.create_enrollment(alice)
        broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
        )

        with self.assertRaises(broker.HTTPException) as context:
            broker.delete_device("alice-mac", bob)
        self.assertEqual(context.exception.status_code, 404)

    async def test_admin_can_disable_user(self) -> None:
        alice = self._create_user("Alice")

        broker.set_user_disabled(alice.id, True, broker.AdminIdentity())

        with self.assertRaises(broker.HTTPException):
            broker.user_usage(alice)

    async def test_admin_console_uses_basic_auth_and_renders_user(self) -> None:
        client = TestClient(broker.app)
        self.assertEqual(client.get("/admin").status_code, 401)
        credentials = b64encode(b"admin:test-admin-token").decode()

        response = client.post(
            "/admin/users",
            data={"username": "console-user", "display_name": "Console User", "password": "console-password-123"},
            headers={"Authorization": f"Basic {credentials}"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn("Console User", response.text)
        self.assertIn("console-user", response.text)

    async def test_installer_runs_registration_check_and_unbuffered_bridge(self) -> None:
        script = broker.installer_script("enrollment-token")

        self.assertIn("/v1/enrollments/consume", script)
        self.assertIn('(cd "$INSTALL_DIR" &&', script)
        self.assertIn('channel.main --check', script)
        self.assertIn("<string>-u</string>", script)
        self.assertIn("<string>-m</string>", script)
        self.assertIn("<string>channel.main</string>", script)
        self.assertIn("<key>WorkingDirectory</key>", script)
        self.assertIn("ExecStart=", script)
        self.assertIn(" -u -m channel.main", script)
        self.assertIn("channel-error.log", script)
        self.assertIn('.deeplink-channel', script)
        self.assertIn("com.deeplink.channel", script)
        self.assertNotIn("deepseekbalance-channel", script)

    async def test_installer_discovers_and_verifies_hermes_key_before_consuming_invite(self) -> None:
        script = broker.installer_script("enrollment-token")

        self.assertIn('HERMES_ENV="${HERMES_ENV:-$HOME/.hermes/.env}"', script)
        self.assertIn('HERMES_KEY="${API_SERVER_KEY:-}"', script)
        self.assertIn('Authorization: Bearer $HERMES_KEY', script)
        self.assertIn('$HERMES_URL/api/sessions', script)
        self.assertLess(script.index('$HERMES_URL/api/sessions'), script.index("/v1/enrollments/consume"))

    async def test_downloading_installer_does_not_consume_enrollment(self) -> None:
        alice = self._create_user("Alice")
        enrollment = broker.create_enrollment(alice)

        script = await broker.channel_installer(enrollment["token"])
        node_session = broker.consume_enrollment(
            enrollment["token"],
            broker.NodeRegistration(device_id="alice-mac", name="Alice Mac"),
        )

        self.assertIn("/v1/enrollments/consume", script)
        self.assertEqual(node_session["device_id"], "alice-mac")

    def _create_user(self, name: str) -> broker.UserIdentity:
        username = name.lower().replace(" ", "-")
        broker.create_user_account(
            broker.AdminUserCreate(username=username, display_name=name, password="test-password-123"),
            broker.AdminIdentity(),
        )
        session = broker.login(broker.LoginRequest(username=username, password="test-password-123"))
        return broker.require_user_token(session["access_token"])


if __name__ == "__main__":
    unittest.main()
