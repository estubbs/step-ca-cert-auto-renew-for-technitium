#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key
PFX=/root/.step/certs/technitium.pfx
PFX_PASS=""   # set a password here if Technitium is configured to expect one

echo "Certificate renewed — converting to PFX"
openssl pkcs12 -export \
  -in    "$CERT" \
  -inkey "$KEY" \
  -out   "$PFX" \
  -passout "pass:${PFX_PASS}"

echo "PFX written to $PFX — Technitium will auto-reload within 1 minute"
