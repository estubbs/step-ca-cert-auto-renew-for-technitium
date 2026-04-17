#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key

# Renew only within the last 1/3 of the cert lifetime (8h for a 24h cert).
# exit 0 = needs renewal, exit 1 = still fresh.
if ! /usr/bin/step certificate needs-renewal --expires-in 33% "$CERT"; then
  echo "Certificate is not due for renewal, skipping."
  exit 0
fi

/usr/bin/step ca renew --force --exec /root/cert-post-renew.sh \
  "$CERT" "$KEY"
