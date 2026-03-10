#!/bin/bash
# Sourced by ptz-patrol.sh — provides the per-camera patrol loop.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPT_DIR/api.sh"
source "$SCRIPT_DIR/discover.sh"

# ---------------------------------------------------------------------------
# Manual control detection
# ---------------------------------------------------------------------------

# Detect if someone else is controlling the camera (not us).
#
# Strategy:
#   1. After each goto we record a timestamp and the preset's expected zoom.
#   2. During dwell, if zoomPosition changes beyond a tolerance AND we are
#      outside the "settle" window after our last goto → external control.
#   3. Periodically poll full preset positions and compare pan/tilt/zoom.
#
# Returns 0 (true) if external control is detected.
is_externally_controlled() {
  local cam_id=$1
  local cam_name=$2
  local settle_seconds=$3
  local last_goto_ts=$4
  local expected_zoom=$5

  local now; now=$(date +%s)

  # Still in settle window after our last goto — not external
  if (( now - last_goto_ts < settle_seconds )); then
    return 1
  fi

  # Skip check if we have no expected zoom to compare against
  if (( expected_zoom < 0 )); then
    return 1
  fi

  # Get current zoom from camera state
  local current_zoom
  current_zoom=$(api_get_zoom_position "$cam_id")

  if (( current_zoom < 0 )); then
    # Failed to read — fail-safe, don't flag as external
    return 1
  fi

  # Compare zoom: if it differs by more than 2% from expected, someone moved it
  local zoom_diff=$(( current_zoom - expected_zoom ))
  zoom_diff=${zoom_diff#-}  # absolute value

  if (( zoom_diff > 2 )); then
    log "$cam_name" "info" "Zoom drift detected (expected=${expected_zoom}% actual=${current_zoom}%)"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Patrol loop
# ---------------------------------------------------------------------------

# Resolve settings and preset list, then loop forever
patrol_camera() {
  local cam_id=$1 cam_name=$2
  # Optional: pre-fetched camera JSON from discovery (3rd arg)
  local cam_discovery_json=${3:-}

  local cam_config
  cam_config=$(get_camera_config "$cam_id")

  local enabled
  enabled=$(echo "$cam_config" | jq -r '.enabled // true')
  if [[ "$enabled" == "false" ]]; then
    log "$cam_name" "info" "Disabled — skipping"
    return
  fi

  local dwell motion_hold max_wait manual_hold settle_seconds
  dwell=$(echo "$cam_config" | jq -r '.dwell_seconds // 30')
  motion_hold=$(echo "$cam_config" | jq -r '.motion_hold_seconds // 15')
  max_wait=$(echo "$cam_config" | jq -r '.max_tracking_wait // 300')
  manual_hold=$(echo "$cam_config" | jq -r '.manual_control_hold_seconds // 120')
  settle_seconds=$(echo "$cam_config" | jq -r '.ptz_settle_seconds // 10')

  # Presets: explicit override or auto-discovered
  local -a presets
  local override_slots
  override_slots=$(echo "$cam_config" | jq -r '.preset_slots // empty')

  if [[ -n "$override_slots" ]]; then
    mapfile -t presets < <(echo "$override_slots" | jq -r '.[]')
  elif [[ -n "$cam_discovery_json" ]]; then
    # Use presets from discovery data (avoids extra API call)
    mapfile -t presets < <(echo "$cam_discovery_json" | jq -r '.presets[].slot')
  else
    # Fetch from the per-camera preset endpoint (ptzPresetPositions on the
    # camera object is empty on many firmware versions)
    mapfile -t presets < <(api_get_with_retry "/cameras/$cam_id/ptz/preset" 3 5 | jq -r '
      [. // [] | sort_by(.slot) | .[].slot] | .[]
    ')
  fi

  if (( ${#presets[@]} < 2 )); then
    log "$cam_name" "warn" "Only ${#presets[@]} preset(s) — need 2+. Skipping."
    return 2  # Permanent condition — caller should not retry frequently
  fi

  log "$cam_name" "info" "Patrol: presets=[${presets[*]}] dwell=${dwell}s hold=${motion_hold}s max_wait=${max_wait}s manual_hold=${manual_hold}s"

  local idx=0
  local last_goto_ts=0
  local expected_zoom=-1
  local external_control_until=0

  while true; do
    api_ensure_auth

    # --- Backoff if too many consecutive API failures ---
    if (( _CONSECUTIVE_FAILURES >= 3 )); then
      local backoff
      backoff=$(api_backoff_delay 10 120)
      log "$cam_name" "warn" "$_CONSECUTIVE_FAILURES consecutive failures — backing off ${backoff}s"
      sleep "$backoff"
      api_ensure_auth
    fi

    local now; now=$(date +%s)

    # --- Check for external control (manual PTZ use) ---
    if (( now < external_control_until )); then
      local remaining=$(( external_control_until - now ))
      log "$cam_name" "debug" "Manual control hold — ${remaining}s remaining"
      sleep 5
      continue
    elif (( external_control_until > 0 )); then
      # Hold just expired — reset expected zoom so we don't immediately
      # re-trigger drift detection against the stale pre-hold value
      expected_zoom=-1
      external_control_until=0
      log "$cam_name" "info" "Manual control hold expired — resuming patrol"
    fi

    # Sample actual zoom once settle window expires (first check after goto)
    if (( expected_zoom < 0 && now - last_goto_ts >= settle_seconds && last_goto_ts > 0 )); then
      expected_zoom=$(api_get_zoom_position "$cam_id")
    fi

    if is_externally_controlled "$cam_id" "$cam_name" "$settle_seconds" "$last_goto_ts" "$expected_zoom"; then
      external_control_until=$(( $(date +%s) + manual_hold ))
      log "$cam_name" "info" "External control detected — holding patrol for ${manual_hold}s"
      sleep 5
      continue
    fi

    # --- Hold while tracking/motion is active ---
    local slot="${presets[$idx]}"
    local waited=0
    while is_tracking "$cam_id" "$motion_hold"; do
      if (( waited == 0 )); then
        log "$cam_name" "info" "Tracking/motion active — holding"
      fi
      sleep 5
      waited=$((waited + 5))
      api_ensure_auth
      if (( waited >= max_wait )); then
        log "$cam_name" "warn" "Max wait (${max_wait}s) hit — advancing anyway"
        break
      fi
    done
    if (( waited > 0 && waited < max_wait )); then
      log "$cam_name" "debug" "Clear after ${waited}s — resuming"
    fi

    # --- Move to next preset ---
    local code
    code=$(api_post_with_retry "/cameras/$cam_id/ptz/goto/$slot" 2 3) || true

    case "$code" in
      200|204)
        last_goto_ts=$(date +%s)
        # Mark zoom unknown until settle completes — we'll sample the actual
        # ISP zoom after the settle window rather than computing from preset
        # data (zoom scale mapping varies between G5 and G6 models).
        expected_zoom=-1
        log "$cam_name" "info" "→ Slot $slot [HTTP $code]"
        ;;
      404)
        log "$cam_name" "error" "Preset slot $slot not found (HTTP 404) — advancing"
        idx=$(( (idx + 1) % ${#presets[@]} ))
        continue
        ;;
      "")
        log "$cam_name" "error" "No response from goto command — advancing"
        idx=$(( (idx + 1) % ${#presets[@]} ))
        continue
        ;;
      *)
        log "$cam_name" "warn" "Unexpected HTTP $code on goto slot $slot"
        ;;
    esac

    # Dwell at current preset, polling for external control and motion every 5s.
    # This replaces a blind sleep so we can react promptly to manual PTZ use
    # or new motion/tracking activity.
    local dwell_remaining=$dwell
    local dwell_interrupted=0
    while (( dwell_remaining > 0 )); do
      local poll_interval=$(( dwell_remaining < 5 ? dwell_remaining : 5 ))
      sleep "$poll_interval"
      dwell_remaining=$(( dwell_remaining - poll_interval ))

      # Sample zoom once after settle if not yet done
      now=$(date +%s)
      if (( expected_zoom < 0 && now - last_goto_ts >= settle_seconds )); then
        expected_zoom=$(api_get_zoom_position "$cam_id")
      fi

      # Check for external control during dwell (zoom drift)
      if is_externally_controlled "$cam_id" "$cam_name" "$settle_seconds" "$last_goto_ts" "$expected_zoom"; then
        external_control_until=$(( $(date +%s) + manual_hold ))
        log "$cam_name" "info" "External control detected — holding patrol for ${manual_hold}s"
        dwell_interrupted=1
        break
      fi

      # Check for new motion/tracking during dwell (catches pan/tilt manual
      # control since motor movement triggers the motion sensor)
      if is_tracking "$cam_id" "$motion_hold"; then
        log "$cam_name" "info" "Activity during dwell — holding"
        dwell_interrupted=1
        break
      fi
    done

    if (( dwell_interrupted )); then
      continue  # Skip advancing — go back to top of loop (hold/tracking checks)
    fi

    idx=$(( (idx + 1) % ${#presets[@]} ))
  done
}
