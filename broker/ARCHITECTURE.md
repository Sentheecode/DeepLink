# Control Plane Architecture

## Current Single-Server Topology

```text
iOS App -- HTTPS/user token -----------+
                                        |
Agent Channel -- HTTPS/node token --> Nginx --> FastAPI Control Plane
                                        |             |
Administrator -- HTTPS/Basic Auth ------+             +-- SQLite
                                                      +-- in-memory relay queues
```

## Responsibility Boundaries

| Area | Current implementation | Persistent |
| --- | --- | --- |
| Identity | Username/password login with rotating user access token | Yes |
| Authorization | User/device ownership checks on every protected API | Yes |
| Device registry | User-owned Agent devices and revocation | Yes |
| Broker relay | Long polling commands and RPC results | No |
| Usage | RPC success/failure counters | Yes |
| Audit | Pairing, activation, disable, and revoke events | Yes |
| Admin frontend | Basic-auth protected HTML console | Generated |

Passwords are stored as salted PBKDF2 hashes. Long-lived user and node tokens are random values, and the server stores only their SHA-256 hashes. One-time Agent enrollment links expire and are marked consumed after use.

## API Groups

- `/health`: public health check
- `/v1/auth/login`: username/password authentication
- `/v1/me*`: current user and usage
- `/v1/devices*`: current user's devices
- `/v1/enrollments`: Agent pairing invitation
- `/v1/nodes/*`: node-only registration and command polling
- `/v1/rpc/*`: user-to-node relay
- `/v1/admin/*`: administrator API
- `/admin`: administrator web console
- `/channel/*`: one-time Agent installer

## Scaling Path

The current service must run as one Uvicorn worker because pending RPC futures and command queues are in process memory.

For multiple instances:

1. Move users, devices, invites, usage, and audit tables to PostgreSQL.
2. Move online presence, command queues, results, and RPC timeouts to Redis Streams.
3. Place multiple stateless FastAPI instances behind a load balancer.
4. Add an asynchronous worker for retention, quota, billing, and notifications.
5. Replace administrator Basic Auth with a separate administrator identity provider.

## Commercial Services To Add Later

- external identity provider for Apple/email login and account recovery
- subscriptions, plans, entitlements, and per-plan quotas
- privacy export and account deletion jobs
- encrypted database backups and restore drills
- metrics, alerting, abuse detection, and incident response
