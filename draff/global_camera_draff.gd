extends Node

@export_group("camera")
@export_range(0.0, 1.0) var mouse_sensitivity := 0.2
#@export_range(1.0, 20.0, 1.0, "length_number") var min_camera_zoom := 1.0
#@export_range(1.0, 20.0, 1.0, "length_number") var max_camera_zoom := 20.0
@export_range(-90.0, 0.0, 0.1, "radian_as_degree") var min_camera_vertical_angle := -PI/4
@export_range(0.0, 90.0, 0.1, "radian_as_degree") var max_camera_vertical_angle := PI/4
#@export var max_horizontal_angle = deg_to_rad(90)
@export var rotation_speed := 8.0

var current_camera_name: String = ""
var current_camera_node: Node3D = null
var current_spring_arm_3d: SpringArm3D = null
var current_camera_3d: Camera3D = null
var camera_input_direction := Vector2.ZERO
var last_input_direction := Vector3(0, deg_to_rad(90), 0)

#----------------------------------------- DEFAULT FUNCTION ------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		#mosue motion input capture, angle + sensitive
		camera_input_direction = event.relative * mouse_sensitivity

func _input(event: InputEvent) -> void:
	pass

func _ready() -> void:
	pass

#----------------------------------------- CUSTOM FUNCTION ------------------------------------------
func is_moving_input_pressed() -> bool:
	return Input.is_action_pressed("move_left") or \
		Input.is_action_pressed("move_right") or \
		Input.is_action_pressed("move_forward") or \
		Input.is_action_pressed("move_backward") or \
		Input.is_action_pressed("move_up") or \
		Input.is_action_pressed("move_down")

func get_movement_input(camera_3d: Camera3D, delta: float) -> Vector3:
	var raw_input_horizontal := Input.get_vector("move_left", "move_right", "move_forward", "move_backward", 0.4)
	
	var raw_input_vertical := Vector3.ZERO
	if Input.is_action_pressed("move_up"):
		raw_input_vertical += Vector3.UP
	if Input.is_action_pressed("move_down"):
		raw_input_vertical += Vector3.DOWN
		
	var move_direction = Vector3.ZERO
	var forward := camera_3d.global_basis.z
	var right := camera_3d.global_basis.x
	var up := camera_3d.global_basis.y
	
	move_direction = forward * raw_input_horizontal.y + right * raw_input_horizontal.x + up * raw_input_vertical
	
	if move_direction.length() > 0.2:
		last_input_direction = move_direction.normalized()
	return move_direction.normalized()

#rotation entire node, for 3rd pov
func handle_camera_rotation_3rd(camera_3d_node: Node3D, delta: float) -> void:
	#check empty camera
	if not camera_3d_node:
		return
	
	#xoay dọc
	camera_3d_node.rotation.x -= camera_input_direction.y * delta
	camera_3d_node.rotation.x = clamp(camera_3d_node.rotation.x, min_camera_vertical_angle, max_camera_vertical_angle)
	# Xoay ngang
	camera_3d_node.rotation.y -= camera_input_direction.x * delta
	camera_3d_node.rotation.y = wrapf(camera_3d_node.rotation.y, 0, TAU)
	camera_input_direction = Vector2.ZERO

#Rotation only camera, like 1st
func handle_camera_rotation_1st(camera_3d: Camera3D, delta: float) -> void:
	#check empty camera
	if not camera_3d:
		return
	
	#xoay dọc
	camera_3d.rotation.x -= camera_input_direction.y * delta
	camera_3d.rotation.x = clamp(camera_3d.rotation.x, min_camera_vertical_angle, max_camera_vertical_angle)
	# Xoay ngang
	camera_3d.rotation.y -= camera_input_direction.x * delta
	camera_3d.rotation.y = wrapf(camera_3d.rotation.y, 0, TAU)
	
	camera_input_direction = Vector2.ZERO

func update_camera_rotation(camera_3d_node: Node3D, move_direction: Vector3, delta: float) -> void:
	# Cập nhật hướng xoay của nhân vật
	if move_direction.length() > 0.2:
		last_input_direction = last_input_direction.slerp(move_direction, rotation_speed * delta)
		var target_angle := Vector3.LEFT.signed_angle_to(last_input_direction, Vector3.UP)
		camera_3d_node.rotation.y = lerp_angle(camera_3d_node.rotation.y, target_angle, min(rotation_speed * delta, 1.0))

func change_camera(camera_3d_name: String, camera_3d_node: Node3D) -> void:
	current_camera_node = camera_3d_node
	current_camera_name = camera_3d_name
	current_camera_3d = current_camera_node.get_child(0)
	
	if current_camera_node.get_child(1) != null:
		current_spring_arm_3d = current_camera_node.get_child(1)
	else: 
		current_spring_arm_3d = null
		
	current_camera_3d.make_current()

func handle_zoom_camera(spring_arm_3d: SpringArm3D, event: InputEvent, min_camera_zoom: float, max_camera_zoom, zoom_length: float) -> void:
	#camera zoom
	if event.is_action_pressed("camera_zoom_in"):
		spring_arm_3d.spring_length = max(min_camera_zoom, spring_arm_3d.spring_length - zoom_length)
	if event.is_action_pressed("camera_zoom_out"):
		spring_arm_3d.spring_length = min(max_camera_zoom, spring_arm_3d.spring_length + zoom_length)

func reset_rotation(camera_3d_node: Node3D, camera_3d: Camera3D, node_base_quanternion: Quaternion, camera_base_quanternion: Quaternion, camera_return_speed: float, delta: float) -> void:
	camera_3d_node.quaternion = camera_3d_node.quaternion.slerp(node_base_quanternion, camera_return_speed * delta)
	camera_3d.quaternion = camera_3d.quaternion.slerp(camera_base_quanternion, camera_return_speed * delta)
	
