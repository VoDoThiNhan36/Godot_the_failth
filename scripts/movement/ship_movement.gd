extends RigidBody3D         # Mới: RigidBody3D để dùng full physics

@export_group("Steering Behavior")
# 2. max_linear_speed: tốc độ tối đa (m/s), clamp thủ công vì RigidBody3D không tự gi��i hạn
@export var max_linear_speed := 15.0
# 3. max_thrust_force: lực đẩy tối đa (Newton) — F = m * a, tăng để tàu nặng vẫn đủ lực
@export var max_thrust_force := 150.0
# 4. max_brake_force: lực phanh tối đa (Newton)
@export var max_brake_force := 80.0
# 5. braking_distance_factor: hệ số tính khoảng cách bắt đầu giảm tốc
@export var braking_distance_factor := 0.5
# 6. distance_threshold: ngưỡng khoảng cách coi như đã đến đích (mét)
@export var distance_threshold := 0.2
# 7. lateral_friction_force: lực triệt tiêu vận tốc ngang (Newton), chống bay vòng tròn
@export var lateral_friction_force := 80.0
# 8. auto_throttle: hệ số ga hiện tại (0.0 → 1.0), expose để debug trên Inspector
@export var auto_throttle := 0.0

@export_group("Rotation Physics")
# 9. max_torque: lực xoay tối đa (N·m) — thay angular_acceleration, đúng đơn vị RigidBody3D
@export var max_torque := 120.0
# 10. torque_brake_multiplier: hệ số nhân torque khi cần phanh xoay / đảo chiều
@export var torque_brake_multiplier := 3.0
# 11. max_turn_speed: tốc độ xoay tối đa (rad/s), clamp angular_velocity
@export var max_turn_speed := 2.0
# 12. turn_sensitivity: độ nhạy bẻ lái, nhân với góc lệch để ra desired turn speed
@export var turn_sensitivity := 3.0
# 13. roll_correction_torque: lực kéo roll về 0 (N·m)
@export var roll_correction_torque := 60.0
# 14. max_pitch_angle: góc pitch tối đa cho phép (độ), ±45 theo yêu cầu
@export var max_pitch_angle := 45.0
# 15. pitch_correction_torque: lực kéo pitch về trong giới hạn (N·m)
@export var pitch_correction_torque := 60.0
# 16. angular_damp_value: damping xoay — export để tune, set vào RigidBody3D.angular_damp trong _ready()
@export var angular_damp_value := 2.5
# 17. linear_damp_value: damping tịnh tiến — export để tune, set vào RigidBody3D.linear_damp trong _ready()
@export var linear_damp_value := 0.5

@export_group("Fajen Dynamical Steering")
@export var fajen_detection_radius := 35.0
@export var fajen_max_obstacles := 15
@export var fajen_kg := 12.0
@export var fajen_ko := 200.0
@export var fajen_b := 4.2
@export var fajen_c4 := 0.2
@export var fajen_noise := 0.2

# 18. nearby_obstacles: danh sách obstacle trong vùng detect của Fajen
var nearby_obstacles: Array[Node3D] = []

# 19. fajen_angular_velocity: momentum xoay riêng của Fajen (Vector2: x=pitch, y=yaw)
var fajen_angular_velocity := Vector2.ZERO

# State machine
enum PlayerState { IDLE, MOVE }
enum ShipSteeringMode { CONTEXT, FAJEN_WARREN }

# 20. current_state: state hiện tại của ship
var current_state: PlayerState = PlayerState.IDLE

# 21. current_steering_mode: thuật toán steering đang dùng
@export var current_steering_mode = ShipSteeringMode.FAJEN_WARREN

#  MOVEMENT VARIABLES
# 22. current_target_position: vị trí đích hiện tại cần bay tới
var current_target_position := Vector3.ZERO
# 23. current_target_direction: hướng ban đầu khi click waypoint (để blend khi đến gần)
var current_target_direction := Vector3.RIGHT
# 24. current_target_height_offset: độ cao offset thêm vào waypoint (scroll wheel)
var current_target_height_offset := 0.0
# 25. ship_movement_waypoints: hàng đợi các waypoint cần đi qua
var ship_movement_waypoints: Array[Movement_Waypoint] = []
# 26. current_waypoint: waypoint hiện tại đang bay tới
var current_waypoint: Movement_Waypoint = null
# 27. is_at_current_waypoint_threshold: flag đã vào vùng ngưỡng waypoint
var is_at_current_waypoint_threshold := false
# 28. ship_length: độ dài tàu (tính từ AABB), dùng để scale switching distance
var ship_length: float

#  NODE REFS
# 29. Lý do đổi type: node gốc đã đổi sang RigidBody3D
# @onready var ship_part: CharacterBody3D = $"."  # Cũ: CharacterBody3D
@onready var ship_part: RigidBody3D = $"."         # Mới: RigidBody3D
# 30. rich_text_label: UI hiển thị debug info
@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"

#  DEBUG MESH
@export_group("Mesh Debug")
var debug_vector_mesh := MeshInstance3D.new()
var trajectory_mesh   := MeshInstance3D.new()
var waypoints_mesh    := MeshInstance3D.new()
@export var show_debug := false

# ─────────────────────────────────────────────────────────────────
#  DEFAULT FUNCTIONS
# ─────────────────────────────────────────────────────────────────
func _init() -> void:
	pass

func _ready() -> void:
	# 1. Tính độ dài ship từ AABB của mesh con đầu tiên
	var ship = ship_part.get_child(0) as Node3D
	var mesh = ship.get_child(0) as MeshInstance3D
	ship_length = mesh.get_aabb().size.x  # Ship nằm hướng X mặc định

	# 2. Cài đặt RigidBody3D physics properties
	gravity_scale = 0.0                     # Tắt gravity: tàu vũ trụ không bị kéo xuống
	lock_rotation = false                   # Cho phép xoay tự do, kiểm soát bằng torque
	linear_damp  = linear_damp_value        # Gán damping tịnh tiến từ export var
	angular_damp = angular_damp_value       # Gán damping xoay từ export var

	# 3. Setup Fajen avoidance area
	setup_fajen_area()

	# 4. Setup debug meshes
	_setup_debug_mesh(
		debug_vector_mesh,   # mesh ref
		Color.WHITE,         # màu placeholder (màu thật set trong draw)
		true                 # vertex_color_use_as_albedo để vẽ nhiều màu
	)
	_setup_debug_mesh(trajectory_mesh, Color.GREEN, false)
	_setup_debug_mesh(waypoints_mesh,  Color.PLUM,  false)

# Hàm khởi tạo 1 debug mesh với material
## mesh_ref: MeshInstance3D cần setup
## color: màu albedo mặc định
## use_vertex_color: bật vertex color hay không (dùng khi vẽ nhiều màu trên 1 mesh)
func _setup_debug_mesh(mesh_ref: MeshInstance3D, color: Color, use_vertex_color: bool) -> void:
	# 1. Tách khỏi hệ trục của tàu để vẽ ở tọa độ Global
	mesh_ref.top_level = true
	mesh_ref.mesh = ImmediateMesh.new()

	# 2. Tạo material
	var mat = StandardMaterial3D.new()
	mat.albedo_color               = color
	mat.vertex_color_use_as_albedo = use_vertex_color
	mat.flags_unshaded             = true   # Sáng bất chấp bóng tối
	mat.no_depth_test              = true   # Nhìn xuyên tường/thân tàu
	mesh_ref.material_override     = mat

	# 3. Add vào scene
	add_child(mesh_ref)

func _physics_process(delta: float) -> void:
	# 1. Chạy state machine
	match current_state:
		PlayerState.IDLE: handle_state_idle(delta)
		PlayerState.MOVE: handle_state_move(delta)

	# 2. Luôn tự cân bằng roll và giới hạn pitch mọi frame
	#    (kể cả IDLE, vì RigidBody3D có thể xoay tự do khi va chạm)
	apply_roll_correction()
	apply_pitch_clamp()

	# 3. Clamp tốc độ tịnh tiến tối đa
	#    RigidBody3D không tự giới hạn speed như CharacterBody3D
	if linear_velocity.length() > max_linear_speed:
		linear_velocity = linear_velocity.normalized() * max_linear_speed

	# 4. Clamp tốc độ xoay tối đa
	if angular_velocity.length() > max_turn_speed:
		angular_velocity = angular_velocity.normalized() * max_turn_speed

	# 5. Vẽ debug waypoints path
	draw_waypoints_path()

	# 6. Cập nhật debug UI
	rich_text_label.text = \
		"\nShip length: "              + str(ship_length)                      + \
		"\nAngular velocity: "         + str(snappedf(angular_velocity.length(), 0.01)) + \
		"\nThrottle: "                 + str(snappedf(auto_throttle, 0.01))    + \
		"\nVelocity: "                 + str(snappedf(linear_velocity.length(), 0.01))  + \
		"\nCurrent target position: "  + str(current_target_position)          + \
		"\nCurrent target direction: " + str(current_target_direction)         + \
		"\nHeight offset: "            + str(current_target_height_offset)     + \
		"\nAt threshold: "             + str(is_at_current_waypoint_threshold) + \
		"\nForward dir: "              + str(-global_transform.basis.z)        + \
		"\nObstacles: "                + str(nearby_obstacles.size())          + \
		"\nWaypoints: "                + str(ship_movement_waypoints.size())

func _unhandled_input(event: InputEvent) -> void:
	# Scroll wheel thay đổi độ cao waypoint
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset = 2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -2.0
			# Giới hạn trần/đáy bay
			current_target_height_offset = clamp(current_target_height_offset + offset, -45.0, 45.0)

			if Input.is_action_pressed("sequence_move"):
				# Trường hợp 1: chỉnh độ cao waypoint cuối trong hàng đợi
				if not ship_movement_waypoints.is_empty():
					_adjust_last_waypoint_height(offset)
				# Trường hợp 2: chỉnh độ cao target hiện tại khi đang MOVE
				elif current_state == PlayerState.MOVE:
					_adjust_current_target_height(offset)

# Hàm chỉnh độ cao waypoint cuối trong hàng đợi
## offset: delta độ cao cần thêm (dương = lên, âm = xuống)
func _adjust_last_waypoint_height(offset: float) -> void:
	var last_waypoint = ship_movement_waypoints.back()

	# Lấy vị trí trước waypoint cuối để tính giới hạn góc 45°
	var prev_position: Vector3
	if ship_movement_waypoints.size() > 1:
		prev_position = ship_movement_waypoints[ship_movement_waypoints.size() - 2].position
	else:
		prev_position = current_target_position if current_state == PlayerState.MOVE else global_position

	# Giới hạn độ cao theo góc 45° (dist_xz = cạnh ngang → max delta Y = dist_xz)
	var dist_xz = Vector2(last_waypoint.position.x, last_waypoint.position.z) \
		.distance_to(Vector2(prev_position.x, prev_position.z))

	# Cập nhật Y với giới hạn clamp
	last_waypoint.position.y = clamp(
		last_waypoint.position.y + offset,
		prev_position.y - dist_xz,
		prev_position.y + dist_xz
	)
	if is_instance_valid(last_waypoint.point_marker):
		last_waypoint.point_marker.global_position.y = last_waypoint.position.y

# Hàm chỉnh độ cao target hiện tại đang bay tới
## offset: delta độ cao cần thêm
func _adjust_current_target_height(offset: float) -> void:
	var dist_xz = Vector2(current_target_position.x, current_target_position.z) \
		.distance_to(Vector2(global_position.x, global_position.z))

	# Cập nhật Y với giới hạn clamp
	current_target_position.y = clamp(
		current_target_position.y + offset,
		global_position.y - dist_xz,
		global_position.y + dist_xz
	)
	if current_waypoint and is_instance_valid(current_waypoint.point_marker):
		current_waypoint.position.y                     = current_target_position.y
		current_waypoint.point_marker.global_position.y = current_target_position.y

# ─────────────────────────────────────────────────────────────────
#  STATE MACHINE FUNCTIONS
# ─────────────────────────────────────────────────────────────────

# Hàm xử lý state IDLE: phanh tịnh tiến + cân bằng tàu
## delta: physics delta time
func handle_state_idle(delta: float) -> void:
	# 1. Phanh tịnh tiến: apply lực ngược chiều velocity
	#    F_brake = -direction * min(max_brake, |v| * m / delta)
	#    Chia delta để ra force thật từ impulse cần thiết
	var speed         = linear_velocity.length()
	var brake_force   = min(max_brake_force, speed * mass / delta)
	if speed > 0.001:
		apply_central_force(-linear_velocity.normalized() * brake_force)

	# 2. Cân bằng tàu về mặt phẳng ngang khi IDLE
	auto_stable_ship_idle_state(delta)

# Hàm xử lý state MOVE: steering + arrive + lateral dampening
## delta: physics delta time
func handle_state_move(delta: float) -> void:
	# ── Vị trí và khoảng cách ──
	var current_position = global_position
	var target_position  = current_target_position
	var distance         = current_position.distance_to(target_position)

	# Tính stopping distance: s = v² / (2 * a) với a = F_brake / m
	var decel                = max_brake_force / mass
	var min_stopping_distance = pow(linear_velocity.length(), 2) / (2.0 * decel)

	# ── Hướng ──
	var ship_heading_vector = -global_transform.basis.z   # Mũi tàu hướng -Z
	var direction_to_target = current_position.direction_to(target_position)
	var raw_direction: Vector3      # Hướng thuần túy đến target
	var desired_direction: Vector3  # Hướng sau khi blend/steering
	var danger_throttle_factor := 1.0

	# ── Direction blending ──
	var rotation_blend_distance = distance_threshold * 2.0
	if distance > rotation_blend_distance:
		# Xa target: hướng thẳng về target
		is_at_current_waypoint_threshold = false
		raw_direction = direction_to_target
	elif distance > distance_threshold:
		# Vùng blend: nội suy giữa hướng click và hướng target
		if not is_at_current_waypoint_threshold:
			var blend_weight = clamp(
				(distance - distance_threshold) / rotation_blend_distance,
				0.8, 1.0
			)
			raw_direction = current_target_direction.slerp(direction_to_target, blend_weight).normalized()
		else:
			raw_direction = current_target_direction
	else:
		# Đã đến ngưỡng: giữ hướng ban đầu
		is_at_current_waypoint_threshold = true
		raw_direction = current_target_direction

	# ── Steering: Fajen khi xa, manual torque khi gần ──
	if distance > ship_length * 5.0:
		desired_direction = raw_direction
		danger_throttle_factor = _apply_fajen_steering(delta, ship_heading_vector, raw_direction)
	else:
		desired_direction = raw_direction
		_apply_manual_torque_steering(delta, ship_heading_vector, desired_direction, distance, min_stopping_distance)

	# ── Heading alignment: độ khớp mũi tàu với hướng cần đi ──
	var heading_alignment = ship_heading_vector.dot(desired_direction)

	# ── Waypoint switching ──
	var waypoint_switch_distance = distance_threshold / 2.0
	if not ship_movement_waypoints.is_empty():
		# Cắt góc sớm hơn khi còn waypoint phía sau
		waypoint_switch_distance = max_linear_speed * 0.5
	if distance < waypoint_switch_distance:
		if not ship_movement_waypoints.is_empty():
			load_next_waypoint()
		else:
			# Phanh mạnh khi về đích cuối
			var speed = linear_velocity.length()
			var brake_force = min(max_brake_force, speed * mass / delta)
			if speed > 0.001:
				apply_central_force(-linear_velocity.normalized() * brake_force)
			
			# Thêm damping cho angular force
			apply_torque(-angular_velocity * angular_damp_value * mass)
			
			if linear_velocity.length() < 0.1 and heading_alignment >= 0.999: sdadasd
				auto_throttle = 0.0

	# ── ARRIVE behavior ──
	_apply_arrive_force(delta, distance, min_stopping_distance, ship_heading_vector, heading_alignment, danger_throttle_factor)

	# ── Lateral dampening: triệt tiêu vận tốc ngang ──
	_apply_lateral_dampening(delta, ship_heading_vector, distance)

	# ── Debug visual ──
	var forward_speed    = linear_velocity.dot(ship_heading_vector)
	var forward_velocity = ship_heading_vector * forward_speed
	var lateral_velocity = linear_velocity - forward_velocity
	draw_debug_vectors(desired_direction, forward_velocity, lateral_velocity)
	draw_trajectory_line(calculate_predicted_path())

# Hàm apply Fajen steering, trả về danger_throttle_factor
## delta: physics delta time
## ship_heading_vector: hướng mũi tàu hiện tại
## raw_direction: hướng thẳng đến target
func _apply_fajen_steering(delta: float, ship_heading_vector: Vector3, raw_direction: Vector3) -> float:
	var fajen_result    = compute_fajen_angular_acceleration(ship_heading_vector, raw_direction, fajen_angular_velocity)
	var raw_fajen_accel: Vector2 = fajen_result["angular_accel"]
	var total_repulsion: float   = fajen_result["repulsion_force"]

	# 1. Clamp gia tốc Fajen theo max_torque / mass → max angular acceleration
	var max_ang_accel      = max_torque / mass
	var applied_accel_pitch = clamp(raw_fajen_accel.x, -max_ang_accel, max_ang_accel)
	var applied_accel_yaw   = clamp(raw_fajen_accel.y, -max_ang_accel, max_ang_accel)

	# 2. Cập nhật Fajen momentum (Vector2)
	fajen_angular_velocity.x += applied_accel_pitch * delta
	fajen_angular_velocity.y += applied_accel_yaw   * delta
	# Damping Fajen momentum dùng angular_damp_value (export)
	fajen_angular_velocity    = fajen_angular_velocity.lerp(Vector2.ZERO, angular_damp_value * delta)
	# Clamp Fajen momentum theo max_turn_speed
	if fajen_angular_velocity.length() > max_turn_speed:
		fajen_angular_velocity = fajen_angular_velocity.normalized() * max_turn_speed

	# 3. Convert Fajen Vector2 momentum sang torque Vector3 và apply
	#    Yaw  (fajen y) → xoay quanh trục Y global
	#    Pitch (fajen x) → xoay quanh trục X local của tàu
	var yaw_torque   = Vector3.UP                    * fajen_angular_velocity.y * max_torque
	var pitch_torque = global_transform.basis.x      * fajen_angular_velocity.x * max_torque
	apply_torque(yaw_torque + pitch_torque)

	# 4. Tính danger_throttle_factor từ repulsion
	if total_repulsion > 5.0:
		return clamp(1.0 - (total_repulsion / 50.0), 0.1, 1.0)
	return 1.0

# Hàm apply manual torque steering khi gần target
## delta: physics delta time
## heading_vector: hướng mũi tàu hiện tại
## desired_direction: hướng cần xoay đến
## distant_to_target: khoảng cách đến target
## min_stopping_distance: quãng đường phanh tối thiểu
func _apply_manual_torque_steering(delta: float, heading_vector: Vector3, desired_direction: Vector3, distant_to_target: float, min_stopping_distance: float) -> void:
	if heading_vector.is_equal_approx(desired_direction): return

	# 1. Tính trục xoay và góc lệch
	var cross = heading_vector.cross(desired_direction)
	if cross.length_squared() < 0.0001: return
	var axis       = cross.normalized()             # Trục vuông góc cần xoay quanh
	var angle_diff = heading_vector.angle_to(desired_direction)  # Góc lệch (radian)

	# 2. Tính desired angular speed: tỉ lệ với góc lệch, giới hạn max_turn_speed
	var desired_ang_speed = clamp(angle_diff * turn_sensitivity, 0.0, max_turn_speed)

	# 3. Lấy angular speed hiện tại theo đúng trục cần xoay
	#    Dùng dot product với angular_velocity Vector3 của RigidBody3D
	var current_ang_speed = angular_velocity.dot(axis)

	# 4. Tính speed difference (steering torque concept)
	var speed_diff = desired_ang_speed - current_ang_speed

	# 5. Chọn torque power: tăng tốc hay phanh/đảo chiều
	var is_accelerating = sign(speed_diff) == sign(current_ang_speed) or abs(current_ang_speed) < 0.01
	var torque_power    = max_torque if is_accelerating else max_torque * torque_brake_multiplier

	# 6. Apply torque theo trục xoay
	#    F_torque = axis * speed_diff * torque_power
	#    Không nhân delta vì apply_torque đã được engine tích phân theo timestep
	apply_torque(axis * speed_diff * torque_power)

	# 7. Level out khi gần đích cuối: kéo tàu về nằm ngang
	if ship_movement_waypoints.is_empty():
		if distant_to_target <= min_stopping_distance or distant_to_target < max_linear_speed:
			var flat_desired = Vector3(desired_direction.x, 0.0, desired_direction.z)
			if flat_desired.length_squared() > 0.001:
				var level_cross = heading_vector.cross(flat_desired.normalized())
				if level_cross.length_squared() > 0.0001:
					# Blend: càng gần đích càng kéo mạnh về nằm ngang
					var blend = clamp(1.0 - (distant_to_target / max_linear_speed), 0.0, 1.0)
					apply_torque(level_cross.normalized() * blend * max_torque * 0.5)

# Hàm apply arrive force: tăng tốc hoặc phanh theo khoảng cách
## delta: physics delta time
## distance: khoảng cách đến target
## min_stopping_distance: quãng đường phanh tối thiểu
## ship_heading_vector: hướng mũi tàu
## heading_alignment: dot product mũi tàu và hướng target (-1 → 1)
## danger_throttle_factor: hệ số giảm ga khi có obstacle (từ Fajen)
func _apply_arrive_force(delta: float, distance: float, min_stopping_distance: float, ship_heading_vector: Vector3, heading_alignment: float, danger_throttle_factor: float) -> void:
	var is_final_waypoint = ship_movement_waypoints.is_empty()

	if distance > min_stopping_distance:
		# ── Tính target speed ──
		var target_speed: float
		if not is_final_waypoint:
			# Waypoint giữa chừng: giữ tốc độ cao để cắt góc mượt
			target_speed = min(distance / (braking_distance_factor * 0.5), max_linear_speed)
		else:
			# Đích cuối: giảm tốc theo khoảng cách
			target_speed = clamp(distance / braking_distance_factor, 0.05, max_linear_speed)

		# ── Tính auto throttle ──
		auto_throttle  = pow(clamp(heading_alignment, 0.0, 1.0), 3)  # Mũi lệch → giảm ga
		auto_throttle *= danger_throttle_factor                        # Obstacle → giảm ga

		if heading_alignment > 0.0:
			# Desired velocity: mũi tàu * target speed * throttle
			var desired_velocity = ship_heading_vector * (target_speed * auto_throttle)

			# Steering force = delta_v / delta * mass → đúng đơn vị Newton
			# delta_v = desired - current (m/s), chia delta → m/s², nhân mass → Newton
			var delta_v        = desired_velocity - linear_velocity
			var steering_force = (delta_v / delta) * mass

			# Clamp theo max_thrust_force
			if steering_force.length() > max_thrust_force:
				steering_force = steering_force.normalized() * max_thrust_force

			apply_central_force(steering_force)
		else:
			# Mũi ngược hướng: phanh lại
			var speed       = linear_velocity.length()
			var brake_force = min(max_brake_force, speed * mass / delta)
			if speed > 0.001:
				apply_central_force(-linear_velocity.normalized() * brake_force)
	else:
		# Trong stopping distance: phanh
		var speed         = linear_velocity.length()
		var brake_mul     = 1.0 if is_final_waypoint else 0.5
		var brake_force   = min(max_brake_force * brake_mul, speed * mass / delta)
		if speed > 0.001:
			apply_central_force(-linear_velocity.normalized() * brake_force)

# Hàm triệt tiêu vận tốc ngang (chống bay vòng tròn)
## delta: physics delta time
## ship_heading_vector: hướng mũi tàu
## distance: khoảng cách đến target (dùng để tăng friction khi gần đích)
func _apply_lateral_dampening(delta: float, ship_heading_vector: Vector3, distance: float) -> void:
	# 1. Tách vận tốc tiến và vận tốc ngang
	var forward_speed    = linear_velocity.dot(ship_heading_vector)
	var forward_velocity = ship_heading_vector * forward_speed
	var lateral_velocity = linear_velocity - forward_velocity

	# 2. Tăng friction khi gần đích để tàu dừng gọn
	var effective_friction = lateral_friction_force
	if distance < distance_threshold / 2.0:
		effective_friction *= 2.0

	# 3. Lateral force: F = -lateral_v / delta * mass → Newton chính xác
	#    Chia delta vì lateral_velocity là m/s, cần ra m/s² rồi nhân mass
	var lateral_force = (-lateral_velocity / delta) * mass
	# Clamp để không vượt quá effective_friction
	if lateral_force.length() > effective_friction:
		lateral_force = lateral_force.normalized() * effective_friction

	apply_central_force(lateral_force)

# ─────────────────────────────────────────────────────────────────
#  ROLL & PITCH CORRECTION
# ─────────────────────────────────────────────────────────────────

# Hàm tự cân bằng roll về 0 mọi frame
func apply_roll_correction() -> void:
	# 1. ship_up: hướng lên của tàu (trục Y local)
	var ship_up   = global_transform.basis.y
	# 2. roll_error: vector lệch giữa ship_up và world UP
	var roll_error = ship_up.cross(Vector3.UP)
	# 3. roll_axis: trục Z local (trục roll)
	var roll_axis  = global_transform.basis.z
	# 4. Chiếu roll_error lên roll_axis → chỉ lấy thành phần roll thuần túy
	var roll_scalar = roll_error.dot(roll_axis)
	# 5. Apply torque kéo roll về 0 (nhân mass để scale đúng với trọng lượng tàu)
	apply_torque(roll_axis * roll_scalar * roll_correction_torque)
	# 6. Damping angular velocity theo trục Z riêng để tắt lắc lư roll
	apply_torque(-angular_velocity.project(roll_axis) * angular_damp_value * mass)

# Hàm giới hạn góc pitch tối đa mọi frame
func apply_pitch_clamp() -> void:
	# 1. Tính pitch hiện tại: y-component của forward vector (-Z)
	var pitch         = asin(clamp(-global_transform.basis.z.y, -1.0, 1.0))
	var max_pitch_rad = deg_to_rad(max_pitch_angle)
	# 2. Nếu vượt giới hạn → apply torque kéo về
	if abs(pitch) > max_pitch_rad:
		var pitch_error  = pitch - sign(pitch) * max_pitch_rad  # Độ lệch so với giới hạn
		# Apply torque quanh trục X local ngược chiều pitch error
		apply_torque(-global_transform.basis.x * pitch_error * pitch_correction_torque)

# ─────────────────────────────────────────────────────────────────
#  AUTO STABLE (IDLE)
# ─────────────────────────────────────────────────────────────────

# Hàm kéo tàu về nằm ngang khi IDLE
## delta: physics delta time
func auto_stable_ship_idle_state(delta: float) -> void:
	var current_forward = -global_transform.basis.z
	var flat_forward    = Vector3(current_forward.x, 0.0, current_forward.z)
	if flat_forward.length_squared() < 0.001: return

	flat_forward = flat_forward.normalized()

	# 1. Tính pitch error: y-component của forward = sin(pitch)
	var pitch_error = current_forward.y
	# 2. Apply torque ngược chiều pitch để kéo về y = 0
	apply_torque(-global_transform.basis.x * pitch_error * pitch_correction_torque * 2.0)
	# 3. Damping angular velocity mạnh hơn khi IDLE để dừng lại nhanh
	apply_torque(-angular_velocity * angular_damp_value * mass * 2.0)

# ─────────────────────────────────────────────────────────────────
#  FAJEN STEERING
# ─────────────────────────────────────────────────────────────────

# Hàm setup Area3D để detect obstacle cho Fajen
func setup_fajen_area() -> void:
	var avoidance_area = Area3D.new()
	avoidance_area.name = "FajenAvoidanceArea"
	add_child(avoidance_area)

	var col_shape  = CollisionShape3D.new()
	var sphere     = SphereShape3D.new()
	sphere.radius  = fajen_detection_radius
	col_shape.shape = sphere
	avoidance_area.add_child(col_shape)

	avoidance_area.collision_mask = 1
	avoidance_area.body_entered.connect(_on_fajen_body_entered)
	avoidance_area.body_exited.connect(_on_fajen_body_exited)

func _on_fajen_body_entered(body: Node3D) -> void:
	if body != self and not nearby_obstacles.has(body):
		nearby_obstacles.append(body)

func _on_fajen_body_exited(body: Node3D) -> void:
	nearby_obstacles.erase(body)

# Hàm tính Fajen & Warren angular acceleration
## Công thức: phi_ddot = -b*phi_dot - kg*(phi-psi_g)*(exp(-c1*dg)+c2) + sum(ko*(phi-psi_o)*exp(-c3*|phi-psi_o|)*exp(-c4*do))
## ship_heading_vector: hướng mũi tàu (Vector3 normalized)
## target_direction: hướng đến target (Vector3 normalized)
## current_angular_velocity: momentum Fajen hiện tại (Vector2: x=pitch, y=yaw)
func compute_fajen_angular_acceleration(
		ship_heading_vector: Vector3,
		target_direction: Vector3,
		current_angular_velocity: Vector2) -> Dictionary:

	var space_state = get_world_3d().direct_space_state

	# Tính góc Yaw và Pitch hiện tại của tàu (trong ship space)
	var current_phi_yaw   = atan2(ship_heading_vector.x, ship_heading_vector.z)
	var current_phi_pitch = atan2(ship_heading_vector.y,
		sqrt(ship_heading_vector.x*ship_heading_vector.x + ship_heading_vector.z*ship_heading_vector.z))

	# Tính góc Yaw và Pitch của target
	var goal_phi_yaw   = atan2(target_direction.x, target_direction.z)
	var goal_phi_pitch = atan2(target_direction.y,
		sqrt(target_direction.x*target_direction.x + target_direction.z*target_direction.z))

	# Khoảng cách tới target (min 0.5 để tránh chia 0)
	var distance_to_goal = max(0.5, global_position.distance_to(current_target_position))

	# Damping: -b * phi_dot
	var phi_ddot_yaw   = -fajen_b * current_angular_velocity.y
	var phi_ddot_pitch = -fajen_b * current_angular_velocity.x

	# Goal error: góc lệch nhỏ nhất về target
	var goal_error_yaw   = fposmod((current_phi_yaw   - goal_phi_yaw)   + PI, TAU) - PI
	var goal_error_pitch = fposmod((current_phi_pitch - goal_phi_pitch) + PI, TAU) - PI

	# Goal attraction: kg * error * (exp(-0.4*d) + 0.4)
	phi_ddot_yaw   -= fajen_kg * goal_error_yaw   * (exp(-0.4 * distance_to_goal) + 0.4)
	phi_ddot_pitch -= fajen_kg * goal_error_pitch * (exp(-0.4 * distance_to_goal) + 0.4)

	var total_repulsion := 0.0
	var count           := 0

	for obstacle in nearby_obstacles:
		if count >= fajen_max_obstacles: break

		var obs_position = obstacle.global_position
		var query        = PhysicsRayQueryParameters3D.create(global_position, obs_position)
		query.exclude    = [self.get_rid()]
		var result       = space_state.intersect_ray(query)

		var hit_position = obs_position
		var obs_radius   = 1.0
		if result:
			hit_position = result.position
			obs_radius   = max(1.0, hit_position.distance_to(obs_position))

		var distance_to_obstacle = global_position.distance_to(hit_position)
		if distance_to_obstacle > fajen_detection_radius or distance_to_obstacle < 0.1: continue

		var direction_to_obs = (hit_position - global_position).normalized()
		if ship_heading_vector.dot(direction_to_obs) < -0.25: continue

		var obs_phi_yaw   = atan2(direction_to_obs.x, direction_to_obs.z)
		var obs_phi_pitch = atan2(direction_to_obs.y,
			sqrt(direction_to_obs.x*direction_to_obs.x + direction_to_obs.z*direction_to_obs.z))

		var obs_error_yaw   = fposmod((current_phi_yaw   - obs_phi_yaw)   + PI, TAU) - PI
		var obs_error_pitch = fposmod((current_phi_pitch - obs_phi_pitch) + PI, TAU) - PI

		var dynamic_ko    = fajen_ko * (1.0 + sqrt(obs_radius))
		var obs_term_yaw  = dynamic_ko * obs_error_yaw   * exp(-6.0 * abs(obs_error_yaw))   * exp(-fajen_c4 * distance_to_obstacle)
		var obs_term_pitch = dynamic_ko * obs_error_pitch * exp(-6.0 * abs(obs_error_pitch)) * exp(-fajen_c4 * distance_to_obstacle)

		phi_ddot_yaw   += obs_term_yaw
		phi_ddot_pitch += obs_term_pitch
		total_repulsion += Vector2(obs_term_yaw, obs_term_pitch).length()
		count += 1

	# Noise chống deadlock khi nhiều obstacle
	if count > 0 and current_angular_velocity.length() < 0.1 \
			and Vector2(phi_ddot_pitch, phi_ddot_yaw).length() < 0.1:
		phi_ddot_yaw   += randf_range(-fajen_noise, fajen_noise)
		phi_ddot_pitch += randf_range(-fajen_noise, fajen_noise)

	return {
		"angular_accel":   Vector2(phi_ddot_pitch, phi_ddot_yaw),  # x=pitch, y=yaw
		"repulsion_force": total_repulsion
	}

# ─────────────────────────────────────────────────────────────────
#  WAYPOINT SYSTEM
# ─────────────────────────────────────────────────────────────────

# Hàm thêm waypoint mới và bắt đầu di chuyển
## new_position: vị trí đích mới (world space)
## is_sequence: true = nối vào hàng đợi, false = clear hàng đợi và di chuyển ngay
func move_to(new_position: Vector3, is_sequence: bool = false) -> void:
	if not is_sequence:
		clear_all_waypoints()

	# Cộng thêm độ cao offset từ scroll wheel
	new_position.y += current_target_height_offset

	# Xác định previous_position để tính direction cho waypoint mới
	var previous_position: Vector3
	if current_state == PlayerState.MOVE:
		previous_position = ship_movement_waypoints.back().position \
			if not ship_movement_waypoints.is_empty() \
			else current_target_position
	else:
		previous_position = global_position

	# Tạo waypoint mới và thêm vào hàng đợi
	var new_waypoint = Movement_Waypoint.new(new_position, previous_position)
	add_child(new_waypoint.point_marker)
	ship_movement_waypoints.append(new_waypoint)

	# Load waypoint ngay nếu chưa đang MOVE hoặc không phải sequence
	if current_state != PlayerState.MOVE or not is_sequence:
		load_next_waypoint()

	change_state(PlayerState.MOVE)

# Hàm xóa tất cả waypoint
func clear_all_waypoints() -> void:
	for wp in ship_movement_waypoints:
		if is_instance_valid(wp.point_marker): wp.point_marker.queue_free()
	ship_movement_waypoints.clear()

	if current_waypoint and is_instance_valid(current_waypoint.point_marker):
		current_waypoint.point_marker.queue_free()
	current_waypoint = null

# Hàm load waypoint tiếp theo từ hàng đợi
func load_next_waypoint() -> void:
	if ship_movement_waypoints.is_empty(): return

	# Xóa marker waypoint hiện tại
	if current_waypoint: current_waypoint.point_marker.queue_free()

	# Lấy waypoint đầu hàng đợi
	current_waypoint         = ship_movement_waypoints.pop_front()
	current_target_position  = current_waypoint.position
	current_target_direction = current_waypoint.direction

	# Reset Fajen momentum để bẻ cua nhanh hơn khi chuyển waypoint
	fajen_angular_velocity *= 0.5

# Hàm đổi state
## new_state: state cần chuyển sang
func change_state(new_state: PlayerState) -> void:
	if current_state == new_state: return
	current_state = new_state
	print("State → ", current_state)

# ─────────────────────────────────────────────────────────────────
#  DEBUG VISUAL
# ─────────────────────────────────────────────────────────────────

# Hàm vẽ 3 tia debug: desired direction, forward velocity, lateral velocity
## desired_direction: hướng mong muốn (xanh lá)
## forward_velocity: vận tốc tiến (xanh dương)
## lateral_velocity: vận tốc ngang (đỏ)
func draw_debug_vectors(desired_direction: Vector3, forward_velocity: Vector3, lateral_velocity: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if current_state == PlayerState.IDLE: return

	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var origin = global_position + Vector3(0, 2.0, 0)

	# 1. Tia XANH LÁ: Hướng mong muốn
	m.surface_set_color(Color.GREEN);  m.surface_add_vertex(origin)
	m.surface_set_color(Color.GREEN);  m.surface_add_vertex(origin + desired_direction * 5.0)
	# 2. Tia XANH DƯƠNG: Vận tốc tiến
	m.surface_set_color(Color.BLUE);   m.surface_add_vertex(origin)
	m.surface_set_color(Color.BLUE);   m.surface_add_vertex(origin + forward_velocity * 2.0)
	# 3. Tia ĐỎ: Vận tốc ngang
	m.surface_set_color(Color.RED);    m.surface_add_vertex(origin)
	m.surface_set_color(Color.RED);    m.surface_add_vertex(origin + lateral_velocity * 2.0)

	m.surface_end()

# Hàm vẽ đường dự đoán trajectory
## points: mảng các điểm dự đoán
func draw_trajectory_line(points: PackedVector3Array) -> void:
	var m = trajectory_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if points.is_empty() or current_state == PlayerState.IDLE: return

	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		m.surface_add_vertex(Vector3(p.x, 1.0, p.z))
	m.surface_end()

# Hàm tính đường dự đoán trajectory (simulate arrival)
func calculate_predicted_path() -> PackedVector3Array:
	var path       := PackedVector3Array()
	var sim_pos    := global_position
	var sim_vel    := linear_velocity
	var target_pos := current_target_position
	var sim_step   := 0.1   # Delta giả: 0.1 giây mỗi bước
	var max_steps  := 100   # Tối đa 100 bước = 10 giây tương lai

	path.append(sim_pos)
	for i in range(max_steps):
		var dist = sim_pos.distance_to(target_pos)
		if dist < 0.5: break

		var speed          = clamp(dist / braking_distance_factor, max_linear_speed / 10.0, max_linear_speed)
		var desired_vel    = sim_pos.direction_to(target_pos) * speed
		var steering       = desired_vel - sim_vel
		if steering.length() > max_thrust_force / mass:
			steering = steering.normalized() * max_thrust_force / mass

		sim_vel += steering * sim_step
		sim_pos += sim_vel * sim_step
		if i % 2 == 0: path.append(sim_pos)

	path.append(target_pos)
	return path

# Hàm vẽ đường nối các waypoints
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
