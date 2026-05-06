extends RigidBody3D

# ============================== EXPORT PARAMS ======================================

@export_group("Movement")
@export var linear_accel_time  := 5.0    # Thời gian đạt max_thrust_force từ đứng yên (s) và ngược lại
@export var max_thrust_force   := 100.0  # Lực đẩy tối đa (N) — tính toán lại trong _ready() dựa trên max_linear_speed, mass, linear_accel_time
@export var linear_damp_value  := 0.0    # Cản tịnh tiến — gán vào RigidBody3D.linear_damp khi _ready()
@export var arrival_radius     := 0.5    # Khoảng cách coi là đã đến đích (m)
@export var lateral_correction_ratio := 5.0   # Tỉ lệ lực dùng để triệt tiêu vận tốc ngang so với max_thrust_force
var power_to_mass_ratio := 0.0
var current_thrust_force	   := 0.0
var is_at_brake_distance := false
var auto_throttle := 0.0
var lateral_velocity := Vector3.ZERO
var forward_velocity := Vector3.ZERO
@onready var node_3d: Node3D = $Node3D
@export var engine_position := Vector3.ZERO
@export var roll_correction_torque := 40.0     # Lực kéo roll về 0 (N·m)
#@export var max_roll_angle         := 8.0      # Góc roll tối đa cho phép (độ) — nghiêng nhẹ cho đẹp
@export var max_roll_angle         := 15.0     # 1. Góc roll tối đa cho phép (độ) — (giới hạn 15 độ chống lật)
#@export var max_pitch_angle        := 45.0     # Góc pitch tối đa (độ)
@export var max_pitch_angle        := 30.0     # 2. Góc pitch tối đa (độ) — (giới hạn 30 độ chống chổng ngược)
@export var angular_damp_roll      := 3.0      # Damp angular_velocity trục Z (chống lắc roll)

@export_group("Rotation")
@export var angular_accel_time := 1.0    # Thời gian đạt max_angular_speed từ đứng yên (s)
@export var max_angular_speed  := 3.0    # Tốc độ góc tối đa (rad/s) — clamp để chống roll loạn
@export var rot_p              := 30.0   # P: lực kéo tỉ lệ với góc lệch
@export var rot_d              := 25.0   # D: lực hãm đà chống overshoot
@export var angular_damp_val   := 5.0    # Hệ số cản xoay thủ công (apply_torque)
@export var lateral_damp_val   := 5.0    # Hệ số cản vận tốc ngang (chống lắc, không block rotation)

# ============================== BIẾN INTERNAL ======================================

var target_position    := Vector3.ZERO
var has_target         := false
var distance_traveled  := 0.0           # Tổng quãng đường đã đi (m)
var last_position      := Vector3.ZERO   # Vị trí frame trước để tính delta distance

var debug_vector_mesh := MeshInstance3D.new()
var _waypoint_mesh : MeshInstance3D      # Visual marker cho target

@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"

# ============================== READY ======================================

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp   = linear_damp_value
	angular_damp  = 0.0   # Tắt engine angular_damp: script tự quản lý bằng apply_torque
	last_position = global_position
	power_to_mass_ratio = max_thrust_force / mass
	engine_position = node_3d.position
	
	# Setup cọ vẽ Debug Vector
	debug_vector_mesh.top_level = true # Tách khỏi hệ trục của tàu để vẽ tọa độ Global chuẩn xác
	var m = ImmediateMesh.new()
	debug_vector_mesh.mesh = m
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true # Cho phép vẽ nhiều màu trên 1 mesh
	mat.flags_unshaded = true # Sáng bất chấp bóng tối
	mat.no_depth_test = true # Nhìn xuyên tường/xuyên qua thân tàu
	debug_vector_mesh.material_override = mat
	add_child(debug_vector_mesh)
	
	_update_derived_params()
	_create_waypoint_marker()

func _update_derived_params() -> void:
	pass
	# F = m * v_max * (1/t + linear_damp)
	# Số hạng 1/t: lực gia tốc — số hạng linear_damp: lực thắng cản ở v_max
	# _max_thrust_force  = max_linear_speed * (1.0 / linear_accel_time + linear_damp_value) * mass
	# α = ω_max / t  →  đạt max_angular_speed sau angular_accel_time giây
	#_angular_accel_max = max_angular_speed / angular_accel_time
# ============================== INPUT ======================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		var from = camera.project_ray_origin(event.position)
		var dir  = camera.project_ray_normal(event.position)
		# Giao điểm tia với mặt phẳng ngang Y = vị trí ship
		if abs(dir.y) > 0.001:
			var t = (global_position.y - from.y) / dir.y
			target_position = from + dir * t
			target_position.y = 0
			has_target = true
			_waypoint_mesh.global_position = target_position
			_waypoint_mesh.visible = true

# ============================== PHYSICS ======================================

func _physics_process(delta: float) -> void:
	# Tích lũy quãng đường đã di chuyển
	distance_traveled += global_position.distance_to(last_position)
	last_position = global_position
	
	var direction := global_position.direction_to(target_position)

	if has_target:
		var distance = global_position.distance_to(target_position)

		if distance < arrival_radius:
			has_target = false
			#_waypoint_mesh.visible = false
		else:
			# 1. Đo lường phương hướng chuẩn đến mục tiêu bằng Vector3
			direction = global_position.direction_to(target_position)
			
			# --- CỐT LÕI KHÓA PITCH (MŨI TÀU) CHỐNG CHỔNG NGƯỢC ---
			# 1.1 Tính giới hạn của trục y tối đa (sin của max_pitch_angle = độ cao tối đa cho vector hướng)
			var max_dir_y = sin(deg_to_rad(max_pitch_angle))
			# 1.2 Cắt ép (clamp) gắt gao phương hướng chiều dọc Y không được ngóc/chúc lố 30 độ
			direction.y = clamp(direction.y, -max_dir_y, max_dir_y)
			# 1.3 Phải chuẩn hóa (normalize) lại vector sau khi ép Y để độ lớn lực đẩy luôn ở mức 1 (tránh bay yếu)
			direction = direction.normalized()
			
			# 1.4 Lúc này truyền direction đã khóa Pitch vào hàm xoay PID
			#rotate_toward_target(direction)

			# 2. Thrust chỉ khi mũi đã gần đúng hướng (alignment lớn hơn 0.85)
			# Thay vì 0.3 (hơi hẹp), ta tăng lên để tàu chỉ bay thẳng khi đã quay gần tới vị trí mong muốn, giảm tình trạng trượt thành đường cong.
			var heading = -global_transform.basis.z # Trục Z của tàu dướng về phía trước
			var alignment = heading.dot(direction) # Tính toán sự chênh lệch hướng (cosine)
			var braking_dist = (mass * pow(linear_velocity.length(), 2) * power_to_mass_ratio) / (2.0 * max_thrust_force) # Khoảng cách để phanh
			var ramp_speed = max_thrust_force / linear_accel_time * delta # Thời gian tăng tốc mượt
			
			if alignment > 0.85: # Chỉ tiến khi lệch góc khoảng dưới 31 độ (cos 0.85 \u2248 31\u00b0)
				auto_throttle = clamp(alignment, 0.0, 1.0)
				auto_throttle = pow(auto_throttle, 3) 
				ramp_speed = clamp(ramp_speed, -max_thrust_force, max_thrust_force)
				if distance > braking_dist:
					# max N force each delta, max after reach linear_accel_time
					current_thrust_force = move_toward(current_thrust_force, max_thrust_force, ramp_speed)
					apply_force(direction * current_thrust_force * auto_throttle, engine_position)
					is_at_brake_distance = false
				else:
					current_thrust_force = move_toward(current_thrust_force, 0.0, ramp_speed)
					var target_force = max_thrust_force * (distance / braking_dist) * power_to_mass_ratio
					var desired_force = target_force - current_thrust_force
					var steering_force = (desired_force * direction).limit_length(max_thrust_force)
					apply_force(steering_force, engine_position)
					is_at_brake_distance = true
				
				# Chống lắc sang 2 bên quá nhiều, ổn định để mũi ship hướng thẳng đến target
				## Tính độ lớn vận tốc đúng: speed(forward) = dot(v(current), direction(ship heading vector3))
				var forward_speed = linear_velocity.dot(heading)	# 1 số float, độ lớn vector
				## Tính vector vận tốc đúng: v(forward) = speed(forward) * direction(ship heading vector3)
				forward_velocity = heading * forward_speed	# Vector có hướng + độ lớn, để biết velocity theo mũi tàu đang lớn bao nhiêu
				
				# 5.2 Tính vận tốc ngang (vận tốc còn thừa ở hướng cũ so với hướng mới)
				## v(curent) = v(lateral) + v(forward) -> v(lateral) = v(current) - v(forward)
				lateral_velocity = linear_velocity - forward_velocity
				
				# Lực cần để triệt tiêu lateral_velocity trong 1 frame: F = mass * lateral_v / delta
				# Limit bằng lateral_correction_ratio * max_thrust để không chiếm hết thrust
				## a = F / mass → F = a * mass → F = (v / delta) * mass
				var cancel_force = (-lateral_velocity * max_thrust_force * lateral_correction_ratio)\
					.limit_length(max_thrust_force * lateral_correction_ratio)
				apply_central_force(cancel_force)
			
			else:
				auto_throttle = 0.0
				current_thrust_force = move_toward(current_thrust_force, 0, ramp_speed)
				# Phanh bằng full thrust ngược chiều velocity — không nhân mass (apply_central_force tự chia)
				apply_central_force(-linear_velocity * max_thrust_force * power_to_mass_ratio * 2.0)
	
	# Clamp angular velocity — chống roll loạn khi click nhanh đổi hướng
	if angular_velocity.length() > max_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_angular_speed

	# Damp toàn bộ angular velocity mọi frame — triệt tiêu quán tính xoay thừa
	# Không dùng apply_torque ở đây vì angular_damp_val đã có trong rotate_toward_target
	# Dùng engine angular_damp tạm thời bằng cách set trực tiếp (safe với RigidBody3D)
	#apply_torque(-angular_velocity * angular_damp_val)

	# Debug
	#apply_roll_correction()
	#apply_pitch_clamp()
	# global_transform.basis.orthonormalized()
	draw_debug_vectors(direction, forward_velocity, lateral_velocity, linear_velocity)
	
	rich_text_label.text = \
		"\nP to M ratio  : " + str(snappedf(power_to_mass_ratio, 0.01)) + \
		"\nLinear velocity  : " + str(snappedf(linear_velocity.length(), 0.01)) + " m/s" + \
		"\nAngular velocity : " + str(snappedf(angular_velocity.length(), 0.001)) + " rad/s" + \
		"\nlateral_velocity     : " + str(lateral_velocity) + " N" + \
		"\nThrust force     : " + str(snappedf(max_thrust_force, 0.1)) + " N" + \
		"\nCurrent thrust force     : " + str(snappedf(current_thrust_force, 0.1)) + " N" + \
		"\nAuto thrust: " + str(snappedf(auto_throttle, 0.01)) + "" + \
		"\nMass             : " + str(mass) + " kg" + \
		"\nHas target       : " + str(has_target) + \
		"\nAt brake distance       : " + str(is_at_brake_distance) + \
		"\nDistance: " + str(global_position.distance_to(target_position)) + \
		"\nBrake distance: " + str((mass * pow(linear_velocity.length(), 2) * power_to_mass_ratio) / (2.0 * max_thrust_force)) + \
		"\nDistance traveled: " + str(snappedf(distance_traveled, 0.01)) + " m"

# Xoay mũi ship về hướng desired_dir bằng PD torque
func rotate_toward_target(desired_dir: Vector3) -> void:
	var heading = -global_transform.basis.z   # Hướng mũi tàu hiện tại
	var cross   = heading.cross(desired_dir)  # Trục xoay

	# Tránh trường hợp đã thẳng hàng (cross gần như 0) nhưng hướng ngược nhau (dot < 0) → chọn trục xoay mặc định để quay 180°
	if cross.length_squared() < 0.0001:
		if heading.dot(desired_dir) < -0.9:
			cross = Vector3.UP   # 180°: ép xoay theo Y
		else:
			# Đã thẳng: damp bằng angular_damp_val (không dùng max_thrust*ratio)
			apply_torque(-angular_velocity * angular_damp_val)
			return

	var rotation_axis = cross.normalized()
	var angle_error   = heading.angle_to(desired_dir)

	# PD: accel tính bằng N·m thuần — không nhân F²/mass
	var p_term = rot_p * angle_error
	var d_term = rot_d * angular_velocity.dot(rotation_axis)
	var accel  = clamp(p_term - d_term, -rot_p, rot_p)
	apply_torque(rotation_axis * accel * 10.0)
	
# -----------------------  DEBUG VISUAL ------------------------------
# Hàm vẽ 3 tia Vector trực quan gồm tia target, tia forward và tia lateral
func draw_debug_vectors(desired_direction: Vector3, forward_velocity: Vector3, lateral_velocity: Vector3, linear_velocity: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Dời tâm vẽ lên cao 2 mét so với gốc tọa độ tàu để không bị lấp dưới gầm tàu
	var origin = global_position + Vector3(0, 2.0, 0) 
	
	# 1. Tia XANH LÁ: Hướng mong muốn (Vẽ cố định dài 5m cho dễ nhìn)
	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(origin + desired_direction * 5.0)
	
	# 2. Tia XANH DƯƠNG: Vận tốc tiến tới (Forward Velocity)
	m.surface_set_color(Color.BLUE)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.BLUE)
	m.surface_add_vertex(origin + forward_velocity * 2)
	
	# 3. Tia ĐỎ: Vận tốc trượt ngang (Lateral Velocity)
	m.surface_set_color(Color.RED)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.RED)
	m.surface_add_vertex(origin + lateral_velocity * 2)
	
	# 4. Tia tim: Linear velocity
	m.surface_set_color(Color.PURPLE)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.PURPLE)
	m.surface_add_vertex(origin + linear_velocity * 2)
	
	m.surface_end()

# 3. Giữ roll gần 0 — Xử lý triệt để hiện tượng xoắn ốc (vặn tàu) không hãm được
func apply_roll_correction() -> void:
	var ship_up    = global_transform.basis.y # Hướng lên của tàu (Y local)
	var roll_error = ship_up.cross(Vector3.UP)          # Vector thể hiện độ lệch roll (lấy cross product với Vector3.UP)
	var roll_axis  = global_transform.basis.z            # Trục Z local = trục roll
	var roll_dot   = roll_error.dot(roll_axis)           # Độ lớn + chiều lệch roll
	
	# Tính góc roll hiện tại (radian)
	var roll_angle = abs(asin(clamp(roll_dot, -1.0, 1.0))) # Đảm bảo biên độ hợp lệ (-1..1) 
	var max_roll_rad = deg_to_rad(max_roll_angle) # Giới hạn góc roll (radian)
	
	# 4. Bỏ qua threshold (ngưỡng chết max_roll_rad) -> luôn apply torque để kéo roll chuẩn 100%
	# Lý do đổi: Nếu dùng `if roll_angle > max_roll_rad`, tàu sẽ lắc qua lại tự do giữa khoảng -15 đến 15 độ, sinh ra dao động vặn xoắn liên hồi. Kéo trực tiếp sẽ mượt nhất.
	# if roll_angle > max_roll_rad:
	# 	var excess = roll_dot * (1.0 - max_roll_rad / max(roll_angle, 0.001)) # Lượng lực xoay vượt mức
	# 	apply_torque(roll_axis * excess * roll_correction_torque) # Apply xoay ngược lại
	
	apply_torque(roll_axis * roll_dot * roll_correction_torque * 2.0) # Nhân 2 lực để dứt khoát khóa đứng thăng bằng
	
	# 5. Nếu tàu bị lật úp ngược do click nhiều lần, cưỡng chế đẩy upright thật cực đoan:
	if ship_up.dot(Vector3.UP) < 0.0:
		# Tàu đang chúc ngược (upside down), apply lực theo roll cực mạnh gấp 10 để kéo nó bật lại khẩn cấp
		apply_torque(roll_axis * sign(roll_dot) * roll_correction_torque * 10.0)

	# 6. Damp angular velocity theo trục Z để tắt rung lắc roll
	apply_torque(-angular_velocity.project(roll_axis) * angular_damp_roll) # Giảm xóc vận tốc góc trục Z

# 1. Giới hạn góc pitch tối đa ±max_pitch_angle để chống ngóc/chúc mũi quá mức (chống chổng ngược)
func apply_pitch_clamp() -> void:
	# 2. Tính góc pitch hiện tại: góc giữa vector tiến (Z local âm) và mặt phẳng XZ toàn cục
	var pitch     = asin(clamp(-global_transform.basis.z.y, -1.0, 1.0)) # Tính sin của góc dốc 
	var max_rad   = deg_to_rad(max_pitch_angle) # Quy đổi giới hạn góc độ ra radian
	
	# 3. Kiểm tra xem hướng mũi đang vượt ngưỡng cho phép hay không
	if abs(pitch) > max_rad:
		var pitch_axis  = global_transform.basis.x          # Trục X local = trục pitch, để xoay mũi lên/xuống
		var pitch_error = pitch - sign(pitch) * max_rad     # Độ vượt quá giới hạn bằng radian (lệch bao nhiêu)
		
		# 4. Khi tàu đã vượt qua 90 độ (bắt đầu ngửa bụng dọc Z), góc pitch sẽ giảm ngược lại và tính sai lệch:
		# Áp dụng lực gia tốc xoay khôi phục giống roll nếu pitch sai nặng.
		var forced_correction = 1.0
		if global_transform.basis.y.dot(Vector3.UP) < 0.0:  # Đang chổng ngược hoàn toàn
			forced_correction = 5.0 # Nhân 5 lần lực chống chổng ngược
			
		# 5. Apply xoay (Torque) đưa góc pitch về ngưỡng an toàn, triệt tiêu độ chênh
		apply_torque(-pitch_axis * pitch_error * roll_correction_torque * forced_correction)

func _create_waypoint_marker() -> void:
	_waypoint_mesh = MeshInstance3D.new()
	var sphere       = SphereMesh.new()
	sphere.radius    = 0.3
	sphere.height    = 0.6
	_waypoint_mesh.mesh = sphere
	# Vật liệu phát sáng màu vàng
	var mat                    = StandardMaterial3D.new()
	mat.albedo_color           = Color(0.145, 0.851, 0.102, 1.0)
	mat.emission_enabled       = true
	mat.emission               = Color(0.556, 0.961, 0.708, 1.0)
	mat.emission_energy_multiplier = 2.0
	_waypoint_mesh.material_override = mat
	_waypoint_mesh.visible     = false
	get_parent().call_deferred("add_child", _waypoint_mesh)
