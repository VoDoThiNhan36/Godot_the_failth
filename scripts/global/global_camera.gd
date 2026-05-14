extends Node

enum CameraType {MAIN, FREE, SHIP_FAR, SHIP_CLOSE }
var current_camera_list := {}
var current_camera_type: CameraType
var current_rig: CameraRigBase = null

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	# Input camera sẽ được handle ở Global Input
	pass

func handle_input(event: InputEvent) -> bool:
	# Exclude input from 
	for action in Global_Input.camera_exclude_input_list:
		if Input.is_action_pressed(action):
			return false
	
	for state in Global_Input.camera_exclude_state_list:
		if Global_Input.current_input_state == state:
			return false
		
	if event.is_action_pressed("change_to_free_camera"):
		#if current_camera_type == CameraType.MAIN:
			#var camera_free = current_camera_list.get(CameraType.FREE, null)
			#if camera_free != null:
				#switch_to(camera_free)
				#get_viewport().set_input_as_handled()
				#return
		#
		#else:
			#var camera_main = current_camera_list.get(CameraType.MAIN, null)
			#switch_to(camera_main)
			#get_viewport().set_input_as_handled()
			#return
			
		var camera_free = current_camera_list.get(CameraType.FREE, null)
		if camera_free != null:
			switch_to(camera_free)
			return true
	
	if event.is_action_pressed("change_to_character_camera"):
		if current_camera_type == CameraType.MAIN or current_camera_type == CameraType.FREE:
			var camera_ship_far = current_camera_list.get(CameraType.SHIP_FAR, null)
			if camera_ship_far != null:
				switch_to(camera_ship_far)
				return true
				
		if current_camera_type == CameraType.SHIP_FAR:
			var camera_ship_close = current_camera_list.get(CameraType.SHIP_CLOSE, null)
			if camera_ship_close != null:
				switch_to(camera_ship_close)
				return true
		else:
			var camera_ship_far = current_camera_list.get(CameraType.SHIP_FAR, null)
			if camera_ship_far != null:
				switch_to(camera_ship_far)
				return true
				
	# Xoay camera
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Free camera luôn xoay, Character camera chỉ xoay khi giữ phím "hold_to_rotate_camera"
		var should_rotate := false
		if current_camera_type == CameraType.FREE:
			should_rotate = true   # Free camera: luôn xoay
		elif Input.is_action_pressed("hold_to_rotate_camera"):
			should_rotate = true   # Character camera: chỉ xoay khi giữ phím

		if should_rotate and current_rig != null:
			# Xoay theo 2 node: Node gốc xoay ngang, node spring arm xoay dọc
			current_rig.rotation.y -= event.relative.x * current_rig.mouse_sensitivity
			# Giới hạn góc nhìn trái/phải nếu có (ví dụ cho camera tàu)
			if "max_horizontal_angle" in current_rig and current_rig.max_horizontal_angle > 0:
				current_rig.rotation.y = clamp(current_rig.rotation.y, -current_rig.max_horizontal_angle, current_rig.max_horizontal_angle)
			# Nhìn lên/xuống: Chỉ xoay SpringArm theo trục X (Đảo dấu trừ thành trừ)
			current_rig.spring_arm.rotation.x -= event.relative.y * current_rig.mouse_sensitivity
			current_rig.spring_arm.rotation.x = clamp(current_rig.spring_arm.rotation.x, current_rig.min_vertical_angle, current_rig.max_vertical_angle)
			return true
	
	else:
		if event.is_action_pressed("camera_zoom_in"):
			current_rig.spring_arm.spring_length = max(current_rig.min_zoom, current_rig.spring_arm.spring_length - current_rig.zoom_step)
			return true
		if event.is_action_pressed("camera_zoom_out"):
			current_rig.spring_arm.spring_length = min(current_rig.max_zoom, current_rig.spring_arm.spring_length + current_rig.zoom_step)
			return true
	
	# Return false nếu không có input nào được xử lý, để các node khác có thể nhận input này
	return false

func switch_to(new_rig: CameraRigBase) -> void:
	if current_rig == new_rig:
		return
		
	if current_rig != null:
		current_rig.deactivate()

	current_camera_type = new_rig.camera_type
	current_rig = new_rig
	current_rig.activate()

# Trả về Camera3D thực tế đang được dùng (cho Raycast, v.v.)
func get_active_camera() -> Camera3D:
	if current_rig:
		return current_rig.camera_3d
	return null
