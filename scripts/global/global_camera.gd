extends Node

var current_rig: CameraRigBase = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func switch_to(new_rig: CameraRigBase) -> void:
	if current_rig == new_rig:
		return
		
	if current_rig != null:
		current_rig.deactivate()
		
	current_rig = new_rig
	current_rig.activate()

# Trả về Camera3D thực tế đang được dùng (cho Raycast, v.v.)
func get_active_camera() -> Camera3D:
	if current_rig:
		return current_rig.camera_3d
	return null
