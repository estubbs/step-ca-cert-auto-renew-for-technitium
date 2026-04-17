#!/bin/bash
set -euo pipefail

export STEPPATH=/data/local/.step   # must be under /data/ to survive firmware upgrades

CERT=/data/local/certs/udmpro.crt
KEY=/data/local/certs/udmpro.key
STEP=/data/local/bin/step

# Renew when within 10 days of expiry (last 1/3 of a 30-day cert).
if ! "$STEP" certificate needs-renewal --expires-in 33% "$CERT"; then
  echo "Certificate is not due for renewal, skipping."
  exit 0
fi

"$STEP" ca renew --force --not-after 720h \
  --exec /data/local/scripts/cert-post-renew.sh \
  "$CERT" "$KEY"
