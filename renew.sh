#!/bin/bash
set -euo pipefail

# --- Configure these ---
CA_URL="https://your-step-ca:9000/acme/acme/directory"
EMAIL="admin@example.com"
DOMAIN="myserver.example.com"
CERT_DIR="/etc/lego/certs"
# Service to reload after a successful renewal (set to "" to skip)
RELOAD_SERVICE="nginx.service"
# ----------------------

/usr/local/bin/lego \
  --server "${CA_URL}" \
  --email  "${EMAIL}" \
  --domains "${DOMAIN}" \
  --path   "${CERT_DIR}" \
  --ca-root /etc/step-ca/certs/root_ca.crt \
  renew \
  --days 30

# Only runs if lego exited 0 (cert was actually renewed)
if [[ -n "${RELOAD_SERVICE}" ]]; then
  systemctl reload-or-restart "${RELOAD_SERVICE}"
fi
