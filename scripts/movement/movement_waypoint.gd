extends Node

class_name Movement_Waypoint

var position: Vector3
var direction: Vector3
var point_marker: MeshInstance3D

# Init nhận vào position mới và direction của target trước đó
func _init(position: Vector3, previous_position: Vector3) -> void:
	self.position = position
	self.direction = previous_position.direction_to(position).normalized()
	self.point_marker = spawn_target_marker(position)

func spawn_target_marker(position: Vector3) -> MeshInstance3D:
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
	marker.global_position = position
	
	# Thêm vào scene
	#add_child(marker)
	return marker
