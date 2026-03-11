# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| dev     | :white_check_mark: |

## Security Considerations

### System Requirements

This software requires:
- **Root access**: Necessary for systemd service management and running on UniFi OS
- **API credentials**: Local admin username/password stored in `config.json`
- **Network access**: HTTPS calls to the local UniFi Protect API (`127.0.0.1` or local NVR IP)

### Design Philosophy

1. **Local-only communication**: All API calls are to the local NVR. No external network access.
2. **Credential storage**: `config.json` contains plaintext credentials. It is excluded from git via `.gitignore`. Ensure proper file permissions on your device.
3. **TLS verification disabled**: `curl -k` is used because the NVR uses a self-signed certificate. This is acceptable for localhost/LAN communication only.
4. **Temporary files**: Cookie jars and response headers are stored in `/tmp` with unique names and cleaned up on exit via `trap`.

### Credential Security

```bash
# Verify config.json permissions on your device
ls -la /data/ptz-patrol/config.json

# Recommended: restrict to root only
sudo chmod 600 /data/ptz-patrol/config.json
sudo chown root:root /data/ptz-patrol/config.json
```

## Reporting a Vulnerability

### Where to Report

1. **GitHub Security Advisories** (preferred):
   - Go to: https://github.com/iceteaSA/unifi-ptz-better-patrol/security/advisories
   - Click "Report a vulnerability"

2. **GitHub Issues** (for less critical issues):
   - https://github.com/iceteaSA/unifi-ptz-better-patrol/issues
   - Use the `security` label

### What to Include

1. **Description**: Clear description of the vulnerability
2. **Impact**: Potential security impact and severity
3. **Reproduction**: Steps to reproduce the issue
4. **Environment**: Device model, UniFi OS version, Protect version
5. **Proposed fix** (if you have one)

### Response Timeline

- **Initial response**: Within 48 hours
- **Status update**: Within 7 days
- **Fix timeline**: Depends on severity
  - Critical: Within 7 days
  - High: Within 14 days
  - Medium: Within 30 days
  - Low: Next regular release

## Third-Party Dependencies

This project has minimal dependencies — all are standard system tools:

| Tool   | Purpose                        |
|--------|--------------------------------|
| `bash` | Shell interpreter (4.x+)      |
| `jq`   | JSON parsing                   |
| `curl` | HTTP calls to Protect API      |

No npm packages, no pip packages, no compiled dependencies, no external downloads at runtime. This minimizes supply chain risk.

## Security Updates

To apply security updates:
```bash
# Re-run installation (preserves config)
curl -sSL https://raw.githubusercontent.com/iceteaSA/unifi-ptz-better-patrol/main/install.sh | sudo bash

# Or manual update
cd unifi-ptz-better-patrol
git pull
sudo ./install.sh
```

---

**Last updated**: 2026-03-11
