#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key

# Renew only within the last 1/3 of the cert lifetime (8h for a 24h cert).
# step ca renew always opens /dev/tty without --force, so we gate renewal
# here and pass --force only when we decide to proceed.
END=$(openssl x509 -noout -enddate -in "$CERT" | cut -d= -f2)
START=$(openssl x509 -noout -startdate -in "$CERT" | cut -d= -f2)
LIFETIME=$(( $(date -d "$END" +%s) - $(date -d "$START" +%s) ))
RENEW_WINDOW=$(( LIFETIME / 3 ))
EXPIRES_IN=$(( $(date -d "$END" +%s) - $(date +%s) ))

if (( EXPIRES_IN > RENEW_WINDOW )); then
  echo "Certificate is not due for renewal (expires in ${EXPIRES_IN}s, window opens at ${RENEW_WINDOW}s), skipping."
  exit 0
fi

/usr/bin/step ca renew --force --exec /root/cert-post-renew.sh \
  "$CERT" "$KEY"
