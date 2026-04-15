extends Node3D

@export var snap_distance: float = 0.2  # snap

var selected_module: Node3D = null  # current selected module
var drag_offset: float = 10.0  # offset from raycast mouse
var modules_placed = []  # modules already placed in the scene
var module_resources = []  # list of available resource loaded
var camera: Camera3D  # current camera of this scene

enum State {NONE, SELECT, CANCEL, PLACE}
var current_state: State
var current_selected_index:= -1	#selected module index from 0, -1 for init

var inventory: Node

var current_collistion_info = {}

@onready var camera_pivot: Node3D = $Camera_pivot
#---------------------------------------DEAFAULT FUNCTION ---------------------------------

func _ready():
	#set camera
	Global_Camera.change_camera("camera", camera_pivot)
	camera = Global_Camera.current_camera_3d
	if not Global_Camera.current_camera_node:
		print("Error: No active Camera3D found! Please add a Camera3D and set 'Current' to true.")
		return
	
	#load resources
	module_resources = read_resource_to_array("res://module_UI/module_resources/")
	
	#set UI
	inventory = $UI/Inventory
	if inventory:
		inventory.clear()
		for resource in module_resources:
			inventory.add_item(resource.name, resource.texture)  # Hiển thị tên và ảnh (texture là icon)
		inventory.item_selected.connect(_on_inventory_item_selected)  # Kết nối sự kiện chọn item
	else:
		print("Error: Inventory node not found!")
	
	#Set state
	current_state = State.NONE

func _process(delta: float) -> void:
	if current_state == State.SELECT and selected_module != null:
		drag_inventory_item()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	
func _input(event):
	match current_state:
		State.NONE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if current_selected_index >= 0:
					create_selected_module()
					change_state(State.SELECT)
		State.SELECT:
			if event.is_action_pressed("cancel_selection"):
				change_state(State.CANCEL)
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
				change_state(State.PLACE)
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				cancel_inventory_item()
				create_selected_module()
				
		State.CANCEL:
			cancel_inventory_item()
			change_state(State.NONE)
		State.PLACE:
			place_inventory_item()
			change_state(State.NONE)
			
	if Input.is_action_pressed("rotate_module"):
		selected_module.rotation.y += 1
#---------------------------------------SIGNAL-------------------------------------------
func _on_inventory_item_selected(index):
	print("Item selected: ", index)
	print(module_resources[index])
	current_selected_index = index
	
#---------------------------------------CUSTOM FUNCTION ---------------------------------
func read_resource_to_array(path: String) -> Array:
	var directory = DirAccess.open(path)
	var resource_arr := []
	if directory:
		directory.list_dir_begin()
		var file_name = directory.get_next()
		while file_name != "":
			#find resource name .tres
			if file_name.ends_with(".tres"):
				var resource = load(path + file_name)
				if resource is ModuleInventoryItem:
					resource_arr.append(resource)
					print("Loaded resource: ", resource.name)  #print check
			file_name = directory.get_next()
	else:
		print("Error: Cannot open directory: ", path)
	return resource_arr
	
func create_selected_module():
	#create resource instance from resources arr
	var resource = module_resources[current_selected_index]
	selected_module = load(resource.scene_path).instantiate()
	add_child(selected_module)
	selected_module.owner = self
	
	#create collisition ray for selected module
	var raycast3D = RayCast3D.new()
	raycast3D.set_collision_mask_value(1, true)	#collsion mask 1
	raycast3D.name = "raycast"
	raycast3D.quaternion = selected_module.quaternion
	raycast3D.target_position = Vector3(-10,0,0)
	raycast3D.visible = true
	selected_module.add_child(raycast3D)
	
	#add visual for raycast using mesh instance
	var ray_visual = MeshInstance3D.new()
	ray_visual.name = "ray_visual"
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.01
	cylinder_mesh.bottom_radius = 0.01
	cylinder_mesh.height = raycast3D.target_position.length()	#length match with raycast
	ray_visual.mesh = cylinder_mesh
	var material2 = StandardMaterial3D.new()
	material2.albedo_color = Color(1, 0, 0, 1)
	ray_visual.material_override = material2
	ray_visual.position = raycast3D.target_position / 2
	ray_visual.quaternion = Quaternion(Vector3(0, 0, 1), deg_to_rad(-90))
	
	#set tree owner
	selected_module.add_child(ray_visual)
	raycast3D.owner = selected_module
	
	#find MeshInstance3D from selected module and set to ghost
	var mesh_instance = selected_module.find_child("*", true, false) as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(1, 1, 1, 0.5)  #white 50%
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA 
		mesh_instance.material_override = material  #set material
	
	#rotate to z
	selected_module.rotation = Vector3(0, deg_to_rad(-90), 0)
	
	#turn off collistion
	selected_module.collision_layer = 0 
	selected_module.collision_mask = 0 
	
func drag_inventory_item():
	if not selected_module:
		return
	
	#get selected module raycast and ray visual + material
	var raycast_node = selected_module.find_child("raycast", true, false) as RayCast3D
	var ray_visual = selected_module.find_child("ray_visual", true, false) as MeshInstance3D
	var material = ray_visual.material_override as StandardMaterial3D	#for ray color

	if raycast_node:
		raycast_node.force_raycast_update()
		if raycast_node.is_colliding():
			var collision_point = raycast_node.get_collision_point()
			var collider = raycast_node.get_collider()
			material.albedo_color = Color(0, 1, 0, 1)	#set collisition material to green
			var new_collistion_info = {	#set current collider info
				"colider": collider,
				"face": check_raycast_face_collide(raycast_node)
			}
			if current_collistion_info != new_collistion_info:
				current_collistion_info = new_collistion_info
		else:
			material.albedo_color = Color(1, 0, 0, 1)	#set ray color to default
		
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# Raycast vật lý
	var to = from + dir * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Layer 1
	query.exclude = [selected_module, camera] if selected_module else [camera]
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)
		
	if result.has("position"):
		var mesh_instance = selected_module.find_child("*", true, false) as MeshInstance3D
		#set y potition when collide, to make app object snap, not 1/2
		var new_position = result.position + Vector3(0,mesh_instance.get_aabb().size.y/2,0)
		if new_position.distance_to(camera.global_position) < 1.0 or new_position.distance_to(camera.global_position) > 100.0:
			print("Warning: Invalid position, too close or too far from camera")
			new_position = from + dir * drag_offset
		selected_module.global_transform.origin = new_position
		
		# Align rotation: sử dụng hàm helper để align Y với normal
		var normal = result.normal if result.has("normal") else Vector3.UP
		normal = normal.normalized()  # Đảm bảo normalized để tránh lỗi scale
		selected_module.global_transform = align_with_x(selected_module.global_transform, normal)

	else:
		#var plane = Plane(Vector3(0, 1, 0), 0)
		#var intersect = plane.intersects_ray(from, dir)
		selected_module.global_transform.origin = from + dir * 10.0
		#if intersect:
			#selected_module.global_transform.origin = intersect
			#print("No collision, using plane intersection: ", intersect)

func drag_inventory_item_2():
	# Di chuyển module theo vị trí chuột hiện tại
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)  # Ray bắt đầu từ camera
	var dir = camera.project_ray_normal(mouse_pos)  # Hướng ray
	var plane = Plane(Vector3(0, 1, 0), 0)  # Mặt phẳng XZ
	var intersect = plane.intersects_ray(from, dir)  # Tìm điểm giao
	if intersect:
		selected_module.global_transform.origin = intersect  # Di chuyển ghost theo ray + offset
		# Tạm khóa trọng lực để tránh rơi khi kéo
	selected_module.freeze = true
	
func place_inventory_item():
	# Khi thả chuột, đặt module vào scene (bỏ khóa, thêm vào danh sách)
	selected_module.freeze = false  # Bỏ khóa trọng lực để module chịu physics
	modules_placed.append(selected_module)  # Thêm vào danh sách module đã đặt
	selected_module = null  # Xóa tham chiếu để có thể tạo mới
	#current_selected_index = -1
	print("Placed module")

func cancel_inventory_item():
	# Hủy module đang kéo bằng cách xóa nó khỏi scene
	selected_module.queue_free()  # Xóa node (an toàn hơn remove_child)
	selected_module = null
	#current_selected_index = -1
	print("Cancelled placement")

func change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	# Reset các thuộc tính khi chuyển trạng thái (nếu cần)
	match new_state:
		State.NONE:
			pass
		State.SELECT:
			pass
		State.PLACE:
			pass
		State.CANCEL:
			pass
			
	current_state = new_state
	print("State changed to: ", current_state)

func check_raycast_face_collide(raycast_node: RayCast3D):
	var normal = raycast_node.get_collision_normal()
	var epsilon = 0.01
	var collider_face: String

	if abs(normal.y - 1.0) < epsilon:
		collider_face = "up"
	elif abs(normal.y + 1.0) < epsilon:
		collider_face = "down"
	elif abs(normal.x - 1.0) < epsilon:
		collider_face = "right"
	elif abs(normal.x + 1.0) < epsilon:
		collider_face = "left"
	elif abs(normal.z - 1.0) < epsilon:
		collider_face = "front"
	elif abs(normal.z + 1.0) < epsilon:
		collider_face = "back"
	else:
		collider_face = "face_off"
		
	return collider_face
	
# Hàm helper để align transform với normal (align local Y với normal, giữ forward projected)
# Hàm align_with_y (rename từ align_with_normal, cho bottom snap)
func align_with_y(xform: Transform3D, new_normal: Vector3) -> Transform3D:
	xform.basis.y = new_normal  # Set Y = normal
	
	# Project current Z (forward) lên mặt phẳng
	var forward = xform.basis.z
	forward -= new_normal * forward.dot(new_normal)
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD if abs(new_normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	forward = forward.normalized()
	
	xform.basis.z = -forward  # Set -Z = forward
	xform.basis.x = xform.basis.y.cross(xform.basis.z)  # X orthogonal
	
	xform.basis = xform.basis.orthonormalized()
	return xform

# Hàm mới align_with_x (cho left side snap)
func align_with_x(xform: Transform3D, new_normal: Vector3) -> Transform3D:
	xform.basis.x = new_normal  # Set X = normal (dựa trên tính toán để outward normals opposite)
	
	# Project current Y (up) lên mặt phẳng perpendicular to X
	var up = xform.basis.y
	up -= new_normal * up.dot(new_normal)
	if up.length_squared() < 0.001:
		up = Vector3.UP if abs(new_normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	up = up.normalized()
	
	xform.basis.y = up  # Set Y = projected up
	xform.basis.z = xform.basis.x.cross(xform.basis.y)  # Z = X x Y (right-handed)
	
	xform.basis = xform.basis.orthonormalized()
	return xform

# Hàm mới align_with_x (cho left side snap)
func align_with_z(xform: Transform3D, new_normal: Vector3) -> Transform3D:
	xform.basis.z = new_normal  # Set X = normal (dựa trên tính toán để outward normals opposite)
	
	# Project current Y (up) lên mặt phẳng perpendicular to X
	var up = xform.basis.y
	up -= new_normal * up.dot(new_normal)
	if up.length_squared() < 0.001:
		up = Vector3.UP if abs(new_normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	up = up.normalized()
	
	xform.basis.x = up  # Set Y = projected up
	xform.basis.x = xform.basis.x.cross(xform.basis.y)  # Z = X x Y (right-handed)
	
	xform.basis = xform.basis.orthonormalized()
	return xform

#if result.has("position"):
		#var mesh_instance = selected_module.find_child("*", true, false) as MeshInstance3D
		#if mesh_instance:
			## Lấy normal của bề mặt, fallback nếu không có
			#var normal = result.normal if result.has("normal") else Vector3.UP
			## Lấy AABB của mesh
			#var aabb = mesh_instance.get_aabb()
			#var aabb_center = aabb.position + aabb.size / 2  # Tâm AABB trong local space
			#var aabb_half_size = aabb.size / 2
			## Tìm điểm thấp nhất của module theo normal
			#var lowest_point_local = aabb_center - aabb_half_size * normal.normalized()
			## Chuyển sang global space
			#var lowest_point_global = mesh_instance.global_transform * lowest_point_local
			## Tính offset từ gốc module đến đáy
			#var offset = selected_module.global_transform.origin - lowest_point_global
			## Đặt vị trí module sao cho đáy chạm điểm va chạm
			#var new_position = result.position + offset + normal * 0.01  # Offset nhỏ tránh z-fighting
			#selected_module.global_transform.origin = new_position
			## Xoay module theo normal của bề mặt (tùy chọn)
			#selected_module.global_transform.basis = Basis.looking_at(-normal, Vector3.UP)
		#else:
			## Fallback nếu không tìm thấy mesh_instance
			#var new_position = result.position + Vector3(0, 0.5, 0)
			#selected_module.global_transform.origin = new_position
	#else:
		#var plane = Plane(Vector3(0, 1, 0), 0)
		#var intersect = plane.intersects_ray(from, dir)
		#selected_module.global_transform.origin = from + dir * drag_offset
