# JustKeepRemote Server (dev)

Self-hosted RustDesk server stack: **hbbs** (ID/rendezvous) + **hbbr** (relay).

## Run (local Docker)
```powershell
docker compose up -d        # start
docker compose ps           # status
docker compose logs -f hbbs # follow logs
docker compose down         # stop
```

## Ports
| Port | Service | Purpose |
|------|---------|---------|
| 21115/tcp | hbbs | NAT type test |
| 21116/tcp | hbbs | TCP hole punching / signaling |
| 21116/udp | hbbs | ID registration / heartbeat |
| 21118/tcp | hbbs | web client (optional) |
| 21117/tcp | hbbr | relay |
| 21119/tcp | hbbr | web client relay (optional) |

## Client configuration
Point the JustKeepRemote / RustDesk client at this server:
- **ID server:**    `<host-ip>` (e.g. `127.0.0.1` for same machine, or LAN IP)
- **Relay server:** `<host-ip>`
- **Key:** the contents of `data/id_ed25519.pub`

> The current dev key fingerprint is recorded in the progress log. The private
> key `data/id_ed25519` is a secret and is gitignored — never commit it.

## Data
`data/` holds the server keypair (`id_ed25519` / `.pub`) and the peer DB
(`db_v2.sqlite3`). It is gitignored. Deleting it regenerates a NEW keypair,
which invalidates all previously configured clients.

## Production
Target is a self-hosted single-node Kubernetes cluster. The compose services map
to two Deployments (hbbs, hbbr) + a Service exposing the ports above, with the
`data/` volume backed by a PersistentVolume. To be built in a later milestone.
