#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key
PFX=/root/.step/certs/technitium.pfx
PFX_PASS=""   # set a password here if Technitium is configured to expect one

echo "Certificate renewed — converting to PFX"
if [ -z "$PFX_PASS" ]; then
  /usr/bin/step certificate p12 --force --no-password --insecure \
    "$PFX" "$CERT" "$KEY"
else
  PASS_FILE=$(mktemp)
  trap 'rm -f "$PASS_FILE"' EXIT
  printf '%s' "$PFX_PASS" > "$PASS_FILE"
  /usr/bin/step certificate p12 --force --password-file "$PASS_FILE" \
    "$PFX" "$CERT" "$KEY"
fi

echo "PFX written to $PFX — Technitium will auto-reload within 1 minute"
