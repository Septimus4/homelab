# Ships At Sea dedicated server (Steam app 3951240).
# Native-Linux build introduced in the v0.8.7 public test — no Wine/Proton needed.
# Base: cm2network/steamcmd (Debian, steamcmd preinstalled at $STEAMCMDDIR).
FROM cm2network/steamcmd:root

# UE5 dedicated-server runtime deps. Most of what UE needs is bundled in the app;
# these cover common dynamic-link gaps (ICU, SSL). ca-certificates is required (steamcmd
# TLS); the rest are best-effort so the build survives base-image distro bumps that rename
# the versioned packages. Add more here if the server logs missing .so files on first launch.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates gosu \
    && (apt-get install -y --no-install-recommends libicu76 libssl3t64 \
        || apt-get install -y --no-install-recommends libicu72 libssl3 \
        || echo "WARN: optional ICU/SSL libs not installed; add the correct names if the server complains") \
    && rm -rf /var/lib/apt/lists/*

# App / install layout. steamcmd must run as the `steam` user (cm2network design): running as
# root puts the Steam dir under /root and trips a Steam Cloud sync assertion that aborts installs.
# The entrypoint starts as root (to chown the mounted volumes) then drops to steam via gosu.
ENV SAS_APPID=3951240 \
    SAS_INSTALL_DIR=/home/steam/sas

RUN mkdir -p /home/steam/sas /home/steam/Steam && chown -R steam:steam /home/steam

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# game (7777) + query (15000), both TCP/UDP — documentation only; published in compose.
EXPOSE 7777/tcp 7777/udp 15000/tcp 15000/udp

ENTRYPOINT ["/entrypoint.sh"]
