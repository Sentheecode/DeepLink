import argparse
import json
import os
import secrets
import sys
from urllib import error, parse, request


def create_user(base_url: str, admin_token: str, username: str, display_name: str, password: str) -> dict:
    body = json.dumps(
        {"username": username, "display_name": display_name, "password": password}
    ).encode()
    req = request.Request(
        f"{base_url.rstrip('/')}/v1/admin/users",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {admin_token}",
            "Content-Type": "application/json",
        },
    )
    with request.urlopen(req, timeout=15) as response:
        return json.load(response)


def main() -> None:
    parser = argparse.ArgumentParser(description="DeepSeekBalance administrator")
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create-user", help="Create a user account")
    create.add_argument("--username", required=True)
    create.add_argument("--name", required=True)
    create.add_argument("--password")
    create.add_argument("--url", default=os.environ.get("BROKER_PUBLIC_URL", "http://127.0.0.1:8010"))
    create.add_argument("--admin-token", default=os.environ.get("BROKER_ADMIN_TOKEN", ""))
    args = parser.parse_args()

    if not args.admin_token:
        parser.error("set BROKER_ADMIN_TOKEN or pass --admin-token")
    password = args.password or secrets.token_urlsafe(15)

    try:
        result = create_user(args.url, args.admin_token, args.username, args.name, password)
    except error.HTTPError as exc:
        sys.exit(f"Server returned HTTP {exc.code}: {exc.read().decode()}")

    print(f"User ID: {result['user_id']}")
    print(f"Username: {result['username']}")
    print(f"Initial password: {password}")
    print("Give these credentials to the user through a secure channel.")


if __name__ == "__main__":
    main()
