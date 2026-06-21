# homelab

GitOps-managed Docker Compose stacks for a self-hosted homelab, deployed with
[Komodo](https://komo.do) behind a [Traefik](https://traefik.io) edge.

Everything site-specific (domain, IPs, host NIC, paths) is externalized to gitignored
`.env` files, so this repo is safe to share — see [Configuration](#configuration).

## What's inside

| Stack | Services |
|-------|----------|
| `infra` | Traefik (reverse proxy + ACME), AdGuard Home (DNS), well-known server |
| `matrix` | Synapse, PostgreSQL, Element Web, Element Call, MatrixRTC (LiveKit SFU + lk-jwt-service), synapse-admin |
| `tools` | Dashy (dashboard), Glances (monitoring), code-server (browser IDE) |
| `public-applications` | Yopass, RustDesk relay (hbbs/hbbr), Stirling-PDF, Memcached, a PocketBase app |
| `games` | CS2 dedicated server (kus modded), Ships At Sea dedicated server |
| `komodo` | Komodo Core + MongoDB + Periphery (the GitOps control plane) |

A full Matrix + Element Call / LiveKit deployment guide lives in
[`docs/matrix-rtc-review.md`](docs/matrix-rtc-review.md).

## Architecture

- **Single source of truth:** this Git repo. Each stack is a plain `compose.yaml` plus a
  `.env.example` template; real values live only in a gitignored `.env` on the host.
- **Edge:** Traefik terminates TLS on `:80`/`:443` (+ `:8448` for Matrix federation), routes by
  hostname via the Docker provider, and pulls certs from Let's Encrypt (HTTP-01) or a DNS-01
  resolver for LAN/VPN-only hostnames. A shared external network `infra_default` connects the stacks.
- **Secrets:** never committed. Site config is interpolated from `.env`; application secrets
  (DB passwords, API keys) likewise. See [Security](#secrets--security).

## Repository layout

```
stacks/
  infra/                 traefik, adguard, wellknown
  matrix/                synapse, postgres, element-web, element-call,
                         synapse-admin, lk-jwt-service, livekit
  tools/                 dashy, glances, code-server
  public-applications/   yopass, rustdesk (hbbs/hbbr), stirling-pdf,
                         memcached, pocketbase app
  games/                 cs2 (kus modded), ships-at-sea (+ cs2/custom_files overrides)
komodo/                  Komodo deployment (compose + env template)
images/                  custom image build contexts
  ships-at-sea/          Dockerfile + entrypoint for the Ships At Sea server
docs/                    deployment notes / guides
```

Each stack provides:
- `compose.yaml` — the stack definition (no secrets; uses `${VAR}` interpolation)
- `.env.example` — documented variables with placeholders (committed)
- `.env` — real values (**gitignored**, host-only)

## Prerequisites

- Docker Engine + Compose v2
- A domain you control, with DNS pointing the relevant hostnames at your host
- (Optional) [Komodo](https://komo.do) if you want UI/GitOps-managed deploys instead of raw compose

## Setup

```bash
git clone https://github.com/Septimus4/homelab.git
cd homelab

# 1. shared network (once)
docker network create infra_default

# 2. per stack: create real env from the template and fill it in
for s in infra matrix tools public-applications games; do
  cp "stacks/$s/.env.example" "stacks/$s/.env"   # then edit stacks/$s/.env
done
cp komodo/compose.env.example komodo/compose.env  # then edit

# 3. matrix mounts JSON configs that can't use ${VAR} interpolation — copy + edit:
cp stacks/matrix/element-web/config.json.example stacks/matrix/element-web/config.json
cp stacks/matrix/element-call/config.json.example stacks/matrix/element-call/config.json
#   (replace example.com with your domain in both)

# 4. deploy a stack (preserves the project name)
docker compose -p infra --env-file stacks/infra/.env -f stacks/infra/compose.yaml up -d
#   ...repeat per stack, or adopt them in Komodo as "Files on Server".
```

> **Note:** the `element-*/config.json` files are bind-mounted. Always copy the `.example` to the
> real filename *before* `up` — if the file is missing, Docker silently creates a **directory** in
> its place.

## Configuration

Site-wide values used for compose interpolation (set in the relevant `.env`):

| Variable | Used by | Purpose |
|----------|---------|---------|
| `DOMAIN` | all stacks | base domain for Traefik `Host()` rules and service URLs |
| `SERVER_IP` | infra | LAN IP the AdGuard DNS listener binds to |
| `HOST_NIC` | matrix | host network interface LiveKit gathers ICE candidates on (e.g. `eth0`) |
| `HOMELAB_REPO_PATH` | komodo | absolute path of this repo, bind-mounted into Periphery as `/repo` |

Application secrets (per-stack `.env`, see each `.env.example`): `POSTGRES_PASSWORD`,
`LIVEKIT_KEY`/`LIVEKIT_SECRET`, `OVH_*` (Traefik DNS-01), `HASHED_PASSWORD` (code-server),
`STIRLING_ADMIN_PASSWORD`, `API_FOOTBALL_KEY`, `PB_*`, `GOOGLE_*`, and the Komodo credentials in
`komodo/compose.env`.

## Secrets & security

- **No secrets in the repo.** `**/.env`, `.secrets/`, `komodo/compose.env`, and the real
  `element-*/config.json` are gitignored; only `*.example` templates are committed.
- **Volumes** are declared `external: true` with stable names, so data is never moved or renamed by
  a redeploy.
- **Recommended hardening:** encrypt the `.env` files with
  [SOPS](https://github.com/getsops/sops) + age so they can be committed (encrypted) and decrypted
  at deploy time; scope down any broad host mounts; split the flat `infra_default` into separate
  edge/backend networks.

## License

[GPL-3.0](LICENSE).
