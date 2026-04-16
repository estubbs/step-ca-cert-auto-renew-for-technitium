#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key

/usr/bin/step ca renew --force --exec /root/cert-post-renew.sh \
  "$CERT" "$KEY"
