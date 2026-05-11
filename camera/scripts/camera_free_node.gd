extends CameraRigBase

@export_group("Free Camera Settings")
@export var acceleration := 100.0
@export var move_speed := 18.0
@export_range(0.0, 20.0, 1.0, "length_number") var min_camera_zoom := 0.0
@export_range(0.0, 20.0, 1.0, "length_number") var max_camera_zoom := 0.0
@export var zoom_step := 1.0
@export var min_vertical_angle := -PI/2
@export var max_vertical_angle := PI/2

var velocity := Vector3.ZERO
var look_angles := Vector2.ZERO

func _ready() -> void:
	super._ready()
	deactivate() # Mặc định tắt khi mới load scene

func handle_scene_input(event: InputEvent) -> bool:
	#if not is_active:
		#return false
#
	#if Input.is_action_pressed("sequence_move") or Input.is_action_pressed("direction_shift_move"):
		#return false

	# Xoay camera bằng chuột
	# Xoay theo 2 node: Node gốc xoay ngang, node spring arm xoay dọc
	#if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		## Nhìn trái/phải: Xoay toàn bộ cụm theo trục Y
		#rotation.y -= event.relative.x * mouse_sensitivity
		#
		## Nhìn lên/xuống: Chỉ xoay SpringArm theo trục X (Đảo dấu trừ thành trừ)
		#spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
		#
		## Giới hạn góc nhìn lên xuống không bị lộn vòng (90 độ)
		#spring_arm.rotation.x = clamp(spring_arm.rotation.x, min_vertical_angle, max_vertical_angle)
		#return true

	# if event is InputEventMouseButton and event.pressed:
	# 	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
	# 		spring_arm.spring_length = max(min_camera_zoom, spring_arm.spring_length - zoom_step)
	# 		return true
	# 	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
	# 		spring_arm.spring_length = min(max_camera_zoom, spring_arm.spring_length + zoom_step)
	# 		return true

	return false

func _process(delta: float) -> void:
	# Không gọi super._process() — free camera không reset rotation về base
	if not is_active: return
	
	# Xử lý input di chuyển (WASD)
	# Input.get_vector trả về x, y. Trong đó move_forward tương ứng với Y âm.
	var raw_input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var vertical = float(Input.is_action_pressed("move_up")) - float(Input.is_action_pressed("move_down"))
	
	# Tính hướng di chuyển từ input, dùng basic của camera (trực x - z)
	var move_direction = (camera_3d.global_transform.basis * Vector3(raw_input.x, 0, raw_input.y)).normalized()
	
	# Cộng thêm trục dọc (y) theo không gian thế giới (Global Y) để dễ điều khiển
	move_direction.y += vertical
	move_direction = move_direction.normalized()
	
	if move_direction.length_squared() > 0:
		velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	else:
		velocity = Vector3.ZERO
		
	# Dùng global_position để cộng dồn vì move_dir đã được tính theo hệ quy chiếu global
	global_position += velocity * delta
