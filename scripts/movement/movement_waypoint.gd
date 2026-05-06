extends Node

class_name Movement_Waypoint

var position: Vector3
var direction: Vector3          # Hướng bay đến waypoint này (từ waypoint trước)
var arrival_facing: Vector3    # Hướng ship cần nhìn KHI ĐẾN đích (Vector3.ZERO = không set)
var point_marker: MeshInstance3D

# Init nhận vào position mới và direction của target trước đó
func _init(new_position: Vector3, previous_position: Vector3) -> void:
	self.position = new_position
	self.direction = previous_position.direction_to(new_position).normalized()
	self.arrival_facing = Vector3.ZERO  # Mặc định không set, scene controller sẽ gọi confirm_arrival_facing() để ghi
	self.point_marker = spawn_target_marker(new_position)

func spawn_target_marker(spawn_position: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	marker.mesh = box
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0, 0.5) # Xanh lá trong suốt
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.flags_unshaded = true
	marker.material_override = mat
	
	marker.top_level = true
	marker.global_position = spawn_position
	
	# Thêm vào scene
	#add_child(marker)
	return marker
