extends Node

# ============================== GAMEPLAY INPUT MODE ======================================
# Camera mode và gameplay mode là 2 thứ khác nhau:
# - Camera mode: camera nào đang active (free, character, ...)
# - Gameplay mode: người chơi đang làm gì với world (flight, facing_set, builder, ...)
# Vì vậy switch camera KHÔNG được tự động tắt input gameplay.

enum GameplayInputMode {
	FLIGHT,
	# FACING_SET,
	# BUILDER,
}

var current_gameplay_mode: GameplayInputMode = GameplayInputMode.FLIGHT

# ============================== NODE REFS ======================================

@onready var ship_player: Node3D               = $Ship_Player/RigidBody3D
@onready var camera_3d_free: Node3D            = $Camera_Free
@onready var camera_3d_character_far: Node3D   = $Ship_Player/RigidBody3D/Camera_Pivot_Far
@onready var camera_3d_character_close: Node3D = $Ship_Player/RigidBody3D/Camera_Pivot_Close

# ============================== FLIGHT INPUT STATE MACHINE ======================================
# Thay thế các boolean flags rời rạc bằng state machine tường minh.
#
# IDLE            → không có gì đang xảy ra
# SEQUENCE_PENDING → vừa nhấn chuột + sequence, đang chờ timer phân biệt click vs hold
# FACING_HOLD     → giữ đủ lâu, chờ drag để set arrival_facing (chưa kéo đủ pixel)
# FACING_DRAG     → đang kéo chuột để set arrival_facing (đã kéo đủ pixel)

enum FlightInputState { IDLE, SEQUENCE_MOVE, FACING_HOLD, FACING_DRAG }
var _flight_input_state: FlightInputState = FlightInputState.IDLE

# Shared data giữa các state
var _facing_drag_threshold := 12.0      # pixel tối thiểu để vào FACING_DRAG
var _facing_drag_accumulated := 0.0     # tổng pixel đã kéo
var _facing_dir_accum := Vector2.ZERO   # tổng vector 2D để tính hướng world
var _hold_timer := 0.0                  # đếm thời gian giữ (SEQUENCE_PENDING)
var _hold_threshold := 0.2              # giây: dưới = click, trên = hold
var _pending_click_pos := Vector3.ZERO  # vị trí world lưu lại khi nhấn

# ============================== FLIGHT STATE TRANSITION ======================================

func _change_flight_state(new_state: FlightInputState) -> void:
	if _flight_input_state == new_state: return

	# EXIT state cũ
	match _flight_input_state:
		FlightInputState.SEQUENCE_MOVE:
			_hold_timer = 0.0
		FlightInputState.FACING_HOLD, FlightInputState.FACING_DRAG:
			_facing_drag_accumulated = 0.0
			_facing_dir_accum = Vector2.ZERO

	# ENTER state mới
	match new_state:
		FlightInputState.SEQUENCE_MOVE:
			_hold_timer = 0.0
		FlightInputState.FACING_HOLD:
			_facing_drag_accumulated = 0.0
			_facing_dir_accum = Vector2.ZERO
		FlightInputState.IDLE:
			pass

	_flight_input_state = new_state

# ============================== READY ======================================

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Add camera to Global list
	Global_Camera.current_camera_list[Global_Camera.CameraType.FREE] = camera_3d_free
	Global_Camera.current_camera_list[Global_Camera.CameraType.SHIP_FAR] = camera_3d_character_far
	Global_Camera.current_camera_list[Global_Camera.CameraType.SHIP_CLOSE] = camera_3d_character_close
	
	Global_Camera.switch_to(camera_3d_character_far)

# ============================== PROCESS ======================================

func _process(delta: float) -> void:
	match _flight_input_state:
		FlightInputState.SEQUENCE_MOVE:
			_hold_timer += delta
			if _hold_timer >= _hold_threshold:
				# Giữ đủ lâu → vào FACING_HOLD: chờ drag, KHÔNG tạo waypoint
				_change_flight_state(FlightInputState.FACING_HOLD)

# ============================== INPUT ROUTER ======================================
# _input() chạy theo thứ tự ưu tiên:
#   1. Global input
#   2. Active camera input (zoom/orbit/look)
#   3. Gameplay input (move/facing/builder...)
# Camera active có thể là free camera nhưng gameplay vẫn là FLIGHT bình thường.

func _input(event: InputEvent) -> void:
	if _input_global(event):
		get_viewport().set_input_as_handled()
		return

	#if _input_active_camera(event):
		#get_viewport().set_input_as_handled()
		#return

	match current_gameplay_mode:
		GameplayInputMode.FLIGHT: _input_flight(event)

# ============================== GLOBAL INPUT (luôn active) ======================================

func _input_global(event: InputEvent) -> bool:
	# Toggle mouse capture / release
	#if event.is_action_pressed("ui_cancel"):
		#if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		#else:
			#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#return true

	## Chuyển đổi giữa Free Camera và Character Camera
	#if event.is_action_pressed("change_camera_bw_free_n_character"):
		#if Global_Camera.current_rig == camera_3d_free:
			#Global_Camera.switch_to(camera_3d_character_far)
		#else:
			#Global_Camera.switch_to(camera_3d_free)
		#return true
#
	## Chuyển đổi giữa Far và Close (chỉ khi đang ở camera nhân vật)
	#if event.is_action_pressed("change_camera_character"):
		#if Global_Camera.current_rig == camera_3d_character_far:
			#Global_Camera.switch_to(camera_3d_character_close)
			#return true
		#elif Global_Camera.current_rig == camera_3d_character_close:
			#Global_Camera.switch_to(camera_3d_character_far)
			#return true
	
	Global_Input._input(event)
	return false

func _input_active_camera(event: InputEvent) -> bool:
	if Global_Camera.current_rig == null:
		return false

	#if Global_Camera.current_rig.has_method("handle_scene_input"):
		#return Global_Camera.current_rig.handle_scene_input(event)
	
	Global_Camera._input(event)

	return false

# ============================== FLIGHT INPUT ======================================

func _input_flight(event: InputEvent) -> void:
	# Scroll và modifier luôn active bất kể state
	_handle_modifier_and_scroll(event)

	# Mỗi state tự xử lý input của nó
	match _flight_input_state:
		FlightInputState.IDLE:             _state_idle(event)
		FlightInputState.SEQUENCE_MOVE: _state_sequence_move(event)
		FlightInputState.FACING_HOLD:      _state_facing_hold(event)
		FlightInputState.FACING_DRAG:      _state_facing_drag(event)

# --- IDLE: chờ input ---
func _state_idle(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE): return
	var cam_3d = Global_Camera.get_active_camera()
	if not cam_3d: return
	var click_pos = Global_RayQuery3d.shoot_ray_3d(cam_3d, ship_player)
	if click_pos == null: return

	if event.is_action("move"):
		if Input.is_action_pressed("sequence_move"):
			_pending_click_pos = click_pos
			_change_flight_state(FlightInputState.SEQUENCE_MOVE)
		else:
			ship_player.move_to(click_pos, false)
		get_viewport().set_input_as_handled()

	elif event.is_action("clear_waypoints"):
		ship_player.clear_all_waypoints()
		ship_player.change_state(ship_player.PlayerState.IDLE)
		get_viewport().set_input_as_handled()

# --- SEQUENCE_MOVE: đang chờ timer phân biệt click vs hold ---
func _state_sequence_move(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.is_action("move"):
		# Thả nhanh → CLICK: tạo waypoint mới
		ship_player.move_to(_pending_click_pos, true)
		_change_flight_state(FlightInputState.IDLE)
		get_viewport().set_input_as_handled()

# --- FACING_HOLD: giữ đủ lâu, chờ drag ---
func _state_facing_hold(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.is_action("move"):
		# Thả mà chưa drag → không làm gì, về IDLE
		_change_flight_state(FlightInputState.IDLE)
		return

	if event is InputEventMouseMotion:
		_facing_drag_accumulated += event.relative.length()
		_facing_dir_accum += event.relative
		if _facing_drag_accumulated > _facing_drag_threshold:
			_change_flight_state(FlightInputState.FACING_DRAG)

# --- FACING_DRAG: đang kéo để set hướng ---
func _state_facing_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.is_action("move"):
		# Thả chuột → confirm arrival facing
		ship_player.confirm_last_waypoint_arrival_facing()
		ship_player.set_arrival_facing_preview(Vector3.ZERO, false)
		_change_flight_state(FlightInputState.IDLE)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_facing_dir_accum += event.relative
		var preview_dir := _get_facing_dir_from_accum(_facing_dir_accum)
		if preview_dir != Vector3.ZERO:
			ship_player.set_arrival_facing_preview(preview_dir, true)

# --- Modifier + Scroll + Shift preview: luôn active ---
func _handle_modifier_and_scroll(event: InputEvent) -> void:
	var is_shift := Input.is_action_pressed("direction_shift_move")
	var is_seq   := Input.is_action_pressed("sequence_move")

	if is_shift:   ship_player.change_moving_state(ship_player.ShipMovingMode.SHIFT_DIRECTION)
	elif is_seq:   ship_player.change_moving_state(ship_player.ShipMovingMode.SEQUENCE)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if is_shift:
				ship_player.adjust_shift_target_height(offset)
				get_viewport().set_input_as_handled()
			elif is_seq:
				ship_player.adjust_waypoint_target_height(offset)
				get_viewport().set_input_as_handled()

	if event.is_action_pressed("direction_shift_move"):
		var cam_3d = Global_Camera.get_active_camera()
		if cam_3d:
			var click_pos = Global_RayQuery3d.shoot_ray_3d(cam_3d, ship_player)
			if click_pos != null:
				ship_player.create_shift_waypoint(click_pos)
				get_viewport().set_input_as_handled()

# ============================== ARRIVAL FACING HELPER ======================================

## Chuyển đổi tổng delta 2D chuột → hướng world XZ dựa theo camera hiện tại
## accum.x dương = kéo phải → hướng camera-right
## accum.y dương = kéo xuống → hướng camera-forward (vào màn hình)
func _get_facing_dir_from_accum(accum: Vector2) -> Vector3:
	if accum.length_squared() < 1.0:
		return Vector3.ZERO
	var cam := Global_Camera.get_active_camera()
	if cam == null:
		return Vector3.ZERO
	var cam_right := cam.global_transform.basis.x                           # trục X world của camera
	var cam_forward_flat := cam.global_transform.basis.z                    # trục Z world (hướng ra phía sau camera)
	cam_forward_flat.y = 0.0
	if cam_forward_flat.length_squared() < 0.0001:
		cam_forward_flat = Vector3.FORWARD
	else:
		cam_forward_flat = cam_forward_flat.normalized()
	# kéo chuột phải (accum.x+) → ship facing sang phải so với camera
	# kéo chuột xuống (accum.y+) → ship facing ra phía sau camera (vào trong màn hình)
	var world_dir := cam_right * accum.x + cam_forward_flat * accum.y
	world_dir.y = 0.0
	if world_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return world_dir.normalized()

# ============================== GAMEPLAY MODE SWITCHER ==============================

func _switch_gameplay_mode(new_mode: GameplayInputMode) -> void:
	if current_gameplay_mode == new_mode:
		return
	print("[GameplayInputMode] ", GameplayInputMode.keys()[current_gameplay_mode], " → ", GameplayInputMode.keys()[new_mode])
	current_gameplay_mode = new_mode
