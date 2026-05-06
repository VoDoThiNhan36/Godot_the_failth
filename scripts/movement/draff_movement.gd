extends CharacterBody3D

# --- Các thuộc tính có thể tùy chỉnh trong Inspector ---
@export_group("Steering Behavior")
@export var max_linear_speed := 15.0      	# Tốc độ tối đa khi đi thẳng
@export var max_thrust_force := 10.0      	# Lực đẩy tối đa động cơ chính
@export var max_brake_force := 5.0			# Lực hãm phanh động cơ tối đa
@export var mass := 10.0            		# Khối lượng tàu 
@export var braking_distance_factor := 0.5  # Khoảng cách bắt đầu hãm phanh
@export var distance_threshold := 0.2		# Khoảng cách bắt đầu giảm tốc và chuyển đổi xoay
@export var lateral_friction := 5.0 		# Lực bám ngang, càng cao chống trượt khi xoay càng tốt
@export var auto_throttle := 0.0			# Gas tự động, giảm/tăng theo điều kiện, và có thể dùng để manuver always max engine

@export_group("Rotation Physics")
@export var angular_acceleration := 8.0 	# Sức mạnh của động cơ xoay (Torque) càng lớn thì bắt đầu xoay càng nhanh
@export var angular_damping := 1.0       	# Lực hãm xoay (Nếu không có, tàu sẽ lắc lư qua lại mãi mãi) càng lớn càng giảm lắc lư nhanh
@export var angular_braking := 6.0       	# Sức mạnh phanh xoay (Hãm đà / Đảo chiều)
@export var max_turn_speed := 1.0       	# Tốc độ xoay tối đa (rad/s)
@export var turn_sensitivity := 3.0			# Độ nhạy vô lăng
var angular_velocity := 0.0			        # Biến lưu trữ "Đà xoay" hiện tại

@export_group("Fajen Dynamical Steering")
@export var fajen_detection_radius := 35.0
@export var fajen_max_obstacles := 15
@export var fajen_kg := 12.0
@export var fajen_ko := 200.0
@export var fajen_b := 4.2
@export var fajen_c4 := 0.2
@export var fajen_noise := 0.2
var nearby_obstacles: Array[Node3D] = []
var fajen_angular_velocity := Vector2.ZERO        # Biến lưu trữ "Đà xoay" hiện tại theo cả 2 trục (Momentum)

# --- Các biến lưu trữ trạng thái ---
enum PlayerState { IDLE, MOVE}
enum ShipSteeringMode {CONTEXT, FAJEN_WARREN}
var current_state: PlayerState = PlayerState.IDLE
@export var current_steering_mode = ShipSteeringMode.FAJEN_WARREN # Set ship steering method to FAJEN sterring default

# --- Các biến lưu trữ movement
var current_target_position := Vector3.ZERO	# Vị trí hiện tại của target
var current_target_direction := Vector3.RIGHT	# Hướng từ vị trí ship đến hướng hiện tại
var current_target_height_offset := 0.0
var ship_movement_waypoints : Array[Movement_Waypoint] = []	# Danh sách các target theo thứ tự cần di chuyển
var current_waypoint : Movement_Waypoint = null	 # Target point hiện tại trong list waypoints
var is_at_current_waypoint_threshold := false
var ship_length: float

# --- Tham chiếu đến các node con ---
@onready var ship_part: CharacterBody3D = $"."
@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"

# --- Biến dùng để vẽ Debug Vector ---
@export_group("Mesh Debug")
var debug_vector_mesh := MeshInstance3D.new()
var trajectory_mesh := MeshInstance3D.new()
var waypoints_mesh := MeshInstance3D.new()
@export var show_debug := false

#----------------------------------------- DEFAULT FUNCTION ------------------------------------------
#init debug
func _init() -> void:
	pass

func _ready() -> void:
	# Tính độ dài của ship
	var ship = ship_part.get_child(0) as Node3D
	var mesh = ship.get_child(0) as MeshInstance3D
	ship_length = mesh.get_aabb().size.x	# Ship mặc định nằm hướng X, khi vào scene đã chỉnh -90 sang -Z
	
	# Set up fajen steering
	setup_fajen_area()
	
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
	# Setup cọ vẽ đường dự đoán (Trajectory)
	trajectory_mesh.top_level = true
	var tm = ImmediateMesh.new()
	trajectory_mesh.mesh = tm
	var t_mat = StandardMaterial3D.new()
	t_mat.albedo_color = Color.GREEN # Màu vàng cho dễ nhìn
	t_mat.flags_unshaded = true
	t_mat.no_depth_test = true
	trajectory_mesh.material_override = t_mat
	add_child(trajectory_mesh)
	# Setup cọ vẽ lộ trình Waypoints
	waypoints_mesh.top_level = true
	var pm = ImmediateMesh.new()
	waypoints_mesh.mesh = pm
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color.PLUM # Màu xanh lơ cho lộ trình cố định
	p_mat.flags_unshaded = true
	p_mat.no_depth_test = true
	waypoints_mesh.material_override = p_mat
	add_child(waypoints_mesh)
	
# --- Hàm xử lý input chưa được xử lý ---
func _unhandled_input(event: InputEvent) -> void:
	# Input event cho thay đổi độ cao waypoint bằng chuột
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset = 2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -2.0
			# Giới hạn trần bay / đáy bay để không lăn chuột quá tay
			current_target_height_offset = clamp(current_target_height_offset + offset, -45.0, 45.0)
		
			# Thay đổi độ cao nếu đang giữ phím nối waypoint
			# Trường hợp 1: Chỉnh độ cao của waypoint cuối cùng trong hàng đợi
			if Input.is_action_pressed("sequence_move"):
				if not ship_movement_waypoints.is_empty():
					var last_waypoint = ship_movement_waypoints.back()
					# Tìm điểm cuối cùng trong waypoints
					var prev_position: Vector3
					# Có nhiều điểm waypoint
					if ship_movement_waypoints.size() > 1:
						prev_position = ship_movement_waypoints[ship_movement_waypoints.size() - 2].position
					else:
						# Nếu chỉ có 1 waypoint dự phòng, điểm trước nó là điểm đang bay tới hiện tại
						prev_position = current_target_position if current_state == PlayerState.MOVE else global_position
					# Tính khoảng cách mặt phẳng ngang (XZ)
					var dist_xz = Vector2(last_waypoint.position.x, last_waypoint.position.z).distance_to(Vector2(prev_position.x, prev_position.z))
					
					# Giới hạn độ cao: Delta Y tối đa = dist_xz (Tương đương góc 45 độ)
					# Tam giác vuông cân, y và distance bằng nhau bên cạnh huyền = 45 độ
					var min_y = prev_position.y - dist_xz
					var max_y = prev_position.y + dist_xz
					
					# Cập nhật Y mới với giới hạn Clamp
					var new_y = clamp(last_waypoint.position.y + offset, min_y, max_y)
					
					# Cập nhật độ cao vào last waypoint
					last_waypoint.position.y = new_y
					if is_instance_valid(last_waypoint.point_marker): last_waypoint.point_marker.global_position.y = new_y
					
				# Trường hợp 2: Nếu đang di chuyển + 1 waypoint thì thay độ cao wwaypoint hiện tại
				elif current_state == PlayerState.MOVE:
					var prev_position = global_position
					var dist_xz = Vector2(current_target_position.x, current_target_position.z).distance_to(Vector2(prev_position.x, prev_position.z))
					
					var min_y = prev_position.y - dist_xz
					var max_y = prev_position.y + dist_xz
					
					var new_y = clamp(current_target_position.y + offset, min_y, max_y)
					
					# Đổi độ cao của target hiện tại
					current_target_position.y = new_y
					# Đổi luôn độ cao của waypont marker
					if current_waypoint and is_instance_valid(current_waypoint.point_marker):
						current_waypoint.position.y = new_y
						current_waypoint.point_marker.global_position.y = new_y
				

# --- Hàm xử lý vật lý chính ---
func _physics_process(delta: float) -> void:
	# -----------------State machine -----------------
	match current_state:
		PlayerState.IDLE: handle_state_idle(delta)
		PlayerState.MOVE: handle_state_move(delta)
	
	# Debug mesh
	draw_waypoints_path()
	
	rich_text_label.text =\
	"\nShip length: " + str(ship_length) +\
	"\nAngular velocity: " + str(angular_velocity) +\
	"\nThrottle: " + str(auto_throttle) +\
	"\nVelocity: " + str(velocity.length()) +\
	"\nCurrent target position: " + str(current_target_position) +\
	"\nCurrent target direction: " + str(current_target_direction) +\
	"\nCurrent_target_height_offset: " + str(current_target_height_offset) +\
	"\nIs at current target threshold: " + str(is_at_current_waypoint_threshold) +\
	"\nCurent dir: " + str(-global_transform.basis.z) +\
	"\nObstacles count: " + str(nearby_obstacles.size()) +\
	"\nWaypoints count: " + str(ship_movement_waypoints.size())
	
	
	#move_and_slide()
# --- Các hàm callback của Godot ---
	
#----------------------------------------- CUSTOM FUNCTION ------------------------------------------

# ----------------------- STEERING --------------------------------
func setup_fajen_area() -> void:
	var avoidance_area = Area3D.new()
	avoidance_area.name = "FajenAvoidanceArea"
	add_child(avoidance_area)
	
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = fajen_detection_radius
	col_shape.shape = sphere
	avoidance_area.add_child(col_shape)
	
	# Collision mask: chỉ detect obstacle layer (bạn tự set layer phù hợp)
	avoidance_area.collision_mask = 1   # ví dụ layer 4 là obstacle, chỉnh theo project của bạn
	
	avoidance_area.body_entered.connect(_on_fajen_body_entered)
	avoidance_area.body_exited.connect(_on_fajen_body_exited)

func _on_fajen_body_entered(body: Node3D) -> void:
	if body != self and not nearby_obstacles.has(body):
		nearby_obstacles.append(body)

func _on_fajen_body_exited(body: Node3D) -> void:
	nearby_obstacles.erase(body)

# Hàm fajen & warren steering - trả về phi_double_dot (Gia tốc bẻ lái) thay vì Vector3
## Formula: phi_double_dot = -b * phi_dot - kg * (phi - psi_g) * (exp(-c1 * dg) + c2) + sum( ko * (phi - psi_o) * exp(-c3 * abs(phi - psi_o)) * exp(-c4 * do) 
## Giải thích tham số:
# phi_double_dot : Gia tốc góc (kết quả đầu ra)
# phi_dot        : Vận tốc góc hiện tại (angular velocity)
# b              : Hệ số giảm chấn (damping coefficient)
# kg, ko         : Hệ số tăng cường cho mục tiêu (goal) và vật cản (obstacle)
# phi            : Hướng hiện tại của vật thể (radians)
# psi_g, psi_o   : Hướng của mục tiêu và hướng của vật cản (radians)
# dg, do         : Khoảng cách tới mục tiêu và khoảng cách tới vật cản
# c1, c2, c3, c4 : Các hằng số điều chỉnh độ nhạy của hàm mũ (decay constants)
# exp(x)         : Hàm mũ e^x
## Ý nghĩa cụm:
# (exp(-c1 * dg) + c2): Suy giảm theo khoảng cách tới target, càng gần càng lớn
# exp(-c3 * abs(phi - psi_o)): Tăng theo góc nhìn tới obstacle, càng chính diện lực đẩy càng lớn
# exp(-c4 * do): Suy giảm theo khoảng cách tới obstacle, càng xa lực đẩy càng nhỏ
func compute_fajen_angular_acceleration(ship_heading_vector: Vector3, target_direction: Vector3, current_angular_velocity: Vector2) -> Dictionary:
	var space_state = get_world_3d().direct_space_state		# Default
	
	# Tính góc Yaw (Trái/Phải) và Pitch (Lên/Xuống) của tàu (theo ship z forward)
	var current_phi_yaw: float = atan2(ship_heading_vector.x, ship_heading_vector.z)
	var current_phi_pitch: float = atan2(ship_heading_vector.y, sqrt(ship_heading_vector.x*ship_heading_vector.x + ship_heading_vector.z*ship_heading_vector.z))
	
	# Tính góc Yaw và Pitch của mục tiêu (theo ship z forward)
	var goal_phi_yaw: float = atan2(target_direction.x, target_direction.z)
	var goal_phi_pitch: float = atan2(target_direction.y, sqrt(target_direction.x*target_direction.x + target_direction.z*target_direction.z))
	
	# Tính khoảng cách tới mục tiêu, cho giá trị default 0.5 để tránh chia cho 0
	var distance_to_goal: float = max(0.5, global_position.distance_to(current_target_position)) # Tính khoảng cách giữa ship và target
	
	## Damping (Lực cản vô lăng hiện tại)
	## -b * phi_dot
	var phi_double_dot_yaw: float = -fajen_b * current_angular_velocity.y
	var phi_double_dot_pitch: float = -fajen_b * current_angular_velocity.x
	
	## Goal error (góc lệch giữa ship và target): (phi - psi_g)
	var goal_error_yaw: float = current_phi_yaw - goal_phi_yaw
	var goal_error_pitch: float = current_phi_pitch - goal_phi_pitch
	## Tính sang góc nhỏ nhất giữa ship và target
	## fposmod dùng +- PI để giới hạn +-180 độ
	goal_error_yaw = fposmod(goal_error_yaw + PI, TAU) - PI	
	goal_error_pitch = fposmod(goal_error_pitch + PI, TAU) - PI	
	
	## Tính trọng số theo khoảng cách: kg * (phi - psi_g) * (exp(-c1 * dg) + c2)
	## c1 và c2 là các hằng số 0.4 
	## (exp(-0.4 * d_goal) + 0.4) càng về gần target thì càng gần bằng 1, lực hút tới target càng lớn
	var goal_term_yaw: float = fajen_kg * goal_error_yaw * (exp(-0.4 * distance_to_goal) + 0.4)
	var goal_term_pitch: float = fajen_kg * goal_error_pitch * (exp(-0.4 * distance_to_goal) + 0.4)
	
	## Tính thêm vào phi double dot
	phi_double_dot_yaw -= goal_term_yaw
	phi_double_dot_pitch -= goal_term_pitch
	
	var total_repulsion := 0.0 # Biến cộng dồn lực đẩy để tính chân ga (Throttle)
	
	## Tính lực đẩy bbstacle repellers
	## sum( ko * (phi - psi_o) * exp(-c3 * abs(phi - psi_o)) * exp(-c4 * do)
	var count: int = 0	# Check số lượng vật thể, lượng tính toán không vượt quá config để hiệu năng
	for obstacle in nearby_obstacles:
		# Break khi đã đủ số lượng
		if count >= fajen_max_obstacles: break
		# Vị trí của obstacle
		var obs_position = obstacle.global_position
		
		# Tính thể tích cho obstacle (temp dùng raycast)
		var query = PhysicsRayQueryParameters3D.create(global_position, obs_position)
		query.exclude = [self.get_rid()]
		# query.collision_mask = 4294967295 # Layer các vật thể cần tính như obstacle
		var result = space_state.intersect_ray(query)
		
		var hit_position = obs_position	# Vị trí va chạm
		var obs_radius = 1.0 # Mặc định obstacle 1 mét
		
		# Result sẽ luôn luôn có vì obstacle đã được load sẵn vào list
		if result:
			hit_position = result.position
			## R = hit position - origin
			obs_radius = max(1.0, hit_position.distance_to(obs_position)) 
		else:
			hit_position = obs_position
			
		# Tính khoảng cách từ vị trí ship đến obstacle(bề mặt thay vì là tâm)
		var distance_to_obstacle = global_position.distance_to(hit_position) 
		if distance_to_obstacle > fajen_detection_radius or distance_to_obstacle < 0.1: continue
		
		## Tính hướng từ ship đến obstacle: do
		var direction_to_obs = (hit_position - global_position).normalized()
		# Loại bỏ các obstacle có hướng nằm xa phía sau
		if ship_heading_vector.dot(direction_to_obs) < -0.25: continue
		
		## Tính góc lệch của obstacle so với Z FORWARD
		var obs_phi_yaw = atan2(direction_to_obs.x, direction_to_obs.z)
		var obs_phi_pitch = atan2(direction_to_obs.y, sqrt(direction_to_obs.x*direction_to_obs.x + direction_to_obs.z*direction_to_obs.z))
		## Tính góc lệch giữa ship và obstacle: (phi - psi_o)
		var obs_error_yaw = current_phi_yaw - obs_phi_yaw
		var obs_error_pitch = current_phi_pitch - obs_phi_pitch
		# Tính sang góc nhỏ nhất giữa ship và target
		obs_error_yaw = fposmod(obs_error_yaw + PI, TAU) - PI
		obs_error_pitch = fposmod(obs_error_pitch + PI, TAU) - PI
		
		## Tính tham số ko, thêm ảnh hưởng của kích thước obstacle vào
		var dynamic_ko = fajen_ko * (1.0 + sqrt(obs_radius))
		
		## Tổng hợp lực đẩy của obstacle
		## Hằng số c3 là 6.0
		var obs_term_yaw = dynamic_ko * obs_error_yaw * exp(-6.0 * abs(obs_error_yaw)) * exp(-fajen_c4 * distance_to_obstacle)
		var obs_term_pitch = dynamic_ko * obs_error_pitch * exp(-6.0 * abs(obs_error_pitch)) * exp(-fajen_c4 * distance_to_obstacle)
		
		# Tính lại phi double dot
		phi_double_dot_yaw += obs_term_yaw
		phi_double_dot_pitch += obs_term_pitch
		
		# Lưu lại độ lớn lực đẩy để lát bóp phanh
		total_repulsion += Vector2(obs_term_yaw, obs_term_pitch).length()
		count += 1
	
	## Noise nhỏ chống deadlock
	if count > 0 and current_angular_velocity.length() < 0.1 and Vector2(phi_double_dot_pitch, phi_double_dot_yaw).length() < 0.1:
		phi_double_dot_yaw += randf_range(-fajen_noise, fajen_noise)
		phi_double_dot_pitch += randf_range(-fajen_noise, fajen_noise)
		
	return {
		"angular_accel": Vector2(phi_double_dot_pitch, phi_double_dot_yaw), # x là pitch, y là yaw,
		"repulsion_force": total_repulsion
	}

# ---------------------- WAYPOINT + ADD MOVE -----------------------
# Hàm chuyển đổi state sang MOVE để di chuyển đến vị trí mới
func move_to(new_position: Vector3, is_sequence: bool = false) -> void:
	# Check, nếu không phải nối waypoint thì clear hết waypoint hiện tại
	if not is_sequence:
		clear_all_waypoints()
	
	# 1. Cộng thêm độ cao lăn chuột vào vị trí click
	new_position.y += current_target_height_offset
	# Lưu lại hướng chuẩn ngay lúc click chuột
	var target_position = new_position
	var previous_position: Vector3
	var new_waypoint: Movement_Waypoint = null
	# Kiểm tra xem state hiện tại
	if current_state == PlayerState.MOVE:
		# Nếu đang MOVE và list empty thì previous position là vị trí target hiện tại
		if ship_movement_waypoints.is_empty():
			previous_position = current_target_position
		# Nếu list còn waypoint thì lấy previous position = position sau cùng
		else:
			previous_position = ship_movement_waypoints.back().position
	# Nếu state không phải MOVE thì lấy luôn global position của ship
	else:
		previous_position =global_position
	
	# Thêm vào list waypoint
	new_waypoint = Movement_Waypoint.new(target_position, previous_position)
	add_child(new_waypoint.point_marker)	# add waypoint visual
	ship_movement_waypoints.append(new_waypoint)
	
	# Load waypoint để chạy lần đầu
	if current_state != PlayerState.MOVE or not is_sequence:
		load_next_waypoint()
	
	# Đổi state
	change_state(PlayerState.MOVE)

# Hàm clear all waypoints
func clear_all_waypoints() -> void:
	for wp in ship_movement_waypoints:
		if is_instance_valid(wp.point_marker): wp.point_marker.queue_free()
	ship_movement_waypoints.clear()
	
	if current_waypoint and is_instance_valid(current_waypoint.point_marker):
		current_waypoint.point_marker.queue_free()
	current_waypoint = null

# Hàm load next waypoint
func load_next_waypoint():	
	if ship_movement_waypoints.size() > 0:
		# Xóa marker hiện tại
		if current_waypoint: current_waypoint.point_marker.queue_free()
		# Gán current way point
		var next_target_movement = ship_movement_waypoints.pop_front()
		current_waypoint = next_target_movement
		#add_child(current_waypoint.point_marker)
		current_target_position = next_target_movement.position
		current_target_direction = next_target_movement.direction
		# Giảm angular velocity để bẻ cua nhanh qua các way point
		angular_velocity *= 0.5
	else:
		return

# ---------------------- STATE MACHINE FUNCTION ---------------------
func change_state(new_state: PlayerState) -> void:
	if current_state == new_state:
		return
	
	# Reset các thuộc tính khi chuyển trạng thái (nếu cần)
	match new_state:
		PlayerState.IDLE:
			pass
		PlayerState.MOVE:
			pass
			
	current_state = new_state
	print("State changed to: ", current_state)

func handle_state_idle(delta: float) -> void:
	# Ép tàu dừng hẳn
	velocity = velocity.move_toward(Vector3.ZERO, (max_brake_force / mass) * delta)
	auto_stable_ship_indie_state(delta)
	move_and_slide()

func handle_state_move(delta: float) -> void:
	# Set các biến tính vị trí
	#var current_position = Vector3(global_position.x, 0, global_position.z)	# Vị trí ship hiện tại
	#var target_position = Vector3(current_target_position.x, 0, current_target_position.z)	# Vị trí cần tới
	var current_position = global_position	# Vị trí ship hiện tại
	var target_position = current_target_position	# Vị trí cần tới
	var distance = current_position.distance_to(target_position)	# Khoảng cách giữa 2 vị trí
	## Tính quãng đường cần thiết để bắt đầu giảm tốc theo max brake force 
	## s = v^2 / 2*a
	var min_stopping_distance = pow(velocity.length(), 2) / (2.0 * max_brake_force / mass)
	
	# Set các biến tính direction
	var ship_heading_vector = -global_transform.basis.z # Hướng mũi tàu (default đang -Z)
	var direction_to_target = current_position.direction_to(target_position)
	var desired_direction: Vector3	# Hướng di chuyển smooth
	var raw_direction: Vector3 # Hướng di chuyển thẳng
	var danger_throttle_factor = 1.0 # Biến hứng giá trị phanh của radar

	# Định nghĩa khoảng cách bắt đầu nội suy (pha trộn) hướng
	var rotation_blend_distance = distance_threshold * 2
	
	# Gán hướng dựa trên blend distance
	# Ở xa: Hoàn toàn hướng về target
	if distance > rotation_blend_distance:
		is_at_current_waypoint_threshold = false
		raw_direction = direction_to_target
	# Khoảng cách chạm ngưỡng cần dừng và quay hướng
	elif distance > distance_threshold:
		# Tránh trường hợp ship bị lặp vô tận khi đổi target direction liên tục ở điểm giữa
		if not is_at_current_waypoint_threshold:
			# Vào vùng blend: Tính tỷ lệ từ 0.0 đến 1.0
			# distance = 3.2 (rìa ngoài) -> weight = 1.0 (hướng 100% về target)
			# distance = 0.2 (tới đích) -> weight = 0.0 (hướng 100% theo current_target_direction)
			var blend_weight = (distance - distance_threshold) / rotation_blend_distance
			blend_weight = clamp(blend_weight, 0.8, 1.0)
			
			# Slerp giữa hướng đích đến và hướng click chuột ban đầu
			raw_direction = current_target_direction.slerp(direction_to_target, blend_weight).normalized()
	# Khoảng cách chạm đích
	else:
		is_at_current_waypoint_threshold = true
		raw_direction = current_target_direction
	
	# Tính desired direction theo thuật toán steering khi distance còn xa
	if distance > ship_length * 5.0:
		# Gán default desired direction theo raw
		desired_direction = raw_direction

		## Steering theo thuật toán Fajen - Angular steering
		if current_steering_mode == ShipSteeringMode.FAJEN_WARREN:
			var fajen_result = compute_fajen_angular_acceleration(ship_heading_vector, raw_direction, fajen_angular_velocity)
			var raw_fajen_accel: Vector2 = fajen_result["angular_accel"]
			var total_repulsion = fajen_result["repulsion_force"]
			
			# =========================================================
			# 1. ĐỒNG BỘ VỚI ĐỘNG CƠ XOAY (Torque Sync)
			# =========================================================
			# Tính gia tốc góc tối đa mà động cơ có thể tạo ra (a = F/m)
			var max_engine_accel = angular_acceleration / mass
			
			# Ép lực Fajen không được vượt quá sức mạnh động cơ
			var applied_accel_pitch = clamp(raw_fajen_accel.x, -max_engine_accel, max_engine_accel)
			var applied_accel_yaw = clamp(raw_fajen_accel.y, -max_engine_accel, max_engine_accel)
			
			# Áp dụng gia tốc vào đà xoay hiện tại (cộng thêm lực hãm tự nhiên của tàu)
			fajen_angular_velocity.x += applied_accel_pitch * delta
			fajen_angular_velocity.y += applied_accel_yaw * delta
			fajen_angular_velocity = fajen_angular_velocity.lerp(Vector2.ZERO, angular_damping * delta)
			
			# Không vượt quá tốc độ xoay tối đa của vô lăng
			if fajen_angular_velocity.length() > max_turn_speed:
				fajen_angular_velocity = fajen_angular_velocity.normalized() * max_turn_speed
			
			# =========================================================
			# 2. ĐỒNG BỘ VỚI CHÂN GA TỊNH TIẾN (Throttle Sync)
			# =========================================================
			# Nếu tàu đang bị đẩy ra rất mạnh (chuẩn bị đụng đá to), ép giảm ga lại!
			# Giả sử lực repulsion > 5.0 là bắt đầu nguy hiểm
			if total_repulsion > 5.0:
				# Lực đẩy càng cao, throttle càng tụt về 0.1
				danger_throttle_factor = clamp(1.0 - (total_repulsion / 50.0), 0.1, 1.0)
			else:
				danger_throttle_factor = 1.0
				
			# Xoay tàu
			# ÁP DỤNG XOAY 3D: Yaw trước (trục Y toàn cục), Pitch sau (trục X cục bộ)
			global_rotate(Vector3.UP, fajen_angular_velocity.y * delta)
			var local_right = global_transform.basis.x.normalized()
			global_rotate(local_right, fajen_angular_velocity.x * delta)
			global_transform.basis = global_transform.basis.orthonormalized()
	
	# Khoảng cách gần target, không dùng steering mà dùng manual
	else:
		desired_direction = raw_direction
		update_character_rotation(delta, ship_heading_vector, desired_direction, distance, min_stopping_distance)
	
	# Tính heading aligment theo desired direction
	var heading_alignment = ship_heading_vector.dot(desired_direction)	# Độ chuẩn xác cảu mũi tàu so với hướng tới
	
	# Kiểm tra, nếu tàu đã sát đích thì chuyển state, không cần di chuyển nữa
	# Tuy nhiên, nếu còn waypoint thì sẽ duy trì tốc độ và cắt góc rộng hơn
	var waypoint_switch_distance = distance_threshold / 2.0
	if ship_movement_waypoints.size() > 0:
		waypoint_switch_distance = max_linear_speed * 0.5 # Ví dụ: Đang chạy nhanh thì cách 7.5m đã rẽ rồi
		
	if distance < waypoint_switch_distance:
		if ship_movement_waypoints.size() > 0:
			load_next_waypoint()
		
		else:
			# Phanh tịnh tiến thật nhanh
			velocity = velocity.move_toward(Vector3.ZERO, max_brake_force * delta * 0.1)
		
			# Dừng ship khi đã xoay đúng
			if velocity.length() < 0.1 and heading_alignment >= 0.999:
				# Reset quán tính và đổi state
				auto_throttle = 0.0
				#change_state(PlayerState.IDLE)
				#return # Chặn sớm, không tính toán bên dưới nữa

	# =========================================================
	# THUẬT TOÁN ARRIVE
	# =========================================================
	var target_speed: float
	# Tính lực hãm phanh
	var deceleration = (max_brake_force / mass) * delta
	# Flag check đã là điểm cuối của waypoint
	var is_final_waypoint = ship_movement_waypoints.is_empty()
	
	# Chỉ bắt đầu tăng tốc khi hướng mũi ship đã ổn so với điểm tới (cách điểm hàm còn xa)
	if distance > min_stopping_distance:
		# 2. Tính vận tốc dựa trên quãng đường / khoảng cách cần hãm
		# Càng gần điểm đến, vận tốc càng chậm
		if not is_final_waypoint:
			# Đang đi waypoint giữa chừng: Luôn giữ Max Speed
			target_speed = distance / (braking_distance_factor * 0.5)
		else:
			# Đang tới đích cuối: Giảm tốc từ từ theo khoảng cách
			target_speed = distance / braking_distance_factor
			target_speed = clamp(target_speed, 0.05, max_linear_speed)
		
		# 3. Tính ga trên góc xoay giữa mũi tàu và điểm tới (Auto throttle)
		# Nếu mũi nhìn thẳng (alignment = 1) -> throttle = 1 (Chạy 100% ga)
		# Nếu mũi quay ngang (alignment <= 0) -> throttle = 0 (Nhả ga về 0)
		auto_throttle = clamp(heading_alignment, 0.0, 1.0)
		auto_throttle = pow(auto_throttle, 3) 
		
		# Ép ga nhỏ lại nếu Radar báo hiệu nguy hiểm phía trước
		auto_throttle *= danger_throttle_factor 
		
		# 4. Tính vận tốc
		if heading_alignment > 0.0:
			# 4.1. Tính vận tốc cần đạt (vận tốc mong muốn)
			## v(desired) = direction(ship heading vector3) * current speed * hệ số ga
			var desired_velocity = ship_heading_vector * (target_speed * auto_throttle)
			
			# 4.2. Tính lực bẻ lái (2 vector3 vận tốc)
			## v(stearing) = v(desired) - v(current)
			var steering_force = desired_velocity - velocity
			
			# Giới hạn lực đẩy (thrust) tối đa cho lực bẻ lại không thể hơn max lực đẩy
			if steering_force.length() > max_thrust_force:
				steering_force = steering_force.normalized() * max_thrust_force
			
			# 4.3. Cập nhật lại vân tốc + gia tốc mới
			## v(new) = v(current) + a * delta_t (vận tốc mới  = vận tốc hiện tại + gia tốc * thời gian)
			velocity += (steering_force / mass) * delta
			
		else:
			# Nếu hướng điểm tới quá ngược
			velocity = velocity.move_toward(Vector3.ZERO, deceleration)
	
	else:
		# Lấy chính max_brake_force làm lực phanh để hãm velocity lại
		if ship_movement_waypoints.size() <= 0:
			velocity = velocity.move_toward(Vector3.ZERO, deceleration)
		else:
			velocity = velocity.move_toward(Vector3.ZERO, deceleration * 0.5)
				
	# =========================================================
	# 5 CHỐNG BAY VÒNG TRÒN (Lateral Dampening) - Khử lực di chuyển ngang
	# =========================================================
	# 5.1 Tính xem vận tốc hiện tại theo mũi ship
	## Tính độ lớn vận tốc đúng: speed(forward) = dot(v(current), direction(ship heading vector3))
	var forward_speed = velocity.dot(ship_heading_vector)	# 1 số float, độ lớn vector
	## Tính vector vận tốc đúng: v(forward) = speed(forward) * direction(ship heading vector3)
	var forward_velocity = ship_heading_vector * forward_speed	# Vector có hướng + độ lớn, để biết velocity theo mũi tàu đang lớn bao nhiêu
	
	# 5.2 Tính vận tốc ngang (vận tốc còn thừa ở hướng cũ so với hướng mới)
	## v(curent) = v(lateral) + v(forward) -> v(lateral) = v(current) - v(forward)
	var lateral_velocity = velocity - forward_velocity
	
	# Tăng cường friction khi gần đích để tàu không bị trôi
	var effective_friction = lateral_friction
	if distance < distance_threshold / 2: effective_friction *= 2.0
	
	# 5.3 Ép vận tốc văng ngang về 0, giảm dần theo 1 khoảng lateral friction
	lateral_velocity = lateral_velocity.lerp(Vector3.ZERO, effective_friction * delta) 
	
	## 5.4 Tính lại velocity v(curent) = v(lateral) + v(forward)
	velocity = forward_velocity + lateral_velocity
	
	# Vẽ Debug 3 tia vector ra màn hình!
	draw_debug_vectors(desired_direction, forward_velocity, lateral_velocity)
	# Vẽ đường dự đoán
	var predicted_path = calculate_predicted_path()
	draw_trajectory_line(predicted_path)
	
	# 6. Áp dụng velocity
	move_and_slide()
	
# ----------------------- SUPPORT FUNCTION --------------------------
# Hàm xoay tàu với vận tốc góc theo engine
func update_character_rotation(delta: float, heading_vector: Vector3, desired_direction: Vector3, distant_to_target: float, min_stopping_distance: float) -> void:
	# delta: tham số delta default
	# heading_vector: Hưỡng mũi ship
	# desired_direction: Hướng xoay cần xoay đến
	
	# Check đã xoay đúng hướng
	if heading_vector.is_equal_approx(desired_direction): return
	
	# 1. Tránh lỗi Gimbal Lock (Lật trục) khi tàu phải nhìn thẳng góc 90 độ lên trời / xuống đất
	var safe_up = Vector3.UP
	if abs(desired_direction.y) > 0.99:
		safe_up = Vector3.RIGHT # Nếu nhìn thẳng lên/xuống, mượn trục X làm trục UP tạm thời

	# 2. Lấy basis mục tiêu (Target Basis)
	var target_basis = Basis.looking_at(desired_direction, safe_up)
	
	# Cân bằng ship khi gần tới đích
	# Nếu đây là waypoint cuối cùng và tàu đang đi chậm lại
	if ship_movement_waypoints.is_empty():
		# Nếu đã vào vùng phanh
		if distant_to_target <= min_stopping_distance or distant_to_target < max_linear_speed:
			var flat_desired_direction = Vector3(desired_direction.x, 0.0, desired_direction.z)
			if flat_desired_direction.length_squared() > 0.001:
				# Basis 2: Nằm ngang hoàn toàn
				var leveled_basis = Basis.looking_at(flat_desired_direction.normalized(), Vector3.UP)
				
				# Tính tỷ lệ mix: Càng gần đích, tỷ lệ leveled càng cao
				var blend_weight = clamp(1.0 - (distant_to_target / max_linear_speed), 0.0, 1.0)
				
				# Trộn 2 Basis lại với nhau!
				var blend_quaternion = Quaternion(target_basis).slerp(Quaternion(leveled_basis), blend_weight)
				target_basis = Basis(blend_quaternion)
	
	# 3. Trích xuất Toán học Quaternion từ tư thế Hiện tại và Mục tiêu
	var current_quat = Quaternion(global_transform.basis.orthonormalized())
	var target_quat = Quaternion(target_basis)
	
	# 4. Tính góc lệch (Signed Angle) - Trả về số âm (xoay phải) hoặc dương (xoay trái)
	# Tính góc lệch 3D tổng quát giữa 2 hướng (đơn vị Radian)
	var angle_diff = current_quat.angle_to(target_quat)
	
	# =========================================================
	# THUẬT TOÁN ĐÀ XOAY LÁI (ANGULAR STEERING BEHAVIOR)
	# =========================================================
	
	# 5. TÍNH TỐC ĐỘ XOAY MONG MUỐN (Giống Desired Velocity)
	# Nhân với độ nhạy vô lăng: Góc lệch càng lớn, tàu càng muốn xoay nhanh.
	var desired_turn_speed = angle_diff * turn_sensitivity

	# Giới hạn không cho xoay vượt quá max_turn_speed (Ví dụ: 3.0 rad/s)
	desired_turn_speed = clamp(desired_turn_speed, -max_turn_speed, max_turn_speed)
	
	# 6. Tính lực bẻ lái (Steering Torque)
	## f(steering) = f(desired) - f(current)
	var steering_torque = desired_turn_speed - angular_velocity
	
	# 4. Tính lực xoay (torque power)
	# angular_acceleration (Ví dụ: 10.0) giờ đóng vai trò là sức mạnh của động cơ xoay.
	var applied_torque_power: float
	
	# Kiểm tra xem tàu đang vung mũi nhanh lên (Cùng chiều) hay đang hãm/đảo chiều (Ngược chiều)
	var is_same_direction = sign(desired_turn_speed) == sign(angular_velocity)
	var is_speeding_up = abs(desired_turn_speed) > abs(angular_velocity)
	
	if is_same_direction and is_speeding_up:
		# Đang rồ ga để xoay nhanh hơn
		applied_torque_power = angular_acceleration / mass
	else:
		# Đang giảm tốc xoay, hoặc đang phải gồng mình đảo chiều từ trái sang phải
		applied_torque_power = angular_braking / mass
	
	# 7.Tính lại quán tính xoay
	angular_velocity += steering_torque * applied_torque_power * delta
	angular_velocity = lerp(angular_velocity, 0.0, angular_damping * delta)
	
	# 5. NỘI SUY XOAY 3D (Slerp)
	# Slerp weight = quãng đường góc đi được trong 1 frame / tổng quãng đường góc
	var step_weight = (angular_velocity * delta) / angle_diff
	step_weight = clamp(step_weight, 0.0, 1.0)
	# Xoay tàu!
	var new_quat = current_quat.slerp(target_quat, step_weight)
	global_transform.basis = Basis(new_quat)
	
	# 7. Dọn dẹp sai số ma trận
	#ssa

# Hàm cân bằng ship về y = 0 khi đã hết waypoint hoặc đang indie
func auto_stable_ship_indie_state(delta: float) -> void:
	# distance_to_start: Khoảng cách bắt đầu cân bằng ship
	var current_forward = -global_transform.basis.z
	var flat_forward = Vector3(current_forward.x, 0.0, current_forward.z)
	
	if flat_forward.length_squared() > 0.001:
		flat_forward = flat_forward.normalized()
		# Tạo Basis mục tiêu song song mặt đất
		var target_basis = Basis.looking_at(flat_forward, Vector3.UP)
		
		var current_quat = Quaternion(global_transform.basis.orthonormalized())
		var target_quat = Quaternion(target_basis)
		
		# Slerp Basis hiện tại về Basis phẳng
		global_transform.basis = Basis(current_quat.slerp(target_quat, 2.0 * delta))

# -----------------------  DEBUG VISUAL ------------------------------
# Hàm vẽ 3 tia Vector trực quan gồm tia target, tia forward và tia lateral
func draw_debug_vectors(desired_direction: Vector3, forward_velocity: Vector3, lateral_velocity: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	
	# Nếu tàu đang IDLE thì không vẽ gì cả
	if current_state == PlayerState.IDLE: return
	
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
	
	m.surface_end()
		
# Hàm vẽ đường line nối các điểm
func draw_trajectory_line(points: PackedVector3Array) -> void:
	var m = trajectory_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	
	if points.is_empty() or current_state == PlayerState.IDLE:
		return
		
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		# Nâng lên 1 chút (y = 1.0) để đường line không bị lấp dưới mặt đất
		m.surface_add_vertex(Vector3(p.x, 1.0, p.z)) 
	m.surface_end()

# Hàm vẽ đường dự đoán
func calculate_predicted_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	
	# Clone các thông số hiện tại để chạy mô phỏng giả
	var sim_position = global_position
	var sim_velocity = velocity
	var target_pos = current_target_position
	
	var sim_step = 0.1 # Giả lập mỗi bước là 0.1 giây (delta giả)
	var max_steps = 100 # Mô phỏng trước 100 bước (tương đương 10 giây tương lai)
	
	path.append(sim_position) # Điểm bắt đầu
	
	for i in range(max_steps):
		var distance = sim_position.distance_to(target_pos)
		if distance < 0.5:
			break # Đã tới đích trong mô phỏng
			
		var direction = sim_position.direction_to(target_pos)
		
		# Tính toán Arrive cơ bản (Rút gọn từ code của bạn)
		var speed = distance / braking_distance_factor
		speed = clamp(speed, max_linear_speed / 10.0, max_linear_speed)
		
		var desired_velocity = direction * speed
		var steering = desired_velocity - sim_velocity
		
		if steering.length() > max_thrust_force:
			steering = steering.normalized() * max_thrust_force
			
		# Áp dụng gia tốc
		sim_velocity += (steering / mass) * sim_step
		# Cập nhật vị trí
		sim_position += sim_velocity * sim_step
		
		# Lưu điểm dự đoán cứ mỗi vài bước để vẽ
		if i % 2 == 0: 
			path.append(sim_position)
			
	path.append(target_pos) # Điểm kết thúc
	return path

# Hàm vẽ các điểm di chuyển waypoint
func draw_waypoints_path() -> void:
	var m = waypoints_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	
	# Nếu không có điểm nào và đang IDLE thì không vẽ
	if current_target_position == Vector3.ZERO and ship_movement_waypoints.is_empty():
		return
		
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	# 1. Điểm bắt đầu là vị trí hiện tại của tàu
	m.surface_add_vertex(global_position + Vector3(0, 0.5, 0)) # Nâng lên một chút để tránh lấp nền
	
	# 2. Điểm tiếp theo là Target hiện tại đang bay tới
	if current_state == PlayerState.MOVE:
		m.surface_add_vertex(current_target_position + Vector3(0, 0.5, 0))
	
	# 3. Vẽ tất cả các Waypoint còn lại trong hàng đợi
	for wp in ship_movement_waypoints:
		m.surface_add_vertex(wp.position + Vector3(0, 0.5, 0))
		
	m.surface_end()
