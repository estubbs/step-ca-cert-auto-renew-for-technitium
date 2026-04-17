#!/bin/bash
set -euo pipefail

CERT=/data/local/certs/udmpro.crt
KEY=/data/local/certs/udmpro.key

UNIFI_CERT=/data/unifi-core/config/unifi-core.crt
UNIFI_KEY=/data/unifi-core/config/unifi-core.key

echo "Certificate renewed — installing to unifi-core"
install -m 644 "$CERT" "$UNIFI_CERT"
install -m 600 "$KEY"  "$UNIFI_KEY"

systemctl restart unifi-core
echo "unifi-core restarted — new certificate is live"
