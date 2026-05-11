extends RigidBody3D

# ============================== EXPORT PARAMS ======================================

@export_group("Movement")
@export var linear_accel_time  		:= 5.0    	# Thời gian đạt max_thrust_force từ đứng yên (s)
@export var max_thrust_force   		:= 100.0  	# Lực đẩy tối đa (N)
@export var linear_damp_value  		:= 0.0    	# Cản tịnh tiến
@export var arrival_radius     		:= 0.5    	# Khoảng cách sai số đến đích (m)
@export var blend_arrival_distance 	:= 2.0    	# Khoảng cách bắt đầu chuyển hướng tới hướng gốc
@export var lateral_damp_value   	:= 5.0	  	# Hệ số giảm chấn cho vận tốc ngang, giúp tàu không bị trượt quá đà
var linear_power_to_mass_ratio 		:= 0.0			# Tỉ số giữa lực đẩy tối đa và khối lượng, multiply cho engine và mass khác nhau
var current_thrust_force 			:= 0.0			# Lực đẩy hiện tại đang áp dụng, dùng để nội suy tăng giảm lực đẩy
var is_at_brake_distance 			:= false		# Flag để check đã vào vùng phanh
var auto_throttle 					:= 0.0			# Giá trị tự động điều chỉnh lực đẩy theo độ lệch hướng (alignment)
var lateral_velocity 				:= Vector3.ZERO	# Velocity của lực trượt ngang
var forward_velocity 				:= Vector3.ZERO	# Velocity của lực đúng hướng
var min_distance_diagonally_move 	:= 0.5			# Khoảng cách tối thiểu để di chuyển chéo (để tránh lỗi khi click quá gần)

@export_group("Rotation")
@export var rotation_accel_time     := 2.0    	# Thời gian đạt max_angular_speed từ đứng yên (s)
@export var max_angular_speed  		:= 1.0		# Tốc độ xoay tối đa (rad/s)
@export var max_turn_torque    		:= 50.0		# Khả năng tạo lực xoay của động cơ (N*m)
@export var rotation_p              := 2.0		# Hệ số phản hồi góc (Rotation Proportional Gain)
@export var rotation_d              := 2.0   	# Hệ số phanh góc (Rotation Derivative/Damping) khi đang xoay
@export var angular_damp_value   	:= 5.0		# Hệ số giảm chấn cho vận tốc góc, giúp tàu không bị xoay quá đà và có cảm giác quán tính khi đổi hướng
@export var rotation_start_delay    := 0.1   	# Thời gian chờ (s) trước khi bắt đầu xoay khi phát hiện waypoint mới góc lệch lớn
@export var rotation_delay_threshold := 60.0  	# Góc lệch tối thiểu (độ) để kích hoạt thời gian chờ
@export var rotation_fine_zone      := 1.0   	# Vùng góc gần đích (độ): khi trong vùng này, tốc độ xoay giảm dần về 0 mượt hơn
@export var angle_change_factor 	:= 1.0		# Hệ số giảm lực xoay nếu góc quay thay đổi đột ngột
@export var angle_fine_factor 		:= 1.0		# Hệ số giảm lực quay khi càng gần hướng đúng 
@export var max_roll_angle         	:= 15.0		# Góc lăn tối đa (độ)
@export var max_pitch_angle        	:= 10.0		# Góc nghiêng tối đa (độ)
@export var angular_damp_roll      	:= 2.0		# Hệ số giảm chấn cho góc roll
@export var angular_damp_pitch		:= 2.0		# Hệ số giảm chấn cho góc pitch
@export var angular_stable_power_ratio	:= 0.5	# Tỉ số lực auto stable roll, pitch theo man thrust
var rotation_power_to_mass_ratio    := 0.0		# Tỉ số lực xoay của main thrust / Khối lượng
var rotation_delay_timer := 0.0             	# Đếm ngược thời gian chờ trước khi xoay
var rotation_prev_angle  := 0.0             	# Lưu góc lệch frame trước để phát hiện waypoint mới

# ============================== BIẾN INTERNAL ======================================

var target_position    := Vector3.ZERO	# Vị trí đích đến được đặt khi click chuột
var distance_traveled  := 0.0			# Quãng đường đã di chuyển
var last_position      := Vector3.ZERO	# Vị trí cuối cùng của tàu, dùng để tính quãng đường đã đi
var ship_length: float                               # Độ dài tàu (tính từ AABB mesh)

# ============================== BIẾN MOVEMENT ======================================

var current_target_position := Vector3.ZERO         # Vị trí target hiện tại
var current_target_direction := Vector3.ZERO        # Hướng từ ship đến target
var current_target_height_offset := 0.0              # Offset độ cao từ scroll wheel
var ship_movement_waypoints: Array[Movement_Waypoint] = []  # Danh sách waypoint
var current_waypoint: Movement_Waypoint = null       # Waypoint đang bay tới
var is_at_current_waypoint_threshold := false        # Flag đã vào vùng ngưỡng đích

# For shift direction move
var shift_target_position := Vector3.ZERO
var shift_target_distance := 10.0

# ============================== TRẠNG THÁI ======================================

enum PlayerState { IDLE, MOVE }
enum ShipSteeringMode { CONTEXT, FAJEN_WARREN }
enum ShipMovingMode {SEQUENCE, SHIFT_DIRECTION}
var current_state: PlayerState
var current_moving_mode: ShipMovingMode
# ============================== DEBUG ======================================

var debug_vector_mesh := MeshInstance3D.new()	# Mesh debug cho các vector di chuyển

# Cache để debug draw dùng ngoài _integrate_forces
var _dbg_direction     := Vector3.ZERO
var _dbg_forward_vel   := Vector3.ZERO
var _dbg_lateral_vel   := Vector3.ZERO
var _dbg_linear_vel    := Vector3.ZERO
var _dbg_distance      := 0.0
var _dbg_braking_dist  := 0.0

# Arrival facing preview (set từ scene controller khi đang drag)
var arrival_facing_preview_direction    := Vector3.ZERO
var arrival_facing_preview_active := false

@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"
@onready var rich_text_label_2: RichTextLabel = $"../RichTextLabel2"

# ============================== READY ======================================

func _ready() -> void:
	# Thiết lập mouse filter để label không chặn mouse event
	rich_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich_text_label_2.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tính độ dài ship từ AABB của mesh con đầu tiên
	var ship = self.get_child(0) as Node3D          # Node3D chứa mesh
	var mesh = ship.get_child(0) as MeshInstance3D       # MeshInstance3D để lấy AABB
	ship_length = mesh.get_aabb().size.x                 # Ship nằm hướng X, đã xoay -90 sang -Z

	# Set state ban đầu
	current_state = PlayerState.IDLE
	current_moving_mode = ShipMovingMode.SEQUENCE
	current_target_direction = -global_transform.basis.z
	
	# Internal setup
	gravity_scale = 0.0
	linear_damp   = 0.0
	angular_damp  = 0.0
	last_position = global_position
	linear_power_to_mass_ratio = max_thrust_force / mass
	rotation_power_to_mass_ratio = max_turn_torque / mass
	min_distance_diagonally_move = ship_length + linear_power_to_mass_ratio * (rotation_power_to_mass_ratio / max_pitch_angle)

	# Thiết lập MeshInstance3D để debug vector hướng đi
	debug_vector_mesh.top_level = true
	var m = ImmediateMesh.new()
	debug_vector_mesh.mesh = m
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.flags_unshaded = true
	mat.no_depth_test = true
	debug_vector_mesh.material_override = mat
	add_child(debug_vector_mesh)

# ============================== PUBLIC INPUT API ======================================
# Không có _unhandled_input ở đây — ship KHÔNG tự xử lý input.
# Scene controller (ship_moving_scene.gd) đọc input rồi gọi các hàm API bên dưới.
# Lợi ích: ship không biết phím nào được nhấn, dễ remap, dễ test, không conflict.

## Chỉnh độ cao waypoint cuối (hoặc target hiện tại) theo offset scroll.
## Gọi từ scene controller khi nhận scroll event + đúng context.
## offset: +1.0 = lên, -1.0 = xuống
func adjust_waypoint_target_height(offset: float) -> void:
	# Trường hợp 1: có waypoint trong hàng đợi → chỉnh waypoint cuối
	if not ship_movement_waypoints.is_empty():
		var last_waypoint = ship_movement_waypoints.back()
		var prev_position: Vector3

		if ship_movement_waypoints.size() > 1:
			prev_position = ship_movement_waypoints[ship_movement_waypoints.size() - 2].position
		else:
			prev_position = current_target_position if current_state == PlayerState.MOVE else global_position

		var dist_xz = Vector2(last_waypoint.position.x, last_waypoint.position.z).distance_to(
			Vector2(prev_position.x, prev_position.z))

		var min_y = prev_position.y - dist_xz * tan(deg_to_rad(max_pitch_angle))
		var max_y = prev_position.y + dist_xz * tan(deg_to_rad(max_pitch_angle))
		last_waypoint.position.y = clamp(last_waypoint.position.y + offset, min_y, max_y)
		if is_instance_valid(last_waypoint.point_marker):
			last_waypoint.point_marker.global_position.y = last_waypoint.position.y

		current_target_height_offset = last_waypoint.position.y - prev_position.y

	# Trường hợp 2: đang MOVE không có waypoint → chỉnh target hiện tại
	elif current_state == PlayerState.MOVE:
		var dist_xz = Vector2(current_target_position.x, current_target_position.z).distance_to(
			Vector2(global_position.x, global_position.z))
		var min_y = global_position.y - dist_xz * tan(deg_to_rad(max_pitch_angle))
		var max_y = global_position.y + dist_xz * tan(deg_to_rad(max_pitch_angle))
		current_target_position.y = clamp(current_target_position.y + offset, min_y, max_y)
		if current_waypoint and is_instance_valid(current_waypoint.point_marker):
			current_waypoint.position.y = current_target_position.y
			current_waypoint.point_marker.global_position.y = current_target_position.y

		current_target_height_offset = current_target_position.y - global_position.y
				
func adjust_shift_target_height(offset: float) -> void:
	current_target_height_offset += offset
	current_target_height_offset = clamp(current_target_height_offset, -30.0, 30.0) # Giới hạn offset để tránh lỗi khi scroll quá nhiều

## Cập nhật preview mũi tên vàng tại waypoint cuối (gọi mỗi frame khi đang drag)
func set_arrival_facing_preview(direction: Vector3, active: bool) -> void:
	arrival_facing_preview_direction = direction
	arrival_facing_preview_active = active

## Ghi arrival_facing vào waypoint cuối (gọi khi thả chuột sau drag)
func confirm_last_waypoint_arrival_facing() -> void:
	if not ship_movement_waypoints.is_empty():
		ship_movement_waypoints.back().arrival_facing = arrival_facing_preview_direction
		print("[ArrivalFacing] Confirmed on last queued waypoint: ", arrival_facing_preview_direction)
	elif current_waypoint != null:
		current_waypoint.arrival_facing = arrival_facing_preview_direction
		print("[ArrivalFacing] Confirmed on current waypoint: ", arrival_facing_preview_direction)
	arrival_facing_preview_active = false

# ============================== PROCESS ==============================

func _process(_delta: float) -> void:
	draw_debug_vectors(_dbg_direction, _dbg_forward_vel, _dbg_lateral_vel, _dbg_linear_vel)
	if current_moving_mode == ShipMovingMode.SHIFT_DIRECTION:
		draw_ship_direciton_move_debug(shift_target_position, arrival_facing_preview_direction)

	rich_text_label.text = \
		"\nLin P to M ratio: "         + str(snappedf(linear_power_to_mass_ratio, 0.01)) + \
		"\nRot P to M ratio: "         + str(snappedf(rotation_power_to_mass_ratio, 0.01)) + \
		"\nLinear velocity  : "       + str(snappedf(_dbg_linear_vel.length(), 0.01)) + " m/s" + \
		"\nAngular velocity : "       + str(snappedf(angular_velocity.length(), 0.001)) + " rad/s" + \
		"\nLateral velocity : "       + str(_dbg_lateral_vel) + \
		"\nThrust force     : "       + str(snappedf(max_thrust_force, 0.1)) + " N" + \
		"\nCurrent thrust   : "       + str(snappedf(current_thrust_force, 0.1)) + " N" + \
		"\nAuto throttle    : "       + str(snappedf(auto_throttle, 0.01)) + \
		"\nRotation Delay    : "      + str(snappedf(rotation_delay_timer, 0.01)) + " s" + \
		"\nAngle change factor    : " + str(snappedf(angle_change_factor, 0.01)) + " " + \
		"\nAngle fine factor    : "   + str(snappedf(angle_fine_factor, 0.01)) + "" + \
		"\nCurrent pitch angle    : " + str(asin(clamp(-transform.basis.z.y, -1.0, 1.0))) + " deg" + \
		"\nCurrent target height offset    : " + str(current_target_height_offset) + " m" + \
		"\nMass             : "       + str(mass) + " kg" + \
		"\nHas target       : "       + str(current_waypoint != null) + \
		"\nCurrent target direction     : "       + str(current_target_direction) + \
		"\nMin distance diag : "       + str(snappedf(min_distance_diagonally_move, 0.01)) + " m" + \
		"\nAt brake dist    : "       + str(is_at_brake_distance) + \
		"\nDistance         : "       + str(snappedf(_dbg_distance, 0.01)) + \
		"\nBrake distance   : "       + str(snappedf(_dbg_braking_dist, 0.01)) + \
		"\nDistance traveled: "       + str(snappedf(distance_traveled, 0.01)) + " m"
	
	rich_text_label_2.text = \
		"state			: "       + str(current_state) + \
		"\nmoving state	: "       + str(current_moving_mode)

func _physics_process(delta: float) -> void:
	match current_state:
		PlayerState.IDLE: handle_state_idle(delta)
		PlayerState.MOVE: pass

# ---------------------- STATE MACHINE FUNCTION ---------------------
func handle_state_idle(_delta: float) -> void:
	# Trong trạng thái IDLE, tàu sẽ từ từ dừng lại bằng lực ngược hướng vận tốc hiện tại
	if current_waypoint == null:
		apply_central_force(-linear_velocity * max_thrust_force * linear_power_to_mass_ratio * 0.5)
		auto_throttle = 0.0
		
# Hàm đổi state — chỉ đổi khi khác state hiện tại
func change_state(new_state: PlayerState) -> void:
	if current_state == new_state: return

	match new_state:
		PlayerState.IDLE: pass
		PlayerState.MOVE: pass

	current_state = new_state
	print("State changed to: ", current_state)

# Hàm đổi state — chỉ đổi khi khác state hiện tại
func change_moving_state(new_state: ShipMovingMode) -> void:
	if current_moving_mode == new_state: return

	match new_state:
		ShipMovingMode.SEQUENCE: pass
		ShipMovingMode.SHIFT_DIRECTION: pass

	current_moving_mode = new_state
	print("Moving mode changed to: ", current_moving_mode)

# ============================== INTEGRATE FORCES (KINEMATIC OVERRIDE) ======================================

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.step

	# Tích lũy quãng đường
	distance_traveled += state.transform.origin.distance_to(last_position)
	last_position = state.transform.origin

	# Xử lý state
	match current_state:
		PlayerState.IDLE: 
			handle_state_idle(delta)
			apply_roll_correction(state, delta)
			apply_pitch_correction(state, delta)
		PlayerState.MOVE: 
			# Xử lý di chuyển
			_integrate_movement(state, delta)
	
	# Triệt tiêu trượt ngang và IDLE damping
	_integrate_lateral_damping(state, delta)

	# Xoay để hướng tới target
	update_rotation(state, current_target_direction, delta)
	
	# Auto correct roll
	apply_roll_clamp(state)
	apply_pitch_clamp(state)
	

# ============================== PHYSICS HELPERS ======================================

## Xử lý di chuyển và thrust khi có target
func _integrate_movement(state: PhysicsDirectBodyState3D, delta: float) -> void:
	var distance_to_target := state.transform.origin.distance_to(current_target_position)
	var direction_to_target := state.transform.origin.direction_to(current_target_position)

	_dbg_distance = distance_to_target

	# Nếu còn xa đích → hướng về target trực tiếp
	if distance_to_target > blend_arrival_distance:
		# Tính hướng từ vị trí hiện tại đến target
		current_target_direction = direction_to_target
		_dbg_direction = current_target_direction

	# Nếu đã vào vùng blend_arrival_distance nhưng chưa vào arrival_radius → bắt đầu chuyển hướng về hướng ban đầu
	# Tránh tình trạng ship đổi hướng vô hạn khi đến gần đích mà vẫn chưa vào radius
	elif distance_to_target > arrival_radius and  ship_movement_waypoints.size() == 0:
		# Chuyển direction sang hướng ban đầu thay vì hướng từ ship đến target
		var blend_weight = (distance_to_target - blend_arrival_distance) / blend_arrival_distance
		blend_weight = clamp(blend_weight, 0.8, 1.0)
		
		# Slerp giữa hướng đích đến và hướng click chuột ban đầu
		current_target_direction = direction_to_target.slerp(current_waypoint.direction, blend_weight).normalized()
		_dbg_direction = current_target_direction

	# Kiểm tra đã đến đích
	else:
		# Đến waypoint → load waypoint tiếp theo nếu có, nếu không thì về IDLE
		if ship_movement_waypoints.size() > 0:
			load_next_waypoint()
		# Nếu không còn waypoint nào thì về IDLE
		else:
			# Trả về INDLE
			if current_waypoint and is_instance_valid(current_waypoint.point_marker):
				current_waypoint.point_marker.queue_free()

			# Giữ hướng ship về phương ngang mặt đất khi về IDLE
			current_target_direction = Vector3(current_waypoint.arrival_facing.x, 0.0, current_waypoint.arrival_facing.z)
			current_waypoint = null

			_dbg_direction = current_target_direction
   
			change_state(PlayerState.IDLE)
		

	# Tính thrust dựa trên alignment
	_integrate_thrust_control(state, current_target_direction, distance_to_target, delta)

## Tính toán thrust và áp dụng lực đẩy
func _integrate_thrust_control(state: PhysicsDirectBodyState3D, direction: Vector3, distance: float, delta: float) -> void:
	var heading := -state.transform.basis.z
	var alignment := heading.dot(direction)
	var linear_speed := state.linear_velocity.length()
	var braking_dist := (mass * linear_speed * linear_speed * linear_power_to_mass_ratio) / (2.0 * max_thrust_force)
	var ramp_speed := max_thrust_force / linear_accel_time * delta
	
	_dbg_braking_dist = braking_dist

	if alignment > 0.85: # Chỉ nhả thrust khi đã quay mặt về hướng đích
		auto_throttle = pow(clamp(alignment, 0.0, 1.0), 3)
		ramp_speed = clamp(ramp_speed, -max_thrust_force, max_thrust_force)

		if distance > braking_dist:
			# Còn xa: tăng ga
			current_thrust_force = move_toward(current_thrust_force, max_thrust_force, ramp_speed)
			state.apply_central_force(heading * current_thrust_force * auto_throttle)
			is_at_brake_distance = false
		else:
			# Gần đích: giảm ga từ từ
			current_thrust_force = move_toward(current_thrust_force, 0.0, ramp_speed)
			var target_force := max_thrust_force * (distance / braking_dist) * linear_power_to_mass_ratio
			var desired_force := target_force - current_thrust_force
			var steering_force := (desired_force * heading).limit_length(max_thrust_force)
			state.apply_central_force(steering_force)
			is_at_brake_distance = true
	else:
		# Hướng chưa ổn: phanh
		auto_throttle = lerp(auto_throttle, 0.0, delta)
		current_thrust_force = move_toward(current_thrust_force, 0.0, ramp_speed)
		state.apply_central_force(-state.linear_velocity * max_thrust_force * linear_power_to_mass_ratio)

## Triệt tiêu trượt ngang và damping khi IDLE
func _integrate_lateral_damping(state: PhysicsDirectBodyState3D, delta: float) -> void:
	# Tách vận tốc thành forward + lateral
	var current_heading := -state.transform.basis.z
	var forward_speed := state.linear_velocity.dot(current_heading)
	forward_velocity  = current_heading * forward_speed
	lateral_velocity  = state.linear_velocity - forward_velocity
	
	# Triệt tiêu vận tốc ngang (chống trượt quá đà)
	var lateral_damp = lateral_damp_value * linear_power_to_mass_ratio
	lateral_velocity = lateral_velocity.lerp(Vector3.ZERO, lateral_damp * delta)
	state.linear_velocity = forward_velocity + lateral_velocity

	# Khi IDLE: dừng hoàn toàn
	if current_waypoint == null and state.linear_velocity != Vector3.ZERO:
		state.linear_velocity = state.linear_velocity.move_toward(Vector3.ZERO, linear_power_to_mass_ratio * delta)
		var mass_adjusted_angular_damp = angular_damp_value * rotation_power_to_mass_ratio
		state.angular_velocity = state.angular_velocity.lerp(Vector3.ZERO, mass_adjusted_angular_damp * delta)

	_dbg_forward_vel  = forward_velocity
	_dbg_lateral_vel  = lateral_velocity
	_dbg_linear_vel   = state.linear_velocity


# ============================== KINEMATIC ROTATION ======================================

# Hàm này ghi đè (Override) sức xoay của lý thuyết Rigid bằng thuật toán Look_At Quaternion
func update_rotation(state: PhysicsDirectBodyState3D, desired_dir: Vector3, delta: float) -> void:
	# Xử lý trường hợp không có hướng (điểm đến trùng với vị trí hiện tại) → giữ nguyên hướng hiện tại
	if desired_dir.length_squared() < 0.000001:
		desired_dir = -state.transform.basis.z
		if desired_dir.length_squared() < 0.000001:
			return

	# 1. Tính toán đích đến cuối cùng của mặt phẳng xoay 
	# Luôn gán mặt phẳng UP song song với sàn để không bao giờ Roll (Xoắn / lật nghiêng)
	var up_ref := Vector3.UP
	if abs(desired_dir.dot(up_ref)) > 0.999: # Chống lỗi trục song song (ngước 90 độ thẳng thiên)
		up_ref = Vector3.RIGHT
		
	# 2. Xây dựng Basis bằng Toán học Vector chuẩn không bị sai hướng (Godot: X=Right, Y=Up, Z=Back)
	# LỖI CŨ: Tính sai cross product làm hệ tọa độ bị lật ngược (mirrored) khiến tàu quay ngược.
	var z_axis := -desired_dir.normalized() # Trục Z hướng ra sau lưng tàu (ngược chiều chạy)
	var x_axis := up_ref.cross(z_axis).normalized() # Trục X = hướng sang phải = Cross(Up, Back)
	var y_axis := z_axis.cross(x_axis).normalized() # Trục Y = hướng lên trên = Cross(Back, Right)
	
	var target_basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	
	# 3. Xoay nội suy bằng Quaternion để tìm ra con đường góc trượt ngắn nhất
	var current_quat := state.transform.basis.get_rotation_quaternion()
	var target_quat  := target_basis.get_rotation_quaternion()
	
	var diff_quat := target_quat * current_quat.inverse()	# Quaternion sai lệch từ hiện tại đến mục tiêu
	var axis := diff_quat.get_axis()
	var angle := diff_quat.get_angle()   # Góc lệch đo bằng Radian
	
	# Đổi chuẩn sang từ -PI đến PI để tàu không vặn xoắn quá lố
	if angle > PI: 
		angle -= TAU

	# 4. PHÁT HIỆN WAYPOINT MỚI (ROTATION DELAY)
	# Nếu góc lệch đột ngột tăng vọt lên (> rot_delay_threshold độ) so với frame trước
	# 0.2 rad ~ 11 độ là ngưỡng nhỏ để tránh false positive khi đang xoay qua đích mà góc lệch tạm thời tăng nhẹ
	var angle_abs: float = abs(angle)
	if angle_abs > deg_to_rad(rotation_delay_threshold) and angle_abs > rotation_prev_angle + 0.2:
		rotation_delay_timer = rotation_start_delay
	rotation_prev_angle = angle_abs

	# Nếu đang trong thời gian chờ: đếm ngược và giảm dần fine_factor
	if rotation_delay_timer > 0.0:
		rotation_delay_timer -= delta
		angle_change_factor -= delta * 3.0
		angle_change_factor = clamp(angle_change_factor, 0.0, 1.0)
	else:
		angle_change_factor += delta * 6.0
		angle_change_factor = clamp(angle_change_factor, 0.0, 1.0)
	
	# 5. TÍNH TỐC ĐỘ XOAY — Giảm dần khi vào vùng fine zone (gần đích)
	# Khi góc lệch < rotation_fine_zone độ: scale turn_speed theo tỷ lệ để xoay vào đích mượt hơn
	var fine_rad := deg_to_rad(rotation_fine_zone)
	# Chỉ áp dụng khi có thiết lập fine_zone > 0 (để tránh chia cho 0)
	if angle_abs < fine_rad and fine_rad > 0.0:	
		# Tối đa 0.7 để tránh trường hợp số nhỏ không vào được góc
		angle_fine_factor = max(0.7, angle_abs / fine_rad)
	else:
		angle_fine_factor = 1.0

	# 6. Ép Vận Tốc Góc (Angular Velocity)
	# Tính tốc độ xoay lý thuyết cần đạt được
	var turn_speed = angle * rotation_p * angle_fine_factor * angle_change_factor # Biến rot_p trở thành độ phi feedback, fine_factor giảm dần khi vào vùng đích

	if abs(turn_speed) > max_angular_speed * rotation_power_to_mass_ratio:
		turn_speed = sign(turn_speed) * max_angular_speed * rotation_power_to_mass_ratio
	
	# 7. Tính tốc độ xoay cần thiết
	# Đích đến của Vận Tốc Góc
	var target_angular_velocity = axis * turn_speed
	
	# NỘI SUY (LERP) TẠO ĐÀ ĐỘNG LỰC CÓ ẢNH HƯỞNG CỦA KHỐI LƯỢNG (MASS):
	# Dùng "tỉ số sức xoay / khối lượng" (Torque / Mass). 
	# Có thêm rot_d làm hệ số phanh (damping) tùy chỉnh khi kéo lerp để trị quay lố.
	var acceleration_strength = rotation_power_to_mass_ratio * rotation_d
	state.angular_velocity = state.angular_velocity.lerp(target_angular_velocity, acceleration_strength * delta)

# Hàm tự cân bằng roll về 0
func apply_roll_correction(state: PhysicsDirectBodyState3D, delta: float) -> void:
	var ship_up   = state.transform.basis.y
	var roll_axis = state.transform.basis.z
	
	# 1. Tính góc roll lệch so với cân bằng hiện tại
	var roll_angle = ship_up.signed_angle_to(Vector3.UP, roll_axis)
	
	# 2. Tính vận tốc góc mục tiêu để đưa góc roll về 0
	var target_roll_velocity = roll_axis * roll_angle * (rotation_p * 0.5) * angular_stable_power_ratio
	
	# 3. Bóc tách vận tốc roll (Z) ra khỏi vận tốc xoay tổng thể
	var current_roll_velocity = state.angular_velocity.project(roll_axis)
	var rest_of_angular_velocity = state.angular_velocity - current_roll_velocity
	
	# 4. Lerp xoay riêng trục Z (Roll) về đích và cộng lại vào angular_velocity
	var acceleration_strength = rotation_power_to_mass_ratio * (rotation_d * 0.5) * angular_damp_roll * angular_stable_power_ratio
	var new_roll_velocity = current_roll_velocity.lerp(target_roll_velocity, acceleration_strength * delta)
	
	state.angular_velocity = rest_of_angular_velocity + new_roll_velocity
	
# Hàm tự cân bằng pitch về 0
func apply_pitch_correction(state: PhysicsDirectBodyState3D, delta: float) -> void:
	var ship_up   = state.transform.basis.y
	var pitch_axis = state.transform.basis.x
	
	# 1. Tính góc pitch lệch so với cân bằng hiện tại
	var pitch_angle = ship_up.signed_angle_to(Vector3.UP, pitch_axis)
	
	# 2. Tính vận tốc góc mục tiêu để đưa góc pitch về 0
	var target_pitch_velocity = pitch_axis * pitch_angle * (rotation_p * 0.5) * angular_stable_power_ratio
	
	# 3. Bóc tách vận tốc pitch (X) ra khỏi vận tốc xoay tổng thể
	var current_pitch_velocity = state.angular_velocity.project(pitch_axis)
	var rest_of_angular_velocity = state.angular_velocity - current_pitch_velocity
	
	# 4. Lerp xoay riêng trục X (Pitch) về đích và cộng lại vào angular_velocity
	var acceleration_strength = rotation_power_to_mass_ratio * (rotation_d * 0.5) * angular_damp_pitch * angular_stable_power_ratio
	var new_pitch_velocity = current_pitch_velocity.lerp(target_pitch_velocity, acceleration_strength * delta)
	
	state.angular_velocity = rest_of_angular_velocity + new_pitch_velocity

# Hàm giới hạn góc pitch tối đa (chạy mọi frame)
func apply_pitch_clamp(state: PhysicsDirectBodyState3D) -> void:
	# 1. Tính pitch hiện tại từ component Y của hướng forward (-Z)
	var pitch_rad = asin(clamp(-state.transform.basis.z.y, -1.0, 1.0))  # Radian
	# 2. Đổi max_pitch_angle từ độ sang radian
	var max_pitch_rad = deg_to_rad(max_pitch_angle)
	# 3. Nếu vượt quá giới hạn thì clamp angular velocity về hướng giới hạn
	if abs(pitch_rad) > max_pitch_rad:
		# Tính pitch_error là phần vượt quá giới hạn
		var pitch_error = pitch_rad - sign(pitch_rad) * max_pitch_rad
		# Clamp vận tốc góc quanh trục X để không cho vượt quá giới hạn
		var pitch_axis = state.transform.basis.x
		var current_pitch_vel = state.angular_velocity.project(pitch_axis)
		var rest_angular_vel = state.angular_velocity - current_pitch_vel
		# Nếu đang quay ra ngoài, giữ nguyên; nếu đang quay vào trong, cho phép giảm
		if sign(current_pitch_vel.dot(pitch_axis)) == sign(pitch_error):
			# Đặt lại vận tốc góc quanh X để không làm tăng vượt giới hạn
			current_pitch_vel = Vector3.ZERO
		state.angular_velocity = rest_angular_vel + current_pitch_vel

# Hàm giới hạn góc roll tối đa (chạy mọi frame)
func apply_roll_clamp(state: PhysicsDirectBodyState3D) -> void:
	# 1. Tính roll hiện tại từ component Y của hướng forward (-Z)
	var roll_rad = asin(clamp(-state.transform.basis.z.y, -1.0, 1.0))  # Radian
	# 2. Đổi max_roll_angle từ độ sang radian
	var max_roll_rad = deg_to_rad(max_roll_angle)
	# 3. Nếu vượt quá giới hạn thì clamp angular velocity về hướng giới hạn
	if abs(roll_rad) > max_roll_rad:
		# Tính roll_error là phần vượt quá giới hạn
		var roll_error = roll_rad - sign(roll_rad) * max_roll_rad
		# Clamp vận tốc góc quanh trục Z để không cho vượt quá giới hạn
		var roll_axis = state.transform.basis.z
		var current_roll_vel = state.angular_velocity.project(roll_axis)
		var rest_angular_vel = state.angular_velocity - current_roll_vel
		# Nếu đang quay ra ngoài, giữ nguyên; nếu đang quay vào trong, cho phép giảm
		if sign(current_roll_vel.dot(roll_axis)) == sign(roll_error):
			# Đặt lại vận tốc góc quanh Z để không làm tăng vượt giới hạn
			current_roll_vel = Vector3.ZERO
		state.angular_velocity = rest_angular_vel + current_roll_vel

# ============================== WAYPOINT MARKER ======================================

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
	var new_waypoint = Movement_Waypoint.new(new_position, previous_position, "sequence")
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
	current_target_position = Vector3.ZERO
	current_target_direction = -global_transform.basis.z
	
	# change_state(PlayerState.IDLE)

# Hàm load waypoint tiếp theo từ hàng đợi
func load_next_waypoint() -> void:
	if ship_movement_waypoints.size() > 0:
		# 1. Xóa marker waypoint hiện tại
		if current_waypoint and is_instance_valid(current_waypoint.point_marker):
			current_waypoint.point_marker.queue_free()

		# 2. Pop waypoint đầu hàng đợi và gán làm current
		var next_target_movement = ship_movement_waypoints.pop_front()
		current_waypoint         = next_target_movement
		current_target_position  = next_target_movement.position
		current_target_direction = next_target_movement.direction
		target_position = current_target_position
		
	else:
		current_waypoint = null

# Hàm tạo shift waypoint
func create_shift_waypoint(position: Vector3) -> void:
	var shift_waypoint = Movement_Waypoint.new(position, Vector3.ZERO, "shift")
	ship_movement_waypoints.append(shift_waypoint)
	add_child(shift_waypoint.point_marker)

# ============================= DEBUG MESH =============================================

func draw_debug_vectors(desired_direction: Vector3, fwd_vel: Vector3, lat_vel: Vector3, lin_vel: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	m.surface_begin(Mesh.PRIMITIVE_LINES)

	var origin := global_position + Vector3(0, 2.0, 0)

	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(origin + desired_direction * 5.0)

	m.surface_set_color(Color.BLUE)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.BLUE)
	m.surface_add_vertex(origin + fwd_vel * 2.0)

	m.surface_set_color(Color.RED)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.RED)
	m.surface_add_vertex(origin + lat_vel * 2.0)

	m.surface_set_color(Color.PURPLE)
	m.surface_add_vertex(origin)
	m.surface_set_color(Color.PURPLE)
	m.surface_add_vertex(origin + lin_vel * 2.0)

	# YELLOW: arrival facing preview — vẽ từ vị trí waypoint cuối
	if arrival_facing_preview_active and arrival_facing_preview_direction != Vector3.ZERO:
		var wp_origin := global_position
		if not ship_movement_waypoints.is_empty():
			wp_origin = ship_movement_waypoints.back().position
		elif current_waypoint != null:
			wp_origin = current_waypoint.position
		wp_origin += Vector3(0, 2.0, 0)
		m.surface_set_color(Color.YELLOW)
		m.surface_add_vertex(wp_origin)
		m.surface_set_color(Color.YELLOW)
		m.surface_add_vertex(wp_origin + arrival_facing_preview_direction * 6.0)

	m.surface_end()

func draw_ship_direciton_move_debug(position: Vector3, direction: Vector3) -> void:
	var m = debug_vector_mesh.mesh as ImmediateMesh
	m.clear_surfaces()
	m.surface_begin(Mesh.PRIMITIVE_LINES)

	# Vẽ tia nối từ ship đến target position
	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(position)
	m.surface_set_color(Color.GREEN)
	m.surface_add_vertex(position + direction.normalized() * 5.0)

	m.surface_end()
