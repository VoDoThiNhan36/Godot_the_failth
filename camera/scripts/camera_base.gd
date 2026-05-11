extends Node3D

class_name CameraRigBase 

@export var mouse_sensitivity := 0.005 # Mouse sensitive
@export var spring_arm_length : float	# Độ dài cánh tay camera
@export var camera_type: Global_Camera.CameraType
@export var return_speed := 10.0
var is_active := false
var base_quaternion: Quaternion
var base_spring_rotation_x := 0.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

func _ready() -> void:
	# Gán các giá trị default vào
	spring_arm.spring_length = spring_arm_length
	base_quaternion = quaternion
	base_spring_rotation_x = spring_arm.rotation.x
	
	# In ra tên của node để không bị nhầm lẫn giữa các camera
	print("[", name, "] Biến cấu hình: ", spring_arm_length, " | Thực tế của gậy: ", spring_arm.spring_length, " | Camera type: ", camera_type)

func _process(delta: float) -> void:
	# Reset camera về sau đuôi tàu khi thả chuột
	if not Input.is_action_pressed("hold_to_rotate_camera"):
		quaternion = quaternion.slerp(base_quaternion, return_speed * delta)
		spring_arm.rotation.x = lerp(spring_arm.rotation.x, base_spring_rotation_x, return_speed * delta)
	
func activate() -> void:
	is_active = true
	camera_3d.make_current()
	set_process_unhandled_input(true)
	set_process(true)
	set_physics_process(true)
	set_default_properties()
	
func deactivate() -> void:
	is_active = false
	set_process_unhandled_input(false)
	set_process(false)
	set_physics_process(false)

func set_default_properties() -> void:
	# Set lại spring length
	spring_arm.spring_length = spring_arm_length

func handle_scene_input(_event: InputEvent) -> bool:
	return false
