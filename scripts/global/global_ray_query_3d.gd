extends Node

# Dùng 1 node TÁI SỬ DỤNG để vẽ debug, tránh rò rỉ RAM (Memory Leak)
@onready var target_marker := MeshInstance3D.new()

func _ready() -> void:
	# Khởi tạo hộp Marker
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1) # Kích thước 1 mét
	#target_marker.mesh = box_mesh
	#target_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	#var material = StandardMaterial3D.new()
	#material.albedo_color = Color(0, 1, 0, 0.5) # Màu xanh lá trong suốt
	#material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	#material.flags_unshaded = true
	#target_marker.material_override = material
	
	# Mặc định ẩn nó đi
	#target_marker.visible = false 
	# Dùng add_child.call_deferred để an toàn khi load Autoload
	#call_deferred("add_child", target_marker)

func shoot_ray_3d(camera_3d: Camera3D, character_body_3d: Node3D, ray_length: float = 2000) -> Variant:
	if camera_3d == null:
		return null

	# Lấy vị trí chuột trong view hiện tại
	var mouse_position = get_viewport().get_mouse_position()
	
	# Config hướng + độ dài ray dọc theo chuột
	var from_position = camera_3d.project_ray_origin(mouse_position)
	var ray_direction = camera_3d.project_ray_normal(mouse_position)
	var to_position = from_position + ray_direction * ray_length
	
	# 1. Bắn tia vật lý (Physics Raycast) để xem có trúng tàu/vật cản không
	# Tạo ray
	var space = camera_3d.get_world_3d().direct_space_state 	# Default context
	var ray_query = PhysicsRayQueryParameters3D.create(from_position, to_position)
	var raycast_result = space.intersect_ray(ray_query)	# Kết quả
	
	# 2. Xử lý kết quả — trả về Dictionary để caller tự quyết định
	# Dictionary gồm: { position, hit_ship, collider, normal }
	# - position: Vector3 vị trí click trong world
	# - hit_ship: bool true nếu click trúng ship của mình
	# - collider: Node3D bị trúng (hoặc null)
	# - normal: Vector3 pháp tuyến tại điểm va chạm (nếu có)
	
	# Trường hợp 1: Click trúng ship của mình
	if raycast_result and raycast_result["collider"] == character_body_3d:
		return {
			"position": raycast_result["position"],
			"hit_ship": true,
			"collider": character_body_3d,
			"normal": raycast_result.get("normal", Vector3.UP)
		}
	
	# Trường hợp 2: Click trúng vật thể khác (tiểu hành tinh, v.v.)
	if raycast_result:
		return {
			"position": raycast_result["position"],
			"hit_ship": false,
			"collider": raycast_result["collider"],
			"normal": raycast_result.get("normal", Vector3.UP)
		}
	
	# Trường hợp 3: Click vào khoảng không — project lên mặt phẳng XZ tại độ cao ship
	# Lấy tọa độ y của ship (default click sẽ là cùng cao độ với ship)
	var ship_y = character_body_3d.global_position.y
	# Tạo mặt phẳng ngang (Vector3.UP) ở độ cao Y của tàu
	var virtual_plane = Plane(Vector3.UP, ship_y)
	# Tìm điểm cắt giữa tia và mặt phẳng
	var intersection = virtual_plane.intersects_ray(from_position, ray_direction)
		
	if intersection != null:
		## Hiện marker lên
		#target_marker.visible = true
		#target_marker.global_position = intersection
		return {
			"position": intersection,
			"hit_ship": false,
			"collider": null,
			"normal": Vector3.UP
		}
	
	# Return null nếu tia song song mặt phẳng XZ (nhìn thẳng lên/xuống)
	return null
