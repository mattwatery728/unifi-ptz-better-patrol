---
name: Bug Report
about: Report a bug or issue with the patrol system
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

A clear and concise description of the bug.

## System Information

- **Device Model**: (e.g., UDM, UDR, UNVR)
- **PTZ Camera Model**: (e.g., G5 PTZ, G6 PTZ)
- **UniFi Protect Version**: (e.g., v6.2.88)
- **UniFi OS Version**: (e.g., 4.0.6)
- **Script Branch/Version**: (e.g., main, commit hash)

## Current Behavior

What is happening? Be specific.

## Expected Behavior

What should happen instead?

## Steps to Reproduce

1. Configure '...'
2. Run '...'
3. Observe '...'

## Configuration

```json
// Paste relevant parts of /data/ptz-patrol/config.json
// REDACT username and password
{
  "nvr_address": "...",
  "defaults": { ... },
  "camera_overrides": { ... }
}
```

## Logs

```bash
# Paste relevant logs from: journalctl -u ptz-patrol.service -n 100
# Include ERROR, WARN, and surrounding context

```

## Discovery Output

```bash
# Paste output from: bash /data/ptz-patrol/discover.sh

```

## Attempted Solutions

- [ ] Restarted the service
- [ ] Checked logs for errors
- [ ] Verified camera presets exist in Protect app
- [ ] Ran discover.sh to confirm camera is found
- [ ] Checked README and existing issues
- [ ] Other:

## Frequency

- [ ] This happens consistently
- [ ] This happens intermittently
- [ ] This happened once

## Impact

- [ ] Critical — Patrol not running at all
- [ ] High — Feature not working (e.g., tracking, schedule)
- [ ] Medium — Working but with issues
- [ ] Low — Minor inconvenience
