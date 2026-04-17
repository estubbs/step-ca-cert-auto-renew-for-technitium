# TLS Certificate Auto-Renewal via step-ca

Scripts for automatically renewing TLS certificates issued by a [step-ca](https://smallstep.com/docs/step-ca/) internal CA.

- **Root directory** — Technitium DNS server (converts to PFX)
- **[udmpro/](udmpro/)** — UniFi Dream Machine Pro (installs PEM directly, restarts unifi-core)

---

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

The script uses `step certificate needs-renewal --expires-in 33%` to check whether the certificate is within the last 1/3 of its lifetime. For the default step-ca 24-hour certificate lifetime this is the last 8 hours. The timer runs every 12 hours, so a cert will be renewed during the first timer firing that falls inside that window.

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

---

# UDM Pro TLS Certificate Auto-Renewal

Same approach adapted for a UniFi Dream Machine Pro. Uses PEM directly (no PFX conversion) and restarts `unifi-core` after renewal. All persistent files live under `/data/` so they survive firmware upgrades.

## How it works

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
      ├─ install PEM → /data/unifi-core/config/unifi-core.crt / .key
      └─ systemctl restart unifi-core
```

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `udmpro/cert-renew.sh` | `/data/local/scripts/cert-renew.sh` | Checks expiry window and calls `step ca renew` |
| `udmpro/cert-post-renew.sh` | `/data/local/scripts/cert-post-renew.sh` | Copies PEM cert/key to unifi-core paths and restarts the service |
| `udmpro/cert-renew.service` | `/etc/systemd/system/cert-renew.service` | Runs `cert-renew.sh` as a oneshot service |
| `udmpro/cert-renew.timer` | `/etc/systemd/system/cert-renew.timer` | Triggers the service every 12 hours |
| `udmpro/on_boot.sh` | `/data/on_boot.d/10-cert-renew.sh` | Reinstalls systemd units after a firmware upgrade wipes `/etc` |

## Prerequisites

- SSH access to the UDM Pro
- `step` CLI ARM64 binary installed at `/data/local/bin/step`
- step-ca bootstrapped: `/root/.step/config/defaults.json` with `ca-url` and `fingerprint`
- An initial certificate already issued at `/data/local/certs/udmpro.crt` / `.key`
- [unifios-utilities](https://github.com/unifi-utilities/unifios-utilities) installed (for on-boot persistence)

## Bootstrap

### 1. Install the `step` CLI

Download the ARM64 binary from [smallstep releases](https://github.com/smallstep/cli/releases) and place it on the UDM Pro:

```bash
# On your workstation — download the linux_arm64 tarball, extract the binary, then copy it
scp step root@udmpro:/data/local/bin/step
ssh root@udmpro 'chmod 755 /data/local/bin/step && /data/local/bin/step version'
```

### 2. Bootstrap step-ca and issue the initial certificate

`step ca bootstrap` writes CA config and the root certificate to `$STEPPATH` (defaults to `~/.step`). On the UDM Pro, `~` is `/root/`, which is wiped on firmware upgrades. Set `STEPPATH` to a `/data/` path so it survives.

```bash
ssh root@udmpro

export STEPPATH=/data/local/.step

# Bootstrap trust for your internal CA
step ca bootstrap --ca-url https://ca.yourdomain.com --fingerprint <ca-fingerprint>

# Issue the initial certificate
mkdir -p /data/local/certs
step ca certificate udmpro.yourdomain.com \
  /data/local/certs/udmpro.crt \
  /data/local/certs/udmpro.key
```

The renewal script exports `STEPPATH=/data/local/.step` automatically, so `step ca renew` will find the CA config at the same location.

### 3. Deploy scripts and units

From your workstation (replace `root@udmpro` as needed):

```bash
# Copy files
scp udmpro/cert-renew.sh udmpro/cert-post-renew.sh \
    udmpro/cert-renew.service udmpro/cert-renew.timer \
    udmpro/on_boot.sh \
    root@udmpro:/tmp/

# Install over SSH
ssh root@udmpro 'bash -s' <<'EOF'
set -euo pipefail

mkdir -p /data/local/scripts /data/on_boot.d

install -m 750 /tmp/cert-renew.sh       /data/local/scripts/cert-renew.sh
install -m 750 /tmp/cert-post-renew.sh  /data/local/scripts/cert-post-renew.sh
install -m 750 /tmp/on_boot.sh          /data/on_boot.d/10-cert-renew.sh

install -m 644 /tmp/cert-renew.service  /data/local/scripts/cert-renew.service
install -m 644 /tmp/cert-renew.timer    /data/local/scripts/cert-renew.timer

# Also install units to systemd now (on_boot.sh handles future firmware upgrades)
install -m 644 /tmp/cert-renew.service  /etc/systemd/system/cert-renew.service
install -m 644 /tmp/cert-renew.timer    /etc/systemd/system/cert-renew.timer

systemctl daemon-reload
systemctl enable --now cert-renew.timer
systemctl status cert-renew.timer --no-pager
EOF
```

### 4. Do the initial certificate install

Run the post-renew script once to copy the just-issued cert into place and restart unifi-core:

```bash
ssh root@udmpro /data/local/scripts/cert-post-renew.sh
```

### 5. Verify

```bash
# Check the timer
ssh root@udmpro systemctl status cert-renew.timer

# Trigger a manual run (will skip if cert was just issued)
ssh root@udmpro systemctl start cert-renew.service
ssh root@udmpro journalctl -u cert-renew.service -n 20
```

## Persistence after firmware upgrades

The systemd units live in `/etc/systemd/system/`, which firmware upgrades may wipe. The `on_boot.sh` script (installed to `/data/on_boot.d/`) is run by unifios-utilities on every boot and reinstalls the units from `/data/local/scripts/` if they are missing.

If you don't use unifios-utilities, you can achieve the same effect by adding a cron `@reboot` job that runs `on_boot.sh`.

## Monitoring

```bash
# Live logs
journalctl -fu cert-renew.service

# Recent history
journalctl -u cert-renew.service --since "7 days ago"
```

A successful skip:
```
Certificate is not due for renewal (expires in 72000s, window opens at 28800s), skipping.
```

A successful renewal:
```
Your certificate has been saved in /data/local/certs/udmpro.crt.
Certificate renewed — installing to unifi-core
unifi-core restarted — new certificate is live
```
