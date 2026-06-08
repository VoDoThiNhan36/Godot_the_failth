extends RigidBody3D

# ============================== EXPORT PARAMS ======================================

@export_group("Movement")
@export var linear_accel_time  		:= 5.0    	# Thời gian đạt max_thrust_force từ đứng yên (s)
@export var max_thrust_force   		:= 100.0  	# Lực đẩy tối đa (N)
@export var linear_damp_value  		:= 1.0    	# Cản tịnh tiến
@export var arrival_radius     		:= 1.0    	# Khoảng cách sai số đến đích (m)
@export var blend_arrival_distance 	:= 3.0    	# Khoảng cách bắt đầu chuyển hướng tới hướng gốc
@export var lateral_damp_value   	:= 5.0	  	# Hệ số giảm chấn cho vận tốc ngang, giúp tàu không bị trượt quá đà
@export var shift_lateral_damp_multiplier := 0.0	# Hệ số giảm chấn cho vận tốc ngang khi thực hiện SHIFT move (0 = giữ nguyên vận tốc ngang)
var linear_power_to_mass_ratio 		:= 0.0			# Tỉ số giữa lực đẩy tối đa và khối lượng, multiply cho engine và mass khác nhau
var current_thrust_force 			:= 0.0			# Lực đẩy hiện tại đang áp dụng, dùng để nội suy tăng giảm lực đẩy
var is_at_brake_distance 			:= false		# Flag để check đã vào vùng phanh
var auto_throttle 					:= 0.0			# Giá trị tự động điều chỉnh lực đẩy theo độ lệch hướng (alignment)
var lateral_velocity 				:= Vector3.ZERO	# Velocity của lực trượt ngang
var forward_velocity 				:= Vector3.ZERO	# Velocity của lực đúng hướng
var min_distance_diagonally_move 	:= 0.5			# Khoảng cách tối thiểu để di chuyển chéo (để tránh lỗi khi click quá gần)

@export_group("Rotation")
var rotation_desired_direction 		:= Vector3.ZERO	# Hướng mong muốn để xoay về
@export var rotation_accel_time     := 2.0    	# Thời gian đạt max_angular_speed từ đứng yên (s)
@export var max_angular_speed  		:= 1.0		# Tốc độ xoay tối đa (rad/s)
@export var max_turn_torque    		:= 50.0		# Khả năng tạo lực xoay của động cơ (N*m)
@export var max_turn_torque_rcs     := 50.0    	# Khả năng tạo lực xoay của RCS (N*m)
@export var rotation_p              := 2.0		# Hệ số phản hồi góc (Rotation Proportional Gain)
@export var rotation_d              := 2.0   	# Hệ số phanh góc (Rotation Derivative/Damping) khi đang xoay
@export var angular_damp_value   	:= 1.0		# Hệ số giảm chấn cho vận tốc góc, giúp tàu không bị xoay quá đà và có cảm giác quán tính khi đổi hướng
@export var rotation_start_delay    := 0.1   	# Thời gian chờ (s) trước khi bắt đầu xoay khi phát hiện waypoint mới góc lệch lớn
@export var rotation_delay_threshold := 60.0  	# Góc lệch tối thiểu (độ) để kích hoạt thời gian chờ
@export var rotation_fine_zone      := 1.0   	# Vùng góc gần đích (độ): khi trong vùng này, tốc độ xoay giảm dần về 0 mượt hơn
@export var angle_change_factor 	:= 1.0		# Hệ số giảm lực xoay nếu góc quay thay đổi đột ngột
@export var angle_fine_factor 		:= 1.0		# Hệ số giảm lực quay khi càng gần hướng đúng 
@export var max_roll_angle         	:= 6.0		# Góc lăn tối đa (độ)
@export var max_pitch_angle        	:= 10.0		# Góc nghiêng tối đa (độ)
@export var angular_damp_roll      	:= 2.0		# Hệ số giảm chấn cho góc roll
@export var angular_damp_pitch		:= 2.0		# Hệ số giảm chấn cho góc pitch
@export var angular_stable_power_ratio	:= 0.5	# Tỉ số lực auto stable roll, pitch theo man thrust
var rotation_power_to_mass_ratio    := 0.0		# Tỉ số lực xoay của main thrust / Khối lượng
var rotation_delay_timer := 0.0             	# Đếm ngược thời gian chờ trước khi xoay
var rotation_prev_angle  := 0.0             	# Lưu góc lệch frame trước để phát hiện waypoint mới

# ============================== BIẾN INTERNAL ======================================

var distance_traveled  := 0.0			# Quãng đường đã di chuyển
var last_position      := Vector3.ZERO	# Vị trí cuối cùng của tàu, dùng để tính quãng đường đã đi
var ship_length: float                               # Độ dài tàu (tính từ AABB mesh)

# ============================== BIẾN MOVEMENT ======================================

var current_ship_origin_position := Vector3.ZERO	# Vị trí gốc của ship trước khi thực hiện movement
var current_target_position := Vector3.ZERO         # Vị trí target hiện tại
var current_target_direction := Vector3.ZERO        # Hướng từ ship đến target
var current_target_height_offset := 0.0              # Offset độ cao từ scroll wheel
var ship_movement_waypoints: Array[Movement_Waypoint] = []  # Danh sách waypoint
var current_waypoint: Movement_Waypoint = null       # Waypoint đang bay tới
var is_at_current_waypoint_threshold := false        # Flag đã vào vùng ngưỡng đích
var is_at_current_shift_waypoint_threshold := false   # Flag đã vào vùng ngưỡng đích khi đang shift move (vì shift move có thể chỉnh hướng tại chỗ nên ngưỡng đích sẽ khác)

# ============================== STEERING FAJEN WARREN ======================================
var fajen_steering: Steering_Fajen_Warrent	# Instance của Fajen steering — tự quản lý momentum nội bộ

# ============================== STATE ======================================
# Player state
enum PlayerState { IDLE, MOVE }
enum ShipSteeringMode { NONE, FAJEN_WARREN }
enum InputMovingState {IDLE, SEQUENCE_MOVE, SHIFT_DIRECTION}
var current_state: PlayerState
var current_steering_mode: ShipSteeringMode
var current_moving_mode: InputMovingState

# Input state
enum FlightInputState { IDLE, SEQUENCE_MOVE, SHIFT_MOVE}
var current_input_state: FlightInputState = FlightInputState.IDLE
var current_input_inner_state: Variant = null
var input_delay_timer := 0.0	# Bộ đếm thời gian để ngắ thao tác một nút giống nhau giữa 2 state
var input_hold_timer := 0.0		# Bộ đếm thời gian để bắt đầu chỉnh hướng khi giữ chuột, chỉ dùng cho SEQUENCE_MOVE
var input_hold_threshold := 0.2		# Ngưỡng thời gian (s) để phân biệt thao tác nhanh và hold
var mouse_direction_accumulated := Vector2.ZERO		# Vector tích lũy hướng di chuột để xác định hướng chỉnh sửa

# For sequence move
enum SequenceMoveState {NONE, HOLD_MOUSE, CHANGE_DIRECTION}
var sequence_target_position := Vector3.ZERO	# Vị trí click chuột được raycast từ camera, dùng để tạo waypoint khi thả chuột sau hold hoặc click nhanh

# For shift direction move
@export var shift_max_radius := 20.0		# Bán kính tối đa cho phép của shift waypoint tính từ ship
@export var rotate_start_buffer: float = 1.5
@export var rotate_start_min_radius_mul: float = 3.0
enum InputShiftState {NONE, DRAG_MOUSE_AND_OFFSET, CHANGE_DIRECTION}
var shift_target_position := Vector3.ZERO
var shift_target_distance := 10.0

# ============================== DEBUG ======================================

var debug_fill_mesh := MeshInstance3D.new()    # MeshInstance để chứa cached fill mesh (ArrayMesh)

# Debug info cho label
var _dbg_ship_position := Vector3.ZERO
var _dbg_direction     := Vector3.ZERO
var _dbg_forward_vel   := Vector3.ZERO
var _dbg_lateral_vel   := Vector3.ZERO
var _dbg_linear_vel    := Vector3.ZERO
var _dbg_distance_to_target := 0.0
var _dbg_braking_dist  := 0.0
var _dbg_rotation_start_dist := 0.0
var _dbg_angle_to_target := 0.0
var _dbg_time_to_rotate := 0.0

# Cache để debug draw fill mesh
var _dbg_shift_target := Vector3(1e9, 1e9, 1e9)   # Cache vị trí target lần cuối build fill mesh

# Arrival facing preview (set từ scene controller khi đang drag)
var arrival_facing_preview_direction    := Vector3.ZERO
var arrival_facing_preview_active := false

@onready var rich_text_label: RichTextLabel = $"../RichTextLabel"
@onready var rich_text_label_2: RichTextLabel = $"../RichTextLabel2"
@onready var rich_text_label_3: RichTextLabel = $"../RichTextLabel3"

# ============================== READY ======================================

func _ready() -> void:
	# Thiết lập mouse filter để label không chặn mouse event
	rich_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich_text_label_2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich_text_label_3.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tính độ dài ship từ AABB của mesh con đầu tiên
	var ship = self.get_child(0) as Node3D          # Node3D chứa mesh
	var mesh = ship.get_child(0) as MeshInstance3D       # MeshInstance3D để lấy AABB
	ship_length = mesh.get_aabb().size.x                 # Ship nằm hướng X, đã xoay -90 sang -Z

	# Set state ban đầu
	current_state = PlayerState.IDLE
	current_moving_mode = InputMovingState.IDLE
	current_steering_mode = ShipSteeringMode.NONE
	current_target_direction = -global_transform.basis.z
	
	# Internal setup
	gravity_scale = 0.0
	# linear_damp   = 0.0
	# angular_damp  = 0.0
	last_position = global_position
	linear_power_to_mass_ratio = max_thrust_force / mass
	rotation_power_to_mass_ratio = (max_turn_torque + max_turn_torque_rcs) / mass
	min_distance_diagonally_move = ship_length + linear_power_to_mass_ratio * (rotation_power_to_mass_ratio / max_pitch_angle)

	# Fajen steering setup — đồng bộ params + steering tự quản lý momentum
	fajen_steering = Steering_Fajen_Warrent.new(max_angular_speed, angular_damp_value)
	add_child(fajen_steering)

	# Thiết lập MeshInstance3D cho fill mesh (ArrayMesh cached, chỉ rebuild khi dirty)
	debug_fill_mesh.top_level = true
	debug_fill_mesh.mesh = ArrayMesh.new()
	var fill_mat := StandardMaterial3D.new()
	fill_mat.vertex_color_use_as_albedo = true
	fill_mat.flags_unshaded = true
	fill_mat.no_depth_test = true
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	debug_fill_mesh.material_override = fill_mat
	debug_fill_mesh.visible = false
	add_child(debug_fill_mesh)

# ============================== PUBLIC INPUT API ======================================
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
	# Shift move luôn có 1 waypoint duy nhất, nên chắc chắn back() sẽ trả về đúng waypoint cần chỉnh
	var shift_waypoint = ship_movement_waypoints.back()	if ship_movement_waypoints.size() > 0 else current_waypoint
	current_target_height_offset += offset
	current_target_height_offset = clamp(current_target_height_offset, -30.0, 30.0) # Giới hạn offset để tránh lỗi khi scroll quá nhiều
	shift_waypoint.position.y = global_position.y + current_target_height_offset

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
	else:
		rotation_desired_direction = arrival_facing_preview_direction
		print("[ArrivalFacing] Confirm on currrent ship rotation: ", arrival_facing_preview_direction)

	arrival_facing_preview_active = false

# ============================== FLIGHT INPUT STATE MACHINE ======================================

## Process để tính thời gian hold, nếu đủ delta time thì chuyển qua FACING_HOLD (giữ waypoint để chỉnh hướng)
func process_flight_input(delta: float) -> void:
	# Xử lý các logic cần process theo state hiện tại mỗi frame
	match current_input_state:
		FlightInputState.SEQUENCE_MOVE:
			# Tích lũy thời gian hold khi đang giữ nút sequence move, nếu đủ thời gian thì chuyển sang state FACING_HOLD
			input_hold_timer += delta
		
		FlightInputState.SHIFT_MOVE:
			if current_input_inner_state == InputShiftState.DRAG_MOUSE_AND_OFFSET:
				# Set shift target position liên tục theo vị trí chuột
				var mouse_hover_position = get_mouse_hover_position()
				if mouse_hover_position == null:
					# Mất raycast: giữ debug/waypoint ở bán kính tối đa theo hướng hiện tại
					shift_target_position = get_shift_fallback_position_at_max()
				else:
					# Tính lại shift target position với offset height
					shift_target_position = mouse_hover_position * Vector3(1, 0, 1) + Vector3(0, global_position.y + current_target_height_offset, 0)
					# Giới hạn bán kính SHIFT theo tham số max
					shift_target_position = clamp_shift_target_to_max_radius(shift_target_position)

				# Tính khoảng cách từ ship đến shift target
				shift_target_distance = global_position.distance_to(shift_target_position)
				# Nếu có waypoint trong hàng đợi, cập nhật vị trí waypoint cuối cùng (cũng là shift waypoint) để hiển thị marker di chuyển theo chuột
				if not ship_movement_waypoints.is_empty():
					ship_movement_waypoints.back().position = shift_target_position
					ship_movement_waypoints.back().point_marker.global_position = shift_target_position
			
			elif current_input_inner_state == InputShiftState.CHANGE_DIRECTION:
				# Tích lũy thời gian delay để tránh chuyển state quá nhanh giữa DRAG_MOUSE_AND_OFFSET và CHANGE_DIRECTION
				input_delay_timer += delta
			
			# Draw debug shift target nếu có, ẩn nếu không có
			if shift_target_position != Vector3.ZERO:
				_draw_shift_debug(global_position, shift_target_position)
				debug_fill_mesh.visible = true
	
## Hàm xử lý input chính — chỉ chuẩn bị data rồi dispatch vào state handler
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return

	var camera_3d := Global_Camera.get_active_camera()
	var camera_basis := camera_3d.global_transform.basis if camera_3d != null else Basis.IDENTITY

	# Raycast chỉ khi có action cần vị trí chuột, không chạy mỗi frame
	var mouse_hover_position: Variant = null
	if (event.is_action_pressed("move") or event.is_action_pressed("direction_shift_move")) and camera_3d != null:
		mouse_hover_position = get_mouse_hover_position()

	match current_input_state:
		FlightInputState.IDLE:          input_state_idle(event, mouse_hover_position)
		FlightInputState.SEQUENCE_MOVE: input_state_sequence_move(event, camera_basis)
		FlightInputState.SHIFT_MOVE:    input_state_shift_move(event, mouse_hover_position, camera_basis)

func _change_flight_state(new_state: FlightInputState) -> void:
	if current_input_state == new_state: return

	match current_input_state:
		FlightInputState.IDLE:
			pass

		FlightInputState.SEQUENCE_MOVE:
			# Set state hiện tại lên Global Input
			Global_Input.change_input_state(Global_Input.InputState.NONE)
			# Reset shift internal state
			current_input_inner_state = SequenceMoveState.NONE
			input_hold_timer = 0.0
			sequence_target_position = Vector3.ZERO

		FlightInputState.SHIFT_MOVE:
			# Set state hiện tại lên Global Input
			Global_Input.change_input_state(Global_Input.InputState.NONE)
			# Reset shift internal state
			current_input_inner_state = InputShiftState.NONE
			input_delay_timer = 0.0
			# Tắt debug shift target khi thoát shift move
			if debug_fill_mesh.visible:
				debug_fill_mesh.visible = false
				(debug_fill_mesh.mesh as ArrayMesh).clear_surfaces()
				_dbg_ship_position = Vector3(1e9, 1e9, 1e9)
				_dbg_shift_target  = Vector3(1e9, 1e9, 1e9)

	match new_state:
		FlightInputState.IDLE:
			pass

		FlightInputState.SEQUENCE_MOVE:
			# Set state hiện tại lên Global Input
			Global_Input.change_input_state(Global_Input.InputState.SEQUENCE_MOVE)
			# Update shift internal state
			current_input_inner_state = SequenceMoveState.HOLD_MOUSE
			mouse_direction_accumulated = Vector2.ZERO

		FlightInputState.SHIFT_MOVE:
			# Set state hiện tại lên Global Input
			Global_Input.change_input_state(Global_Input.InputState.SHIFT_MOVE)
			# Reset shift target position khi mới vào shift move
			shift_target_position = Vector3.ZERO
			# Update shift internal state
			current_input_inner_state = InputShiftState.DRAG_MOUSE_AND_OFFSET
			# Show immediate preview for shift move
			set_arrival_facing_preview(Vector3.FORWARD, true)

	# Set state mới
	current_input_state = new_state

# Hàm xử lý Input state IDLE
# Click -> Sequence move -> Nếu giữ nút sequence -> Nhận scroll chỉnh height -> Nhấn giữ chuột -> Cho điều chỉnh hướng
# Nhấn nút shift move -> Shift move -> Nhận mouse motion để chỉnh độ dài + hướng
func input_state_idle(event: InputEvent, mouse_hover_position: Variant) -> void:
	# Click chuột để di chuyển
	if event.is_action_pressed("move"):
		if mouse_hover_position == null:
			return
		# Nếu đang nhấn giữ sequence move → vào SEQUENCE_MOVE để chờ hold hoặc chỉnh hướnng
		if Input.is_action_pressed("sequence_move"):
			sequence_target_position = mouse_hover_position
			_change_flight_state(FlightInputState.SEQUENCE_MOVE)
		# Nếu không giữ sequence move → tạo waypoint và di chuyển ngay
		else:
			move_to(mouse_hover_position, false)

	# Nhấn shift move → tạo waypoint tại vị trí chuột + vào SHIFT_MOVE
	if event.is_action_pressed("direction_shift_move") and mouse_hover_position != null:
		create_shift_waypoint(mouse_hover_position)
		_change_flight_state(FlightInputState.SHIFT_MOVE)

	# Scroll khi đang giữ sequence_move → chỉnh height waypoint
	_handle_scroll_with_sequence_modifier(event)

	if event.is_action_pressed("clear_waypoints"):
		clear_all_waypoints()
		_change_flight_state(FlightInputState.IDLE)
		change_state(PlayerState.IDLE)

# Hàm xử lý nút sequence move đang giữ để vào trạng thái chờ hold, nếu đủ thời gian hold sẽ vào trạng thái chỉnh hướng
func input_state_sequence_move(event: InputEvent, camera_basis: Basis) -> void:
	# Nếu thả chuột ra
	if event.is_action_released("move"):
		# Click nhanh → tạo waypoint ngay tại vị trí click
		if input_hold_timer < input_hold_threshold:
			move_to(sequence_target_position, true)
			set_arrival_facing_preview(Vector3.ZERO, false)
			_change_flight_state(FlightInputState.IDLE)
			return
		# Giữ chuột -> tạo waypoint + hướng
		elif current_input_inner_state == SequenceMoveState.CHANGE_DIRECTION:
			confirm_last_waypoint_arrival_facing()
			set_arrival_facing_preview(Vector3.ZERO, false)
			_change_flight_state(FlightInputState.IDLE)
			return
	
	# Giữ đủ lâu -> chuyển state để chỉnh hướng
	if current_input_inner_state == SequenceMoveState.HOLD_MOUSE:
		# Nếu có di chuyển chuột khi đang hold thì ghi nhận các số liệu chỉnh hướng
		if event is InputEventMouseMotion:
			mouse_direction_accumulated += event.relative

		# Nếu giữ chuột đủ lâu → chuyển sang state chỉnh hướng
		if input_hold_timer >= input_hold_threshold:
			current_input_inner_state = SequenceMoveState.CHANGE_DIRECTION
	
	# Tính hướng và set preview
	if current_input_inner_state == SequenceMoveState.CHANGE_DIRECTION:
		# Drag chuột → cập nhật preview hướng
		if event is InputEventMouseMotion:
			mouse_direction_accumulated += event.relative
			var preview_dir := calculate_translate_direction_from_mouse_motion(mouse_direction_accumulated, camera_basis)
			if preview_dir != Vector3.ZERO:
				set_arrival_facing_preview(preview_dir, true)

	# Scroll khi đang giữ sequence_move → chỉnh height
	_handle_scroll_with_sequence_modifier(event)

# Hàm xử lý shift move: không cần hold threshold, vào mode ngay, scroll + drag hoạt động tự do
# Exit: nhấn shift_move lần nữa hoặc nhấn move để clear
func input_state_shift_move(event: InputEvent, _mouse_hover_position: Variant, camera_basis: Basis) -> void:
	# Nhấn chuột trái hoặc nhấn shift_move lần nữa để cancel shift move, bỏ waypoint
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("direction_shift_move"):
		ship_movement_waypoints.pop_back().point_marker.queue_free() # Xóa marker của shift waypoint
		set_arrival_facing_preview(Vector3.ZERO, false)
		_change_flight_state(FlightInputState.IDLE)
		return
	
	# Thay đổi độ dài + offset waypoint theo di chuyển chuột liên tục
	# Nhấn move sẽ giữ cố định waypoint lại, chuyển sang state tiếp theo để chỉnh hướng
	if current_input_inner_state == InputShiftState.DRAG_MOUSE_AND_OFFSET and event.is_pressed():
		if event.is_action_pressed("move"):
			current_input_inner_state = InputShiftState.CHANGE_DIRECTION

	# Drag chuột → cập nhật preview facing (dùng chung helper với FACING_DRAG)
	if current_input_inner_state == InputShiftState.CHANGE_DIRECTION:
		if event is InputEventMouseMotion:
			mouse_direction_accumulated += event.relative
			var preview_dir := calculate_translate_direction_from_mouse_motion(mouse_direction_accumulated, camera_basis)
			if preview_dir != Vector3.ZERO:
				set_arrival_facing_preview(preview_dir, true)

		# Nhấn move khi đang ở CHANGE_DIRECTION sẽ xác nhận hướng và thoát về IDLE
		# Cần check input timer để tránh 1 input move chạy ở cả 2 state CHANGE_DIRECTION và DRAG_MOUSE_AND_OFFSET gây lỗi xác nhận sớm
		if event.is_action_pressed("move") and input_delay_timer > 0.1:
			confirm_last_waypoint_arrival_facing()
			set_arrival_facing_preview(Vector3.ZERO, false)
			_change_flight_state(FlightInputState.IDLE)
			# Di chuyển ship nếu ship hiện không di chuyển
			if current_state == PlayerState.IDLE:
				load_next_waypoint()
				change_state(PlayerState.MOVE)
			return

	# Scroll → chỉnh height, không cần modifier
	_handle_scroll(event)
	
# ======================================== INPUT HELPERS ========================================

# Helper: scroll chỉnh height, chỉ có tác dụng khi giữ modifier sequence_move
func _handle_scroll_with_sequence_modifier(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN: return
	if not Input.is_action_pressed("sequence_move"): return
	var offset := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	adjust_waypoint_target_height(offset)

# Helper: scroll chỉnh height không cần modifier (dùng cho SHIFT_MOVE)
func _handle_scroll(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN: return
	var offset := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	adjust_shift_target_height(offset)

# Hàm translate Vector2 tích lũy thành vector3 hướng chỉnh sửa dựa trên basis của camera
func calculate_translate_direction_from_mouse_motion(accum: Vector2, camera_basis: Basis) -> Vector3:
	# Nếu vector tích lũy quá nhỏ, trả về ZERO để không chỉnh hướng
	if accum.length_squared() < 1.0:
		return Vector3.ZERO
	
	var camera_right := camera_basis.x		# Vector right của camera để tính hướng ngang
	var camera_forward_flat := camera_basis.z # Vector forward của camera, nhưng bỏ qua thành phần y để chỉ lấy hướng trên mặt phẳng XZ
	camera_forward_flat.y = 0.0			# Đặt y về 0 để đảm bảo hướng chỉnh chỉ nằm trên mặt phẳng ngang

	# Check nếu vector hướng gần như bằng 0, thì cho mặc ddingj là (0,0,1) để tránh lỗi normalize ZERO
	if camera_forward_flat.length_squared() < 0.0001:
		camera_forward_flat = Vector3.BACK # +Z đồng bộ với camera z
	
	# Normalize lại camera foward sau khi bỏ y 
	# Camera right thì không cần normalize vì camera đổi góc tương đương xoay zy trên trục x, nên x không đổi
	else:
		camera_forward_flat = camera_forward_flat.normalized()

	# Tính hướng chỉnh sửa dựa trên vector tích lũy và basis của camera
	var world_dir := camera_right * accum.x + camera_forward_flat * accum.y
	world_dir.y = 0.0

	# Check nếu vector hướng gần như bằng 0, thì trả về ZERO để không chỉnh hướng
	if world_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	
	return world_dir.normalized()

# Hàm lấy vị trí hover chuột liên tục khi đang ở state SHIFT_MOVE, để cập nhật waypoint tạm thời
func get_mouse_hover_position() -> Variant:
	var camera_3d = Global_Camera.get_active_camera()
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		var ray_result = Global_RayQuery3d.shoot_ray_3d(camera_3d, self)
		if ray_result != null:
			return ray_result

	return null

func clamp_shift_target_to_max_radius(target_pos: Vector3) -> Vector3:
	var ship_origin_flat := Vector3(global_position.x, 0.0, global_position.z)
	var target_flat := Vector3(target_pos.x, 0.0, target_pos.z)
	var offset_flat := target_flat - ship_origin_flat
	var dist_flat: float = offset_flat.length()

	if dist_flat > shift_max_radius and dist_flat > 0.0001:
		var clamped_flat: Vector3 = ship_origin_flat + offset_flat.normalized() * shift_max_radius
		return Vector3(clamped_flat.x, target_pos.y, clamped_flat.z)

	return target_pos

func get_shift_fallback_position_at_max() -> Vector3:
	# Ưu tiên: project camera ray → XZ plane tại độ cao ship để indicator vẫn theo chuột
	var camera_3d = Global_Camera.get_active_camera()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_dir    := camera_3d.project_ray_normal(mouse_pos)

	# Nếu raycast không trúng, sử dụng hướng từ chuột
	var dir_flat := ray_dir
	dir_flat.y = 0.0

	# Nếu hướng gần như bằng 0, fallback về hướng thẳng sau ship 
	# Nếu vẫn gần bằng 0, fallback về hướng thẳng sau world (đồng thời tránh lỗi normalize ZERO)
	if dir_flat.length_squared() < 0.0001:
		dir_flat = -global_transform.basis.z
		dir_flat.y = 0.0
		if dir_flat.length_squared() < 0.0001:
			dir_flat = Vector3.BACK

	dir_flat = dir_flat.normalized()

	return Vector3(
		global_position.x + dir_flat.x * shift_max_radius,
		global_position.y + current_target_height_offset,
		global_position.z + dir_flat.z * shift_max_radius
	)

# ============================== PROCESS ==============================

func _process(_delta: float) -> void:
	# Process input
	process_flight_input(_delta)

	# Debug draw: DebugDraw3D tự xóa mỗi frame, không cần dirty check
	draw_debug_vectors(_dbg_direction, _dbg_forward_vel, _dbg_lateral_vel, _dbg_linear_vel)

	rich_text_label.text = \
		"\nLin P to M ratio: "         + str(snappedf(linear_power_to_mass_ratio, 0.01)) + \
		"\nRot P to M ratio: "         + str(snappedf(rotation_power_to_mass_ratio, 0.01)) + \
		"\nLinear velocity  : "       + str(snappedf(_dbg_linear_vel.length(), 0.01)) + " m/s" + \
		"\nAngular velocity : "       + str(snappedf(angular_velocity.length(), 0.001)) + " rad/s" + \
		"\nLateral velocity : "       + str(_dbg_lateral_vel) + \
		"\nForward velocity : "       + str(_dbg_forward_vel) + \
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
		"\nCurrent origin position     : "       + str(current_ship_origin_position) + \
		"\nMin distance diag : "       + str(snappedf(min_distance_diagonally_move, 0.01)) + " m" + \
		"\nAt brake dist    : "       + str(is_at_brake_distance) + \
		"\nDistance to target: "       + str(snappedf(_dbg_distance_to_target, 0.01)) + \
		"\nBrake distance   : "       + str(snappedf(_dbg_braking_dist, 0.01)) + \
		"\nDistance traveled: "       + str(snappedf(distance_traveled, 0.01)) + " m" + \
		"\nWaypoint count: " 		  + str(ship_movement_waypoints.size())
	
	rich_text_label_2.text = \
		"Ship state			: "       + str(current_state) + \
		"\nMoving state	: "       + str(current_moving_mode) + \
		"\nInput state		: "       + str(current_input_state) + \
		"\nInput inner state: "       + str(current_input_inner_state) + \
		"\nDirection preview active: " + str(arrival_facing_preview_active) + \
		"\nRotation start distance: " + str(snappedf(_dbg_rotation_start_dist, 0.01)) + " m" + \
		"\nAngle to target: " + str(snappedf(_dbg_angle_to_target, 0.01)) + " rad" + \
		"\nTime to rotate: " + str(snappedf(_dbg_time_to_rotate, 0.01)) + " s" + \
		"\nSteering mode: " + str(current_steering_mode)

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
func change_moving_state(new_state: InputMovingState) -> void:
	if current_moving_mode == new_state: return

	match new_state:
		InputMovingState.SEQUENCE_MOVE: pass
		InputMovingState.SHIFT_DIRECTION: pass

	current_moving_mode = new_state
	print("Moving mode changed to: ", current_moving_mode)

# ============================== INTEGRATE FORCES (KINEMATIC OVERRIDE) ======================================

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.step

	# Tính các số liệu chung
	var distance_to_target := state.transform.origin.distance_to(current_target_position)
	var direction_to_target := state.transform.origin.direction_to(current_target_position)
	var ship_heading := -state.transform.basis.z
	var danger_throttle_factor = 1.0  # Hệ số giảm ga khi có obstacle nguy hiểm

	# Tích lũy quãng đường
	distance_traveled += state.transform.origin.distance_to(last_position)
	last_position = state.transform.origin

	# Xử lý state
	match current_state:
		PlayerState.IDLE: 
			handle_state_idle(delta)
			apply_roll_correction(state, delta)
			apply_pitch_correction(state, delta)
			# Khi IDLE: dừng hoàn toàn
			if current_waypoint == null and state.linear_velocity != Vector3.ZERO:
				# Damp vận tốc tuyến tính
				state.linear_velocity = state.linear_velocity.move_toward(Vector3.ZERO, linear_damp_value * linear_power_to_mass_ratio * delta)
				# Damp vận tốc góc
				var mass_adjusted_angular_damp = angular_damp_value * rotation_power_to_mass_ratio
				state.angular_velocity = state.angular_velocity.lerp(Vector3.ZERO, mass_adjusted_angular_damp * delta)
				# Triệt tiêu trượt ngang và IDLE damping
				lateral_velocity = lateral_velocity.move_toward(Vector3.ZERO, lateral_damp_value * linear_power_to_mass_ratio * delta)
				forward_velocity = forward_velocity.move_toward(Vector3.ZERO, lateral_damp_value * linear_power_to_mass_ratio * delta)

				# Update debug info
				_dbg_forward_vel = forward_velocity
				_dbg_lateral_vel = lateral_velocity
				_dbg_linear_vel = state.linear_velocity
				
		PlayerState.MOVE: 
			# Xử lý di chuyển theo loại waypoint hiện tại
			match current_waypoint.type:
				"sequence":
					compute_sequence_move_target_direction(state, distance_to_target, direction_to_target, ship_heading, delta)
					# Triệt tiêu trượt ngang và IDLE damping
					compute_sequence_move_lateral_damping(state, delta)
					 
				"shift":
					compute_shift_move_target_direction(state, distance_to_target, direction_to_target, ship_heading, delta)
					# Triệt tiêu trượt ngang và IDLE damping
					# Không cần triệt tiêu, damping đã có thrust control lo
					# compute_shift_move_lateral_damping(state, delta)
	
	# Xoay để hướng tới target
	# =========================================================
	# STEERING: Fajen (xa) hoặc manual torque (gần)
	# =========================================================
	# Tính desired direction theo thuật toán steering khi distance còn xa
	if distance_to_target > ship_length * 3.0:
		# Set mode steering đang dùng
		current_steering_mode = ShipSteeringMode.FAJEN_WARREN

		# =========================================================
		# FAJEN STEERING — Steering tự tích lũy nội bộ (giống draff)
		# Chỉ gọi compute(), steering tự lo clamp/damp/clamp max,
		# ship chỉ việc gán velocity vào state.angular_velocity
		# =========================================================
		var max_engine_accel := rotation_power_to_mass_ratio  # = angular_acceleration / mass

		# 1. Gọi Fajen — steering tự tích lũy vào fajen_angular_velocity nội bộ
		var fajen_result = fajen_steering.compute_fajen_angular_acceleration(
			self, ship_heading, direction_to_target, current_target_position, delta, max_engine_accel)
		var fajen_vel: Vector2 = fajen_steering.get_fajen_angular_velocity()  # Đã tích lũy + damp + clamp
		var total_repulsion: float = fajen_result["repulsion_force"]

		# 2. Gán trực tiếp velocity vào angular_velocity (Kinematic override)
		var yaw_axis   := Vector3.UP
		var pitch_axis := state.transform.basis.x.normalized()
		state.angular_velocity = yaw_axis * fajen_vel.y + pitch_axis * fajen_vel.x

		# 3. Danger throttle — giống draff: ngưỡng 5.0
		if total_repulsion > 5.0:
			danger_throttle_factor = clamp(1.0 - (total_repulsion / 50.0), 0.1, 1.0)
			auto_throttle *= danger_throttle_factor
		else:
			danger_throttle_factor = 1.0
		
		# 4. Debug — hiển thị tất cả kết quả công thức Fajen
		var obs_debug_str := ""
		var obs_details: Array = fajen_result.get("obstacle_details", [])
		for i in range(obs_details.size()):
			var obs = obs_details[i]
			obs_debug_str += "  #%d: err=%s, term=%s, dist=%.1f, r=%.1f, ko=%.1f\n" % [
				i + 1,
				obs["obs_error"],
				obs["obs_term"],
				obs["distance"],
				obs["radius"],
				obs["dynamic_ko"]
			]
		if obs_debug_str == "": obs_debug_str = "  (none)\n"
		
		rich_text_label_3.text = \
			"FAJEN FORMULA\n" + \
			"─────────────────────────\n" + \
			"damping_term (pitch, yaw): "   + str(fajen_result["damping_term"]) + "\n" + \
			"goal_term   (pitch, yaw): "   + str(fajen_result["goal_term"]) + "\n" + \
			"goal_error  (pitch, yaw): "   + str(fajen_result["goal_error"]) + "\n" + \
			"goal_weight              : "   + str(snappedf(fajen_result["goal_weight"], 0.001)) + "\n" + \
			"distance_to_goal         : "   + str(snappedf(fajen_result["distance_to_goal"], 0.1)) + " m\n" + \
			"noise_added              : "   + str(fajen_result["noise_added"]) + "\n" + \
			"\nRAW → APPLIED → VELOCITY\n" + \
			"─────────────────────────\n" + \
			"raw_accel   (pitch, yaw): "   + str(fajen_result["angular_accel"]) + "\n" + \
			"max_engine_accel       : "   + str(snappedf(max_engine_accel, 0.001)) + "\n" + \
			"applied     (pitch, yaw): "   + str(fajen_result["applied_accel"]) + "\n" + \
			"fajen_vel   (pitch, yaw): "   + str(fajen_vel) + "\n" + \
			"\nREPULSION\n" + \
			"─────────────────────────\n" + \
			"total_repulsion         : "   + str(snappedf(total_repulsion, 0.001)) + "\n" + \
			"obstacle_count          : "   + str(fajen_result["obstacle_count"]) + "\n" + \
			"danger_throttle_factor  : "   + str(snappedf(danger_throttle_factor, 0.01)) + "\n" + \
			"\nOBSTACLE DETAILS\n" + \
			obs_debug_str	
	
	# Khoảng cách gần target, không dùng steering mà dùng manual
	else:
		# Set mode steering đang dùng
		current_steering_mode = ShipSteeringMode.NONE
		update_rotation(state, rotation_desired_direction, delta)

	# Auto correct roll
	apply_roll_clamp(state)
	apply_pitch_clamp(state)

# ============================== PHYSICS HELPERS ======================================

## Xử lý di chuyển khi có target
func compute_sequence_move_target_direction(state: PhysicsDirectBodyState3D, distance_to_target: float, direction_to_target: Vector3, ship_heading: Vector3, delta: float) -> void:
	# Nếu còn xa đích → hướng về target trực tiếp
	if distance_to_target > blend_arrival_distance:
		# Tính hướng từ vị trí hiện tại đến target
		current_target_direction = direction_to_target
		_dbg_direction = current_target_direction

	# Nếu đã vào vùng blend_arrival_distance nhưng chưa vào arrival_radius → bắt đầu chuyển hướng về hướng ban đầu
	# Tránh tình trạng ship đổi hướng vô hạn khi đến gần đích mà vẫn chưa vào radius
	elif distance_to_target > arrival_radius and ship_movement_waypoints.size() == 0:
		# Chuyển direction sang hướng ban đầu thay vì hướng từ ship đến target
		var blend_weight = (distance_to_target - blend_arrival_distance) / blend_arrival_distance
		blend_weight = clamp(blend_weight, 0.2, 1.0)
		
		# Slerp giữa hướng đích đến và hướng click chuột ban đầu
		current_target_direction = direction_to_target.slerp(current_waypoint.direction, blend_weight).normalized()
		_dbg_direction = current_target_direction

	# Kiểm tra đã đến đích
	else:
		# Đến waypoint → load waypoint tiếp theo nếu có, nếu không thì về IDLE (trừ trường hợp đang shift direction move)
		is_at_current_waypoint_threshold = true
		if ship_movement_waypoints.size() > 0:
			# Nếu waypoint tiếp theo là shift và đang ở SHIFT_MOVE (chưa confirm hướng), thì giữ nguyên, không load tiếp
			var next_wp = ship_movement_waypoints.front()
			if next_wp.type == "shift" and current_input_state == FlightInputState.SHIFT_MOVE:
				# Đang chỉnh hướng shift waypoint, giữ nguyên vị trí, không load tiếp
				# Không còn waypoint nào thì về IDLE
				change_state(PlayerState.IDLE)
			else:
				# Nếu là waypoint thường hoặc đang không ở SHIFT_MOVE thì load waypoint tiếp theo bình thường
				load_next_waypoint()
		
		# Đã hết waypoint
		else:
			# Chỉnh hướng về phía mà waypoint đã set
			if current_waypoint and is_instance_valid(current_waypoint.point_marker):
				current_waypoint.point_marker.queue_free()

			# Giữ hướng ship về phương ngang mặt đất khi về IDLE
			current_target_direction = Vector3(current_waypoint.arrival_facing.x, 0.0, current_waypoint.arrival_facing.z)
			current_waypoint = null

			_dbg_direction = current_target_direction
			change_state(PlayerState.IDLE)
	
	# Set hướng mà ship sẽ hướng tới để update_rotation xử lý xoay
	rotation_desired_direction = current_target_direction

	# Tính thrust dựa trên alignment
	if current_waypoint:
		compute_sequence_move_thrust_control(state, current_target_direction, distance_to_target, delta)

func compute_shift_move_target_direction(state: PhysicsDirectBodyState3D, distance_to_target: float, direction_to_target: Vector3, ship_heading: Vector3, delta: float) -> void:
	# Nếu còn xa đích → hướng về target trực tiếp
	if distance_to_target > arrival_radius and not is_at_current_shift_waypoint_threshold:
		# Set hướng từ vị trí hiện tại đến target làm hướng di chuyển
		current_target_direction = direction_to_target

		# Chuẩn hóa arrival_facing về mặt phẳng ngang
		direction_to_target.y = 0.0
		var waypoint_arrival_direction := Vector3(current_waypoint.arrival_facing.x, 0.0, current_waypoint.arrival_facing.z)

		# ── TÍNH QUÃNG ĐƯỜNG CẦN BẮT ĐẦU XOAY ────────────────────────────────────
		# Góc cần xoay từ direction_to_target → arrival_facing
		var angle := ship_heading.angle_to(waypoint_arrival_direction)

		# Vận tốc góc tối đa thực tế theo RCS
		var desired_turn_speed := max_angular_speed * (max_turn_torque_rcs / mass)

		# Thời gian cần để hoàn thành xoay (ω = const = max)
		var time_to_rotate: float = angle / max(desired_turn_speed, 0.0001)

		# Quãng đường tàu sẽ đi trong thời gian xoay đó
		var linear_speed := state.linear_velocity.length()
		var rotate_start_dist: float = linear_speed * time_to_rotate * 1.5
		rotate_start_dist = max(rotate_start_dist, arrival_radius * 3.0)  # Tối thiểu 3× radius

		# ── BLEND direction_to_target → arrival_facing ─────────────────────────────
		var blend_t := 0.0
		if distance_to_target <= rotate_start_dist:
			# 0 = đang ở điểm bắt đầu xoay, 1 = đã đến đích
			blend_t = clamp(1.0 - distance_to_target / rotate_start_dist, 0.0, 1.0)
			# Ease-in-out: bắt đầu chậm → giữa nhanh → gần đích giữ nguyên
			blend_t = ease(blend_t, 2.0)

		rotation_desired_direction = ship_heading.slerp(waypoint_arrival_direction, blend_t).normalized()

		# Debug
		_dbg_direction = current_target_direction
		_dbg_rotation_start_dist = rotate_start_dist
		_dbg_angle_to_target = angle
		_dbg_time_to_rotate = time_to_rotate

	# Kiểm tra đã đến đích
	elif distance_to_target <= arrival_radius:
		# Đến waypoint → load waypoint tiếp theo nếu có, nếu không thì về IDLE (trừ trường hợp đang shift direction move)
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

			# Set hướng mà ship sẽ hướng tới để update_rotation xử lý xoay
			rotation_desired_direction = current_target_direction
			is_at_current_shift_waypoint_threshold = true

			_dbg_direction = current_target_direction
   
			change_state(PlayerState.IDLE)
		
	# Tính thrust dựa trên alignment
	if current_waypoint:
		compute_shift_move_thrust_control(state, current_target_direction, distance_to_target, delta)
		

## Tính toán lực sử dụng cho Shift move
func compute_shift_move_thrust_control(state: PhysicsDirectBodyState3D, direction: Vector3, distance: float, delta: float) -> void:
	# Shift move có cùng logic tính thrust nhưng không có braking distance để chỉnh hướng
	var heading := -state.transform.basis.z
	var alignment := heading.dot(direction)
	var linear_speed := state.linear_velocity.length()
	var braking_dist := (mass * linear_speed * linear_speed) / (2.0 * max_thrust_force * linear_power_to_mass_ratio)
	var ramp_speed := max_thrust_force / linear_accel_time * delta

	if distance > braking_dist:
		auto_throttle = pow(clamp(alignment, 0.5, 1.0), 3)
		ramp_speed = clamp(ramp_speed, -max_thrust_force, max_thrust_force)
		current_thrust_force = move_toward(current_thrust_force, max_thrust_force, ramp_speed)  
		state.apply_central_force(direction * current_thrust_force * auto_throttle)
	else:
		auto_throttle = lerp(auto_throttle, 0.0, delta)
		current_thrust_force = move_toward(current_thrust_force, 0.0, ramp_speed)
		state.apply_central_force(-state.linear_velocity * max_thrust_force * linear_power_to_mass_ratio)

## Tính toán thrust và áp dụng lực đẩy
func compute_sequence_move_thrust_control(state: PhysicsDirectBodyState3D, direction: Vector3, distance: float, delta: float) -> void:
	var heading := -state.transform.basis.z
	var alignment := heading.dot(direction)
	var linear_speed := state.linear_velocity.length()
	var braking_dist := (mass * linear_speed * linear_speed) / (2.0 * max_thrust_force * linear_power_to_mass_ratio)
	var ramp_speed := max_thrust_force / linear_accel_time * delta

	# Debug
	_dbg_braking_dist = braking_dist

	# Checking alignment để quyết định có được phép đẩy hay không
	if alignment >= 0.85:
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
func compute_sequence_move_lateral_damping(state: PhysicsDirectBodyState3D, delta: float) -> void:
	# Tách vận tốc thành forward + lateral
	var current_heading := -state.transform.basis.z
	var forward_speed := state.linear_velocity.dot(current_heading)
	forward_velocity  = current_heading * forward_speed
	lateral_velocity  = state.linear_velocity - forward_velocity
	
	# Triệt tiêu vận tốc ngang lateral (chống trượt quá đà)
	var lateral_damp = lateral_damp_value * linear_power_to_mass_ratio	# Điều chỉnh damping theo tỷ lệ lực/mass để đảm bảo hiệu quả trên nhiều loại tàu
	lateral_velocity = lateral_velocity.lerp(Vector3.ZERO, lateral_damp * delta)	# Lerp để giảm dần vận tốc ngang về 0
	state.linear_velocity = forward_velocity + lateral_velocity

	_dbg_forward_vel  = forward_velocity
	_dbg_lateral_vel  = lateral_velocity
	_dbg_linear_vel   = state.linear_velocity


## Triệt tiêu trượt ngang và damping khi IDLE
func compute_shift_move_lateral_damping(state: PhysicsDirectBodyState3D, delta: float) -> void:
	# Tách vận tốc thành forward + lateral
	var current_heading := -state.transform.basis.z
	var forward_speed := state.linear_velocity.dot(current_heading)
	forward_velocity  = current_heading * forward_speed
	lateral_velocity  = state.linear_velocity - forward_velocity

	# Giữ lại vận tốc ngang hiện tại của ship khi đang shift move
	state.linear_velocity = forward_velocity + lateral_velocity

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
		# Phát hiện sự thay đổi góc đột ngột -> ngay lập tức dừng mọi xoay nhỏ
		rotation_delay_timer = rotation_start_delay
		angle_change_factor = 0.0
		state.angular_velocity = state.angular_velocity * 0.5 # Giảm mạnh vận tốc góc hiện tại để tránh quay lố
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
				# current_pitch_vel = Vector3.ZERO
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
		current_ship_origin_position = -global_transform.basis.z if global_position != Vector3.ZERO else Vector3.FORWARD

		#3 Reset arival flag
		is_at_current_waypoint_threshold = false
		is_at_brake_distance = false
		is_at_current_shift_waypoint_threshold = false
		
	else:
		current_waypoint = null

# Hàm tạo shift waypoint
func create_shift_waypoint(wp_pos: Vector3) -> void:
	var shift_pos := wp_pos * Vector3(1, 0, 1) + Vector3(0, global_position.y + current_target_height_offset, 0)
	shift_pos = clamp_shift_target_to_max_radius(shift_pos)
	shift_target_position = shift_pos
	shift_target_distance = global_position.distance_to(shift_pos)
	var shift_waypoint = Movement_Waypoint.new(shift_pos, global_position, "shift")
	ship_movement_waypoints.append(shift_waypoint)
	add_child(shift_waypoint.point_marker)

# ============================= DEBUG MESH =============================================

func draw_debug_vectors(desired_direction: Vector3, fwd_vel: Vector3, lat_vel: Vector3, lin_vel: Vector3) -> void:
	var origin := global_position + Vector3(0, 2.0, 0)
	
	DebugDraw3D.draw_arrow(origin, origin + desired_direction * 5.0, Color.GREEN, 0.1)	# Desired direction (hướng mục tiêu) — xanh lá
	DebugDraw3D.draw_arrow(origin, origin + fwd_vel * 2.0, Color.BLUE, 0.1)	# Forward velocity (vận tốc về hướng trước) — xanh dương
	DebugDraw3D.draw_arrow(origin, origin + lat_vel * 2.0, Color.RED, 0.1)	# Lateral velocity (vận tốc ngang) — đỏ
	DebugDraw3D.draw_arrow(origin, origin + lin_vel * 1.0, Color.PURPLE, 0.1)	# Linear velocity (vận tốc tổng thể) — tím

	# Arrival facing preview — vẽ từ vị trí waypoint cuối
	if arrival_facing_preview_active and arrival_facing_preview_direction != Vector3.ZERO:
		var wp_origin := global_position
		if not ship_movement_waypoints.is_empty():
			wp_origin = ship_movement_waypoints.back().position
		elif current_waypoint != null:
			wp_origin = current_waypoint.position
		wp_origin += Vector3(0, 0, 0)
		
		DebugDraw3D.draw_arrow(wp_origin, wp_origin + arrival_facing_preview_direction * 6.0, Color.YELLOW, 0.1)
	
	# Waypoint connect
	var points: PackedVector3Array = PackedVector3Array()
	
	# 1. Thêm điểm đang bay tới hiện tại (nếu đang di chuyển)
	if current_state == PlayerState.MOVE:
		points.append(current_target_position + Vector3(0, 0.0, 0))
	
	# 2. Thêm các waypoint còn lại trong hàng đợi
	for wp in ship_movement_waypoints:
		points.append(wp.position + Vector3(0, 0.0, 0))
		
	# 3. Vẽ toàn bộ đường đi bằng DebugDraw3D (chỉ vẽ khi có từ 2 điểm trở lên)
	if points.size() >= 2:
		# Duyệt qua mảng và nối từng cặp điểm lại với nhau
		for i in range(points.size() - 1):
			DebugDraw3D.draw_line(points[i], points[i + 1], Color.GREEN)

	elif points.size() == 1:
		# Nếu chỉ có 1 điểm duy nhất, vẽ một vị trí nhỏ để dễ nhìn
		DebugDraw3D.draw_position(Transform3D(Basis(), points[0]), Color.GREEN)

## Vẽ debug shift: lines (mọi frame) + fill mesh (chỉ rebuild khi dirty)
func _draw_shift_debug(ship_position: Vector3, shift_target_pos: Vector3) -> void:
	# --- Màu ---
	var col_h      := Color(0.18, 0.97, 0.38, 1.0)   # Quạt ngang  – xanh matrix sáng
	var col_v      := Color(0.4,  1.0,  0.55, 1.0)   # Quạt dọc   – xanh matrix nhạt
	var col_actual := Color(0.75, 1.0,  0.2,  0.9)   # Tia thực tế – vàng xanh
	var fill_h     := Color(0.18, 0.97, 0.38, 0.13)  # Fill quạt ngang – xanh matrix mờ
	var fill_v     := Color(0.4,  1.0,  0.55, 0.20)  # Fill quạt dọc   – xanh matrix đậm hơn

	# --- Tham số chung ---
	var half_angle_h: float = deg_to_rad(20.0)
	var half_angle_v: float = deg_to_rad(60.0)
	var arc_steps    := 16
	var fill_steps   := 24
	var max_radius: float = maxf(0.1, shift_max_radius)

	# --- Thiết lập vector cơ bản ---
	var origin_flat  := ship_position
	var target_flat  := Vector3(shift_target_pos.x, ship_position.y, shift_target_pos.z)
	var dir_flat     := target_flat - origin_flat
	var radius_xz_raw: float = dir_flat.length()
	var radius_xz: float     = minf(radius_xz_raw, max_radius)

	if radius_xz > 0.1:
		dir_flat = dir_flat.normalized()
		var center_tip: Vector3 = origin_flat + dir_flat * radius_xz

		# --- Tham số phụ thuộc vào hướng ---
		var y_offset: float    = shift_target_pos.y - ship_position.y
		var y_limit: float     = tan(half_angle_v) * radius_xz
		var y_clamped: float   = sign(y_offset) * minf(abs(y_offset), y_limit)
		var open_angle: float  = atan2(y_clamped, radius_xz)
		var pitch_axis: Vector3   = dir_flat.cross(Vector3.UP).normalized()
		var fixed_dir_3d: Vector3 = (center_tip - ship_position).normalized()

		# ==================== LINES (DebugDraw3D, mọi frame) ====================

		# Quạt ngang: tia trung tâm + hai cạnh biên
		var left_tip:  Vector3 = origin_flat + dir_flat.rotated(Vector3.UP,  half_angle_h) * radius_xz
		var right_tip: Vector3 = origin_flat + dir_flat.rotated(Vector3.UP, -half_angle_h) * radius_xz
		DebugDraw3D.draw_line(origin_flat, center_tip, col_h)
		DebugDraw3D.draw_line(origin_flat, left_tip,   col_h)
		DebugDraw3D.draw_line(origin_flat, right_tip,  col_h)

		# Cung tròn quạt ngang
		var arc_pts := PackedVector3Array()
		for i in range(arc_steps + 1):
			var ang: float = lerpf(-half_angle_h, half_angle_h, float(i) / float(arc_steps))
			arc_pts.append(origin_flat + dir_flat.rotated(Vector3.UP, ang) * radius_xz)
		DebugDraw3D.draw_line_path(arc_pts, col_h)

		# Quạt dọc: tia giới hạn + tia mở + tia thực tế
		var shift_tip_limited: Vector3 = Vector3(center_tip.x, ship_position.y + y_clamped, center_tip.z)
		var shift_tip_actual:  Vector3 = Vector3(center_tip.x, shift_target_pos.y, center_tip.z)
		var open_tip: Vector3          = ship_position + fixed_dir_3d.rotated(pitch_axis, open_angle) * radius_xz
		DebugDraw3D.draw_line(ship_position, shift_tip_limited, col_v)
		DebugDraw3D.draw_line(center_tip,    shift_tip_actual,  col_actual)
		DebugDraw3D.draw_line(ship_position, open_tip,          col_v)

		# Cung tròn quạt dọc
		if abs(open_angle) > 0.0001:
			var v_steps := maxi(2, int(round(float(arc_steps) * abs(open_angle) / half_angle_v)))
			var v_arc_pts := PackedVector3Array()
			for i in range(v_steps + 1):
				var ang: float = lerpf(0.0, open_angle, float(i) / float(v_steps))
				v_arc_pts.append(ship_position + fixed_dir_3d.rotated(pitch_axis, ang) * radius_xz)
			DebugDraw3D.draw_line_path(v_arc_pts, col_v)

		# ==================== FILL (ArrayMesh, chỉ khi dirty) ====================

		var _pos_moved: bool = ship_position.distance_squared_to(_dbg_ship_position) > 0.01
		var _tgt_moved: bool = shift_target_pos.distance_squared_to(_dbg_shift_target) > 0.01
		if _pos_moved or _tgt_moved:
			var am := debug_fill_mesh.mesh as ArrayMesh
			am.clear_surfaces()
			var verts  := PackedVector3Array()
			var colors := PackedColorArray()

			# Fill quạt ngang
			for i in range(fill_steps):
				var ang0: float = lerpf(-half_angle_h, half_angle_h, float(i)     / float(fill_steps))
				var ang1: float = lerpf(-half_angle_h, half_angle_h, float(i + 1) / float(fill_steps))
				var p0: Vector3 = origin_flat + dir_flat.rotated(Vector3.UP, ang0) * radius_xz
				var p1: Vector3 = origin_flat + dir_flat.rotated(Vector3.UP, ang1) * radius_xz
				verts.append(origin_flat); colors.append(fill_h)
				verts.append(p0);          colors.append(fill_h)
				verts.append(p1);          colors.append(fill_h)

			# Fill quạt dọc
			var abs_open: float = abs(open_angle)
			if abs_open > 0.0001:
				var step_count: int = maxi(2, int(round(float(fill_steps) * abs_open / half_angle_v)))
				for i in range(step_count):
					var ang0: float = lerpf(0.0, open_angle, float(i)     / float(step_count))
					var ang1: float = lerpf(0.0, open_angle, float(i + 1) / float(step_count))
					var p0: Vector3 = ship_position + fixed_dir_3d.rotated(pitch_axis, ang0) * radius_xz
					var p1: Vector3 = ship_position + fixed_dir_3d.rotated(pitch_axis, ang1) * radius_xz
					verts.append(ship_position); colors.append(fill_v)
					verts.append(p0);            colors.append(fill_v)
					verts.append(p1);            colors.append(fill_v)

			if not verts.is_empty():
				var arrays: Array = []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = verts
				arrays[Mesh.ARRAY_COLOR]  = colors
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

			_dbg_ship_position = ship_position
			_dbg_shift_target  = shift_target_pos

	else:
		# Hover ngay trên ship (radius_xz ≈ 0): indicator dọc thẳng đứng
		var y_offset_direct: float = shift_target_pos.y - ship_position.y
		if abs(y_offset_direct) > 0.05:
			var tip_direct: Vector3 = ship_position + Vector3.UP * y_offset_direct
			DebugDraw3D.draw_line(ship_position, tip_direct, col_v)
			var perp: float = 0.5
			DebugDraw3D.draw_line(tip_direct + Vector3(-perp, 0, 0), tip_direct + Vector3(perp, 0, 0), col_v)
			DebugDraw3D.draw_line(tip_direct + Vector3(0, 0, -perp), tip_direct + Vector3(0, 0, perp), col_v)

	# Vòng tròn giới hạn shift_max_radius
	var limit_color := Color.ORANGE_RED if radius_xz_raw > max_radius else Color(1.0, 0.5, 0.0, 0.6)
	var circle_pts := PackedVector3Array()
	for i in range(37):
		var a: float = TAU * float(i) / 36.0
		circle_pts.append(origin_flat + Vector3(cos(a), 0.0, sin(a)) * max_radius)
	DebugDraw3D.draw_line_path(circle_pts, limit_color)
