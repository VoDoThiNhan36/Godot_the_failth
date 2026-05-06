# Ship Movement Flow (IDLE → MOVE → IDLE)

## 1. IDLE State
- **Condition:** No current waypoint (`current_waypoint == null`).
- **Behavior:**
  - Ship applies a force opposite to its current velocity to gradually stop (`apply_central_force(-linear_velocity * max_thrust_force * linear_power_to_mass_ratio)`).
  - Lateral and angular damping are applied to bring the ship to a full stop.

## 2. Adding a Waypoint (move_to)
- **Trigger:** Player clicks to set a new target position.
- **Behavior:**
  - If not in sequence mode, all old waypoints are cleared.
  - Height offset is applied if set.
  - A new `Movement_Waypoint` is created and added to the queue.
  - If not already moving, the first waypoint is loaded and state changes to MOVE.

## 3. MOVE State (Following Waypoints)
- **Condition:** `current_waypoint != null`.
- **Behavior:**
  - Each physics frame, `_integrate_forces` is called:
    - Loads next waypoint if needed.
    - Calls `_integrate_movement` to:
      - Calculate distance and direction to target.
      - Blend direction as ship approaches target for smooth arrival.
      - Calls `update_rotation` to steer ship toward target direction.
      - Calls `_integrate_thrust_control` to apply thrust based on alignment and distance.
    - Applies lateral damping and auto-correction for roll/pitch.
    - Clamps pitch/roll if exceeding limits.
  - When within `arrival_radius` of the target:
    - If more waypoints exist, load the next one.
    - If no more waypoints, clear current waypoint and switch to IDLE.

## 4. Returning to IDLE
- **Condition:** No more waypoints (`current_waypoint == null`).
- **Behavior:**
  - Ship applies braking force and damping to come to a stop.
  - State remains IDLE until a new waypoint is set.

---

## Key Functions
- `handle_state_idle`: Applies braking force in IDLE.
- `move_to`: Adds a new waypoint and starts movement.
- `_integrate_forces`: Main physics loop, handles movement, damping, and corrections.
- `_integrate_movement`: Calculates direction, triggers rotation and thrust.
- `update_rotation`: Handles ship steering.
- `_integrate_thrust_control`: Applies thrust based on alignment and distance.
- `apply_pitch_clamp` / `apply_roll_clamp`: Prevents exceeding pitch/roll limits.
- `apply_pitch_correction` / `apply_roll_correction`: Auto-stabilizes ship orientation.
