# Hetzner Port Map

Current deployment reference for the Hetzner host `ubuntu-4gb-nbg1-1`.
Updated from the live box on May 2, 2026.

## Exposure classes

### Public edge

These are the ports intended to be reached through the normal web entrypoint.

| Port | Protocol | Service | Notes |
| --- | --- | --- | --- |
| `80` | TCP | Caddy | HTTP entrypoint / redirect layer |
| `443` | TCP | Caddy | HTTPS + websocket proxy |

### VPN-only game access

These are allowed from `10.8.0.0/24` in `ufw` and should stay private to the
WireGuard network unless we deliberately change policy.

| Port | Protocol | Service | Notes |
| --- | --- | --- | --- |
| `43594` | TCP | Legacy game server | Direct game protocol |
| `43494` | TCP | Legacy websocket listener | Web client / VPN path |
| `43596` | TCP | Java 21 game server | Direct game protocol for iOS/native testing |
| `8080` | TCP | Caddy | VPN-only hosted client path |

### Internal-only listeners

These are bound by services on the host but are not opened in `ufw`.

| Port | Protocol | Service | Notes |
| --- | --- | --- | --- |
| `43496` | TCP | Java 21 websocket listener | Reached through Caddy `/rsc21-ws` |
| `43595` | TCP | Java 21 REST API | Local auth/status/profile API |

## Java 21 deployment

### Service

- `systemd`: `openrsc21.service`
- install root: `/opt/openrsc21/server`
- database: cloned from the live server into `/opt/openrsc21/server/inc/sqlite/preservation.db`

### Ports

- game TCP: `43596`
- game websocket: `43496`
- REST API: `43595`

### Browser entrypoint

- `https://earlybird.novelgames.dev/rsc21/mudclient21.html`
- websocket path: `/rsc21-ws`

## Current `ufw` intent

The working policy is:

- raw game ports stay private to the VPN
- the Java 21 REST API stays closed externally
- browser traffic goes through Caddy instead of directly to backend ports

The Java 21 direct game port was explicitly added as VPN-only with:

```bash
ufw allow from 10.8.0.0/24 to any port 43596 proto tcp
```

## Existing mapped VPN-only rules

These were already present on the host and are not part of the Java 21 work,
but they are now mapped:

| Port | Protocol | Owner | Notes |
| --- | --- | --- | --- |
| `43600` | TCP | `2009scape-server` Docker container | Host port forwarded to container `43595/tcp` |
| `43601` | TCP | `2009scape-ws-proxy` Docker container | `websockify` bridge on `0.0.0.0:43601` to `server:43595` |
| `43602` | TCP | `2009scape-socat.service` | Host `socat` bridge from VPN to Docker IP `172.18.0.3:43595` |
| `8500` | TCP | `/opt/2009scape-web/serve.py` | Python-hosted 2009scape web app |

## 2009scape private-service notes

The 2009scape stack is split across a couple of layers:

- Docker app server: `43600 -> container 43595`
- Docker websocket proxy: `43601 -> container 43601`
- Host VPN bridge: `43602 -> 172.18.0.3:43595`
- Hosted web app: `8500 -> /opt/2009scape-web/serve.py`

That means `43600` and `43602` both ultimately reach the 2009scape app
backend, but through different paths:

- `43600` is the direct Docker-published host port
- `43602` is the extra `socat` bridge kept for VPN-only access

If we simplify this later, `43600` and `43602` are the first pair worth
reviewing together so we can decide whether both paths are still needed.
