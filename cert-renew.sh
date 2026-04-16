#!/bin/bash
set -euo pipefail

CERT=/root/.step/certs/technitium.crt
KEY=/root/.step/certs/technitium.key

/usr/bin/step ca renew --force "$CERT" "$KEY" \
  --renew-hook /root/cert-post-renew.sh
