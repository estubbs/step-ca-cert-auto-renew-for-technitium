#!/bin/bash
set -euo pipefail

HOST=root@unifi
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/udmpro-ssh -o ControlPersist=5m -o StrictHostKeyChecking=accept-new"

CA_URL="https://ca.robb.erickstubbs.com"
CA_FINGERPRINT="6135b368d2eeff36b240529fd83f907f5a8fd1d4acaf55ad8fd7305af0368e18"

echo "==> Opening SSH connection (enter password once)"
ssh $SSH_OPTS "$HOST" true

echo "==> Copying scripts"
scp $SSH_OPTS \
  "$SCRIPTS/cert-renew.sh" \
  "$SCRIPTS/cert-post-renew.sh" \
  "$SCRIPTS/cert-renew.service" \
  "$SCRIPTS/cert-renew.timer" \
  "$SCRIPTS/on_boot.sh" \
  "$SCRIPTS/20-authorized-keys.sh" \
  "$HOST:/tmp/"

REMOTE_SCRIPT=$(mktemp)
cat > "$REMOTE_SCRIPT" << 'REMOTE'
set -euo pipefail

# ── Directories ────────────────────────────────────────────────────────────
mkdir -p /data/local/bin /data/local/scripts /data/local/certs /data/on_boot.d

# ── Install step CLI (ARM64) ───────────────────────────────────────────────
echo "==> Installing step CLI"
STEP_VERSION=$(curl -fsSL https://api.github.com/repos/smallstep/cli/releases/latest \
  | grep -o '"tag_name": *"[^"]*"' | head -1 | grep -o '[0-9][^"]*')
curl -fsSL "https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_linux_${STEP_VERSION}_arm64.tar.gz" \
  | tar xz --strip-components=2 -C /data/local/bin "step_${STEP_VERSION}/bin/step"
chmod 755 /data/local/bin/step
/data/local/bin/step version

# ── Bootstrap step-ca ─────────────────────────────────────────────────────
echo "==> Bootstrapping step-ca"
export STEPPATH=/data/local/.step
/data/local/bin/step ca bootstrap \
  --ca-url "CA_URL_PLACEHOLDER" \
  --fingerprint "CA_FINGERPRINT_PLACEHOLDER" \
  --install

# ── Issue initial certificate ─────────────────────────────────────────────
echo "==> Issuing certificate (you will be prompted for your provisioner password)"
/data/local/bin/step ca certificate \
  --san unifi.robb.erickstubbs.com \
  --san unifi \
  --san 192.168.1.1 \
  --kty RSA \
  --not-after 720h \
  unifi.robb.erickstubbs.com \
  /data/local/certs/udmpro.crt \
  /data/local/certs/udmpro.key

# ── Install scripts ────────────────────────────────────────────────────────
echo "==> Installing scripts"
install -m 750 /tmp/cert-renew.sh       /data/local/scripts/cert-renew.sh
install -m 750 /tmp/cert-post-renew.sh  /data/local/scripts/cert-post-renew.sh
install -m 750 /tmp/on_boot.sh          /data/on_boot.d/10-cert-renew.sh
install -m 750 /tmp/20-authorized-keys.sh /data/on_boot.d/20-authorized-keys.sh
install -m 644 /tmp/cert-renew.service  /data/local/scripts/cert-renew.service
install -m 644 /tmp/cert-renew.timer    /data/local/scripts/cert-renew.timer

# ── unifios-utilities boot service ────────────────────────────────────────
echo "==> Installing unifios-utilities boot service"
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifi-common/HEAD/remote_install.sh" | /bin/bash

# ── systemd units ─────────────────────────────────────────────────────────
echo "==> Installing systemd units"
install -m 644 /data/local/scripts/cert-renew.service /etc/systemd/system/cert-renew.service
install -m 644 /data/local/scripts/cert-renew.timer   /etc/systemd/system/cert-renew.timer
systemctl daemon-reload
systemctl enable --now cert-renew.timer
systemctl status cert-renew.timer --no-pager

# ── Initial cert install into unifi-core ──────────────────────────────────
echo "==> Installing certificate into unifi-core"
export STEPPATH=/data/local/.step
/data/local/scripts/cert-post-renew.sh

echo "==> All done"
REMOTE

sed -i '' "s|CA_URL_PLACEHOLDER|$CA_URL|g; s|CA_FINGERPRINT_PLACEHOLDER|$CA_FINGERPRINT|g" "$REMOTE_SCRIPT"
scp $SSH_OPTS "$REMOTE_SCRIPT" "$HOST:/tmp/install-remote.sh"
rm "$REMOTE_SCRIPT"
ssh -t $SSH_OPTS "$HOST" 'bash /tmp/install-remote.sh; rm /tmp/install-remote.sh'

ssh $SSH_OPTS -O exit "$HOST" 2>/dev/null || true
