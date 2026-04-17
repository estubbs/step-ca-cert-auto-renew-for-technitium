#!/bin/bash
# /data/on_boot.d/10-cert-renew.sh
# Reinstalls the cert-renew systemd units after a firmware upgrade wipes /etc.
# Requires unifios-utilities: https://github.com/unifi-utilities/unifios-utilities
set -euo pipefail

UNIT_DIR=/etc/systemd/system
SERVICE_SRC=/data/local/scripts/cert-renew.service
TIMER_SRC=/data/local/scripts/cert-renew.timer

# Only reinstall if the timer is missing (i.e. after a firmware wipe)
if ! systemctl list-unit-files cert-renew.timer &>/dev/null || \
   ! systemctl is-enabled cert-renew.timer &>/dev/null; then
  install -m 644 "$SERVICE_SRC" "$UNIT_DIR/cert-renew.service"
  install -m 644 "$TIMER_SRC"   "$UNIT_DIR/cert-renew.timer"
  systemctl daemon-reload
  systemctl enable --now cert-renew.timer
  echo "cert-renew.timer installed and enabled"
else
  echo "cert-renew.timer already present, nothing to do"
fi
