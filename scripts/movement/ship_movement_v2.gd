extends RigidBody3D

# --- Các thuộc tính có thể tùy chỉnh trong Inspector ---
@export_group("Steering Behavior")
@export var max_linear_speed := 15.0
@export var max_thrust_force := 100.0       # Lực đẩy tối đa (N) - tăng lên vì dùng force thật
@export var max_brake_force := 50.0         # Lực phanh tối đa (N)
@export var braking_distance_factor := 0.5
@export var distance_threshold := 0.5
@export var lateral_friction := 5.0
@export var auto_throttle := 0.0

@export_group("Rotation Physics")
@export var max_torque := 80.0              # Lực xoay tối đa (N*m)
@export var angular_damping_custom := 3.0   # Damping xoay bổ sung (trên angular_damp của RigidBody)
@export var max_turn_speed := 2.0           # Tốc độ xoay tối đa (rad/s)
@export var turn_sensitivity := 3.0
@export var roll_correction_torque := 40.0  # Lực tự cân bằng roll về 0
@export var max_pitch_angle := 45.0         # Góc pitch tối đa (độ)

@export_group("Fajen Dynamical Steering")
@export var fajen_detection_radius := 35.0
@export var fajen_max_obstacles := 15
@export var fajen_kg := 12.0
@export var fajen_ko := 200.0
@export var fajen_b := 4.2
@export var fajen_c4 := 0.2
@export var fajen_noise := 0.2
var nearby_obstacles: Array[Node3D] = []
var fajen_angular_velocity := Vector2.ZERO  # Momentum xoay (pitch, yaw)

# --- Biến lưu trữ trạng thái ---
enum PlayerState { IDLE, MOVE }
enum ShipSteeringMode { FAJEN_WARREN }
var current_state: PlayerState = PlayerState.IDLE
@export var current_steering_mode = ShipSteeringMode.FAJEN_WARREN

# --- Biến movement ---
var current_target_position := Vector3.ZERO
var current_target_direction := Vector3.RIGHT
var current_target_height_offset := 0.0
var ship_movement_waypoints: Array[Movement_Waypoint] = []
var current_waypoint: Movement_Waypoint = null
var is_at_current_waypoint_threshold := false
var ship_length: float

# --- Node refs ---
@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"

# --- Debug meshes ---
var debug_vector_mesh := MeshInstance3D.new()
var trajectory_mesh := MeshInstance3D.new()
var waypoints_mesh := MeshInstance3D.new()
@export var show_debug := false

# ─────────────────────────────────────────────────────────────────
#  DEFAULT FUNCTIONS
# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Tính ship length từ mesh con đầu tiên
	var ship_part = get_child(0) as Node3D
	if ship_part:
		var mesh = ship_part.get_child(0) as MeshInstance3D
		if mesh:
			ship_length = mesh.get_aabb().size.x

	# RigidBody3D settings
	gravity_scale = 0.0             # Không bị kéo xuống
	lock_rotation = false           # Cho phép xoay, tự cân bằng bằng torque
	linear_damp = 0.5               # Damping tịnh tiến nhẹ
	angular_damp = angular_damping_custom  # Damping xoay

	# Fajen area
	setup_fajen_area()

	# Debug meshes setup
	_setup_debug_meshes()

func _physics_process(delta: float) -> void:
	match current_state:
		PlayerState.IDLE: handle_state_idle(delta)
		PlayerState.MOVE: handle_state_move(delta)

	# Auto cân bằng roll luôn luôn (cả IDLE lẫn MOVE)
	apply_roll_correction()
	# Clamp pitch
	apply_pitch_clamp()

	draw_waypoints_path()

	rich_text_label.text = \
		"\nAngular velocity: " + str(angular_velocity.length()) + \
		"\nThrottle: " + str(auto_throttle) + \
		"\nVelocity: " + str(linear_velocity.length()) + \
		"\nTarget: " + str(current_target_position) + \
		"\nObstacles: " + str(nearby_obstacles.size()) + \
		"\nWaypoints: " + str(ship_movement_waypoints.size())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset = 2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -2.0
			current_target_height_offset = clamp(current_target_height_offset + offset, -45.0, 45.0)

			if Input.is_action_pressed("sequence_move"):
				_handle_height_offset_waypoint(offset)

# ─────────────────────────────────────────────────────────────────
#  STATE MACHINE
# ─────────────────────────────────────────────────────────────────
func handle_state_idle(delta: float) -> void:
	# Phanh tịnh tiến: apply lực ngược chiều velocity
	var brake_force = -linear_velocity.normalized() * min(max_brake_force, linear_velocity.length() * mass)
	apply_central_force(brake_force)

	# Damping xoay mạnh hơn khi IDLE
	apply_torque(-angular_velocity * angular_damping_custom * mass)

func handle_state_move(delta: float) -> void:
	var current_position = global_position
	var target_position = current_target_position
	var distance = current_position.distance_to(target_position)

	# Stopping distance: s = v² / 2a
	var current_speed = linear_velocity.length()
	var deceleration = max_brake_force / mass
	var min_stopping_distance = (current_speed * current_speed) / (2.0 * deceleration)

	# Heading vector
	var ship_heading_vector = -global_transform.basis.z

	# ── Direction blending (giữ nguyên logic cũ) ──
	var rotation_blend_distance = distance_threshold * 2.0
	var raw_direction: Vector3
	if distance > rotation_blend_distance:
		is_at_current_waypoint_threshold = false
		raw_direction = current_position.direction_to(target_position)
	elif distance > distance_threshold:
		if not is_at_current_waypoint_threshold:
			var blend_weight = clamp((distance - distance_threshold) / rotation_blend_distance, 0.8, 1.0)
			raw_direction = current_target_direction.slerp(
				current_position.direction_to(target_position), blend_weight).normalized()
		else:
			raw_direction = current_target_direction
	else:
		is_at_current_waypoint_threshold = true
		raw_direction = current_target_direction

	var desired_direction := raw_direction
	var danger_throttle_factor := 1.0

	# ── Fajen steering hoặc manual rotation ──
	if distance > ship_length * 5.0:
		var fajen_result = compute_fajen_angular_acceleration(
			ship_heading_vector, raw_direction, fajen_angular_velocity)
		var raw_fajen_accel: Vector2 = fajen_result["angular_accel"]
		var total_repulsion: float = fajen_result["repulsion_force"]

		# Clamp accel theo max torque
		var max_engine_accel = max_torque / mass
		var applied_accel_pitch = clamp(raw_fajen_accel.x, -max_engine_accel, max_engine_accel)
		var applied_accel_yaw   = clamp(raw_fajen_accel.y, -max_engine_accel, max_engine_accel)

		# Cập nhật fajen momentum
		fajen_angular_velocity.x += applied_accel_pitch * delta
		fajen_angular_velocity.y += applied_accel_yaw   * delta
		fajen_angular_velocity = fajen_angular_velocity.lerp(Vector2.ZERO, angular_damping_custom * delta)
		if fajen_angular_velocity.length() > max_turn_speed:
			fajen_angular_velocity = fajen_angular_velocity.normalized() * max_turn_speed

		# ── Apply torque thật (thay global_rotate) ──
		# Yaw: xoay quanh trục Y global
		var yaw_torque   = Vector3.UP * fajen_angular_velocity.y * max_torque
		# Pitch: xoay quanh trục X local
		var pitch_torque = global_transform.basis.x * fajen_angular_velocity.x * max_torque
		apply_torque(yaw_torque + pitch_torque)

		# Danger throttle
		if total_repulsion > 5.0:
			danger_throttle_factor = clamp(1.0 - (total_repulsion / 50.0), 0.1, 1.0)

	else:
		# Gần target: dùng torque steering đơn giản
		apply_torque_steering(delta, ship_heading_vector, desired_direction, distance, min_stopping_distance)

	# ── Heading alignment ──
	var heading_alignment = ship_heading_vector.dot(desired_direction)

	# ── Waypoint switching ──
	var waypoint_switch_distance = distance_threshold / 2.0
	if ship_movement_waypoints.size() > 0:
		waypoint_switch_distance = max_linear_speed * 0.5
	if distance < waypoint_switch_distance:
		if ship_movement_waypoints.size() > 0:
			load_next_waypoint()
		else:
			# Phanh nhanh khi đến đích cuối
			var brake = -linear_velocity.normalized() * max_brake_force
			apply_central_force(brake)
			if linear_velocity.length() < 0.1 and heading_alignment >= 0.999:
				auto_throttle = 0.0

	# ── ARRIVE: tính lực đẩy ──
	var is_final_waypoint = ship_movement_waypoints.is_empty()

	if distance > min_stopping_distance:
		# Target speed
		var target_speed: float
		if not is_final_waypoint:
			target_speed = min(distance / (braking_distance_factor * 0.5), max_linear_speed)
		else:
			target_speed = clamp(distance / braking_distance_factor, 0.05, max_linear_speed)

		# Auto throttle theo heading alignment
		auto_throttle = pow(clamp(heading_alignment, 0.0, 1.0), 3)
		auto_throttle *= danger_throttle_factor

		if heading_alignment > 0.0:
			# Desired velocity → steering force → apply force
			var desired_velocity = ship_heading_vector * (target_speed * auto_throttle)
			var steering_force   = (desired_velocity - linear_velocity) * mass
			if steering_force.length() > max_thrust_force:
				steering_force = steering_force.normalized() * max_thrust_force
			apply_central_force(steering_force)
		else:
			# Ngược hướng: phanh lại
			var brake = -linear_velocity.normalized() * max_brake_force
			apply_central_force(brake)
	else:
		# Trong vùng stopping distance: phanh
		var brake_strength = max_brake_force * (0.5 if not is_final_waypoint else 1.0)
		var brake = -linear_velocity.normalized() * brake_strength
		apply_central_force(brake)

	# ── Lateral dampening (chống trượt ngang) ──
	var forward_speed    = linear_velocity.dot(ship_heading_vector)
	var forward_velocity = ship_heading_vector * forward_speed
	var lateral_velocity = linear_velocity - forward_velocity

	# Tăng friction khi gần đích
	var effective_friction = lateral_friction
	if distance < distance_threshold / 2.0:
		effective_friction *= 2.0

	# Apply lực triệt tiêu vận tốc ngang
	var lateral_force = -lateral_velocity * effective_friction * mass
	apply_central_force(lateral_force)

	# ── Speed clamp ──
	if linear_velocity.length() > max_linear_speed:
		linear_velocity = linear_velocity.normalized() * max_linear_speed

	# Debug
	draw_debug_vectors(desired_direction, forward_velocity, lateral_velocity)
	var predicted = calculate_predicted_path()
	draw_trajectory_line(predicted)

# ─────────────────────────────────────────────────────────────────
#  ROTATION SUPPORT
# ─────────────────────────────────────────────────────────────────

# Tự cân bằng roll về 0 bằng torque (luôn chạy)
func apply_roll_correction() -> void:
	# Roll = góc nghiêng trái/phải (trục Z local so với UP global)
	var ship_up    = global_transform.basis.y
	var world_up   = Vector3.UP
	var roll_error = ship_up.cross(world_up)

	# Chiếu lên trục Z local để chỉ lấy thành phần roll
	var roll_axis  = global_transform.basis.z
	var roll_correction = roll_axis * roll_error.dot(roll_axis) * roll_correction_torque

	# Damping angular velocity trục Z để không lắc lư
	var roll_damp = -angular_velocity.project(global_transform.basis.z) * angular_damping_custom * mass

	apply_torque(roll_correction * mass + roll_damp)

# Clamp góc pitch tối đa (không cho ngóc đầu quá ±45°)
func apply_pitch_clamp() -> void:
	var ship_forward = -global_transform.basis.z
	# Tính pitch hiện tại
	var pitch = asin(clamp(ship_forward.y, -1.0, 1.0))
	var max_pitch_rad = deg_to_rad(max_pitch_angle)

	if abs(pitch) > max_pitch_rad:
		# Apply torque ngược lại để kéo về giới hạn
		var pitch_error  = pitch - sign(pitch) * max_pitch_rad
		var pitch_torque = -global_transform.basis.x * pitch_error * max_torque
		apply_torque(pitch_torque)

# Torque steering đơn giản khi ở gần target (thay Fajen)
func apply_torque_steering(delta: float, heading: Vector3, desired: Vector3,
							dist: float, stopping_dist: float) -> void:
	if heading.is_equal_approx(desired): return

	# Tính trục và góc lệch
	var cross = heading.cross(desired)
	if cross.length_squared() < 0.0001: return
	var axis  = cross.normalized()
	var angle = heading.angle_to(desired)

	# Desired angular velocity tỉ lệ với góc lệch
	var desired_ang_speed = clamp(angle * turn_sensitivity, -max_turn_speed, max_turn_speed)
	var current_ang_speed = angular_velocity.dot(axis)
	var torque_scalar     = (desired_ang_speed - current_ang_speed) * max_torque
	apply_torque(axis * torque_scalar)

	# Level out khi gần đích cuối
	if ship_movement_waypoints.is_empty():
		if dist <= stopping_dist or dist < max_linear_speed:
			var flat_fwd = Vector3(desired.x, 0.0, desired.z).normalized()
			if flat_fwd.length_squared() > 0.001:
				var level_cross = heading.cross(flat_fwd)
				if level_cross.length_squared() > 0.0001:
					var blend = clamp(1.0 - dist / max_linear_speed, 0.0, 1.0)
					apply_torque(level_cross.normalized() * blend * max_torque * 0.5)

# ─────────────────────────────────────────────────────────────────
#  FAJEN STEERING (giữ nguyên logic, chỉ đổi apply)
# ─────────────────────────────────────────────────────────────────
func setup_fajen_area() -> void:
	var area = Area3D.new()
	area.name = "FajenAvoidanceArea"
	add_child(area)
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = fajen_detection_radius
	col.shape = sphere
	area.add_child(col)
	area.collision_mask = 1
	area.body_entered.connect(_on_fajen_body_entered)
	area.body_exited.connect(_on_fajen_body_exited)

func _on_fajen_body_entered(body: Node3D) -> void:
	if body != self and not nearby_obstacles.has(body):
		nearby_obstacles.append(body)

func _on_fajen_body_exited(body: Node3D) -> void:
	nearby_obstacles.erase(body)

func compute_fajen_angular_acceleration(
		ship_heading_vector: Vector3,
		target_direction: Vector3,
		current_angular_velocity: Vector2) -> Dictionary:

	var space_state = get_world_3d().direct_space_state

	var current_phi_yaw   = atan2(ship_heading_vector.x, ship_heading_vector.z)
	var current_phi_pitch = atan2(ship_heading_vector.y,
		sqrt(ship_heading_vector.x*ship_heading_vector.x + ship_heading_vector.z*ship_heading_vector.z))

	var goal_phi_yaw   = atan2(target_direction.x, target_direction.z)
	var goal_phi_pitch = atan2(target_direction.y,
		sqrt(target_direction.x*target_direction.x + target_direction.z*target_direction.z))

	var distance_to_goal = max(0.5, global_position.distance_to(current_target_position))

	var phi_double_dot_yaw   = -fajen_b * current_angular_velocity.y
	var phi_double_dot_pitch = -fajen_b * current_angular_velocity.x

	var goal_error_yaw   = fposmod((current_phi_yaw   - goal_phi_yaw)   + PI, TAU) - PI
	var goal_error_pitch = fposmod((current_phi_pitch - goal_phi_pitch) + PI, TAU) - PI

	var goal_term_yaw   = fajen_kg * goal_error_yaw   * (exp(-0.4 * distance_to_goal) + 0.4)
	var goal_term_pitch = fajen_kg * goal_error_pitch * (exp(-0.4 * distance_to_goal) + 0.4)

	phi_double_dot_yaw   -= goal_term_yaw
	phi_double_dot_pitch -= goal_term_pitch

	var total_repulsion := 0.0
	var count := 0

	for obstacle in nearby_obstacles:
		if count >= fajen_max_obstacles: break

		var query = PhysicsRayQueryParameters3D.create(global_position, obstacle.global_position)
		query.exclude = [self.get_rid()]
		var result = space_state.intersect_ray(query)

		var hit_position = obstacle.global_position
		var obs_radius   = 1.0
		if result:
			hit_position = result.position
			obs_radius   = max(1.0, hit_position.distance_to(obstacle.global_position))

		var distance_to_obstacle = global_position.distance_to(hit_position)
		if distance_to_obstacle > fajen_detection_radius or distance_to_obstacle < 0.1: continue

		var direction_to_obs = (hit_position - global_position).normalized()
		if ship_heading_vector.dot(direction_to_obs) < -0.25: continue

		var obs_phi_yaw   = atan2(direction_to_obs.x, direction_to_obs.z)
		var obs_phi_pitch = atan2(direction_to_obs.y,
			sqrt(direction_to_obs.x*direction_to_obs.x + direction_to_obs.z*direction_to_obs.z))

		var obs_error_yaw   = fposmod((current_phi_yaw   - obs_phi_yaw)   + PI, TAU) - PI
		var obs_error_pitch = fposmod((current_phi_pitch - obs_phi_pitch) + PI, TAU) - PI

		var dynamic_ko      = fajen_ko * (1.0 + sqrt(obs_radius))
		var obs_term_yaw    = dynamic_ko * obs_error_yaw   * exp(-6.0 * abs(obs_error_yaw))   * exp(-fajen_c4 * distance_to_obstacle)
		var obs_term_pitch  = dynamic_ko * obs_error_pitch * exp(-6.0 * abs(obs_error_pitch)) * exp(-fajen_c4 * distance_to_obstacle)

		phi_double_dot_yaw   += obs_term_yaw
		phi_double_dot_pitch += obs_term_pitch
		total_repulsion      += Vector2(obs_term_yaw, obs_term_pitch).length()
		count += 1

	if count > 0 and current_angular_velocity.length() < 0.1 \
			and Vector2(phi_double_dot_pitch, phi_double_dot_yaw).length() < 0.1:
		phi_double_dot_yaw   += randf_range(-fajen_noise, fajen_noise)
		phi_double_dot_pitch += randf_range(-fajen_noise, fajen_noise)

	return {
		"angular_accel":   Vector2(phi_double_dot_pitch, phi_double_dot_yaw),
		"repulsion_force": total_repulsion
	}

# ─────────────────────────────────────────────────────────────────
#  WAYPOINT SYSTEM (giữ nguyên)
# ─────────────────────────────────────────────────────────────────
func move_to(new_position: Vector3, is_sequence: bool = false) -> void:
	if not is_sequence:
		clear_all_waypoints()

	new_position.y += current_target_height_offset

	var previous_position: Vector3
	if current_state == PlayerState.MOVE:
		previous_position = ship_movement_waypoints.back().position \
			if not ship_movement_waypoints.is_empty() else current_target_position
	else:
		previous_position = global_position

	var new_waypoint = Movement_Waypoint.new(new_position, previous_position)
	add_child(new_waypoint.point_marker)
	ship_movement_waypoints.append(new_waypoint)

	if current_state != PlayerState.MOVE or not is_sequence:
		load_next_waypoint()

	change_state(PlayerState.MOVE)

func clear_all_waypoints() -> void:
	for wp in ship_movement_waypoints:
		if is_instance_valid(wp.point_marker): wp.point_marker.queue_free()
	ship_movement_waypoints.clear()
	if current_waypoint and is_instance_valid(current_waypoint.point_marker):
		current_waypoint.point_marker.queue_free()
	current_waypoint = null

func load_next_waypoint() -> void:
	if ship_movement_waypoints.is_empty(): return
	if current_waypoint: current_waypoint.point_marker.queue_free()
	current_waypoint            = ship_movement_waypoints.pop_front()
	current_target_position     = current_waypoint.position
	current_target_direction    = current_waypoint.direction
	# Giảm momentum xoay khi chuyển waypoint
	fajen_angular_velocity     *= 0.5

func change_state(new_state: PlayerState) -> void:
	if current_state == new_state: return
	current_state = new_state
	print("State → ", current_state)

# ─────────────────────────────────────────────────────────────────
#  HEIGHT OFFSET INPUT (giữ nguyên logic)
# ─────────────────────────────────────────────────────────────────
func _handle_height_offset_waypoint(offset: float) -> void:
	if not ship_movement_waypoints.is_empty():
		var last_wp = ship_movement_waypoints.back()
		var prev_pos = ship_movement_waypoints[ship_movement_waypoints.size() - 2].position \
			if ship_movement_waypoints.size() > 1 \
			else (current_target_position if current_state == PlayerState.MOVE else global_position)
		var dist_xz = Vector2(last_wp.position.x, last_wp.position.z) \
			.distance_to(Vector2(prev_pos.x, prev_pos.z))
		last_wp.position.y = clamp(last_wp.position.y + offset,
			prev_pos.y - dist_xz, prev_pos.y + dist_xz)
		if is_instance_valid(last_wp.point_marker):
			last_wp.point_marker.global_position.y = last_wp.position.y

	elif current_state == PlayerState.MOVE:
		var dist_xz = Vector2(current_target_position.x, current_target_position.z) \
			.distance_to(Vector2(global_position.x, global_position.z))
		current_target_position.y = clamp(current_target_position.y + offset,
			global_position.y - dist_xz, global_position.y + dist_xz)
		if current_waypoint and is_instance_valid(current_waypoint.point_marker):
			current_waypoint.position.y                  = current_target_position.y
			current_waypoint.point_marker.global_position.y = current_target_position.y

# ─────────────────────────────────────────────────────────────────
#  DEBUG VISUAL (giữ nguyên)
# ─────────────────────────────────────────────────────────────────
func _setup_debug_meshes() -> void:
	for mesh_ref in [debug_vector_mesh, trajectory_mesh, waypoints_mesh]:
		mesh_ref.top_level = true
		add_child(mesh_ref)

	debug_vector_mesh.mesh = ImmediateMesh.new()
	var dmat = StandardMaterial3D.new()
	dmat.vertex_color_use_as_albedo = true
	dmat.flags_unshaded = true
	dmat.no_depth_test  = true
	debug_vector_mesh.material_override = dmat

	trajectory_mesh.mesh = ImmediateMesh.new()
	var tmat = StandardMaterial3D.new()
	tmat.albedo_color  = Color.GREEN
	tmat.flags_unshaded = true
	tmat.no_depth_test  = true
	trajectory_mesh.material_override = tmat

	waypoints_mesh.mesh = ImmediateMesh.new()
	var wmat = StandardMaterial3D.new()
	wmat.albedo_color  = Color.PLUM
	wmat.flags_unshaded = true
	wmat.no_depth_test  = true
	waypoints_mesh.material_override = wmat

func draw_debug_vectors(desired_direction: Vector3, forward_velocity: Vector3, lateral_velocity: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if current_state == PlayerState.IDLE: return
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var origin = global_position + Vector3(0, 2.0, 0)
	m.surface_set_color(Color.GREEN);  m.surface_add_vertex(origin); m.surface_add_vertex(origin + desired_direction * 5.0)
	m.surface_set_color(Color.BLUE);   m.surface_add_vertex(origin); m.surface_add_vertex(origin + forward_velocity * 2.0)
	m.surface_set_color(Color.RED);    m.surface_add_vertex(origin); m.surface_add_vertex(origin + lateral_velocity * 2.0)
	m.surface_end()

func draw_trajectory_line(points: PackedVector3Array) -> void:
	var m = trajectory_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if points.is_empty() or current_state == PlayerState.IDLE: return
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		m.surface_add_vertex(Vector3(p.x, 1.0, p.z))
	m.surface_end()

func calculate_predicted_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	var sim_pos = global_position
	var sim_vel = linear_velocity
	path.append(sim_pos)
	for i in range(100):
		var dist = sim_pos.distance_to(current_target_position)
		if dist < 0.5: break
		var speed = clamp(dist / braking_distance_factor, max_linear_speed / 10.0, max_linear_speed)
		var desired_vel = sim_pos.direction_to(current_target_position) * speed
		var steering    = desired_vel - sim_vel
		if steering.length() > max_thrust_force / mass:
			steering = steering.normalized() * max_thrust_force / mass
		sim_vel += steering * 0.1
		sim_pos += sim_vel * 0.1
		if i % 2 == 0: path.append(sim_pos)
	path.append(current_target_position)
	return path

func draw_waypoints_path() -> void:
	var m = waypoints_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if current_target_position == Vector3.ZERO and ship_movement_waypoints.is_empty(): return
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	m.surface_add_vertex(global_position + Vector3(0, 0.5, 0))
	if current_state == PlayerState.MOVE:
		m.surface_add_vertex(current_target_position + Vector3(0, 0.5, 0))
	for wp in ship_movement_waypoints:
		m.surface_add_vertex(wp.position + Vector3(0, 0.5, 0))
	m.surface_end()
