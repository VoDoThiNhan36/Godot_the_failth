# Lý do đổi: CharacterBody3D dùng move_and_slide() + set velocity trực tiếp,
# không tương thích với Builder ship (RigidBody3D) và không có physics thật (inertia, torque)
# extends CharacterBody3D  # Cũ
extends RigidBody3D         # Mới: dùng apply_central_force() + apply_torque() + linear_velocity

# ============================== STEERING BEHAVIOR ======================================

@export_group("Steering Behavior")
@export var max_linear_speed := 15.0           # Tốc độ tối đa (m/s)
@export var max_thrust_force := 10.0           # Lực đẩy tối đa động cơ chính (N)
@export var max_brake_force := 5.0             # Lực hãm phanh tối đa (N/kg → nhân mass thành N)
@export var braking_distance_factor := 0.5     # Hệ số khoảng cách bắt đầu hãm phanh
@export var distance_threshold := 0.2          # Khoảng cách bắt đầu giảm tốc và chuyển hướng
@export var lateral_friction := 5.0            # Lực bám ngang, càng cao chống trượt càng tốt
@export var auto_throttle := 0.0               # Gas tự động, thay đổi theo điều kiện
@export var linear_damp_value := 0.5           # Damping tịnh tiến — gán vào RigidBody3D.linear_damp
@export var idle_brake_multiplier := 2.0       # Nhân lực phanh khi IDLE để dừng nhanh hơn

# Lý do comment out: RigidBody3D đã có sẵn property mass tích hợp, không cần export riêng
# @export var mass := 10.0   # Cũ: CharacterBody3D không có mass, phải khai báo tay

# ============================== ROTATION PHYSICS ======================================

@export_group("Rotation Physics")
@export var pid_rot_p := 20.0       # Lực bẻ lái tỉ lệ thuận với độ lệch góc (Proportional)
@export var pid_rot_i := 0.0        # Bù sai số tích lũy (Integral - thường để 0 trong không gian)
@export var pid_rot_d := 10.0       # Lực hãm đà tỉ lệ với vận tốc góc (Derivative - Chống rung lắc)
var rot_error_integral := 0.0       # Biến lưu trữ sai số tích lũy cho I
@export var angular_acceleration := 8.0        # Sức mạnh động cơ xoay — nhân mass thành torque (N*m/kg)
#@export var angular_braking := 6.0             # Sức mạnh phanh xoay (N*m/kg)
@export var max_turn_speed := 1.0              # Tốc độ xoay tối đa (rad/s)
#@export var turn_sensitivity := 3.0            # Độ nhạy vô lăng — góc lệch × sensitivity = desired speed
@export var roll_correction_torque := 40.0     # Lực kéo roll về 0 (N*m/kg)
@export var max_pitch_angle := 45.0            # Góc pitch tối đa (độ)
@export var stabilization_speed := 2.0         # Tốc độ tự cân bằng khi IDLE
@export var angular_damp_value := 1.0          # Hệ số cản xoay thủ công — dùng trong apply_torque() của script, KHÔNG gán vào RigidBody3D.angular_damp (đã tắt = 0)

# Lý do comment out: RigidBody3D có sẵn angular_velocity dạng Vector3
# Biến float thủ công này không cần thiết nữa, engine tự track qua angular_velocity Vector3
# var angular_velocity := 0.0   # Cũ: float thủ công, conflict với RigidBody3D.angular_velocity (Vector3)

# Lý do comment out: angular_damping đã đổi tên sang angular_damp_value để rõ ràng hơn
# và tránh nhầm với RigidBody3D.angular_damp
# @export var angular_damping := 1.0   # Cũ: tên không rõ, dùng angular_damp_value thay thế

# ============================== FAJEN DYNAMICAL STEERING ======================================

@export_group("Fajen Dynamical Steering")
@export var fajen_detection_radius := 35.0
@export var fajen_max_obstacles := 15
@export var fajen_kg := 12.0
@export var fajen_ko := 200.0
@export var fajen_b := 4.2
@export var fajen_c4 := 0.2
@export var fajen_noise := 0.2
var nearby_obstacles: Array[Node3D] = []       # Danh sách obstacle trong vùng detect
# fajen_angular_velocity GIỮ NGUYÊN vì Fajen tính pitch/yaw riêng trong ship-space
# Không thể thay bằng angular_velocity Vector3 của RigidBody3D (world-space, 3 trục)
var fajen_angular_velocity := Vector2.ZERO     # Momentum xoay của Fajen: x = pitch, y = yaw

# ============================== TRẠNG THÁI ======================================

enum PlayerState { IDLE, MOVE }
enum ShipSteeringMode { CONTEXT, FAJEN_WARREN }
var current_state: PlayerState = PlayerState.IDLE
@export var current_steering_mode = ShipSteeringMode.FAJEN_WARREN  # Thuật toán steering mặc định

# ============================== BIẾN MOVEMENT ======================================

var current_target_position := Vector3.ZERO         # Vị trí target hiện tại
var current_target_direction := Vector3.RIGHT        # Hướng từ ship đến target
var current_target_height_offset := 0.0              # Offset độ cao từ scroll wheel
var ship_movement_waypoints: Array[Movement_Waypoint] = []  # Hàng đợi waypoint
var current_waypoint: Movement_Waypoint = null       # Waypoint đang bay tới
var is_at_current_waypoint_threshold := false        # Flag đã vào vùng ngưỡng đích
var ship_length: float                               # Độ dài tàu (tính từ AABB mesh)

# ============================== NODE REFS ======================================

# Lý do đổi type: node gốc đã đổi từ CharacterBody3D sang RigidBody3D
# @onready var ship_part: CharacterBody3D = $"."   # Cũ
@onready var ship_part: RigidBody3D = $"."          # Mới: khớp type với node gốc
@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"
@onready var rich_text_label_2: RichTextLabel = $"../RichTextLabel2"

# ============================== DEBUG MESH ======================================

@export_group("Mesh Debug")
var debug_vector_mesh := MeshInstance3D.new()
var trajectory_mesh := MeshInstance3D.new()
var waypoints_mesh := MeshInstance3D.new()
@export var show_debug := false

# =============================== DEFAULT FUNCTIONS ==============================

func _init() -> void:
	pass

# Hàm khởi tạo — setup RigidBody3D settings + Fajen area + debug meshes
func _ready() -> void:
	# 1. Tính độ dài ship từ AABB của mesh con đầu tiên
	var ship = ship_part.get_child(0) as Node3D          # Node3D chứa mesh
	var mesh = ship.get_child(0) as MeshInstance3D       # MeshInstance3D để lấy AABB
	ship_length = mesh.get_aabb().size.x                 # Ship nằm hướng X, đã xoay -90 sang -Z

	# 2. Cài đặt RigidBody3D (thêm mới khi đổi từ CharacterBody3D)
	gravity_scale = 0.0                  # Tắt gravity: tàu vũ trụ không rơi
	lock_rotation = false                # Cho phép xoay tự do, cân bằng bằng torque
	linear_damp = linear_damp_value      # Gán damping tịnh tiến từ export var để tunable
	angular_damp = 0.0                   # Tắt engine angular_damp: script tự quản lý hoàn toàn bằng apply_torque

	# 3. Setup Fajen avoidance area
	setup_fajen_area()

	# 4. Setup debug vector mesh
	debug_vector_mesh.top_level = true   # Tách khỏi hệ trục tàu để vẽ global coords
	var m = ImmediateMesh.new()
	debug_vector_mesh.mesh = m
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true  # Cho phép vẽ nhiều màu trên 1 mesh
	mat.flags_unshaded = true              # Sáng bất chấp bóng tối
	mat.no_depth_test = true               # Nhìn xuyên thân tàu
	debug_vector_mesh.material_override = mat
	add_child(debug_vector_mesh)

	# 5. Setup trajectory mesh
	trajectory_mesh.top_level = true
	var tm = ImmediateMesh.new()
	trajectory_mesh.mesh = tm
	var t_mat = StandardMaterial3D.new()
	t_mat.albedo_color = Color.GREEN
	t_mat.flags_unshaded = true
	t_mat.no_depth_test = true
	trajectory_mesh.material_override = t_mat
	add_child(trajectory_mesh)

	# 6. Setup waypoints path mesh
	waypoints_mesh.top_level = true
	var pm = ImmediateMesh.new()
	waypoints_mesh.mesh = pm
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color.PLUM
	p_mat.flags_unshaded = true
	p_mat.no_depth_test = true
	waypoints_mesh.material_override = p_mat
	add_child(waypoints_mesh)

# Hàm xử lý input: scroll wheel để chỉnh độ cao waypoint
func _unhandled_input(event: InputEvent) -> void:
	# Chỉ xử lý scroll wheel
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset = 2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -2.0  # Offset Y mỗi lần scroll
			# Giới hạn trần/đáy bay
			current_target_height_offset = clamp(current_target_height_offset + offset, -45.0, 45.0)

			# Chỉ chỉnh độ cao khi giữ phím sequence_move
			if Input.is_action_pressed("sequence_move"):
				# Trường hợp 1: có waypoint trong hàng đợi → chỉnh waypoint cuối
				if not ship_movement_waypoints.is_empty():
					var last_waypoint = ship_movement_waypoints.back()
					var prev_position: Vector3

					if ship_movement_waypoints.size() > 1:
						prev_position = ship_movement_waypoints[ship_movement_waypoints.size() - 2].position
					else:
						prev_position = current_target_position if current_state == PlayerState.MOVE else global_position

					var dist_xz = Vector2(last_waypoint.position.x, last_waypoint.position.z).distance_to(
						Vector2(prev_position.x, prev_position.z))  # Khoảng cách mặt phẳng XZ

					# Giới hạn độ cao theo góc 45 độ (tam giác vuông cân)
					var min_y = prev_position.y - dist_xz
					var max_y = prev_position.y + dist_xz
					last_waypoint.position.y = clamp(last_waypoint.position.y + offset, min_y, max_y)
					if is_instance_valid(last_waypoint.point_marker):
						last_waypoint.point_marker.global_position.y = last_waypoint.position.y

				# Trường hợp 2: đang MOVE không có waypoint → chỉnh target hiện tại
				elif current_state == PlayerState.MOVE:
					var dist_xz = Vector2(current_target_position.x, current_target_position.z).distance_to(
						Vector2(global_position.x, global_position.z))
					var min_y = global_position.y - dist_xz
					var max_y = global_position.y + dist_xz
					current_target_position.y = clamp(current_target_position.y + offset, min_y, max_y)
					if current_waypoint and is_instance_valid(current_waypoint.point_marker):
						current_waypoint.position.y = current_target_position.y
						current_waypoint.point_marker.global_position.y = current_target_position.y

# Hàm vật lý chính — chạy mỗi physics frame
func _physics_process(delta: float) -> void:
	# 1. State machine điều phối hành vi
	match current_state:
		PlayerState.IDLE: handle_state_idle(delta)
		PlayerState.MOVE: handle_state_move(delta)

	# 2. Tự cân bằng roll về 0 mọi lúc (RigidBody3D có thể lăn khi va chạm)
	apply_roll_correction()

	# 3. Giới hạn góc pitch mọi lúc (không cho ngóc đầu quá max_pitch_angle)
	apply_pitch_clamp()

	# 4. Debug
	draw_waypoints_path()

	# 5. Hiển thị debug text
	rich_text_label.text = \
		"\nShip length: " + str(ship_length) + \
		"\nAngular velocity: " + str(angular_velocity.length()) +  \
		"\nThrottle: " + str(auto_throttle) + \
		"\nVelocity: " + str(linear_velocity.length()) + \
		"\nCurrent target position: " + str(current_target_position) + \
		"\nCurrent target direction: " + str(current_target_direction) + \
		"\nCurrent_target_height_offset: " + str(current_target_height_offset) + \
		"\nIs at threshold: " + str(is_at_current_waypoint_threshold) + \
		"\nCurrent dir: " + str(-global_transform.basis.z) + \
		"\nObstacles count: " + str(nearby_obstacles.size()) + \
		"\nWaypoints count: " + str(ship_movement_waypoints.size())

	# Lý do comment out: RigidBody3D tự xử lý collision response, không cần gọi thủ công
	# move_and_slide()   # Cũ: chỉ dùng cho CharacterBody3D

# =============================== CUSTOM FUNCTIONS ===============================

# ----------------------- STATE MACHINE ---------------------------------

# Hàm xử lý state IDLE — phanh và tự cân bằng
func handle_state_idle(delta: float) -> void:
	# 1. Phanh tịnh tiến bằng lực ngược chiều linear_velocity
	# Lý do đổi: velocity.move_toward() set thẳng không hợp lệ với RigidBody3D
	# velocity = velocity.move_toward(Vector3.ZERO, (max_brake_force / mass) * delta)   # Cũ
	if linear_velocity.length() > 0.01:  # Chỉ apply khi còn đang chạy
		# F = mass * a, a = max_brake_force → F = mass * max_brake_force
		var brake_force = -linear_velocity.normalized() * max_brake_force * mass
		apply_central_force(brake_force)   # Mới: apply lực phanh ngược chiều

	# 2. Tự cân bằng tư thế về nằm ngang
	auto_stable_ship_indie_state(delta)

	# Lý do comment out: RigidBody3D tự xử lý collision, không cần gọi
	# move_and_slide()   # Cũ

# Hàm xử lý state MOVE — arrive behavior + fajen steering
func handle_state_move(delta: float) -> void:
	var current_position = global_position              # Vị trí ship hiện tại
	var target_position = current_target_position       # Vị trí cần tới
	var distance = current_position.distance_to(target_position)  # Khoảng cách đến target

	## Tính quãng đường phanh tối thiểu: s = v² / (2 * a), a = max_brake_force
	# Lý do đổi: velocity → linear_velocity
	# var min_stopping_distance = pow(velocity.length(), 2) / (2.0 * max_brake_force / mass)   # Cũ
	var min_stopping_distance = pow(linear_velocity.length(), 2) / (2.0 * (max_brake_force / mass))  # Mới
	min_stopping_distance = clamp(min_stopping_distance, distance_threshold, min_stopping_distance)

	var ship_heading_vector = -global_transform.basis.z  # Hướng mũi tàu (trục -Z local)
	var direction_to_target = current_position.direction_to(target_position)  # Hướng thẳng đến target
	var desired_direction: Vector3   # Hướng di chuyển sau khi blend/steering
	var raw_direction: Vector3       # Hướng thô trước khi Fajen
	var danger_throttle_factor = 1.0  # Hệ số giảm ga khi có obstacle nguy hiểm

	# =========================================================
	# FIX BUG: Arrive xoay loạn khi đến đích cuối
	# Khi is_at_current_waypoint_threshold = true và không còn waypoint,
	# distance rất nhỏ → direction_to_target không ổn định → tàu xoay loạn
	# Fix: giữ nguyên current_target_direction, bỏ qua tính toán steering/fajen
	# =========================================================
	#if is_at_current_waypoint_threshold and ship_movement_waypoints.is_empty():
		#raw_direction = current_target_direction      # Giữ hướng cũ, không tính lại
		#desired_direction = current_target_direction  # Không để direction_to_target gây loạn
	#else:
	
	# =========================================================
	# BLENDING DIRECTION: Gần đích thì xoay hướng từ từ vào target direction ban đầu cho mượt
	# =========================================================
	# Định nghĩa khoảng cách bắt đầu blend hướng
	var rotation_blend_distance = distance_threshold * 2.0

	# Gán hướng dựa trên blend distance
	if distance > rotation_blend_distance:
		# Ở xa: hoàn toàn hướng về target
		is_at_current_waypoint_threshold = false
		raw_direction = direction_to_target
	
	# Khoảng cách chạm ngưỡng cần dừng và quay hướng
	elif distance > distance_threshold:
		# Tránh trường hợp ship bị lặp vô tận khi đổi target direction liên tục ở điểm giữa
		if not is_at_current_waypoint_threshold:
			var blend_weight = (distance - distance_threshold) / rotation_blend_distance
			blend_weight = clamp(blend_weight, 0.8, 1.0)
			
			# Slerp giữa hướng đích đến và hướng click chuột ban đầu
			raw_direction = current_target_direction.slerp(direction_to_target, blend_weight).normalized()
			
	# Khoảng cách chạm đích
	else:
		is_at_current_waypoint_threshold = true
		raw_direction = current_target_direction

	# =========================================================
	# STEERING: Fajen (xa) hoặc manual torque (gần)
	# =========================================================
	# Tính desired direction theo thuật toán steering khi distance còn xa
	if distance > ship_length * 5.0:
		# Gán default desired direction theo raw
		desired_direction = raw_direction
		
		## Steering theo thuật toán Fajen - Angular steering
		if current_steering_mode == ShipSteeringMode.FAJEN_WARREN:
			# FIX "XOAY VÒNG TRÒN": Lấy vận tốc góc THỰC TẾ của RigidBody3D 
			# x = pitch (quanh trục X local), y = yaw (quanh trục Y global)
			var real_angular_vel = Vector2(
				angular_velocity.dot(global_transform.basis.x),
				angular_velocity.dot(Vector3.UP)
			)

			# Truyền vận tốc góc THỰC vào Fajen (hàm Fajen đã có sẵn lực Damping hãm đà bên trong)
			var fajen_result = compute_fajen_angular_acceleration(ship_heading_vector, raw_direction, real_angular_vel)
			var raw_fajen_acceleration: Vector2 = fajen_result["angular_accel"]  
			var total_repulsion: float = fajen_result["repulsion_force"]  

			# Giới hạn gia tốc theo sức m��nh động cơ (angular_acceleration)
			var applied_accel_pitch = clamp(raw_fajen_acceleration.x, -angular_acceleration, angular_acceleration)
			var applied_accel_yaw   = clamp(raw_fajen_acceleration.y, -angular_acceleration, angular_acceleration)

			# Danger throttle: giảm ga khi obstacle đẩy mạnh
			if total_repulsion > 5.0:
				danger_throttle_factor = clamp(1.0 - (total_repulsion / 50.0), 0.1, 1.0)
			else:
				danger_throttle_factor = 1.0

			# Đổi gia tốc thành Lực (Torque = Gia tốc * mass) và apply thẳng vào thân tàu
			var pitch_torque = global_transform.basis.x * applied_accel_pitch * mass
			var yaw_torque   = Vector3.UP * applied_accel_yaw * mass
			
			apply_torque(yaw_torque + pitch_torque)   # Mới: apply tổng torque
	
	# Khoảng cách gần target, không dùng steering mà dùng manual
	else:
		desired_direction = raw_direction
		update_character_rotation(delta, ship_heading_vector, desired_direction, distance, min_stopping_distance)

	# Tính heading alignment theo desired direction: 1.0 = nhìn thẳng vào target, 0.0 = vuông góc, -1.0 = ngược
	var heading_alignment = ship_heading_vector.dot(desired_direction)

	# =========================================================
	# WAYPOINT SWITCHING
	# =========================================================
	#var waypoint_switch_distance = distance_threshold / 2.0  # Ngưỡng chuyển waypoint mặc định
	var waypoint_switch_distance = distance_threshold / 2.0
	if ship_movement_waypoints.size() > 0:
		waypoint_switch_distance = max_linear_speed * 0.5  # Cắt góc sớm hơn khi đang chạy nhanh
	
	# Nếu vào ngưỡng đổi waypoint
	if distance < waypoint_switch_distance:
		if ship_movement_waypoints.size() > 0:
			# Còn waypoint: chuyển sang waypoint tiếp theo
			load_next_waypoint()
		else:
			# Đích cuối: phanh nhanh
			# velocity = velocity.move_toward(Vector3.ZERO, max_brake_force * delta * 0.1)   # Cũ
			if linear_velocity.length() > 0.1:
				apply_central_force(-linear_velocity.normalized() * max_brake_force)  # Mới: phanh bằng force
				linear_velocity = linear_velocity.move_toward(Vector3.ZERO, max_brake_force * delta * 0.1)

			# Dừng hẳn khi đã thẳng hướng và gần dừng
			if linear_velocity.length() < 0.1 and (heading_alignment >= 0.999 or heading_alignment == 0.0):
				print("you are here deadass")
				auto_throttle = 0.0

	# =========================================================
	# THUẬT TOÁN ARRIVE —Tính lực đẩy tiến
	# =========================================================
	var target_speed: float
	## Gia tốc phanh (m/s²), F = mass * deceleration
	var deceleration = max_brake_force
	var is_final_waypoint = ship_movement_waypoints.is_empty() 	# Flag check đã là điểm cuối của waypoint
	
	# Tính tốc độ cần thiết dựa trên distance và waypoint
	if distance > min_stopping_distance:
		# Càng gần điểm đến, vận tốc càng chậm nhưng luôn giữ tối thiểu 0.05
		# Tính target speed theo khoảng cách
		if not is_final_waypoint:
			target_speed = min(distance / (braking_distance_factor * 0.5), max_linear_speed)  # Waypoint giữa: giữ max speed
		else:
			target_speed = clamp(distance / braking_distance_factor, 0.05, max_linear_speed)  # Đích cuối: giảm dần

		# Tính ga trên góc xoay giữa mũi tàu và điểm tới (Auto throttle)
		# Nếu mũi nhìn thẳng (alignment = 1) -> throttle = 1 (Chạy 100% ga)
		# Nếu mũi quay ngang (alignment <= 0) -> throttle = 0 (Nhả ga về 0)
		auto_throttle = clamp(heading_alignment, 0.0, 1.0)
		auto_throttle = pow(auto_throttle, 3)   # Lũy thừa 3 để nhạy hơn khi lệch
		
		# Ép ga nhỏ lại nếu Radar báo hiệu nguy hiểm phía trước
		auto_throttle *= danger_throttle_factor 
		
		# Tính vận tốc áp dụng
		# Chỉ bắt đầu tăng tốc khi hướng mũi ship đã ổn so với điểm tới (cách điểm hàm còn xa)
		if heading_alignment > 0.0:
			# Hướng mũi hợp lệ: tính và apply thrust force
			## v(desired) = direction(ship heading vector3) * current speed * hệ số ga
			var desired_velocity = ship_heading_vector * (target_speed * auto_throttle)  # Vận tốc mong muốn

			# Lý do đổi: không dùng velocity trực tiếp, dùng linear_velocity
			# var steering_force = desired_velocity - velocity                              # Cũ
			## v(stearing) = v(desired) - v(current)
			var steering_force = desired_velocity - linear_velocity  # Mới: delta velocity

			# Giới hạn lực đẩy (thrust) tối đa cho lực bẻ lại không thể hơn max lực đẩy
			if steering_force.length() > max_thrust_force:
				steering_force = steering_force.normalized() * max_thrust_force

			# Lý do đổi: không set velocity trực tiếp, dùng apply_central_force
			# velocity += (steering_force / mass) * delta   # Cũ: set velocity thủ công
			## F = mass * a = mass * steering_force (steering_force đơn vị m/s, nhân mass → Newton)
			apply_central_force(steering_force * mass)  # Mới: Newton thật

		else:
			# Hướng ngược: phanh lại
			# velocity = velocity.move_toward(Vector3.ZERO, deceleration)   # Cũ
			apply_central_force(-linear_velocity.normalized() * deceleration)  # Mới

	else:
		# Trong vùng stopping distance: phanh
		# velocity = velocity.move_toward(Vector3.ZERO, deceleration)           # Cũ (final)
		# velocity = velocity.move_toward(Vector3.ZERO, deceleration * 0.5)     # Cũ (mid)
		# Lấy chính max_brake_force làm lực phanh để hãm velocity lại
		# Trong vùng stopping distance: phanh
		# 1. Kiểm tra vận tốc hiện tại
		if linear_velocity.length() > 0.1:
			# 2. Phanh dần nếu vận tốc còn lớn
			if is_final_waypoint:
				apply_central_force(-linear_velocity.normalized() * deceleration * mass)  # Mới (Nhân mass)
			else:
				apply_central_force(-linear_velocity.normalized() * deceleration * 0.5 * mass)  # Mới (Nhân mass)
		else:
			# 3. Ép vận tốc về 0 nếu quá nhỏ để tránh giật
			linear_velocity = Vector3.ZERO

	# =========================================================
	# LATERAL DAMPENING — triệt tiêu vận tốc ngang, chống bay vòng tròn
	# =========================================================
	# Tách vận tốc thành 2 thành phần: tiến và ngang
	## Tính độ lớn vận tốc đúng: speed(forward) = dot(v(current), direction(ship heading vector3))
	var forward_speed = linear_velocity.dot(ship_heading_vector)	# 1 số float, độ lớn vector
	## Tính vector vận tốc đúng: v(forward) = speed(forward) * direction(ship heading vector3)
	var forward_velocity = ship_heading_vector * forward_speed		# Vector có hướng + độ lớn, để biết velocity theo mũi tàu đang lớn bao nhiêu
	
	# Tính vận tốc ngang (vận tốc còn thừa ở hướng cũ so với hướng mới)
	## v(curent) = v(lateral) + v(forward) -> v(lateral) = v(current) - v(forward)
	var lateral_velocity = linear_velocity - forward_velocity

	# Tăng friction khi gần đích để không bị trôi
	var effective_friction = lateral_friction
	if distance < distance_threshold / 2.0:
		effective_friction *= 2.0  # Tăng gấp đôi khi sát đích

	# Lý do đổi: không lerp velocity trực tiếp, dùng apply_central_force
	# lateral_velocity = lateral_velocity.lerp(Vector3.ZERO, effective_friction * delta)   # Cũ
	# velocity = forward_velocity + lateral_velocity                                        # Cũ
	## F_lateral = -lateral_velocity * friction (Newton = kg * m/s²)
	# Dead zone: không apply khi lateral_velocity quá nhỏ
	# Tránh oscillation do floating point và heading rotation liên tục
	# 1. Kiểm tra độ lớn vận tốc ngang
	if lateral_velocity.length() > 0.1: # Giảm ngưỡng deadzone xuống để mượt hơn
		# 2. Áp dụng lực triệt tiêu
		apply_central_force(-lateral_velocity * effective_friction * mass)

	# Clamp tốc độ tối đa (RigidBody3D không tự clamp như CharacterBody3D)
	if linear_velocity.length() > max_linear_speed:
		linear_velocity = linear_velocity.normalized() * max_linear_speed

	# Debug visuals
	draw_debug_vectors(desired_direction, forward_velocity, lateral_velocity)
	var predicted_path = calculate_predicted_path()
	draw_trajectory_line(predicted_path)
	
	rich_text_label_2.text = \
		"\nMin stopping distance: " + str(min_stopping_distance) + \
		"\nDistance: " + str(distance) + \
		"\nHeading alignment: " + str(heading_alignment) + \
		"\nlateral_velocity: " + str(lateral_velocity)

	# Lý do comment out: RigidBody3D tự xử lý collision, không cần gọi thủ công
	# move_and_slide()   # Cũ: chỉ dùng cho CharacterBody3D

# ----------------------- STEERING --------------------------------

# Hàm setup area3D detect obstacle cho Fajen steering
func setup_fajen_area() -> void:
	var avoidance_area = Area3D.new()
	avoidance_area.name = "FajenAvoidanceArea"
	add_child(avoidance_area)

	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = fajen_detection_radius  # Bán kính vùng phát hiện obstacle
	col_shape.shape = sphere
	avoidance_area.add_child(col_shape)

	avoidance_area.collision_mask = 1  # Layer obstacle (chỉnh theo project)
	avoidance_area.body_entered.connect(_on_fajen_body_entered)
	avoidance_area.body_exited.connect(_on_fajen_body_exited)

func _on_fajen_body_entered(body: Node3D) -> void:
	if body != self and not nearby_obstacles.has(body):
		nearby_obstacles.append(body)

func _on_fajen_body_exited(body: Node3D) -> void:
	nearby_obstacles.erase(body)

# Hàm Fajen & Warren steering — tính phi_double_dot (gia tốc góc) cho yaw và pitch
## Formula: phi_double_dot = -b*phi_dot - kg*(phi-psi_g)*(exp(-c1*dg)+c2) + sum(ko*(phi-psi_o)*exp(-c3*|phi-psi_o|)*exp(-c4*do))
## Giải thích tham số:
# ship_heading_vector : Hướng mũi tàu (Vector3 normalized)
# target_direction    : Hướng mục tiêu cần bay đến (Vector3 normalized)
# current_angular_velocity : Momentum xoay hiện tại của Fajen (Vector2: x=pitch, y=yaw)
func compute_fajen_angular_acceleration(ship_heading_vector: Vector3, target_direction: Vector3, current_angular_velocity: Vector2) -> Dictionary:
	
	var space_state = get_world_3d().direct_space_state  # Physics space để raycast

	# Tính góc Yaw và Pitch của tàu (trong world space theo trục Z forward)
	var current_phi_yaw:   float = atan2(ship_heading_vector.x, ship_heading_vector.z)
	var current_phi_pitch: float = atan2(ship_heading_vector.y,
		sqrt(ship_heading_vector.x * ship_heading_vector.x + ship_heading_vector.z * ship_heading_vector.z))

	# Tính góc Yaw và Pitch của mục tiêu
	var goal_phi_yaw:   float = atan2(target_direction.x, target_direction.z)
	var goal_phi_pitch: float = atan2(target_direction.y,
		sqrt(target_direction.x * target_direction.x + target_direction.z * target_direction.z))

	# Khoảng cách đến goal, min 0.5 để tránh chia cho 0
	var distance_to_goal: float = max(0.5, global_position.distance_to(current_target_position))

	# Damping term: -b * phi_dot
	var phi_double_dot_yaw:   float = -fajen_b * current_angular_velocity.y
	var phi_double_dot_pitch: float = -fajen_b * current_angular_velocity.x

	# Goal error: góc lệch giữa ship và target (chuẩn hóa về [-PI, PI])
	var goal_error_yaw:   float = fposmod((current_phi_yaw   - goal_phi_yaw)   + PI, TAU) - PI
	var goal_error_pitch: float = fposmod((current_phi_pitch - goal_phi_pitch) + PI, TAU) - PI

	# Goal attraction term: kg * error * (exp(-0.4*d) + 0.4)
	var goal_term_yaw:   float = fajen_kg * goal_error_yaw   * (exp(-0.4 * distance_to_goal) + 0.4)
	var goal_term_pitch: float = fajen_kg * goal_error_pitch * (exp(-0.4 * distance_to_goal) + 0.4)
	phi_double_dot_yaw   -= goal_term_yaw
	phi_double_dot_pitch -= goal_term_pitch

	var total_repulsion := 0.0  # Tổng lực đẩy obstacle để tính danger throttle
	var count: int = 0          # Đếm số obstacle đã tính

	# Tính obstacle repulsion cho từng obstacle trong vùng detect
	for obstacle in nearby_obstacles:
		if count >= fajen_max_obstacles: break  # Giới hạn để đảm bảo hiệu năng

		var obs_position = obstacle.global_position
		var query = PhysicsRayQueryParameters3D.create(global_position, obs_position)
		query.exclude = [self.get_rid()]
		var result = space_state.intersect_ray(query)

		var hit_position = obs_position
		var obs_radius   = 1.0  # Mặc định obstacle bán kính 1m

		if result:
			hit_position = result.position
			obs_radius   = max(1.0, hit_position.distance_to(obs_position))  # Ước tính radius từ raycast
		else:
			hit_position = obs_position

		var distance_to_obstacle = global_position.distance_to(hit_position)
		if distance_to_obstacle > fajen_detection_radius or distance_to_obstacle < 0.1: continue

		var direction_to_obs = (hit_position - global_position).normalized()
		if ship_heading_vector.dot(direction_to_obs) < -0.25: continue  # Bỏ qua obstacle phía sau

		var obs_phi_yaw:   float = atan2(direction_to_obs.x, direction_to_obs.z)
		var obs_phi_pitch: float = atan2(direction_to_obs.y,
			sqrt(direction_to_obs.x * direction_to_obs.x + direction_to_obs.z * direction_to_obs.z))

		var obs_error_yaw:   float = fposmod((current_phi_yaw   - obs_phi_yaw)   + PI, TAU) - PI
		var obs_error_pitch: float = fposmod((current_phi_pitch - obs_phi_pitch) + PI, TAU) - PI

		var dynamic_ko = fajen_ko * (1.0 + sqrt(obs_radius))  # Ko tăng theo kích thước obstacle

		# Repulsion term: ko * error * exp(-c3*|error|) * exp(-c4*distance)
		var obs_term_yaw   = dynamic_ko * obs_error_yaw   * exp(-6.0 * abs(obs_error_yaw))   * exp(-fajen_c4 * distance_to_obstacle)
		var obs_term_pitch = dynamic_ko * obs_error_pitch * exp(-6.0 * abs(obs_error_pitch)) * exp(-fajen_c4 * distance_to_obstacle)

		phi_double_dot_yaw   += obs_term_yaw
		phi_double_dot_pitch += obs_term_pitch
		total_repulsion      += Vector2(obs_term_yaw, obs_term_pitch).length()
		count += 1

	# Noise nhỏ chống deadlock khi bị kẹp giữa các lực đối nhau
	if count > 0 and current_angular_velocity.length() < 0.1 \
			and Vector2(phi_double_dot_pitch, phi_double_dot_yaw).length() < 0.1:
		phi_double_dot_yaw   += randf_range(-fajen_noise, fajen_noise)
		phi_double_dot_pitch += randf_range(-fajen_noise, fajen_noise)

	return {
		"angular_accel":   Vector2(phi_double_dot_pitch, phi_double_dot_yaw),  # x = pitch, y = yaw
		"repulsion_force": total_repulsion
	}

# ---------------------- WAYPOINT + ADD MOVE -----------------------

# Hàm thêm waypoint và bắt đầu di chuyển
## new_position  : Điểm cần di chuyển đến
## is_sequence   : true = nối tiếp vào hàng đợi, false = xóa hàng đợi cũ
func move_to(new_position: Vector3, is_sequence: bool = false) -> void:
	# 1. Clear hàng đợi nếu không phải sequence
	if not is_sequence:
		clear_all_waypoints()

	# 2. Cộng offset độ cao từ scroll wheel
	new_position.y += current_target_height_offset

	# 3. Xác định previous_position để tính direction của waypoint mới
	var previous_position: Vector3
	if current_state == PlayerState.MOVE:
		previous_position = ship_movement_waypoints.back().position \
			if not ship_movement_waypoints.is_empty() \
			else current_target_position
	else:
		previous_position = global_position

	# 4. Tạo waypoint mới và thêm vào hàng đợi
	var new_waypoint = Movement_Waypoint.new(new_position, previous_position)
	add_child(new_waypoint.point_marker)     # Hiện marker trực quan
	ship_movement_waypoints.append(new_waypoint)

	# 5. Load waypoint đầu tiên nếu chưa di chuyển
	if current_state != PlayerState.MOVE or not is_sequence:
		load_next_waypoint()

	# 6. Đổi state sang MOVE
	change_state(PlayerState.MOVE)

# Hàm xóa toàn bộ waypoint và reset
func clear_all_waypoints() -> void:
	# 1. Xóa tất cả marker trong hàng đợi
	for wp in ship_movement_waypoints:
		if is_instance_valid(wp.point_marker): wp.point_marker.queue_free()
	ship_movement_waypoints.clear()

	# 2. Xóa current waypoint
	if current_waypoint and is_instance_valid(current_waypoint.point_marker):
		current_waypoint.point_marker.queue_free()
	current_waypoint = null

# Hàm load waypoint tiếp theo từ hàng đợi
func load_next_waypoint() -> void:
	if ship_movement_waypoints.size() > 0:
		# 1. Xóa marker waypoint hiện tại
		if current_waypoint: current_waypoint.point_marker.queue_free()

		# 2. Pop waypoint đầu hàng đợi và gán làm current
		var next_target_movement = ship_movement_waypoints.pop_front()
		current_waypoint         = next_target_movement
		current_target_position  = next_target_movement.position
		current_target_direction = next_target_movement.direction

		# 3. Lý do đổi: không dùng float angular_velocity thủ công nữa
		# angular_velocity *= 0.5   # Cũ: giảm float angular_velocity thủ công
		fajen_angular_velocity *= 0.5  # Mới: reset Fajen momentum để bẻ cua nhanh qua waypoint

# ---------------------- STATE MACHINE FUNCTION ---------------------

# Hàm đổi state — chỉ đổi khi khác state hiện tại
func change_state(new_state: PlayerState) -> void:
	if current_state == new_state: return

	match new_state:
		PlayerState.IDLE: pass
		PlayerState.MOVE: pass

	current_state = new_state
	print("State changed to: ", current_state)

# ----------------------- SUPPORT FUNCTION --------------------------

# Hàm xoay tàu bằng PID Controller khi ở gần target để chống rung lắc (Jitter)
## delta                : thời gian của 1 frame
## heading_vector       : hướng mũi tàu hiện tại (-Z local)
## desired_direction    : hướng cần xoay đến
## distant_to_target    : khoảng cách đến target
## min_stopping_distance: quãng đường phanh tối thiểu
func update_character_rotation(delta: float, heading_vector: Vector3, desired_direction: Vector3, distant_to_target: float, min_stopping_distance: float) -> void:
	# 2. Tính toán trục xoay và góc lệch (Error)
	var cross = heading_vector.cross(desired_direction)  # Trục vuông góc giữa heading và desired
	var rotation_axis: Vector3
	
	# Sửa lỗi "bị đơ": Khi hướng hiện tại và đích đối diện 180 độ, cross vector = (0,0,0) tàu sẽ không biết quay trái hay phải.
	if cross.length_squared() < 0.001: 
		if heading_vector.dot(desired_direction) < -0.9:
			# Đang ngược hướng 180 độ -> Ép tàu quay theo trục Y (Yaw)
			rotation_axis = Vector3.UP
		else:
			# Đã thẳng hàng hoàn toàn (0 độ) -> Kết thúc
			rot_error_integral = 0.0 
			return                   
	else:
		rotation_axis = cross.normalized()               

	var angle_error = heading_vector.angle_to(desired_direction)  # Góc lệch (Radian)

	# 3. Tính toán 3 thành phần của PID (Đóng vai trò là Gia Tốc Góc - Angular Acceleration)
	# 3.1. Proportional (P) - Gia tốc kéo tỉ lệ với góc lệch
	var p_term = pid_rot_p * angle_error
	
	# 3.2. Integral (I) - Tích lũy góc lệch theo thời gian
	rot_error_integral += angle_error * delta
	var i_term = pid_rot_i * rot_error_integral
	
	# 3.3. Derivative (D) - Gia tốc cản tỉ lệ với vận tốc góc hiện tại (Chống overshoot)
	var current_angular_vel = angular_velocity.dot(rotation_axis) 
	var d_term = pid_rot_d * current_angular_vel 

	# 4. Tính tổng gia tốc góc cần thiết từ thuật toán PID
	var pid_accel = p_term + i_term - d_term

	# 5. Giới hạn gia tốc không vượt quá sức mạnh động cơ (angular_acceleration)
	pid_accel = clamp(pid_accel, -angular_acceleration, angular_acceleration)

	# 6. Đổi gia tốc thành Lực Torque (Torque = Gia tốc * Khối lượng)
	# Việc nhân mass ở bước cuối giúp thuật toán PID luôn mạnh mẽ dù tàu nặng hay nhẹ
	var pid_torque = pid_accel * mass

	# 7. Apply lực Torque vào RigidBody3D
	if abs(pid_torque) > 0.05:
		apply_torque(rotation_axis * pid_torque)
	else:
		# Ép góc về tĩnh nếu lực đã cực nhỏ để tránh vi rung
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 10.0 * delta)

	# 8. Level-out torque khi gần đích cuối (Kéo tàu về nằm ngang)
	if ship_movement_waypoints.is_empty() and distant_to_target <= min_stopping_distance:
		var flat_desired = Vector3(desired_direction.x, 0.0, desired_direction.z)
		if flat_desired.length_squared() > 0.001:
			var level_cross = heading_vector.cross(flat_desired.normalized())
			if level_cross.length_squared() > 0.0001:
				var blend = clamp(1.0 - (distant_to_target / max_linear_speed), 0.0, 1.0)
				apply_torque(level_cross.normalized() * blend * (angular_acceleration * mass) * 0.5)

## Hàm xoay tàu bằng torque khi ở gần target (thay thế set transform trực tiếp)
### delta                : delta time
### heading_vector       : hướng mũi tàu hiện tại (-Z local)
### desired_direction    : hướng cần xoay đến
### distant_to_target    : khoảng cách đến target
### min_stopping_distance: quãng đường phanh tối thiểu
#func update_character_rotation(delta: float, heading_vector: Vector3, desired_direction: Vector3, distant_to_target: float, min_stopping_distance: float) -> void:
	## 1. Check đã thẳng hướng chưa
	##if heading_vector.is_equal_approx(desired_direction): return
#
	## 2. Tránh Gimbal Lock khi nhìn thẳng lên/xuống
	#var safe_up = Vector3.UP
	#if abs(desired_direction.y) > 0.99:
		#safe_up = Vector3.RIGHT  # Mượn trục X làm UP tạm thời
#
	## 3. Level-out basis khi gần đích cuối (blend về nằm ngang)
	#var target_basis = Basis.looking_at(desired_direction, safe_up)
	#
	## Cân bằng ship khi gần tới đích
	## Nếu đây là waypoint cuối cùng và tàu đang đi chậm lại
	#if ship_movement_waypoints.is_empty():
		## Nếu đã vào vùng phanh
		#if distant_to_target <= min_stopping_distance or distant_to_target < max_linear_speed:
			#var flat_desired_direction = Vector3(desired_direction.x, 0.0, desired_direction.z)
			#if flat_desired_direction.length_squared() > 0.001:
				## Basis 2: Nằm ngang hoàn toàn
				#var leveled_basis = Basis.looking_at(flat_desired_direction.normalized(), Vector3.UP)
				#
				## Tính tỷ lệ mix: Càng gần đích, tỷ lệ leveled càng cao
				#var blend_weight = clamp(1.0 - (distant_to_target / max_linear_speed), 0.0, 1.0)
				#
				## Trộn 2 Basis lại với nhau!
				#var blend_quaternion = Quaternion(target_basis).slerp(Quaternion(leveled_basis), blend_weight)
				#target_basis = Basis(blend_quaternion)
#
	## 4. Tính trục và góc lệch để xoay
	#var cross = heading_vector.cross(desired_direction)  # Trục vuông góc giữa heading và desired
	#if cross.length_squared() < 0.0001: return           # Đã thẳng hàng
	#var rotation_axis = cross.normalized()               # Trục xoay chuẩn hóa
	#var angle_diff    = heading_vector.angle_to(desired_direction)  # Góc lệch (radian)
#
	## 5. Tính desired turn speed theo góc lệch (arrive behavior)
	## Càng gần đích, xoay càng mượt để tránh rung lắc
	#var distance_factor = clamp(distant_to_target / (distance_threshold * 2.0), 0.1, 1.0)
	#var turn_dampening = 1.0
	#if ship_movement_waypoints.is_empty() and distant_to_target < distance_threshold:
		#turn_dampening = distance_factor
		#
	#var desired_turn_speed = clamp(angle_diff * turn_sensitivity * turn_dampening, -max_turn_speed, max_turn_speed)
#
	## 6. Lấy current turn speed từ RigidBody3D angular_velocity theo đúng trục xoay
	#var current_turn_speed = angular_velocity.dot(rotation_axis)        # Mới: lấy từ engine Vector3
#
	## 7. Tính steering torque
	#var speed_diff = desired_turn_speed - current_turn_speed
#
	## 8. Chọn torque power: tăng tốc hay phanh xoay
	#var is_same_direction = sign(desired_turn_speed) == sign(current_turn_speed)
	#var is_speeding_up    = abs(desired_turn_speed) > abs(current_turn_speed)
	#var torque_power: float
	#if is_same_direction and is_speeding_up:
		#torque_power = angular_acceleration  # Đang tăng tốc xoay
	#else:
		#torque_power = angular_braking       # Đang phanh hoặc đảo chiều xoay
#
	## 9. Apply torque (thay set global_transform.basis trực tiếp)
	## 1. Kiểm tra speed_diff có đủ lớn không để tránh rung lắc liti
	#if abs(speed_diff) > 0.01:
		## 2. Apply torque có nhân mass (Torque = I * alpha, mass thường tỉ lệ với Inertia)
		#apply_torque(rotation_axis * speed_diff * torque_power * mass)          # Nhân mass để lực đủ mạnh và ổn định
	#else:
		## 3. Ép angular velocity về 0 nếu góc đã chuẩn để chống jitter
		#angular_velocity = angular_velocity.lerp(Vector3.ZERO, 5.0 * delta)
#
	## 10. Level-out torque khi gần đích cuối (kéo về nằm ngang)
	#if ship_movement_waypoints.is_empty():
		#if distant_to_target <= min_stopping_distance or distant_to_target < max_linear_speed:
			#var flat_desired = Vector3(desired_direction.x, 0.0, desired_direction.z)
			#if flat_desired.length_squared() > 0.001:
				#var level_cross = heading_vector.cross(flat_desired.normalized())
				#if level_cross.length_squared() > 0.0001:
					#var blend = clamp(1.0 - (distant_to_target / max_linear_speed), 0.0, 1.0)
					#apply_torque(level_cross.normalized() * blend * angular_acceleration * 0.5)

## Hàm cân bằng tàu về nằm ngang khi IDLE bằng torque
### delta: delta time
#func auto_stable_ship_indie_state(delta: float) -> void:
	#var current_forward = -global_transform.basis.z                          # Hướng mũi tàu hiện tại
	#var flat_forward    = Vector3(current_forward.x, 0.0, current_forward.z) # Chiếu xuống mặt phẳng XZ
#
	#if flat_forward.length_squared() > 0.001:
		#flat_forward = flat_forward.normalized()
#
		## Lý do đổi: set global_transform.basis trực tiếp conflict với RigidBody3D physics
		## var target_basis = Basis.looking_at(flat_forward, Vector3.UP)                       # Cũ
		## var current_quat = Quaternion(global_transform.basis.orthonormalized())             # Cũ
		## var target_quat  = Quaternion(target_basis)                                         # Cũ
		## global_transform.basis = Basis(current_quat.slerp(target_quat, 2.0 * delta))       # Cũ: set trực tiếp
#
		## 1. Tính pitch error: component Y của forward = độ nghiêng so với mặt phẳng ngang
		#var pitch_error = current_forward.y  # > 0: đang ngóc đầu lên, < 0: cúi đầu xuống
		## 2. Apply torque kéo pitch về 0 quanh trục X local
		#apply_torque(-global_transform.basis.x * pitch_error * angular_acceleration * stabilization_speed)
		## 3. Damping angular velocity để dừng lắc lư khi IDLE
		#apply_torque(-angular_velocity * angular_damp_value)

# Hàm cân bằng tàu về nằm ngang khi IDLE bằng Mini-PID
func auto_stable_ship_indie_state(delta: float) -> void:
	var current_forward = -global_transform.basis.z
	
	# ==================================================
	# 1. CÂN BẰNG PITCH (NGÓC/CÚI ĐẦU)
	# ==================================================
	var pitch_error = asin(clamp(current_forward.y, -1.0, 1.0)) # >0 là đang ngóc lên, <0 là chúi xuống
	var pitch_axis = -global_transform.basis.x # Trục xoay ngóc/cúi
	
	# P - Lực kéo về 0 độ
	var p_term = pitch_error * (angular_acceleration * stabilization_speed)
	# D - Lực hãm đà chống lắc qua lại
	var current_pitch_vel = angular_velocity.dot(pitch_axis)
	var d_term = current_pitch_vel * (angular_damp_value * 5.0) # Nhân 5 để phanh gắt hơn
	
	var pitch_torque = (p_term - d_term) * mass
	
	# Apply torque nếu còn lệch, nếu đã rất phẳng thì dập tắt luôn vận tốc pitch
	if abs(pitch_error) > 0.005 or abs(current_pitch_vel) > 0.01:
		apply_torque(pitch_axis * pitch_torque)
	else:
		angular_velocity -= angular_velocity.project(pitch_axis) # Trừ bỏ phần xoay pitch

	# ==================================================
	# 2. HÃM ĐÀ YAW (XOAY TRÁI/PHẢI KHI ĐANG ĐỨNG IM)
	# ==================================================
	var yaw_axis = Vector3.UP
	var current_yaw_vel = angular_velocity.dot(yaw_axis)
	
	if abs(current_yaw_vel) > 0.01:
		# Áp dụng lực phanh hãm xoay ngang
		apply_torque(-yaw_axis * current_yaw_vel * (angular_damp_value * mass * 5.0))
	else:
		angular_velocity -= angular_velocity.project(yaw_axis) # Trừ bỏ phần xoay ngang

# Hàm tự cân bằng roll về 0 bằng torque (chạy mọi frame)
func apply_roll_correction() -> void:
	# 1. ship_up: hướng lên của tàu (trục Y local)
	var ship_up   = global_transform.basis.y
	# 2. roll_error: cross product ship_up và world UP → vector thể hiện độ lệch roll
	var roll_error = ship_up.cross(Vector3.UP)
	# 3. roll_axis: trục Z local (trục forward = trục roll của tàu)
	var roll_axis  = global_transform.basis.z
	# 4. Chiếu roll_error lên roll_axis để lấy thành phần roll thuần túy, apply torque kéo về 0
	apply_torque(roll_axis * roll_error.dot(roll_axis) * roll_correction_torque)
	# 5. Damping angular velocity theo trục Z để tắt lắc lư roll
	apply_torque(-angular_velocity.project(global_transform.basis.z) * angular_damp_value)

# Hàm giới hạn góc pitch tối đa (chạy mọi frame)
func apply_pitch_clamp() -> void:
	# 1. Tính pitch hiện tại từ component Y của hướng forward (-Z)
	var pitch = asin(clamp(-global_transform.basis.z.y, -1.0, 1.0))  # Radian
	# 2. Đổi max_pitch_angle từ độ sang radian
	var max_pitch_rad = deg_to_rad(max_pitch_angle)
	# 3. Nếu vượt quá giới hạn thì apply torque kéo về
	if abs(pitch) > max_pitch_rad:
		var pitch_error = pitch - sign(pitch) * max_pitch_rad  # Độ lệch so với giới hạn
		# Apply torque ngược chiều quanh trục X local
		apply_torque(-global_transform.basis.x * pitch_error * angular_acceleration)

# -----------------------  DEBUG VISUAL ------------------------------

# Hàm vẽ 3 tia vector debug: hướng mong muốn, vận tốc tiến, vận tốc ngang
## desired_direction: hướng mong muốn di chuyển
## forward_velocity : vận tốc theo hướng mũi tàu
## lateral_velocity : vận tốc ngang (cần triệt tiêu)
func draw_debug_vectors(desired_direction: Vector3, forward_velocity: Vector3, lateral_velocity: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if current_state == PlayerState.IDLE: return

	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var origin = global_position + Vector3(0, 2.0, 0)  # Nâng lên 2m để không bị lấp

	# 1. Tia XANH LÁ: hướng mong muốn
	m.surface_set_color(Color.GREEN);  m.surface_add_vertex(origin); m.surface_add_vertex(origin + desired_direction * 5.0)
	# 2. Tia XANH DƯƠNG: vận tốc tiến
	m.surface_set_color(Color.BLUE);   m.surface_add_vertex(origin); m.surface_add_vertex(origin + forward_velocity * 2.0)
	# 3. Tia ĐỎ: vận tốc ngang
	m.surface_set_color(Color.RED);    m.surface_add_vertex(origin); m.surface_add_vertex(origin + lateral_velocity * 2.0)

	m.surface_end()

# Hàm vẽ đường trajectory dự đoán
## points: mảng các điểm dự đoán
func draw_trajectory_line(points: PackedVector3Array) -> void:
	var m = trajectory_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if points.is_empty() or current_state == PlayerState.IDLE: return

	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		m.surface_add_vertex(Vector3(p.x, 1.0, p.z))  # Nâng lên 1m để không lấp nền
	m.surface_end()

# Hàm mô phỏng đường bay dự đoán
func calculate_predicted_path() -> PackedVector3Array:
	var path        := PackedVector3Array()
	var sim_position = global_position
	# Lý do đổi: velocity → linear_velocity
	# var sim_velocity = velocity         # Cũ
	var sim_velocity = linear_velocity    # Mới
	var target_pos   = current_target_position
	var sim_step     = 0.1   # Mỗi bước mô phỏng = 0.1 giây
	var max_steps    = 100   # Tối đa 100 bước = 10 giây tương lai

	path.append(sim_position)

	for i in range(max_steps):
		var dist = sim_position.distance_to(target_pos)
		if dist < 0.5: break

		var direction     = sim_position.direction_to(target_pos)
		var speed         = clamp(dist / braking_distance_factor, max_linear_speed / 10.0, max_linear_speed)
		var desired_vel   = direction * speed
		var steering      = desired_vel - sim_velocity

		if steering.length() > max_thrust_force:
			steering = steering.normalized() * max_thrust_force

		sim_velocity += (steering / mass) * sim_step
		sim_position += sim_velocity * sim_step

		if i % 2 == 0: path.append(sim_position)

	path.append(target_pos)
	return path

# Hàm vẽ đường nối các waypoint
func draw_waypoints_path() -> void:
	var m = waypoints_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	if current_target_position == Vector3.ZERO and ship_movement_waypoints.is_empty(): return

	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	m.surface_add_vertex(global_position + Vector3(0, 0.5, 0))  # Điểm bắt đầu: vị trí tàu

	if current_state == PlayerState.MOVE:
		m.surface_add_vertex(current_target_position + Vector3(0, 0.5, 0))  # Điểm đang bay tới

	for wp in ship_movement_waypoints:
		m.surface_add_vertex(wp.position + Vector3(0, 0.5, 0))  # Các waypoint còn lại trong hàng đợi

	m.surface_end()
