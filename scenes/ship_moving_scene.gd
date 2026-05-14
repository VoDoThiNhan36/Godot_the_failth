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

# ============================== FLIGHT INPUT ======================================
# Flight input state machine đã được chuyển vào ship_movement_integrate.gd.
# Scene chỉ tính raycast + cam_basis rồi gọi ship.handle_flight_input().

# ============================== READY ======================================

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Add camera to Global list
	Global_Camera.current_camera_list[Global_Camera.CameraType.FREE] = camera_3d_free
	Global_Camera.current_camera_list[Global_Camera.CameraType.SHIP_FAR] = camera_3d_character_far
	Global_Camera.current_camera_list[Global_Camera.CameraType.SHIP_CLOSE] = camera_3d_character_close
	
	Global_Camera.switch_to(camera_3d_character_far)

# ============================== INPUT ROUTER ======================================
# _input() chạy theo thứ tự ưu tiên:
#   1. Global input
#   2. Active camera input (zoom/orbit/look)
#   3. Gameplay input (move/facing/builder...)

func _input(event: InputEvent) -> void:
	# Gọi input của Global trước để xử lý các phím chung (menu, toggle mouse, switch camera)
	Global_Input._input(event)

	match current_gameplay_mode:
		GameplayInputMode.FLIGHT: 
			pass # Ship tự xử lý input qua _unhandled_input của chính nó

# ============================== GAMEPLAY MODE SWITCHER ==============================

func _switch_gameplay_mode(new_mode: GameplayInputMode) -> void:
	if current_gameplay_mode == new_mode:
		return
	print("[GameplayInputMode] ", GameplayInputMode.keys()[current_gameplay_mode], " → ", GameplayInputMode.keys()[new_mode])
	current_gameplay_mode = new_mode
