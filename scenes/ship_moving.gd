extends Node

@onready var ship_player: Node3D = $Ship_Player/RigidBody3D
@onready var camera_3d_free : Node3D = $Camera_Free
@onready var camera_3d_character_far: Node3D = $Ship_Player/RigidBody3D/Camera_Pivot_Far
@onready var camera_3d_character_close: Node3D = $Ship_Player/RigidBody3D/Camera_Pivot_Close

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Khởi tạo camera mặc định
	Global_Camera.switch_to(camera_3d_character_far)

func _input(event: InputEvent) -> void:
	# 1. Chuyển đổi giữa Free Camera và Character Camera
	if event.is_action_pressed("change_camera_bw_free_n_character"):
		if Global_Camera.current_rig == camera_3d_free:
			Global_Camera.switch_to(camera_3d_character_far)
		else:
			Global_Camera.switch_to(camera_3d_free)
			
	# 2. Chuyển đổi giữa camera Xa (Far) và camera Gần (Close) của nhân vật
	if event.is_action_pressed("change_camera_character"):
		if Global_Camera.current_rig == camera_3d_character_far:
			Global_Camera.switch_to(camera_3d_character_close)
		elif Global_Camera.current_rig == camera_3d_character_close:
			Global_Camera.switch_to(camera_3d_character_far)
	
	# Thoát chuột + chuyển đổi
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	# Di chuyển ship bằng raycast, kiểm tra xem có đang giữ nut nối waypoint không
	if event.is_action_pressed("move"):
		var cam_3d = Global_Camera.get_active_camera()
		if cam_3d:
			# 1. Nhờ Global tính toán tọa độ click
			var click_pos = Global_RayQuery3d.shoot_ray_3d(cam_3d, ship_player)
			
			# 2. Nếu có tọa độ hợp lệ, ra lệnh cho Tàu đi tới đó
			if click_pos != null:
				# Kiểm tra xem có đang giữ nút nối waypoint không (vd: phím Shift / Ctrl)
				var is_sequence = Input.is_action_pressed("sequence_move")
				ship_player.move_to(click_pos, is_sequence)
