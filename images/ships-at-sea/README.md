# ships-at-sea

Custom Docker image for a **Ships At Sea** dedicated server (Steam app **3951240**).

The native-Linux dedicated server was introduced in the **v0.8.7 public test** (up to 16
players), so this is a plain SteamCMD + native-binary image — **no Wine/Proton**. Built and run
by the `games` stack (`stacks/games/compose.yaml`, service `ships-at-sea`).

## How it works

`entrypoint.sh` on every start:
1. `steamcmd +app_update 3951240` — optionally on a beta branch (`SAS_BETA` + `SAS_BETA_PASSWORD`)
   and with an account login (`STEAM_USER`/`STEAM_PASS`, else anonymous).
2. Seeds `SAS/Saved/Config/LinuxServer/DedicatedServerSettings.ini` **only if absent** (won't
   clobber the example the server ships or your edits on the `games_sas_data` volume).
3. Auto-detects the Linux launcher (`*Server.sh`, else `*/Binaries/Linux/*Server*Shipping*`) and
   execs it with `-Port` / `-QueryPort` / `-log`.

## Configuration (env, set in `stacks/games/.env`)

| Var | Default | Notes |
|-----|---------|-------|
| `SAS_BETA` | `public_test` | Confirmed branch name (`publictest` is rejected; `public_test` is accepted). Hidden branch — not shown in app_info. Set `""` for the default build once v0.8.7 ships to stable. |
| `SAS_BETA_PASSWORD` | `SaSPublicTest` | From the official v0.8.7 announcement. |
| `STEAM_USER` / `STEAM_PASS` | _(required)_ | **App 3951240 needs a Steam account that owns Ships At Sea** — anonymous fails with "Missing configuration" on every branch. After the one-time login below, leave `STEAM_PASS` blank (cached token is used). |
| `SAS_SERVER_NAME` | `Ships At Sea` | In-game server name. |
| `SAS_MAXPLAYERS` | `16` | v0.8.7 raised the cap from 8 → 16. |
| `SAS_PASSWORD` | _(empty)_ | Server join password. |
| `SAS_PORT` / `SAS_QUERY_PORT` | `7777` / `15000` | Both published TCP+UDP. |
| `SAS_LAUNCH` | _(auto)_ | Override the launcher path (relative to install root) if detection fails. |
| `SAS_EXTRA_ARGS` | _(empty)_ | Extra args appended to the launch command. |

## One-time login + install (Steam Guard)

App 3951240 requires an owning account, and with Steam Guard a steamcmd token rarely survives
container restarts. So instead of relying on a cached token, do a **one-time login that also
downloads the game** into the persisted `games_sas_data` volume. The entrypoint's update step is
best-effort: on later restarts it tries to update and, if it can't re-auth, just launches the
install that's already there (`have_install` fallback; or force it with `SAS_SKIP_UPDATE=1`).

Run once (it's a real download, several GB), passing your password + Steam Guard code inline so no
TTY is needed (mobile authenticator: current code; email guard: run once without the code to
trigger the email, then again with it):

```bash
docker run --rm \
  -v games_sas_data:/home/steam/sas \
  --entrypoint bash games-ships-at-sea \
  -c '/home/steam/steamcmd/steamcmd.sh +force_install_dir /home/steam/sas \
      +login YOUR_STEAM_USER "PASSWORD" "STEAMGUARDCODE" \
      +app_update 3951240 -beta public_test -betapassword SaSPublicTest validate +quit'
# success ends with: Success! App '3951240' fully installed
```

Then set `SAS_STEAM_USER` in `stacks/games/.env` and
`docker compose -p games --env-file stacks/games/.env -f stacks/games/compose.yaml up -d ships-at-sea`.

> **Easiest long-term:** a dedicated Steam account that owns the game with Steam Guard **disabled** —
> set `SAS_STEAM_USER` + `SAS_STEAM_PASS` in `.env` and the server self-updates on every restart with
> no interactive step. To update the test build by hand later, just re-run the command above.

## Caveats

- **Bleeding edge.** This targets a public-test build; the Linux server and its exact
  launch flags / ini keys may change. Only `DedicatedServerName` is officially documented;
  other ini keys here are best-effort — reconcile against the example file the server writes
  into the `games_sas_data` volume.
- If the launcher isn't found, the entrypoint prints the candidate paths it saw — set
  `SAS_LAUNCH` accordingly.
- Ports `7777` and `15000` (UDP) must be forwarded on the router for WAN play.
