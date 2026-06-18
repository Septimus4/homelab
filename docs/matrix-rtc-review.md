# Matrix + Element Call (MatrixRTC / LiveKit) deployment guide

How the `matrix` stack is set up for **reliable group calls on PC and mobile, both on the LAN and
externally**. Placeholder values used throughout: domain `example.com`, public IP `203.0.113.10`,
LAN host `192.168.1.2`.

## Architecture

The modern, recommended Element Call stack is:

```
Synapse  ──  Element Web / Element X        (clients)
   │
   ├─ .well-known advertises an "RTC focus" (LiveKit) via m.rtc_foci (MSC4143/MSC4195)
   │
LiveKit SFU  ◀── lk-jwt-service (MatrixRTC Authorization Service: mints LiveKit JWTs for
                 authenticated Matrix users; gates room creation)
```

Synapse must enable the MSCs Element Call relies on: **MSC3266** (room summary), **MSC4140**
(delayed events / "delayed leave"), **MSC4143** (RTC foci), **MSC4222**, plus
`max_event_delay_duration` and the matching `rc_message` / `rc_delayed_event_mgmt` rate limits.

## coturn is not needed

| | Legacy Matrix 1:1 VoIP | Element Call / MatrixRTC |
|---|---|---|
| Media path | peer-to-peer, needs a TURN relay | via the **LiveKit SFU** (public-IP server) |
| TURN | coturn (`turn_uris` in Synapse) | **LiveKit's own** ICE (host/srflx; optional built-in TURN) |
| Clients | old Element clients | Element Web/Desktop, **Element X (Android/iOS)** |

Element Call only talks to LiveKit; it never uses coturn. So:

- **Don't run coturn.** Remove `turn_uris` + `turn_shared_secret` from `homeserver.yaml`.
- For clients on networks that block UDP entirely, enable **LiveKit's built-in TURN** rather than a
  separate coturn (see below). For normal home/mobile networks, UDP media + the TCP `7881` fallback
  is enough.

## Internal vs. external: let ICE do its job

The common failure ("works externally but not on the LAN", or vice-versa) comes from pinning LiveKit
to a single IP:

```yaml
rtc:
  node_ip: "203.0.113.10"   # public IP, hard-pinned
  external_ip_only: true    # advertise ONLY the public IP  ← breaks internal clients
```

With `external_ip_only`, LAN clients receive only the public IP and must "hairpin" back out through
the router — which fails without NAT reflection. Instead, let LiveKit advertise both candidates:

```yaml
rtc:
  use_external_ip: true              # STUN-discover the public IP → srflx candidate
  stun_servers:
    - stun.l.google.com:19302
    - stun1.l.google.com:19302
  tcp_port: 7881
  port_range_start: 52000
  port_range_end: 52127
  enable_loopback_candidate: false
  interfaces:
    includes:
      - eth0                         # the real host NIC — keeps docker-bridge 172.x junk out
```

Run LiveKit with `network_mode: host`. It then offers a **host candidate** (LAN IP → internal
clients connect directly) and a **srflx candidate** (public IP → external clients via the
port-forward); ICE picks the working path per client. Restricting `interfaces.includes` to the real
NIC suppresses docker-bridge `172.x` candidates that otherwise slow call setup.

## Service config

### LiveKit
- Use `use_external_ip` + `stun_servers` (above); do **not** set `external_ip_only`/`node_ip`.
- `room.auto_create: false` — room creation is gated by lk-jwt-service +
  `LIVEKIT_FULL_ACCESS_HOMESERVERS=example.com`, so only authorized Matrix users open rooms.
- Webhook → `https://matrix-rtc.example.com/livekit/jwt/sfu_webhook`.

### lk-jwt-service
- Bind with `LIVEKIT_JWT_BIND=:8080` (the older `LIVEKIT_JWT_PORT` is deprecated).
- Optionally use `LIVEKIT_KEY_FROM_FILE` / `LIVEKIT_SECRET_FROM_FILE` for file-based secrets.

### Traefik routes for lk-jwt
A prefixed router (`PathPrefix(/livekit/jwt)`, strip prefix) covers most access. The **root** router
must also include the MSC4140 endpoint `/delegate_delayed_leave` so calls end cleanly when a client
drops:

```
Host(`matrix-rtc.example.com`) && (Path(`/get_token`) || Path(`/sfu/get`)
  || Path(`/sfu_webhook`) || Path(`/healthz`) || Path(`/delegate_delayed_leave`))
```

### well-known (`/.well-known/matrix/client`)
Advertise both the stable and unstable RTC-foci keys for broad client compatibility:

```json
"m.rtc_foci": [
  { "type": "livekit", "livekit_service_url": "https://matrix-rtc.example.com/livekit/jwt" }
],
"org.matrix.msc4143.rtc_foci": [
  { "type": "livekit", "livekit_service_url": "https://matrix-rtc.example.com/livekit/jwt" }
]
```

### (Optional) LiveKit built-in TURN — only for blocked-UDP networks
```yaml
turn:
  enabled: true
  udp_port: 3478
  relay_range_start: 52200
  relay_range_end: 52299
```
Forward `udp/3478` to the host. TURN/TLS on `443` gives the broadest corporate-firewall coverage but
conflicts with Traefik on `443` (single public IP) — skip unless you specifically need it.

## DNS & firewall

**DNS:** public `A`/`AAAA` records → your public IP for `example.com`, `element`, `call`,
`matrix-rtc`, `synapse-admin`. Federation uses `.well-known/matrix/server` = `example.com:443`
(no SRV record needed). Optional split-horizon: resolve those hostnames to the LAN IP internally so
LAN signalling goes direct (media is handled by ICE host candidates regardless).

**Port-forwards (→ host):**

| Port | Proto | Purpose |
|------|-------|---------|
| 443 | tcp | Traefik: element-web, call, matrix-rtc (signalling + JWT), Synapse client |
| 8448 | tcp | Synapse federation (only if you federate) |
| **52000–52127** | **udp** | **LiveKit media (required for external calls)** |
| **7881** | **tcp** | **LiveKit ICE/TCP fallback (UDP-blocked networks)** |
| 3478 | udp | only if LiveKit built-in TURN is enabled |

**Hairpin NAT** (optional): with the host ICE candidate present, internal media goes direct, so NAT
reflection is only a belt-and-suspenders fallback (e.g. for a guest VLAN that can't reach the host
directly).

## Pin image versions

Don't run `:latest` — it drifts silently. Pin each image to a known stable tag and bump
deliberately: `ghcr.io/element-hq/synapse`, `ghcr.io/element-hq/element-web`,
`ghcr.io/element-hq/element-call`, `livekit/livekit-server`, `ghcr.io/element-hq/lk-jwt-service`.
Back up first — Synapse upgrades can run DB migrations, so start Synapse alone and watch the logs
after bumping.

## Element X (Android) note

`MISSING_MATRIX_RTC_TRANSPORT` has been reported on some Element X builds even against a correct
server — it's tracked as a **client-side** bug. To stay clear of it: advertise both `m.rtc_foci` +
`org.matrix.msc4143.rtc_foci`, keep the Synapse MSC flags, and test with a current Element X. PC and
Element X share the same MatrixRTC backend, so once the above is in place both use the identical
LiveKit path.

## Test matrix

| Client | Internal (LAN) | External (cellular / off-site) |
|--------|----------------|-------------------------------|
| Element Web/Desktop | join call → `chrome://webrtc-internals` selected pair uses the LAN IP | selected pair uses the public IP |
| Element X (Android) | 1:1 + group call connects | 1:1 + group call connects over cellular |

Also confirm: `curl https://matrix-rtc.example.com/livekit/jwt/healthz` → `200`; a call creates a
room only when authorized (`auto_create=false`); federation returns `200` on `:8448` if used.
