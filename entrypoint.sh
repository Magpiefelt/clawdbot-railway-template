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

# ── Ensure workspace directory exists ──────────────────────────
mkdir -p /data/workspace
chown openclaw:openclaw /data/workspace

# ── Clone/update workspace repo if not present ─────────────────
WORKSPACE_REPO="https://github.com/Magpiefelt/openclaw-workspace.git"
if [ ! -f /data/workspace/bootstrap.sh ]; then
  echo "[entrypoint] Workspace bootstrap not found. Cloning workspace repo..."
  if command -v git >/dev/null 2>&1; then
    # Clone into a temp dir and copy files to workspace
    TMPWS=$(mktemp -d)
    git clone --depth 1 "$WORKSPACE_REPO" "$TMPWS" 2>/dev/null && {
      cp -a "$TMPWS"/* /data/workspace/ 2>/dev/null || true
      cp -a "$TMPWS"/.* /data/workspace/ 2>/dev/null || true
      rm -rf "$TMPWS"
      chown -R openclaw:openclaw /data/workspace
      echo "[entrypoint] Workspace repo cloned to /data/workspace"
    } || echo "[entrypoint] WARNING: Failed to clone workspace repo"
  else
    echo "[entrypoint] git not available, skipping workspace clone"
  fi
fi

# ── Workspace bootstrap hook ────────────────────────────────────
BOOTSTRAP="/data/workspace/bootstrap.sh"
if [ -f "$BOOTSTRAP" ]; then
  echo "[entrypoint] Running workspace bootstrap: $BOOTSTRAP"
  chmod +x "$BOOTSTRAP"
  gosu openclaw bash "$BOOTSTRAP" || echo "[entrypoint] WARNING: bootstrap exited with code $?"
else
  echo "[entrypoint] No workspace bootstrap found at $BOOTSTRAP"
fi

# ── Boot-acpx hook ──────────────────────────────────────────────
BOOT_ACPX="/data/workspace/boot-acpx.sh"
if [ -f "$BOOT_ACPX" ]; then
  echo "[entrypoint] Running boot-acpx: $BOOT_ACPX"
  chmod +x "$BOOT_ACPX"
  gosu openclaw bash "$BOOT_ACPX" || echo "[entrypoint] WARNING: boot-acpx exited with code $?"
else
  echo "[entrypoint] No boot-acpx found at $BOOT_ACPX"
  # ── Fallback: configure acpx directly if baked into image ──
  if command -v acpx >/dev/null 2>&1; then
    echo "[entrypoint] acpx binary found, configuring plugins.allow..."
    CONFIG="/data/.openclaw/openclaw.json"
    if [ -f "$CONFIG" ]; then
      gosu openclaw python3 -c "
import json, sys
try:
    with open('$CONFIG') as f:
        cfg = json.load(f)
    plugins = cfg.setdefault('plugins', {})
    allow = plugins.get('allow', [])
    if 'acpx' not in allow:
        allow.append('acpx')
        plugins['allow'] = allow
        with open('$CONFIG', 'w') as f:
            json.dump(cfg, f, indent=2)
        print('[entrypoint] Added acpx to plugins.allow')
    else:
        print('[entrypoint] acpx already in plugins.allow')
except Exception as e:
    print(f'[entrypoint] WARNING: Failed to update config: {e}', file=sys.stderr)
" || echo "[entrypoint] WARNING: Failed to configure acpx"
    fi
  fi
fi

exec gosu openclaw node src/server.js
