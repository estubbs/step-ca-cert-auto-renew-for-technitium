# Technitium TLS Certificate Auto-Renewal

Automatically renews a Technitium DNS server's TLS certificate issued by a [step-ca](https://smallstep.com/docs/step-ca/) internal CA, and converts it to PFX format so Technitium can pick it up without intervention.

## How it works

A systemd timer fires every 12 hours (and 5 minutes after boot). Each run checks whether the certificate is within the last 1/3 of its lifetime. If not, it exits cleanly. If renewal is due, it calls `step ca renew`, which fetches a fresh certificate from the CA using mTLS, then runs a post-renewal hook that converts the PEM cert/key into a PFX file. Technitium watches the PFX path and reloads within ~1 minute of it changing.

```
cert-renew.timer  (every 12h)
      │
      ▼
cert-renew.service
      │
      ▼
cert-renew.sh  ──── not due? exit 0
      │
      │  due for renewal
      ▼
step ca renew  (mTLS to step-ca)
      │
      │  on success
      ▼
cert-post-renew.sh
      │
      ▼
openssl pkcs12  →  technitium.pfx
```

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `cert-renew.sh` | `/root/cert-renew.sh` | Checks expiry window and calls `step ca renew` |
| `cert-post-renew.sh` | `/root/cert-post-renew.sh` | Converts renewed PEM cert to PFX |
| `cert-renew.service` | `/etc/systemd/system/cert-renew.service` | Runs `cert-renew.sh` as a oneshot service |
| `cert-renew.timer` | `/etc/systemd/system/cert-renew.timer` | Triggers the service every 12 hours |

## Prerequisites

- `step` CLI installed (`step version`)
- step-ca bootstrapped on the host (`~/.step/config/defaults.json` exists with `ca-url` and `fingerprint`)
- An initial certificate already issued at `/root/.step/certs/technitium.crt` / `.key`
- `openssl` installed
- Technitium configured to use the PFX path `/root/.step/certs/technitium.pfx`

## Bootstrap

### 1. Issue the initial certificate

If you haven't issued the certificate yet, do so with your step-ca provisioner. For example, with a JWK provisioner:

```bash
step ca certificate technitium.yourdomain.com \
  /root/.step/certs/technitium.crt \
  /root/.step/certs/technitium.key
```

### 2. (Optional) Set a PFX password

If Technitium is configured to expect a password on import, edit `cert-post-renew.sh` and set `PFX_PASS` before deploying:

```bash
PFX_PASS="your-password-here"
```

Leave it empty for a passwordless PFX.

### 3. Deploy the scripts and units

#### Local (on the server directly)

```bash
# Install scripts
install -m 750 cert-renew.sh       /root/cert-renew.sh
install -m 750 cert-post-renew.sh  /root/cert-post-renew.sh

# Install systemd units
install -m 644 cert-renew.service  /etc/systemd/system/cert-renew.service
install -m 644 cert-renew.timer    /etc/systemd/system/cert-renew.timer

# Enable and start the timer
systemctl daemon-reload
systemctl enable --now cert-renew.timer
```

#### Remote (from your workstation over SSH)

Replace `user@host` with your SSH target (e.g. `estubbs@dns1`).

```bash
# Copy all four files to /tmp on the remote host
scp cert-renew.sh cert-post-renew.sh cert-renew.service cert-renew.timer user@host:/tmp/

# Install, reload, and enable over SSH
ssh user@host 'sudo bash -s' <<'EOF'
set -euo pipefail

install -m 750 /tmp/cert-renew.sh       /root/cert-renew.sh
install -m 750 /tmp/cert-post-renew.sh  /root/cert-post-renew.sh

install -m 644 /tmp/cert-renew.service  /etc/systemd/system/cert-renew.service
install -m 644 /tmp/cert-renew.timer    /etc/systemd/system/cert-renew.timer

systemctl daemon-reload
systemctl enable --now cert-renew.timer
systemctl status cert-renew.timer --no-pager
EOF
```

### 4. Build the initial PFX

The timer will handle renewals going forward, but run the post-renew script once manually to generate the initial PFX for Technitium:

```bash
/root/cert-post-renew.sh
```

### 5. Verify

```bash
# Check the timer is active
systemctl status cert-renew.timer

# Run a manual check (should skip if cert was just issued)
systemctl start cert-renew.service
journalctl -u cert-renew.service -n 20
```

## Renewal window

The script renews when the certificate has less than 1/3 of its lifetime remaining. For the default step-ca 24-hour certificate lifetime this is the last 8 hours. The timer runs every 12 hours, so a cert will be renewed during the first timer firing that falls inside that window.

## Monitoring

All output goes to the systemd journal:

```bash
# Live logs
journalctl -fu cert-renew.service

# Recent history
journalctl -u cert-renew.service --since "7 days ago"
```

A successful skip looks like:
```
Certificate is not due for renewal (expires in 72000s, window opens at 28800s), skipping.
```

A successful renewal looks like:
```
Your certificate has been saved in /root/.step/certs/technitium.crt.
Certificate renewed — converting to PFX
PFX written to /root/.step/certs/technitium.pfx — Technitium will auto-reload within 1 minute
```
