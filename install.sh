#!/bin/bash
set -euo pipefail

HOST=estubbs@dns1
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/technitium-ssh -o ControlPersist=5m -o StrictHostKeyChecking=accept-new"

echo "==> Opening SSH connection (enter password once)"
ssh $SSH_OPTS "$HOST" true

echo "==> Copying scripts"
scp $SSH_OPTS \
  "$SCRIPTS/cert-renew.sh" \
  "$SCRIPTS/cert-post-renew.sh" \
  "$SCRIPTS/cert-renew.service" \
  "$SCRIPTS/cert-renew.timer" \
  "$HOST:/tmp/"

REMOTE_SCRIPT=$(mktemp)
cat > "$REMOTE_SCRIPT" << 'REMOTE'
set -euo pipefail

# ── Install scripts ────────────────────────────────────────────────────────
echo "==> Installing scripts"
install -m 750 /tmp/cert-renew.sh       /root/cert-renew.sh
install -m 750 /tmp/cert-post-renew.sh  /root/cert-post-renew.sh
install -m 644 /tmp/cert-renew.service  /etc/systemd/system/cert-renew.service
install -m 644 /tmp/cert-renew.timer    /etc/systemd/system/cert-renew.timer

# ── systemd units ─────────────────────────────────────────────────────────
echo "==> Installing systemd units"
systemctl daemon-reload
systemctl enable --now cert-renew.timer
systemctl status cert-renew.timer --no-pager

# ── Build initial PFX for Technitium ──────────────────────────────────────
echo "==> Building initial PFX"
/root/cert-post-renew.sh

echo "==> All done"
REMOTE

scp $SSH_OPTS "$REMOTE_SCRIPT" "$HOST:/tmp/install-remote.sh"
rm "$REMOTE_SCRIPT"
ssh -t $SSH_OPTS "$HOST" 'sudo bash /tmp/install-remote.sh; rm /tmp/install-remote.sh'

ssh $SSH_OPTS -O exit "$HOST" 2>/dev/null || true
