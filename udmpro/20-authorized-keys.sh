#!/bin/bash
# /data/on_boot.d/20-authorized-keys.sh
# Fetches EC public keys from GitHub and ensures they are in root's authorized_keys.
set -euo pipefail

GITHUB_USER="estubbs"
AUTH_KEYS="/root/.ssh/authorized_keys"
KEYS_URL="https://github.com/${GITHUB_USER}.keys"

mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

FETCHED=$(curl -fsSL "$KEYS_URL" | grep '^ssh-ed25519\|^ecdsa\|^sk-')

if [ -z "$FETCHED" ]; then
  echo "No EC keys found for ${GITHUB_USER} on GitHub, aborting"
  exit 1
fi

ADDED=0
while IFS= read -r key; do
  KEY_BODY=$(echo "$key" | awk '{print $2}')
  if ! grep -qF "$KEY_BODY" "$AUTH_KEYS"; then
    echo "$key" >> "$AUTH_KEYS"
    echo "Added key: ${key##* }"
    ADDED=$((ADDED + 1))
  fi
done <<< "$FETCHED"

if [ "$ADDED" -eq 0 ]; then
  echo "EC keys already present, nothing to do"
else
  echo "Added ${ADDED} EC key(s) for ${GITHUB_USER}"
fi
