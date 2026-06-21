#!/usr/bin/env bash
# Ships At Sea dedicated server entrypoint.
#  1. install/update app 3951240 via steamcmd (optionally a beta branch + password)
#  2. seed DedicatedServerSettings.ini if the install didn't ship one
#  3. auto-detect the native Linux launcher and exec it
set -euo pipefail

STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${SAS_APPID:-3951240}"
INSTALL_DIR="${SAS_INSTALL_DIR:-/home/steam/sas}"

# steamcmd must run as `steam` (running as root trips a Steam Cloud sync assertion that aborts
# installs). Start as root only to chown the mounted volumes, then re-exec this script as steam.
if [[ "$(id -u)" == "0" ]]; then
  mkdir -p "${INSTALL_DIR}" /home/steam/Steam
  chown -R steam:steam "${INSTALL_DIR}" /home/steam/Steam 2>/dev/null || true
  exec gosu steam "$0" "$@"
fi

# ---- steamcmd login ----
# App 3951240 requires an account that OWNS Ships At Sea (anonymous => "Missing
# configuration"). After a one-time interactive login (see images/ships-at-sea/README.md)
# the Steam Guard token is cached under the persisted /root/Steam volume, so here we can
# log in with just the username (no password needed, and no 2FA re-prompt).
if [[ -z "${STEAM_USER:-}" ]]; then
  echo "ERROR: STEAM_USER is empty. The Ships At Sea dedicated server needs a Steam account"
  echo "       that owns the game. Set SAS_STEAM_USER (and do the one-time login) — see"
  echo "       images/ships-at-sea/README.md."
  exit 1
fi
if [[ -n "${STEAM_PASS:-}" ]]; then
  login=(+login "${STEAM_USER}" "${STEAM_PASS}")
else
  login=(+login "${STEAM_USER}")   # relies on the cached Steam Guard token in /root/Steam
fi

# ---- beta branch (public test) ----
beta=()
if [[ -n "${SAS_BETA:-}" ]]; then
  beta=(-beta "${SAS_BETA}")
  if [[ -n "${SAS_BETA_PASSWORD:-}" ]]; then
    beta+=(-betapassword "${SAS_BETA_PASSWORD}")
  fi
fi

# Helper: does a runnable server install already exist?
have_install() {
  find "${INSTALL_DIR}" -maxdepth 2 -type f -iname '*Server.sh' 2>/dev/null | grep -q . \
    || find "${INSTALL_DIR}" -path '*/Binaries/Linux/*' -type f -iname '*Server*Shipping*' 2>/dev/null | grep -q .
}

# ---- install / update ----
# steamcmd needs the owning account logged in. With Steam Guard, a token rarely persists
# across container restarts, so the UPDATE is best-effort: if it can't auth but the game is
# already installed (from the one-time login+install, see README), we just launch what's
# there. Set SAS_SKIP_UPDATE=1 to skip steamcmd entirely.
if [[ "${SAS_SKIP_UPDATE:-0}" == "1" ]]; then
  echo "==> SAS_SKIP_UPDATE=1 — skipping steamcmd, launching existing install."
elif [[ -z "${STEAM_PASS:-}" ]] && ! have_install; then
  echo "ERROR: no install present and no SAS_STEAM_PASS / cached token to download with."
  echo "       Do the one-time login+install (README), or set SAS_STEAM_PASS, or SAS_SKIP_UPDATE=1."
  exit 1
else
  echo "==> Updating Ships At Sea (app ${APPID}, branch='${SAS_BETA:-default}') ..."
  if "${STEAMCMDDIR}/steamcmd.sh" \
        +force_install_dir "${INSTALL_DIR}" \
        "${login[@]}" \
        +app_update "${APPID}" "${beta[@]}" validate \
        +quit; then
    echo "==> steamcmd update OK."
  elif have_install; then
    echo "WARN: steamcmd update failed (Steam auth/branch?) — launching the existing install."
  else
    echo "ERROR: steamcmd update failed and no install present. See README for the one-time login."
    exit 1
  fi
fi

# ---- seed config (do not clobber the example the install ships, or your edits) ----
CFG_DIR="${INSTALL_DIR}/SAS/Saved/Config/LinuxServer"
CFG_FILE="${CFG_DIR}/DedicatedServerSettings.ini"
if [[ ! -f "${CFG_FILE}" ]]; then
  echo "==> Seeding ${CFG_FILE}"
  mkdir -p "${CFG_DIR}"
  {
    echo "[/Script/Sas.DedicatedServerSettings]"
    echo "DedicatedServerName=${SAS_SERVER_NAME:-Ships At Sea}"
    # The keys below are best-effort (only DedicatedServerName is documented). Edit the
    # persisted file (volume games_sas_data) to match the example the server ships.
    [[ -n "${SAS_MAXPLAYERS:-}" ]] && echo "MaxPlayers=${SAS_MAXPLAYERS}"
    [[ -n "${SAS_PASSWORD:-}" ]]   && echo "ServerPassword=${SAS_PASSWORD}"
  } > "${CFG_FILE}"
else
  echo "==> Existing ${CFG_FILE} found — leaving it untouched."
fi

# ---- locate the Linux launcher ----
# UE5 dedicated servers ship either a top-level <Name>Server.sh wrapper or a raw
# ELF at <Project>/Binaries/Linux/<Name>Server-Linux-Shipping. The public-test name
# isn't documented yet, so detect it (override with SAS_LAUNCH if needed).
launch=""
if [[ -n "${SAS_LAUNCH:-}" ]]; then
  launch="${INSTALL_DIR}/${SAS_LAUNCH}"
else
  launch="$(find "${INSTALL_DIR}" -maxdepth 2 -type f -iname '*Server.sh' 2>/dev/null | head -1 || true)"
  if [[ -z "${launch}" ]]; then
    launch="$(find "${INSTALL_DIR}" -path '*/Binaries/Linux/*' -type f -iname '*Server*Shipping*' 2>/dev/null | head -1 || true)"
  fi
fi

if [[ -z "${launch}" || ! -f "${launch}" ]]; then
  echo "ERROR: could not find a Linux server launcher under ${INSTALL_DIR}."
  echo "       Set SAS_LAUNCH to the correct path. Candidates found:"
  find "${INSTALL_DIR}" -maxdepth 3 -type f -iname '*server*' 2>/dev/null || true
  exit 1
fi
chmod +x "${launch}" 2>/dev/null || true

echo "==> Launching: ${launch}"
# shellcheck disable=SC2086  # SAS_EXTRA_ARGS is intentionally word-split
exec "${launch}" \
  -Port="${SAS_PORT:-7777}" \
  -QueryPort="${SAS_QUERY_PORT:-15000}" \
  -log ${SAS_EXTRA_ARGS:-}
