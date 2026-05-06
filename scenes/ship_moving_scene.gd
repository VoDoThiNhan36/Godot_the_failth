extends Node

@onready var ship_player: Node3D                  = $Ship_Player/RigidBody3D              # RigidBody3D chứa script ship_movement.gd
@onready var camera_3d_free : Node3D              = $Camera_Free                          # Camera tự do (WASD + nhìn tự do)
@onready var camera_3d_character_far: Node3D      = $Ship_Player/RigidBody3D/Camera_Pivot_Far    # Camera bám tàu — góc xa
@onready var camera_3d_character_close: Node3D    = $Ship_Player/RigidBody3D/Camera_Pivot_Close  # Camera bám tàu — góc gần

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED    # Bắt chuột vào game khi bắt đầu
	# 1. Khởi tạo camera mặc định là camera bám tàu — góc xa
	Global_Camera.switch_to(camera_3d_character_far)

# Hàm xử lý input — dùng _input (không phải _unhandled_input)
# Lý do PHẢI dùng _input thay vì _unhandled_input:
# _unhandled_input chỉ nhận event SAU KHI GUI/Viewport đã xử lý xong
# Trong một số trạng thái (focus GUI, Viewport đặc biệt), click chuột bị GUI chặn
# → _unhandled_input ở scene root không bao giờ được gọi → click không nhận được
# _input nhận MỌI event trước GUI, đảm bảo click luôn đến được scene root
#
# Fix spam waypoint cũ (thay vì đổi sang _unhandled_input):
# Guard bằng "event is InputEventMouseButton" TRƯỚC is_action_pressed("move")
# InputEventMouseMotion không phải InputEventMouseButton → bị chặn ngay từ đầu
# → move_to() chỉ được gọi khi click chuột thật, không bị gọi khi drag
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

	# 3. Toggle mouse capture / release
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 4. Di chuyển ship bằng raycast
	# Guard 1: "event is InputEventMouseButton" — lọc ra chỉ mouse click thật
	#   InputEventMouseMotion thỏa is_action_pressed("move") khi đang giữ LMB (button_mask)
	#   nhưng KHÔNG thỏa "is InputEventMouseButton" → bị chặn trước → không spam waypoint
	# Guard 2: event.pressed — chỉ xử lý khi button được nhấn xuống, không xử lý khi thả ra
	if event is InputEventMouseButton and event.pressed and event.is_action_pressed("move"):
		var cam_3d = Global_Camera.get_active_camera()    # Camera đang active
		if cam_3d:
			# 4.1. Nhờ Global tính toán tọa độ click bằng raycast
			var click_pos = Global_RayQuery3d.shoot_ray_3d(cam_3d, ship_player)

			# 4.2. Nếu có tọa độ hợp lệ, ra lệnh cho Tàu đi tới đó
			if click_pos != null:
				# Kiểm tra xem có đang giữ nút nối waypoint không (vd: phím Shift / Ctrl)
				var is_sequence = Input.is_action_pressed("sequence_move")  # true = thêm vào hàng đợi
				ship_player.move_to(click_pos, is_sequence)                 # Gửi lệnh di chuyển
