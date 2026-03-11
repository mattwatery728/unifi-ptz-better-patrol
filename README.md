# UniFi PTZ Better Patrol

Motion-aware PTZ camera patrol system for Ubiquiti UniFi Protect devices running UniFi OS.

Confirmed working on: UDM, UDR, UNVR (any device running UniFi Protect with PTZ cameras)

Tested with: **G5 PTZ** and **G6 PTZ** cameras only. Other UniFi PTZ models may work but are untested.

> **Warning — Use at your own risk.** This software continuously moves PTZ cameras through preset positions. The pan/tilt motors in some cameras (particularly the G5 PTZ) may not be rated for sustained, continuous patrol operation. Extended use could accelerate motor wear or cause mechanical failure. The authors take no responsibility for any hardware damage, reduced camera lifespan, or warranty implications. **You have been warned.**

## Features

- **Motion-Aware Patrol**: Automatically pauses patrol when motion or smart detection is active
- **Manual Control Detection**: Detects when you're controlling the camera via the Protect app and backs off — won't interrupt your PTZ session
- **Active Dwell Monitoring**: Polls for external control and motion every 5 seconds during dwell — reacts within seconds, not minutes
- **Auto-Tracking Compatible**: Auto-tracking works with this patrol mode — patrol pauses while the camera tracks a subject and resumes when done. UniFi's built-in patrol mode does not support auto-tracking.
- **Dynamic Auto-Tracking**: Optionally enables auto-tracking only when a smart detection (e.g. person) occurs, then disables it when the detection clears — giving you the best of both worlds (motion events for patrol + tracking when it matters)
- **Auto-Setup**: Automatically disables conflicting Protect settings on startup (built-in patrols, return-to-home)
- **Auto-Discovery**: Finds all connected PTZ cameras and their preset positions automatically
- **Per-Camera Overrides**: Customize dwell time, motion hold, and preset slots per camera
- **Optional Patrol Schedule**: Restrict patrol to specific time windows and days of the week, with optional "go home" when paused
- **Parallel Patrol Loops**: Each camera runs its own independent patrol process with isolated auth
- **Configurable Log Levels**: Control verbosity with `error`, `warn`, `info`, or `debug`
- **Max Wait Protection**: Configurable timeout prevents indefinite tracking holds
- **Resilient Operation**: Automatic retry with exponential backoff, per-camera restart on errors
- **Graceful Shutdown**: Clean SIGTERM handling with optional "go home" on service stop
- **Re-Auth Handling**: Transparent token refresh keeps long-running patrols alive
- **Firmware Update Survival**: `on_boot.d` hook re-bootstraps after UniFi OS updates
- **Lightweight**: ~11 MB RSS total, ~8% of one CPU core for 3 cameras

> This project is built and maintained independently in spare time. If it saves you from wiring up Home Assistant automations or dealing with the terrible default patrol mode, [consider supporting it](https://ko-fi.com/H2H719VB0U).

## Prerequisites

Before installing, make sure the following are configured in UniFi Protect:

1. **Local user with admin role** — Create a dedicated local user (e.g. `patrol`) in UniFi OS Settings > Admins with the **Admin** role. This script uses local username/password authentication.

The script automatically handles these on startup (no manual action required):
- **Built-in patrols** — Stopped automatically if running (avoids conflicts)
- **Auto return home** — Disabled automatically if enabled (the script manages positioning itself)

## Installation

### One-Line Install

```bash
curl -sSL https://raw.githubusercontent.com/iceteaSA/unifi-ptz-better-patrol/main/install.sh | sudo bash
```

### With Credentials (skip manual config editing)

```bash
curl -sSL https://raw.githubusercontent.com/iceteaSA/unifi-ptz-better-patrol/main/install.sh \
  | sudo bash -s -- --nvr https://10.0.0.1 --username patrol --password secret
```

All three flags are optional — provide any combination. If `config.json` already exists, only the provided values are updated; everything else is preserved.

### Using a Different Branch

```bash
# Direct URL
curl -sSL https://raw.githubusercontent.com/iceteaSA/unifi-ptz-better-patrol/dev/install.sh | sudo bash

# Or via environment variable
PTZ_PATROL_BRANCH=dev curl -sSL https://raw.githubusercontent.com/iceteaSA/unifi-ptz-better-patrol/main/install.sh | sudo bash
```

### Manual Installation

If you prefer to inspect the code before installation:

```bash
git clone https://github.com/iceteaSA/unifi-ptz-better-patrol.git
cd unifi-ptz-better-patrol

# Run the installer (optionally with credentials)
sudo ./install.sh --nvr https://10.0.0.1 --username patrol --password secret
```

## Configuration

Edit `/data/ptz-patrol/config.json`:

```json
{
  "nvr_address": "https://127.0.0.1",
  "username": "api-user",
  "password": "changeme",
  "reauth_seconds": 3600,
  "auto_discover": true,
  "log_level": "info",

  "defaults": {
    "dwell_seconds": 30,
    "motion_hold_seconds": 15,
    "max_tracking_wait": 300,
    "manual_control_hold_seconds": 120,
    "ptz_settle_seconds": 10,
    "home_on_shutdown": false
  },

  "camera_overrides": {
    "YOUR_CAMERA_ID_HERE": {
      "enabled": true,
      "dwell_seconds": 45,
      "motion_hold_seconds": 20,
      "max_tracking_wait": 180,
      "manual_control_hold_seconds": 60,
      "preset_slots": [0, 1, 3]
    }
  }
}
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `nvr_address` | `https://127.0.0.1` | UniFi Protect NVR address |
| `username` | `api-user` | Local admin username |
| `password` | `changeme` | Local admin password |
| `reauth_seconds` | `3600` | Token refresh interval (seconds) |
| `auto_discover` | `true` | Auto-discover PTZ cameras on startup |
| `log_level` | `info` | Log verbosity: `error`, `warn`, `info`, `debug` |
| `defaults.dwell_seconds` | `30` | Time at each preset before advancing |
| `defaults.motion_hold_seconds` | `15` | Hold time after motion/smart detection |
| `defaults.max_tracking_wait` | `300` | Max seconds to wait during active tracking |
| `defaults.manual_control_hold_seconds` | `120` | Backoff time after manual PTZ control detected |
| `defaults.ptz_settle_seconds` | `10` | Grace period after a goto before checking for drift |
| `defaults.home_on_shutdown` | `false` | Send cameras to home position on service stop |
| `defaults.dynamic_auto_tracking` | `false` | Enable dynamic auto-tracking (see below) |

### Per-Camera Overrides

Add entries under `camera_overrides` keyed by camera ID. Any field from `defaults` can be overridden. Set `"enabled": false` to skip a camera. Use `"preset_slots": [0, 1, 3]` to patrol specific presets instead of all discovered ones.

> **Tip**: Run `bash /data/ptz-patrol/discover.sh` to see all discovered cameras, their IDs, presets, zoom positions, and effective config.

Apply changes:
```bash
systemctl restart ptz-patrol.service
```

### Patrol Schedule

By default, patrol runs 24/7. Add a `schedule` block to restrict patrol to specific time windows. This can be set globally in `defaults` or per-camera in `camera_overrides`.

```json
{
  "defaults": {
    "schedule": {
      "start": "22:00",
      "end": "06:00",
      "days": ["mon", "tue", "wed", "thu", "fri"],
      "home_on_pause": true
    }
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `start` | — | Start time in 24h format (`"HH:MM"`). Required to enable schedule. |
| `end` | — | End time in 24h format (`"HH:MM"`). Required to enable schedule. |
| `days` | all days | Array of 3-letter day names: `"mon"`, `"tue"`, `"wed"`, `"thu"`, `"fri"`, `"sat"`, `"sun"` |
| `home_on_pause` | `false` | Send camera to home position when patrol pauses outside the schedule window |

Overnight windows work correctly — `"start": "22:00", "end": "06:00"` means patrol is active from 10 PM to 6 AM. Times use the system clock of the device (not UTC) — check with `date` on your NVR to verify the timezone.

If no `schedule` is set (or set to `null`), patrol runs continuously. Per-camera schedules override the global default:

```json
{
  "defaults": {
    "schedule": null
  },
  "camera_overrides": {
    "CAMERA_ID": {
      "schedule": {
        "start": "20:00",
        "end": "07:00",
        "home_on_pause": true
      }
    }
  }
}
```

### Dynamic Auto-Tracking

UniFi Protect suppresses motion events when auto-tracking is enabled (the camera is moving, so there's no relative motion in the frame). This creates a problem: you can't have both motion-aware patrol and auto-tracking at the same time.

Dynamic auto-tracking solves this by keeping auto-tracking **disabled by default** and only enabling it when a smart detection (e.g. person) is actively occurring. When the detection clears, it disables tracking again so motion events resume for the next patrol cycle.

```json
{
  "defaults": {
    "dynamic_auto_tracking": true
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `dynamic_auto_tracking` | `false` | Enable dynamic auto-tracking (person detection only) |

When enabled, the script will:
1. Disable auto-tracking on the camera at startup
2. Enable it when a matching smart detection occurs (patrol holds)
3. Disable it when the detection clears (patrol resumes)
4. Disable it on shutdown and schedule pause

This is per-camera configurable — you can enable it on specific cameras via `camera_overrides`.

### Log Levels

| Level | Shows | Use case |
|-------|-------|----------|
| `error` | Errors only (auth failures, missing presets, fatal conditions) | Production — minimal output |
| `warn` | Errors + warnings (retries, backoff, unexpected HTTP codes) | Production — recommended minimum |
| `info` | Normal operations (goto, hold, resume, discovery) | **Default** — day-to-day monitoring |
| `debug` | Everything (retry details, hold countdowns, motion clear) | Troubleshooting only |

Log format: `[timestamp] [LEVEL] [tag] message`
```log
[2026-03-10 12:00:00] [ERROR] [api] Auth failed
[2026-03-10 12:00:10] [WARN] [api] Auth attempt 1/5 failed — retrying in 10s
[2026-03-10 12:00:20] [INFO] [api] Authenticated
[2026-03-10 12:00:20] [DEBUG] [api] GET /cameras returned HTTP 200 (attempt 1/3)
```

## Operational Overview

### Patrol Loop (per camera)

```
┌──────────────────────┐
│  Check auth token    │ <-- refreshes automatically
└──────────┬───────────┘
           │
     ┌─────▼──────┐
     │ Failures > │──yes──> Exponential backoff
     │ threshold? │
     └─────┬──────┘
           │ no
     ┌─────▼──────┐
     │  External  │──yes──> Hold for manual_control_hold_seconds
     │  control?  │         (zoom drift detection)
     └─────┬──────┘
           │ no
     ┌─────▼──────┐
     │  Tracking  │──yes──> Hold (check every 5s, up to max_wait)
     │  active?   │
     └─────┬──────┘
           │ no
     ┌─────▼──────┐
     │  Go to     │ --> Records timestamp
     │  preset    │ --> Handles HTTP errors (retry, re-auth)
     └─────┬──────┘
           │
     ┌─────▼──────────────────────────┐
     │  Dwell (active polling, 5s)   │ <-- NOT a blind sleep
     │  ├─ Sample actual zoom after  │
     │  │  settle window             │
     │  ├─ Check zoom drift          │──> Hold if external control
     │  └─ Check motion/tracking     │──> Hold if activity detected
     └─────┬──────────────────────────┘
           │
     next preset ──> (loop)
```

### Manual Control Detection

The Protect API doesn't expose a "camera is being controlled" flag or current pan/tilt position. Detection uses two complementary strategies:

**Zoom drift detection** catches zoom-based manual control:

1. After each `goto`, we wait for the settle window (`ptz_settle_seconds`) to elapse
2. We then **sample the actual `ispSettings.zoomPosition`** from the camera as the baseline (this avoids zoom scale differences between G5 and G6 models)
3. During the dwell period, we poll every 5 seconds — if the zoom drifts >2% from the sampled baseline, someone else moved the camera
4. The patrol enters a hold state for `manual_control_hold_seconds` before resuming
5. When the hold expires, the baseline is reset so stale values don't cause false re-triggers

**Motion-based detection** catches pan/tilt manual control:

1. When you pan or tilt a camera from the Protect app, the motor movement causes the scene to change, which triggers the camera's motion sensor
2. The dwell polling loop checks `lastMotion` every 5 seconds
3. If motion is detected during dwell, the patrol holds until motion clears + `motion_hold_seconds` elapses

Together, these two strategies cover the vast majority of manual control scenarios without requiring any additional hardware or Home Assistant integration.

### Detection Hierarchy

The patrol hold checks these signals in priority order:
1. **External control** — zoom drift from sampled baseline position
2. **Auto-tracking flag** (`isAutoTracking`, `isPtzAutoTracking`, `isTracking`) — firmware-dependent
3. **Smart detection** (`lastSmartDetect`) — person, vehicle, animal, etc.
4. **Motion detection** (`lastMotion`) — generic motion fallback; also catches pan/tilt manual control during dwell

### Error Resilience

- **API retry**: All HTTP calls retry up to 3 times with re-auth on 401/403
- **Exponential backoff**: After 3+ consecutive failures, backs off 10s->20s->40s->...->120s
- **Per-camera restart**: If a patrol loop crashes, it restarts after 10 seconds
- **No-preset backoff**: Cameras with fewer than 2 presets re-check every 5 minutes instead of spamming retries
- **Auth retry on startup**: Retries up to 5 times with backoff (NVR may still be booting)
- **Camera disconnect handling**: Treats disconnected cameras as "active" (fail-safe hold)
- **Process isolation**: Each camera has its own cookie jar and auth token (no shared state)

## Resource Usage

Measured on a UNVR with 3 PTZ cameras patrolling (30s dwell, 5s polling):

| Resource | Value | Notes |
|----------|-------|-------|
| **Memory** | ~11 MB total | ~3 MB per process (1 main + 1 per camera) |
| **CPU** | ~8% of one core | Mostly jq + curl; idle between polls |
| **Processes** | 4 bash | 1 main + 3 camera subprocesses |
| **Temp files** | 12 | 3 per process (cookie, headers, body); cleaned on exit |
| **File descriptors** | 3-4 per process | Minimal; no long-lived connections |

## Monitoring & Logging

Key operational signals:

```log
# Discovery
[2026-03-10 12:00:00] [INFO] [main] Discovering PTZ cameras...
[2026-03-10 12:00:01] [INFO] [main] Found 3 PTZ camera(s) — launching patrol loops

# Normal patrol
[2026-03-10 12:00:02] [INFO] [Front Door] Patrol: presets=[0 1 2 3] dwell=30s hold=15s max_wait=300s manual_hold=120s
[2026-03-10 12:00:32] [INFO] [Front Door] → Slot 1 [HTTP 200]

# Zoom-based manual control detection
[2026-03-10 12:02:00] [WARN] [Front Door] Zoom drift detected (expected=42% actual=78%)
[2026-03-10 12:02:00] [WARN] [Front Door] External control detected — holding patrol for 120s
[2026-03-10 12:04:00] [INFO] [Front Door] Manual control hold expired — resuming patrol

# Motion during dwell (catches pan/tilt manual control)
[2026-03-10 12:05:02] [INFO] [Gate PTZ] Activity during dwell — holding
[2026-03-10 12:05:02] [INFO] [Gate PTZ] Tracking/motion active — holding

# Camera with no presets configured
[2026-03-10 12:00:03] [WARN] [Back Yard] Only 0 preset(s) — need 2+. Skipping.
[2026-03-10 12:00:03] [WARN] [Back Yard] No presets — will re-check in 5 minutes

# Error recovery
[2026-03-10 12:10:00] [WARN] [api] Auth error on GET /cameras/abc123 (HTTP 401) — re-authenticating
[2026-03-10 12:10:00] [WARN] [Driveway] 3 consecutive failures — backing off 20s
[2026-03-10 12:10:20] [WARN] [Driveway] Patrol loop exited — restarting in 10s

# Graceful shutdown
[2026-03-10 13:00:00] [INFO] [main] Shutdown requested — stopping all patrols
[2026-03-10 13:00:00] [INFO] [main] Sending cameras to home position...
[2026-03-10 13:00:01] [INFO] [main] Shutdown complete
```

View logs with:
```bash
journalctl -u ptz-patrol.service -f                        # Live monitoring
journalctl -u ptz-patrol.service --since "10 minutes ago"  # Recent history
journalctl -u ptz-patrol.service -p warning                # Warnings and errors only
```

## Maintenance

```bash
# Service Management
systemctl status ptz-patrol.service    # Current state
systemctl restart ptz-patrol.service   # Apply config changes

# Discovery (see cameras, presets, zoom, effective config)
bash /data/ptz-patrol/discover.sh

# Full Removal
/data/ptz-patrol/uninstall.sh
```

## Project Structure

- **ptz-patrol.sh**: Main entrypoint — discovers cameras and launches parallel patrol loops with per-process isolation and graceful shutdown
- **api.sh**: Shared library for auth, HTTP with retry, config caching, motion/tracking detection, PTZ position queries, and log level filtering
- **discover.sh**: PTZ camera discovery and config dump (dual-mode: sourceable + standalone). Fetches presets from the per-camera `/ptz/preset` endpoint (the `ptzPresetPositions` field on camera objects is empty on many firmware versions)
- **patrol.sh**: Core per-camera patrol loop with manual control detection, active dwell monitoring, and error resilience
- **config.json.example**: Example configuration template (copied to `config.json` on install)
- **install.sh**: Installation script with optional `--nvr`, `--username`, `--password` flags
  - Supports installation from different branches via the `PTZ_PATROL_BRANCH` environment variable
  - Automatically downloads required files if not found locally
- **uninstall.sh**: Script to remove the patrol system
- **ptz-patrol.service**: Systemd service configuration

## Credits & Acknowledgments

- **Original Concept**: [Jason Tucker — Adding Tour/Patrol Mode to UniFi G5 PTZ](https://jasontucker.blog/adding-a-tour-or-patrol-mode-to-unifi-g5-ptz-using-home-assistant/)
- **API Research**: [uiprotect](https://github.com/uilibs/uiprotect) — Unofficial Python API for UniFi Protect
- **Architecture**: Based on patterns from [ucg-max-fan-control](https://github.com/iceteaSA/ucg-max-fan-control)
- **PTZ State Discussion**: [uiprotect #436](https://github.com/uilibs/uiprotect/issues/436), [HA #142129](https://github.com/home-assistant/core/pull/142129)

---

If this project is useful to you, consider supporting continued development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/H2H719VB0U)

---

**Disclaimer**: This is a community project — not affiliated with or endorsed by Ubiquiti Inc. The authors accept no liability for hardware damage, motor wear, reduced camera lifespan, or any other consequences of using this software. PTZ cameras are mechanical devices; continuous automated patrol increases wear on pan/tilt/zoom motors beyond typical manual use. Use at your own risk.

**Compatibility**: Verified on UniFi OS 4.0.0+ with G5 PTZ and G6 PTZ cameras.
**License**: MIT

### Keywords

unifi, unifi-protect, ptz, ptz-patrol, ptz-tour, pan-tilt-zoom, g5-ptz, g6-ptz, ubiquiti, udm, udr, unvr, camera-patrol, preset-tour, motion-aware, auto-tracking, home-assistant-alternative, bash, systemd, unifi-os
