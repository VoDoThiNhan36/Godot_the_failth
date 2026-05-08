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

# ============================== SEQUENCE HOLD STATE (arrival facing) ======================================
# sequence + click       → tạo waypoint bình thường
# sequence + giữ + kéo  → drag để set hướng tàu khi đến đích (arrival_facing)
# thả chuột             → confirm hướng vừa kéo

var _is_holding_sequence_mouse := false   # đang trong drag-facing mode (đã qua hold threshold)
var _is_in_facing_drag_mode := false       # đã vượt pixel threshold → đang drag để set facing
var _facing_drag_threshold := 12.0        # pixel tối thiểu cần kéo để kích hoạt
var _facing_drag_accumulated := 0.0       # tổng pixel đã kéo
var _facing_dir_accum := Vector2.ZERO     # tổng delta 2D để tính hướng world

# Timer để phân biệt "click nhanh" vs "giữ lâu"
var _is_press_pending := false            # đang chờ phân biệt click / hold
var _hold_timer := 0.0                   # đếm thời gian giữ chuột
var _hold_threshold := 0.2               # giây: dưới ngưỡng = click, trên = hold
var _pending_click_pos := Vector3.ZERO   # vị trí world lưu lại khi nhấn chuột

# ============================== READY ======================================

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Global_Camera.switch_to(camera_3d_character_far)

# ============================== PROCESS ======================================

func _process(delta: float) -> void:
	# Đếm thời gian giữ chuột để phân biệt click vs hold
	if _is_press_pending:
		_hold_timer += delta
		if _hold_timer >= _hold_threshold:
			# Đủ lâu → hold mode: chỉ adjust facing của waypoint cuối, KHÔNG tạo waypoint mới
			_is_press_pending = false
			_is_holding_sequence_mouse = true
			_facing_drag_accumulated = 0.0
			_facing_dir_accum = Vector2.ZERO

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

	if _input_active_camera(event):
		get_viewport().set_input_as_handled()
		return

	match current_gameplay_mode:
		GameplayInputMode.FLIGHT: _input_flight(event)

# ============================== GLOBAL INPUT (luôn active) ======================================

func _input_global(event: InputEvent) -> bool:
	# Toggle mouse capture / release
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return true

	# Chuyển đổi giữa Free Camera và Character Camera
	if event.is_action_pressed("change_camera_bw_free_n_character"):
		if Global_Camera.current_rig == camera_3d_free:
			Global_Camera.switch_to(camera_3d_character_far)
		else:
			Global_Camera.switch_to(camera_3d_free)
		return true

	# Chuyển đổi giữa Far và Close (chỉ khi đang ở camera nhân vật)
	if event.is_action_pressed("change_camera_character"):
		if Global_Camera.current_rig == camera_3d_character_far:
			Global_Camera.switch_to(camera_3d_character_close)
			return true
		elif Global_Camera.current_rig == camera_3d_character_close:
			Global_Camera.switch_to(camera_3d_character_far)
			return true

	return false

func _input_active_camera(event: InputEvent) -> bool:
	if Global_Camera.current_rig == null:
		return false

	if Global_Camera.current_rig.has_method("handle_scene_input"):
		return Global_Camera.current_rig.handle_scene_input(event)

	return false

# ============================== FLIGHT INPUT ======================================

func _input_flight(event: InputEvent) -> void:
	var is_direction_shift_pressed := Input.is_action_pressed("direction_shift_move")
	var is_sequence_pressed := Input.is_action_pressed("sequence_move")

	if is_direction_shift_pressed: ship_player.change_moving_state(ship_player.ShipMovingMode.SHIFT_DIRECTION)
	elif is_sequence_pressed: ship_player.change_moving_state(ship_player.ShipMovingMode.SEQUENCE)

	# ----------------------------------------------------------------
	# --- Click / Hold to move + set arrival facing ---
	# ----------------------------------------------------------------
	if event is InputEventMouseButton and event.is_action("move"):
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			var cam_3d = Global_Camera.get_active_camera()
			if cam_3d:
				var click_pos = Global_RayQuery3d.shoot_ray_3d(cam_3d, ship_player)
				if click_pos != null:
					if is_sequence_pressed and ship_player.current_moving_mode == ship_player.ShipMovingMode.SEQUENCE:
						# Sequence: buffer lại, chờ timer phân biệt click vs hold
						_pending_click_pos = click_pos
						_is_press_pending = true
						_hold_timer = 0.0
						_is_holding_sequence_mouse = false
						_is_in_facing_drag_mode = false
					else:
						# Không sequence → click thường, tạo waypoint ngay
						ship_player.move_to(click_pos, false)
					get_viewport().set_input_as_handled()

		elif not event.pressed:
			if _is_press_pending:
				# Thả nhanh (< hold_threshold) → click: tạo waypoint mới
				ship_player.move_to(_pending_click_pos, true)
				_is_press_pending = false
			elif _is_in_facing_drag_mode:
				# Thả sau drag → confirm arrival facing cho waypoint cuối
				ship_player.confirm_last_waypoint_arrival_facing()
				ship_player.set_arrival_facing_preview(Vector3.ZERO, false)
			_is_holding_sequence_mouse = false
			_is_in_facing_drag_mode = false
	
	# ----------------------------------------------------------------
	# --- Double click both mouse side to clear waypoint ---
	# ----------------------------------------------------------------
	if event is InputEventMouseButton and event.is_action("clear_waypoints") and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		ship_player.clear_all_waypoints()
		ship_player.change_state(ship_player.PlayerState.IDLE)
		get_viewport().set_input_as_handled()


	# ----------------------------------------------------------------
	# --- Mouse motion: update arrival facing preview khi đang giữ ---
	# ----------------------------------------------------------------
	if event is InputEventMouseMotion and _is_holding_sequence_mouse:
		_facing_drag_accumulated += event.relative.length()
		_facing_dir_accum += event.relative
		if _facing_drag_accumulated > _facing_drag_threshold:
			_is_in_facing_drag_mode = true
			var preview_dir := _get_facing_dir_from_accum(_facing_dir_accum)
			if preview_dir != Vector3.ZERO:
				ship_player.set_arrival_facing_preview(preview_dir, true)

	# ----------------------------------------------------------------
	# --- Scroll wheel ---
	# ----------------------------------------------------------------
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var offset := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0

			# direction_shift_move + Scroll: chỉnh độ cao shift direction
			if is_direction_shift_pressed:
				ship_player.adjust_shift_target_height(offset)
				get_viewport().set_input_as_handled()

			# sequence_move + Scroll: chỉnh độ cao waypoint cuối
			elif is_sequence_pressed:
				ship_player.adjust_waypoint_target_height(offset)
				get_viewport().set_input_as_handled()
	
	# ----------------------------------------------------------------
	# --- Press shift move: create preview waypoint ---
	# ----------------------------------------------------------------
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
