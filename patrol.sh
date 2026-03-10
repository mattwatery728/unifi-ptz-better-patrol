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
# Schedule
# ---------------------------------------------------------------------------

# Check if the current time falls within a patrol schedule window.
# Arguments: schedule_start schedule_end schedule_days_json
#   schedule_start/end: "HH:MM" strings (24h). Empty = no schedule (always active).
#   schedule_days_json: JSON array of 3-letter day names, e.g. '["mon","tue","wed"]'
#                       Empty or "null" = all days.
# Returns 0 if patrol should be active, 1 if outside the schedule window.
#
# Day-of-week handling for overnight windows:
#   For "22:00-06:00" on ["mon","tue","wed","thu","fri"]:
#   - Friday 23:00 → check Friday (today) → in list → active
#   - Saturday 01:00 → in early-morning tail, check Friday (yesterday) → in list → active
#   - Saturday 23:00 → check Saturday (today) → not in list → inactive
is_within_schedule() {
  local sched_start=$1 sched_end=$2 sched_days=$3

  # No schedule configured — always active
  if [[ -z "$sched_start" || -z "$sched_end" ]]; then
    return 0
  fi

  # LC_ALL=C forces English day names regardless of system locale
  local now_hhmm; now_hhmm=$(date +%H:%M)
  local is_overnight=0
  [[ "$sched_start" > "$sched_end" ]] && is_overnight=1

  # Determine which time portion we're in and check accordingly
  local in_window=0
  if (( is_overnight )); then
    # Overnight window: e.g. 22:00-06:00
    if [[ ! "$now_hhmm" < "$sched_start" || "$now_hhmm" < "$sched_end" ]]; then
      in_window=1
    fi
  else
    # Same-day window: e.g. 08:00-18:00
    if [[ ! "$now_hhmm" < "$sched_start" && "$now_hhmm" < "$sched_end" ]]; then
      in_window=1
    fi
  fi

  if (( ! in_window )); then
    return 1
  fi

  # Check day-of-week if days are specified
  if [[ -n "$sched_days" && "$sched_days" != "null" ]]; then
    local check_day
    if (( is_overnight )) && [[ "$now_hhmm" < "$sched_end" ]]; then
      # Early-morning tail of an overnight window — check yesterday's day
      # because the window started the previous calendar day
      check_day=$(LC_ALL=C date -d "yesterday" +%a 2>/dev/null \
               || LC_ALL=C date -v-1d +%a 2>/dev/null)
    else
      check_day=$(LC_ALL=C date +%a)
    fi
    check_day=$(echo "$check_day" | tr '[:upper:]' '[:lower:]')

    local match; match=$(echo "$sched_days" | jq -r --arg d "$check_day" '[.[] | ascii_downcase] | index($d)')
    if [[ "$match" == "null" ]]; then
      return 1
    fi
  fi

  return 0
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

  # Schedule: optional time window for when patrol should be active
  local sched_start sched_end sched_days sched_home
  sched_start=$(echo "$cam_config" | jq -r '.schedule.start // empty')
  sched_end=$(echo "$cam_config" | jq -r '.schedule.end // empty')
  sched_days=$(echo "$cam_config" | jq -c '.schedule.days // null')
  sched_home=$(echo "$cam_config" | jq -r '.schedule.home_on_pause // false')

  if [[ -n "$sched_start" && -n "$sched_end" && "$sched_start" == "$sched_end" ]]; then
    log "$cam_name" "warn" "Schedule start and end are the same ($sched_start) — patrol will never run. Remove schedule or fix times."
  fi

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

  local sched_info=""
  if [[ -n "$sched_start" && -n "$sched_end" ]]; then
    sched_info=" schedule=${sched_start}-${sched_end}"
    if [[ -n "$sched_days" && "$sched_days" != "null" ]]; then
      local days_str; days_str=$(echo "$sched_days" | jq -r 'join(",")')
      sched_info+=" days=${days_str}"
    fi
    sched_info+=" home_on_pause=${sched_home}"
  fi
  log "$cam_name" "info" "Patrol: presets=[${presets[*]}] dwell=${dwell}s hold=${motion_hold}s max_wait=${max_wait}s manual_hold=${manual_hold}s${sched_info}"

  local idx=0
  local last_goto_ts=0
  local expected_zoom=-1
  local external_control_until=0
  local schedule_paused=0

  while true; do
    api_ensure_auth

    # --- Schedule check ---
    if ! is_within_schedule "$sched_start" "$sched_end" "$sched_days"; then
      if (( schedule_paused == 0 )); then
        log "$cam_name" "info" "Outside schedule window (${sched_start}-${sched_end}) — pausing patrol"
        if [[ "$sched_home" == "true" ]]; then
          local home_code
          home_code=$(api_post_with_retry "/cameras/$cam_id/ptz/goto/-1" 2 3) || true
          if [[ "$home_code" == "200" || "$home_code" == "204" ]]; then
            log "$cam_name" "info" "Sent to home position"
          else
            log "$cam_name" "warn" "Failed to send to home position (HTTP ${home_code:-timeout})"
          fi
        fi
        schedule_paused=1
      fi
      sleep 60
      continue
    fi
    if (( schedule_paused == 1 )); then
      log "$cam_name" "info" "Schedule window active (${sched_start}-${sched_end}) — resuming patrol"
      schedule_paused=0
      expected_zoom=-1
    fi

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
