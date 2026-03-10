#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/api.sh"
source "$SCRIPT_DIR/patrol.sh"

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

_CHILD_PIDS=()
_CAMERA_IDS=()
_SHUTTING_DOWN=0

shutdown() {
  # Guard against re-entrancy (EXIT fires again after exit 0)
  (( _SHUTTING_DOWN )) && return
  _SHUTTING_DOWN=1

  log "main" "info" "Shutdown requested — stopping all patrols"
  for pid in "${_CHILD_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true

  # Optionally send cameras home on shutdown
  local home_on_shutdown
  home_on_shutdown=$(cfg '.defaults.home_on_shutdown // false')
  if [[ "$home_on_shutdown" == "true" && ${#_CAMERA_IDS[@]} -gt 0 ]]; then
    api_ensure_auth
    log "main" "info" "Sending cameras to home position..."
    for cam_id in "${_CAMERA_IDS[@]}"; do
      api_post "/cameras/$cam_id/ptz/goto/-1" >/dev/null 2>&1 || true
    done
  fi

  log "main" "info" "Shutdown complete"
  api_cleanup
  exit 0
}

# ---------------------------------------------------------------------------
# Main: init, discover, launch
# ---------------------------------------------------------------------------

api_init

# Set traps AFTER api_init (which sets its own EXIT trap for cleanup).
# This overrides api_cleanup on EXIT so shutdown() handles everything.
trap shutdown SIGTERM SIGINT EXIT

# Auth with retry (NVR may still be booting after firmware update)
if ! api_auth_with_retry 5 10; then
  log "main" "error" "Could not authenticate with NVR — exiting"
  exit 1
fi

auto_discover=$(cfg '.auto_discover // true')
if [[ "$auto_discover" != "true" ]]; then
  log "main" "error" "auto_discover is disabled — enable it in config.json to use patrol"
  exit 1
fi

log "main" "info" "Discovering PTZ cameras..."
cameras=$(discover_ptz_cameras)
count=$(echo "$cameras" | jq 'length')

if (( count == 0 )); then
  log "main" "error" "No PTZ cameras found"
  exit 1
fi

log "main" "info" "Found $count PTZ camera(s) — launching patrol loops"

# Camera IDs populated in the loop below (used by shutdown handler)

for (( i = 0; i < count; i++ )); do
  cam_id=$(echo "$cameras" | jq -r ".[$i].id")
  cam_name=$(echo "$cameras" | jq -r ".[$i].name")
  cam_json=$(echo "$cameras" | jq -c ".[$i]")

  # Skip cameras disabled in config
  cam_config=$(get_camera_config "$cam_id")
  enabled=$(echo "$cam_config" | jq -r '.enabled // true')
  if [[ "$enabled" == "false" ]]; then
    log "main" "info" "$cam_name: disabled in config — skipping"
    continue
  fi

  _CAMERA_IDS+=("$cam_id")

  # Each camera gets its own subshell with independent auth and temp files.
  # The restart wrapper ensures a single API error doesn't permanently kill
  # a camera's patrol — it just restarts after a delay.
  (
    # Fresh init for this subprocess (own cookie jar, own auth token)
    api_init
    api_auth_with_retry 5 10 || {
      log "$cam_name" "error" "Could not authenticate — patrol not started"
      exit 1
    }

    while true; do
      rc=0
      patrol_camera "$cam_id" "$cam_name" "$cam_json" || rc=$?

      if (( rc == 2 )); then
        # Permanent condition (e.g. no presets) — retry infrequently
        log "$cam_name" "warn" "No presets — will re-check in 5 minutes"
        sleep 300
      else
        log "$cam_name" "warn" "Patrol loop exited — restarting in 10s"
        sleep 10
      fi
      api_ensure_auth
    done
  ) &
  _CHILD_PIDS+=("$!")
done

# Wait for all children (shutdown trap handles SIGTERM)
wait
