extends CameraRigBase

@export_group("Character Camera Settings")
@export var min_zoom := 6.0
@export var max_zoom := 20.0
@export var zoom_step := 1.0
@export var min_vertical_angle := -PI/4
@export var max_vertical_angle := PI/4
@export var return_speed := 10.0

var is_holding_to_rotate := false
var base_quaternion: Quaternion

func _ready() -> void:
	super._ready()
	base_quaternion = quaternion
	deactivate()

func handle_scene_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	
	# Giữ phím để xoay camera quanh tàu (Orbit)
	if event.is_action_pressed("hold_to_rotate_camera"):
		is_holding_to_rotate = true
		return true
	elif event.is_action_released("hold_to_rotate_camera"):
		is_holding_to_rotate = false
		return true

	# Xoay khi giữ phím
	if is_holding_to_rotate and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		rotation.x -= event.relative.y * mouse_sensitivity
		rotation.x = clamp(rotation.x, min_vertical_angle, max_vertical_angle)
		return true

	# Zoom
	if Input.is_action_pressed("sequence_move") or Input.is_action_pressed("direction_shift_move"): 
		return false # Không zoom khi đang giữ phím di chuyển sequence / shift
	
	else:
		if event.is_action_pressed("camera_zoom_in"):
			spring_arm.spring_length = max(min_zoom, spring_arm.spring_length - zoom_step)
			return true
		if event.is_action_pressed("camera_zoom_out"):
			spring_arm.spring_length = min(max_zoom, spring_arm.spring_length + zoom_step)
			return true

	return false

func _process(delta: float) -> void:
	if not is_active: return
	
	# Reset camera về sau đuôi tàu khi thả chuột
	if not is_holding_to_rotate:
		quaternion = quaternion.slerp(base_quaternion, return_speed * delta)
