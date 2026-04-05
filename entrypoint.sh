#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ── Stale gateway PID lock cleanup ──────────────────────────────
# After a container restart, stale lock files from the previous
# gateway process cause the new gateway to exit immediately with
# code=1, creating a crash loop. Remove them before starting.
echo "[entrypoint] Cleaning stale gateway locks..."
rm -f /tmp/openclaw-*/gateway.*.lock 2>/dev/null || true
rm -f /tmp/openclaw/gateway.*.lock 2>/dev/null || true

# ── Workspace bootstrap hook ────────────────────────────────────
# If a bootstrap.sh exists on the persistent volume, run it as the
# openclaw user before starting the server. This installs acpx,
# configures plugins, and applies workspace customizations that
# survive container redeployments.
BOOTSTRAP="/data/workspace/bootstrap.sh"
if [ -f "$BOOTSTRAP" ]; then
  echo "[entrypoint] Running workspace bootstrap: $BOOTSTRAP"
  chmod +x "$BOOTSTRAP"
  gosu openclaw bash "$BOOTSTRAP" || echo "[entrypoint] WARNING: bootstrap exited with code $?"
else
  echo "[entrypoint] No workspace bootstrap found at $BOOTSTRAP"
fi

# ── Boot-acpx hook ──────────────────────────────────────────────
# Separate hook specifically for ACPX installation and config.
BOOT_ACPX="/data/workspace/boot-acpx.sh"
if [ -f "$BOOT_ACPX" ]; then
  echo "[entrypoint] Running boot-acpx: $BOOT_ACPX"
  chmod +x "$BOOT_ACPX"
  gosu openclaw bash "$BOOT_ACPX" || echo "[entrypoint] WARNING: boot-acpx exited with code $?"
else
  echo "[entrypoint] No boot-acpx found at $BOOT_ACPX"
fi

exec gosu openclaw node src/server.js
