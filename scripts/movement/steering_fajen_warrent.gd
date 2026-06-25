extends Node3D
# ============================== FAJEN DYNAMICAL STEERING ======================================

class_name Steering_Fajen_Warrent

@export_group("Fajen Dynamical Steering")
@export var fajen_detection_radius := 35.0
@export var fajen_max_obstacles := 15
@export var fajen_kg := 20.0
@export var fajen_ko := 180.0
@export var fajen_b := 2.2
@export var fajen_c1 := 0.4
@export var fajen_c2 := 0.4
@export var fajen_c3 := 6.0
@export var fajen_c4 := 0.2
@export var fajen_noise := 0.2
@export var fajen_angular_damping := 1.0	# Damping cho fajen_angular_velocity (giống draff angular_damping)
@export var fajen_max_angular_speed  := 1.0	# Tốc độ xoay tối đa (giống draff max_turn_speed)
var nearby_obstacles: Array[Node3D] = []       # Danh sách obstacle trong vùng detect
# fajen_angular_velocity GIỮ NGUYÊN vì Fajen tính pitch/yaw riêng trong ship-space
# Không thể thay bằng angular_velocity Vector3 của RigidBody3D (world-space, 3 trục)
# Biến này được tích lũy nội bộ mỗi frame (giống draff: += accel*delta, lerp damping, clamp max)
# Ship gọi compute() rồi dùng getter để lấy velocity đã tích lũy, không cần biến riêng
var fajen_angular_velocity := Vector2.ZERO     # Momentum xoay của Fajen: x = pitch, y = yaw
var fajen_area_collision_mask := 1 # Layer mask để phát hiện obstacle, chỉnh theo project

# =============================== GETTER / SETTER ==============================

# Getter: ship gọi để lấy velocity đã tích lũy sau compute()
func get_fajen_angular_velocity() -> Vector2:
	return fajen_angular_velocity

# Setter: ship gọi để reset momentum (vd: khi đổi waypoint)
func set_fajen_angular_velocity(vel: Vector2) -> void:
	fajen_angular_velocity = vel

# =============================== DEFAULT FUNCTIONS ==============================

func _init(max_angular_speed: float, angular_damping: float) -> void:
	fajen_max_angular_speed = max_angular_speed
	fajen_angular_damping = angular_damping

# Hàm khởi tạo — setup RigidBody3D settings + Fajen area + debug meshes
func _ready() -> void:
	setup_fajen_area()

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

	avoidance_area.collision_mask = fajen_area_collision_mask  # Layer obstacle (chỉnh theo project)
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
func compute_fajen_angular_acceleration(ship: Node3D, ship_heading_vector: Vector3, target_direction: Vector3, target_position: Vector3, delta: float, max_engine_accel: float) -> Dictionary:
	# ship_heading_vector: Vector3 normalized chỉ hướng mũi tàu (trong world space)
	# target_direction: Vector3 normalized chỉ hướng từ tàu đến mục tiêu (trong world space)
	# target_position: Vị trí mục tiêu
	# delta: Thời gian frame để tích lũy momentum nội bộ
	# max_engine_accel: Giới hạn gia tốc từ ship (angular_acceleration / mass) để clamp

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
	var distance_to_goal: float = max(0.5, global_position.distance_to(target_position))

	## Damping (Lực cản vô lăng hiện tại)
	## -b * phi_dot — dùng fajen_angular_velocity nội bộ
	var phi_double_dot_yaw:   float = -fajen_b * fajen_angular_velocity.y
	var phi_double_dot_pitch: float = -fajen_b * fajen_angular_velocity.x

	# Goal error (góc lệch giữa ship và target): (phi - psi_g)
	var goal_error_yaw: float = current_phi_yaw - goal_phi_yaw
	var goal_error_pitch: float = current_phi_pitch - goal_phi_pitch
	## Tính sang góc nhỏ nhất giữa ship và target
	## fposmod dùng +- PI để giới hạn +-180 độ
	goal_error_yaw = fposmod(goal_error_yaw + PI, TAU) - PI	
	goal_error_pitch = fposmod(goal_error_pitch + PI, TAU) - PI	

	## Tính trọng số theo khoảng cách: kg * (phi - psi_g) * (exp(-c1 * dg) + c2)
	## c1 và c2 là các hằng số 0.4 
	## (exp(-0.4 * d_goal) + 0.4) càng về gần target thì càng gần bằng 1, lực hút tới target càng lớn
	var goal_term_yaw: float = fajen_kg * goal_error_yaw * (exp(-fajen_c1 * distance_to_goal) + fajen_c2)
	var goal_term_pitch: float = fajen_kg * goal_error_pitch * (exp(-fajen_c1 * distance_to_goal) + fajen_c2)

	## Tính thêm vào phi double dot
	phi_double_dot_yaw -= goal_term_yaw
	phi_double_dot_pitch -= goal_term_pitch

	var total_repulsion := 0.0  # Tổng lực đẩy obstacle để tính danger throttle
	var obstacle_details: Array[Dictionary] = []  # Chi tiết từng obstacle để debug
	
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
		query.exclude = [ship.get_rid()] 
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
		var obs_term_yaw = dynamic_ko * obs_error_yaw * exp(-fajen_c3 * abs(obs_error_yaw)) * exp(-fajen_c4 * distance_to_obstacle)
		var obs_term_pitch = dynamic_ko * obs_error_pitch * exp(-fajen_c3 * abs(obs_error_pitch)) * exp(-fajen_c4 * distance_to_obstacle)
		
		# Tính lại phi double dot
		phi_double_dot_yaw += obs_term_yaw
		phi_double_dot_pitch += obs_term_pitch
		
		# Lưu lại độ lớn lực đẩy để lát bóp phanh
		total_repulsion += Vector2(obs_term_yaw, obs_term_pitch).length()
		# Chi tiết obstacle để debug
		obstacle_details.append({
			"obs_term":  Vector2(obs_term_pitch, obs_term_yaw),  # x=pitch, y=yaw
			"obs_error": Vector2(obs_error_pitch, obs_error_yaw),
			"distance":  distance_to_obstacle,
			"radius":    obs_radius,
			"dynamic_ko": dynamic_ko,
		})
		count += 1
	
	## Noise nhỏ chống deadlock — dùng fajen_angular_velocity nội bộ để check
	var noise_added := false
	if count > 0 and fajen_angular_velocity.length() < 0.1 and Vector2(phi_double_dot_pitch, phi_double_dot_yaw).length() < 0.1:
		phi_double_dot_yaw += randf_range(-fajen_noise, fajen_noise)
		phi_double_dot_pitch += randf_range(-fajen_noise, fajen_noise)
		noise_added = true

	# Raw angular acceleration (x=pitch, y=yaw)
	var raw_accel := Vector2(phi_double_dot_pitch, phi_double_dot_yaw)

	# Các giá trị công thức để trả về
	## damping_term: -b * phi_dot (riêng damping, trước goal và obstacle)
	var damping_term   := Vector2(-fajen_b * fajen_angular_velocity.x, -fajen_b * fajen_angular_velocity.y)
	## Goal weight (exp(-c1*dg)+c2) — đã dùng trong goal_term
	var goal_weight    := exp(-0.4 * distance_to_goal) + 0.4

	# ====================================================================================
	# TÍCH LŨY NỘI BỘ (GIỐNG DRAFF)
	# velocity += accel * delta → lerp damping → clamp max speed
	# ====================================================================================
	# Clamp gia tốc theo khả năng động cơ của ship
	var applied_accel: Vector2 = Vector2(
		clamp(raw_accel.x, -max_engine_accel, max_engine_accel),
		clamp(raw_accel.y, -max_engine_accel, max_engine_accel)
	)
	# Tích phân
	fajen_angular_velocity += applied_accel * delta
	# Damping mọi frame
	fajen_angular_velocity = fajen_angular_velocity.lerp(Vector2.ZERO, fajen_angular_damping * delta)
	# Clamp max speed
	if fajen_angular_velocity.length() > fajen_max_angular_speed:
		fajen_angular_velocity = fajen_angular_velocity.normalized() * fajen_max_angular_speed

	return {
		# --- Giá trị chính dùng cho steering ---
		"angular_accel":          raw_accel,                    # Gia tốc góc thô (pitch, yaw)
		"applied_accel":          applied_accel,                # Gia tốc đã clamp (pitch, yaw)
		"fajen_angular_velocity": fajen_angular_velocity,      # Momentum đã tích lũy (pitch, yaw)
		"repulsion_force":        total_repulsion,              # Tổng lực đẩy obstacle

		# --- Chi tiết công thức Fajen (debug) ---
		"damping_term":     damping_term,                               # -b*phi_dot (pitch, yaw)
		"goal_term":        Vector2(goal_term_pitch, goal_term_yaw),   # Goal attraction (pitch, yaw)
		"goal_error":       Vector2(goal_error_pitch, goal_error_yaw), # Góc lệch target (pitch, yaw)
		"distance_to_goal": distance_to_goal,                 # Khoảng cách đến target
		"goal_weight":      goal_weight,                      # Trọng số exp(-c1*dg)+c2

		# --- Obstacle ---
		"obstacle_count": count,                              # Số obstacle đã xử lý
		"obstacle_details": obstacle_details,                 # Chi tiết từng obstacle

		# --- Noise ---
		"noise_added": noise_added,                           # Đã thêm noise chống deadlock?
	}
