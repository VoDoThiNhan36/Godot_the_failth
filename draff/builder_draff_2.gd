extends Node3D

var world_vector: = Vector3.FORWARD

@export var snap_distance: float = 0.2  # snap
var drag_offset: float = 10.0  # offset from raycast mouse
var modules_placed = []  # modules already placed in the scene
var module_resources = []  # list of available resource loaded
var camera: Camera3D  # current camera of this scene

enum State {NONE, SELECT, CANCEL, PLACE}	# states for selected module
var module_materials: Dictionary = {}  # Module materials
var inventory: Node		# inventory UI node

var current_state: State
var current_selected_index:= -1	#selected module index from 0, -1 for init
var current_collision_info = {} # current collision info	
var selected_module: Node3D = null  # current selected module
var selected_module_origin_basis: Basis # current selected module origin basis
var current_selected_module_mesh: MeshInstance3D
var current_selected_module_ray_visual: MeshInstance3D
var current_selected_module_raycast: RayCast3D

const LAYER_COMMON: int = 1
const LAYER_SNAP_POINT: int = 128	# layer 8

@onready var camera_pivot: Node3D = $Camera_pivot
@onready var extra_01_root: RigidBody3D = $extra_01_Root

#---------------------------------------DEAFAULT FUNCTION ---------------------------------
func _ready():
	# set current camera to camera this scene
	Global_Camera.change_camera("camera", camera_pivot)
	camera = Global_Camera.current_camera_3d
	if not Global_Camera.current_camera_node:
		print("Error: No active Camera3D found! Please add a Camera3D and set 'Current' to true.")
		return
	
	# load resources
	module_resources = read_resource_to_array("res://module_UI/module_resources/")
	
	# set UI Node
	inventory = $UI/Inventory
	if inventory:
		inventory.clear()
		for resource in module_resources:
			# add items from resource array to inventory items
			inventory.add_item(resource.name, resource.texture_2d)  # display name and texture icon
		inventory.item_selected.connect(_on_inventory_item_selected)  # Kết nối sự kiện chọn item
	else:
		print("Error: Inventory node not found!")
	
	# set init state
	current_state = State.NONE
	
	# init list module materials 
	module_materials["no_collide"] = create_module_material(Color(0.906, 0.948, 1.0, 0.345))
	module_materials["collide_with_common"] = create_module_material(Color(0.0, 0.788, 0.983, 0.345))
	module_materials["collide_with_snap_point"] = create_module_material(Color(0.184, 0.859, 0.027, 0.345))
	module_materials["blocked"] = create_module_material(Color(1.0, 0.2, 0.2, 0.5))
	
	# add default module (for test only)
	modules_placed.append(extra_01_root)

func _process(delta: float) -> void:
	# if current existed a selected module, then aplly drag func
	if current_state == State.SELECT and selected_module != null:
		drag_inventory_item()

func _unhandled_input(event: InputEvent) -> void:
	# for changing mouse mode
	if event.is_action_pressed("toggle_camera"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
func _input(event):
	# handle module interactive
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
			
	# handle manual module rotation
	if current_state == State.SELECT and selected_module != null and Input.is_action_just_pressed("rotate_module"):
		selected_module.rotation.y += deg_to_rad(10)
		
#---------------------------------------SIGNAL-------------------------------------------
func _on_inventory_item_selected(index):
	print("Item selected: ", index)
	print(module_resources[index])
	current_selected_index = index
	
#---------------------------------------CUSTOM FUNCTION ---------------------------------
# Hàm load resource hiện có vào 1 mảng
func read_resource_to_array(path: String) -> Array:
	# path: Đường dẫn tới thư mục cần đọc
	
	var directory = DirAccess.open(path)
	var resource_arr := []
	if directory:
		directory.list_dir_begin()
		var file_name = directory.get_next()
		while file_name != "":
			# Chỉ lấy các file resource có đuôi .tres
			if file_name.ends_with(".tres"):
				var resource = load(path + file_name)
				# Tất cả resource đều là instance của ModuleInventoryResource class
				if resource is Module:
					resource_arr.append(resource)
					print("Loaded resource: ", resource.name)  #print check
			file_name = directory.get_next()
		directory.list_dir_end()
	else:
		print("Error: Cannot open directory: ", path)
	return resource_arr

# Hàm để tạo 1 module gắn
func create_selected_module():
	# 1. Xóa module hiện có
	if selected_module:
		selected_module.queue_free()
		selected_module = null
		
	# 2. Lấy resource tương ứng từ danh sách đã load + tạo instance
	var resource = module_resources[current_selected_index]
	# Tạo 1 instance node 3D - scene 3D từ resource trong script module inventory item
	selected_module = resource.create_node_3d_scene_instance()
	add_child(selected_module)	# Thêm vào cây node hiện tại
	selected_module.owner = self
	
	# 3. Tạo ray node + ray visual để thể hiện mặt cần gắn
	var raycast_created = create_raycast_visual(selected_module, selected_module.attach_face_vector, 10.0, Color(1, 0, 0, 0.5))
	
	# 4. Xoay mặt cần gắn về hướng -Z
	align_face_to_direction(selected_module, selected_module.attach_face_vector, world_vector)
	
	# 5. Lưu các biến hiện tại để dùng
	selected_module_origin_basis = selected_module.basis
	current_selected_module_mesh = selected_module.find_child("*", true, false) as MeshInstance3D
	current_selected_module_ray_visual = raycast_created["ray_visual"]
	current_selected_module_raycast = raycast_created["raycast3D"]
	
	# 6. Chuyển visual cho module sang ban đầu là chưa va chạm gì
	switch_module_material(selected_module, "no_collide")
	
	# 7. Tắt các chức năng collistion và set freeze để không bị ảnh hưởng bới các tác nhân khác
	if selected_module is RigidBody3D:
		selected_module.freeze = true
	selected_module.collision_layer = 0  
	selected_module.collision_mask = 0  
	selected_module.linear_velocity = Vector3.ZERO
	selected_module.angular_velocity = Vector3.ZERO

# Hàm tạo raycast cho visual hướng gắn
func create_raycast_visual(module: Node3D, direction_vector: Vector3, ray_length: float, ray_color: Color):
	# module: node3D để gắn ray vào
	# direction_vector: hướng mà ray sẽ chiếu theo, trong trường hợp gắn module thì sẽ là vector mặt gắn (attach face vector)
	# ray_length: độ dài muốn ray hiển thị
	# ray_color: màu mặc định của ray 
	
	# 1. Tạo RayCast3D + set collistion mask to 1
	var raycast3D = RayCast3D.new()
	raycast3D.set_collision_mask_value(1, true)
	
	# QUAN TRỌNG: RayCast bắn từ tâm module theo hướng direction_vector
	# direction_vector nên là vector đơn vị (normalized), ví dụ Vector3.FORWARD
	var normalized_dir = direction_vector.normalized()
	
	# Target Position xác định điểm cuối của tia (trong local space của module)
	raycast3D.target_position = normalized_dir * ray_length
	raycast3D.visible = true
	
	# 2. Tạo Visual (Hình trụ)
	var ray_visual = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.01
	cylinder_mesh.bottom_radius = 0.01
	cylinder_mesh.height = ray_length # Chiều cao bằng đúng độ dài tia
	ray_visual.mesh = cylinder_mesh
	
	# Tạo meterial
	var material = StandardMaterial3D.new()
	material.albedo_color = ray_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Để có thể chỉnh alpha
	ray_visual.material_override = material
	
	# 3. Xử lý Vị trí & Xoay cho Visual
	# Cylinder mặc định đứng (trục Y). Cần xoay nó nằm ngang theo hướng bắn.
	
	# - Bước A: Xoay Visual khớp hướng bắn
	if normalized_dir.is_equal_approx(Vector3.UP):
		ray_visual.rotation = Vector3.ZERO
	elif normalized_dir.is_equal_approx(Vector3.DOWN):
		ray_visual.rotation_degrees.x = 180
	else:
		# Tìm trục xoay vuông góc giữa UP và Hướng Bắn
		var axis = Vector3.UP.cross(normalized_dir).normalized()
		var angle = Vector3.UP.angle_to(normalized_dir)
		ray_visual.quaternion = Quaternion(axis, angle)
		
	# - Bước B: Dịch chuyển tâm
	# Sau khi xoay, Cylinder vẫn có tâm tại (0,0,0). Nó bị thụt lùi 1 nửa.
	# Cần đẩy nó đi tới 1 nửa chiều dài THEO HƯỚNG BẮN.
	ray_visual.position = normalized_dir * (ray_length / 2.0)
	
	# 4. Add vào scene
	# Add visual vào module (cùng cấp với raycast) để nó di chuyển cùng module
	module.add_child(raycast3D) # RayCast đi theo module
	module.add_child(ray_visual) 
	
	# Trả về dictionary để quản lý bên ngoài
	return {"raycast3D": raycast3D, "ray_visual": ray_visual}

# Hàm handle việc di chuyển module sau khi tạo xong (gồm tự động tương tác với các bề mặt, điểm gắn)
func drag_inventory_item():
	if not selected_module:
		return
	
	# 1. Set các biến liên quan đến selected module
	var raycast_node = current_selected_module_raycast
	var ray_visual = current_selected_module_ray_visual
	var ray_material = ray_visual.material_override as StandardMaterial3D # for ray color
	var mesh_instance = current_selected_module_mesh	# mesh để lấy aabb
	var aabb = mesh_instance.get_aabb() if mesh_instance else AABB() # AABB là hình khối của module (bounding_box)

	# 2. Lấy vị trí chuột trên màn hình, from + dir tạo thành 1 tia vector thẳng
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# 3. Config raycast
	var to = from + dir * 1000.0	# Cho tia ray dài 1000 đơn vị
	var query = PhysicsRayQueryParameters3D.create(from, to)	# Tạo tia raycast
	query.collision_mask = LAYER_COMMON + LAYER_SNAP_POINT # Layer 1 & 8 (common module and snap point)
	query.collide_with_areas = true # set collide with area body (cho phép va chạm với Area object)
	query.exclude = [selected_module, camera] if selected_module else [camera] # Bỏ camera và selected module ra khỏi va chạm với raycast
	var space_state = get_world_3d().direct_space_state # Default
	var result = space_state.intersect_ray(query) # Lấy kết quả va chạm giữa tia raycast và view hiện tại
	
	# 4. Set các biến cho tính toán va chạm tiếp theo
	var new_position = from + dir * drag_offset		# Default cho position nếu không va chạm gì (xa bao nhiêu so với màn hình)
	var snap_found = false		# Check xem có trúng vào điểm gắn nào không
	var distance_to_face: float		# Khoang cách xa nhất từ mặt va chạm đến mặt bên kia (để làm module nổi lên, default bị chìm ngay tâm)
	var epsilon = 0.001		# Sai số để làm cho module không bị khít quá khi gắn trên bề mặt khác
	var attach_face_vector = selected_module.attach_face_vector		# Vector hướng mặt gắn của module, mỗi mặt là 1 vector chuẩn hóa khác nhau
	var new_collistion_info = {}	# Dict để lưu thông tin collistion hiện tại
	var new_normal: Vector3		# Vector normal(pháp tuyến) mới được tính toán liên tục khi va chạm
	
	# 5. Xử lý va chạm
	# 5.1 Nếu có va chạm (Nếu có collision xảy ra (properties position sẽ có kết quả))
	if result.has("position"):
		# Lưu thông tin collistion
		var collider = result.collider	# Vật bị va chạm bởi raycast
		var collider_position = result.position		# Position nơi va chạm xảy ra
		var collider_normal = result.normal.normalized()	# Vector pháp tuyến nới va chạm xảy ra
		
		# Set các biến liên quan cho điểm gắn
		var snap_position: Vector3	# Vị trí của điểm gắn
		var snap_face_normal: Vector3	# Normal của điểm gắn
		var snap_basis: Basis	# basis của điểm gắn
		var snap_direction: Vector3 = Vector3.ZERO	# Hướng gắn
		
		# Tính chiều dài của module theo mặt cần gắn (ví dụ gắn -x thì thính từ -x đến x)
		# default collide at origin (1/2), so distant will be size to avoid immerse module to object
		distance_to_face = calculate_distant_to_face_module(attach_face_vector, aabb)
		
		# 5.1.1 Xử lý nếu bề mặt va chạm là 1 điểm gắn (snap point), điểm này sẽ có dạng Area3D
		# Cần gắn selected module vào điểm này và phải ứng với hướng của nó (khớp basis)
		if collider is Area3D and collider.name.begins_with("Snap_Point"):
			# Set snap flag and get basis + position from snap point
			snap_found = true	# flag đã tìm thấy điểm gắn
			snap_face_normal = get_snap_point_local_normal(collider) # Tính normal của bề mặt điểm gắn
			snap_basis = collider.global_transform.basis	# set basis của điểm gắn sang collider (collider ở trường hợp này chính là điểm gắn)
			snap_position = collider.global_transform.origin	# tương tự set vị trí gắn qua global transform origin của collider
			
			# Tính hướng gắn
			snap_direction = snap_basis * snap_face_normal
			
			# Set normal hướng gắn và vị trí gắn 
			new_normal = snap_direction.normalized()
			new_position = snap_position
				
			# So sánh xem có thông tin nào thay đổi không, nếu không thì bỏ qua tính toán
			if collider.get_instance_id() == current_collision_info.get("collider_id")\
				and snap_face_normal.is_equal_approx(current_collision_info.get("normal"))\
				and snap_position.is_equal_approx(current_collision_info.get("collider_point"))\
				and snap_found == current_collision_info.get("is_snap_point"):
				pass
			else:
				# Chuyển module visual sang màu tương ứng
				ray_material.albedo_color = Color(0, 1, 0, 1)  # ray green
				switch_module_material(selected_module, "collide_with_snap_point")
				
				# Gắn selected module vào điểm gắn theo basis điểm gắn và mặt gắn
				align_with_basis(selected_module, snap_basis, attach_face_vector)
				# Lưu thông tin
				current_collision_info["collider"] = collider.get_parent()
				current_collision_info["collider_id"] = collider.get_instance_id()
				current_collision_info["collider_point"] = snap_position
				current_collision_info["normal"] = snap_face_normal
				current_collision_info["is_snap_point"] = snap_found
		
		# 5.1.2 Xử lý va chạm nếu là bề mặt thông thường
		# Bề mặt thông thuongf chỉ cần gắn theo bề mặt hiện tại là được(đúng theo normal bề mặt)
		else:
			new_normal = collider_normal
			new_position = collider_position
			
			# So sánh xem có thông tin nào thay đổi không, nếu không thì bỏ qua tính toán
			if collider.get_instance_id() == current_collision_info.get("collider_id")\
				and collider_normal.is_equal_approx(current_collision_info.get("normal"))\
				and collider_position.is_equal_approx(current_collision_info.get("collider_point"))\
				and current_collision_info.get("is_snap_point") == false:
				pass
			else:
				# Chuyển module visual sang màu tương ứng
				ray_material.albedo_color = Color(0, 0.7, 1, 1)  # ray blue
				switch_module_material(selected_module, "collide_with_common")
				
				# Gắn selected module vào bề mặt, basis không đổi mà vẫn giữ theo selected module
				align_with_basis(selected_module, selected_module_origin_basis, attach_face_vector)
				# Lưu thông tin
				current_collision_info["collider"] = collider
				current_collision_info["collider_id"] = collider.get_instance_id()
				current_collision_info["collider_point"] = collider_position
				current_collision_info["normal"] = collider_normal
				current_collision_info["is_snap_point"] = false
	
		#var new_transform = align_with_x(selected_module.global_transform, new_normal)
		var new_transform = align_by_normal(selected_module.global_transform, new_normal, attach_face_vector)
		new_transform.origin = new_position + new_normal * distance_to_face - new_normal * epsilon
		selected_module.global_transform = new_transform
			
	else:
		# Không va chạm gì
		ray_material.albedo_color = Color(1, 0, 0, 1)
		switch_module_material(selected_module, "no_collide")
		selected_module.global_transform.basis = selected_module_origin_basis
		selected_module.global_transform.origin = new_position
		
	
	if raycast_node:
		raycast_node.force_raycast_update()
		if raycast_node.is_colliding():
			if ray_material:
				ray_material.albedo_color = Color(0, 1, 0, 1) #set collisition material to green
		else:
			if ray_material:
				ray_material.albedo_color = Color(1, 0, 0, 1) #set ray color to default (red)
	
func place_inventory_item():
	# Khi thả chuột, đặt module vào scene (bỏ khóa, thêm vào danh sách)
	modules_placed.append(selected_module)  # Thêm vào danh sách module đã đặt
	# Restore physics properties
	selected_module.collision_layer = 1  # Restore collision layer (adjust as needed)
	selected_module.collision_mask = 1  # Restore collision mask
	# Get raycast and mesh instance for visual feedback
	var raycast_node = current_selected_module_raycast
	var mesh_instance = current_selected_module_mesh
	# Remove ghost material
	if mesh_instance and mesh_instance.material_override:
		mesh_instance.material_override = null  # Reset to default material

	# Remove raycast and visual
	var ray_visual = current_selected_module_ray_visual
	if ray_visual:
		ray_visual.queue_free()
	if raycast_node:
		raycast_node.queue_free()
		
	# Giả định attach_to_module và các hàm khác tồn tại
	attach_to_module(selected_module, current_collision_info.get('collider'), current_collision_info.get('collider_point'))
	#if selected_module is RigidBody3D:
		#selected_module.freeze = false  # Enable physics if applicable
		
	selected_module = null  # Xóa tham chiếu để có thể tạo mới
	#current_selected_index = -1
	print("Placed module")

func cancel_inventory_item():
	# Hủy module đang kéo bằng cách xóa nó khỏi scene
	if selected_module:
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

func align_face_to_direction(node: Node3D, local_face: Vector3, world_direction: Vector3):
	# Bước 1: Reset xoay để tính toán từ trạng thái gốc
	node.rotation = Vector3.ZERO
	
	# Bước 2: Xác định trục nào của module sẽ đóng vai trò là "mắt" để nhìn
	var axis = Vector3.FORWARD # Mặc định Godot nhìn bằng trục -Z
	
	if local_face.is_equal_approx(Vector3(1,0,0)): axis = Vector3.RIGHT
	elif local_face.is_equal_approx(Vector3(-1,0,0)): axis = Vector3.LEFT
	elif local_face.is_equal_approx(Vector3(0,1,0)): axis = Vector3.UP
	elif local_face.is_equal_approx(Vector3(0,-1,0)): axis = Vector3.DOWN
	elif local_face.is_equal_approx(Vector3(0,0,1)): axis = Vector3.BACK
	elif local_face.is_equal_approx(Vector3(0,0,-1)): axis = Vector3.FORWARD

	# Bước 3: Tính toán Quaternion xoay từ "trục mặt dính" sang "hướng mục tiêu"
	# Đây là công thức toán học chuẩn để xoay vector A trùng vào vector B
	var rotation_quat = Quaternion(axis, world_direction.normalized())
	
	# Bước 4: Áp dụng xoay
	node.global_transform.basis = Basis(rotation_quat)

#func align_face_to_direction(node: Node3D, attach_face_vector: Vector3, world_direction: Vector3):
	## 1. Reset rotation (Chỉ cần thiết nếu bạn muốn tính toán sạch từ đầu)
	##node.rotation = Vector3.ZERO
	#
	## 2. Xác định trục Up mong muốn (để giữ module không bị lộn ngược)
	#var desired_up: Vector3
	#if attach_face_vector == Vector3(1,0,0): 
		#desired_up = Vector3.UP
	#elif attach_face_vector == Vector3(0,1,0):
		#desired_up = Vector3.FORWARD
	#elif attach_face_vector == Vector3(0,0,1):
		#desired_up = Vector3.RIGHT
	#
	## 3. Tính Rotation cần thiết
	## Ta muốn vector 'local_face' của module hướng theo 'world_direction'
	#
	## Cách 1: Nếu local_face là trục -Z (Vector3.FORWARD) - Đây là chuẩn của Godot
	#if attach_face_vector.is_equal_approx(Vector3.FORWARD): # (0, 0, -1)
		## LookAt mặc định align trục -Z theo hướng target
		## Lưu ý: look_at yêu cầu tọa độ điểm đích, không phải vector hướng
		## Nên ta lấy vị trí hiện tại + vector hướng
		#node.look_at(node.global_position + world_direction, desired_up)
		#return
#
	## Cách 2: Nếu local_face là trục khác (ví dụ trục X, Y hoặc +Z)
	## Ta phải dùng Basis xoay thủ công
	#var target_basis = Basis()
	#
	#if abs(attach_face_vector.x) > 0.9: # Mặt bên (Right/Left)
		#target_basis.x = world_direction * sign(attach_face_vector.x)
		#target_basis.y = target_basis.x.cross(desired_up if attach_face_vector.x > 0 else -desired_up).normalized()
		#target_basis.z = target_basis.x.cross(target_basis.y).normalized()
		#
	#elif abs(attach_face_vector.y) > 0.9: # Mặt trên/dưới
		#target_basis.y = world_direction * sign(attach_face_vector.y)
		#target_basis.x = desired_up.cross(target_basis.y).normalized() # Up x Forward = Right
		#target_basis.z = target_basis.x.cross(target_basis.y).normalized()
		#
	#else: # Mặt trước/sau (Z)
		## Nếu local_face là BACK (0,0,1) -> Muốn BACK hướng theo world_dir
		## Thì FORWARD (-Z) sẽ hướng ngược lại (-world_dir)
		#var forward_dir = -world_direction if attach_face_vector.z > 0 else world_direction
		#
		## Dùng logic LookAt chuẩn
		## Z = -forward
		#target_basis.z = -forward_dir 
		#target_basis.x = desired_up.cross(target_basis.z).normalized()
		#target_basis.y = target_basis.z.cross(target_basis.x).normalized()
#
	## Áp dụng rotation
	#node.global_transform.basis = target_basis.orthonormalized()

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

# Hàm mới align_with_z (cho side snap)
func align_with_z(xform: Transform3D, new_normal: Vector3) -> Transform3D:
	xform.basis.z = new_normal  # Set Z = normal
	
	# Project current Y (up) lên mặt phẳng perpendicular to Z
	var up = xform.basis.y
	up -= new_normal * up.dot(new_normal)
	if up.length_squared() < 0.001:
		up = Vector3.UP if abs(new_normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	up = up.normalized()
	
	xform.basis.y = up  # Set Y = projected up
	xform.basis.x = xform.basis.y.cross(xform.basis.z)  # X = Y x Z (right-handed)
	
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

#Align selected module's basis to match snap point's basis, with face attachment
func align_with_basis(selected_module: Node3D, target_basis: Basis, attach_face_vector: Vector3, invert_z: bool = true):
	# - target_basis: basis của snap point (hoặc target module)
	# - attach_face_vector: Vector3 chỉ mặt cần gắn của module
	# - invert_z: true để invert Z nếu cần forward ngược

	var new_basis = target_basis  # Bắt đầu từ basis của snap/target
	
	# Adjust cho mặt gắn: luôn gắn -X của selected vào face của snap
	match attach_face_vector:
		Vector3(1,0,0):   # Snap face LEFT (+X của snap hướng ra) → selected +X hướng vào = -snap.x
			new_basis.x = -target_basis.x
			new_basis.z = -target_basis.z if invert_z else target_basis.z  # Invert Z để forward ngược (đối diện)
		Vector3(0,0,1):  # Snap face RIGHT (-X của snap hướng ra) → selected +X hướng vào = snap.x (vì snap -X ra ngoài?)
			new_basis.x = target_basis.x
			new_basis.z = target_basis.z if invert_z else -target_basis.z
		Vector3(0,1,0):
			new_basis.y = -target_basis.y  # Tương tự, adjust cho Y
			new_basis.z = -target_basis.z if invert_z else target_basis.z
		Vector3(-1,0,0):
			new_basis.y = target_basis.y
			new_basis.z = target_basis.z if invert_z else -target_basis.z
		# Thêm FRONT/BACK nếu cần (adjust Z)
		Vector3(0,0,-1):
			new_basis.z = -target_basis.z
			new_basis.x = -target_basis.x if invert_z else target_basis.x  # Adjust tùy theo convention
		Vector3(0,-1,0):
			new_basis.z = target_basis.z
			new_basis.x = target_basis.x if invert_z else -target_basis.x
	
	# Orthonormalize để tránh skew
	new_basis = new_basis.orthonormalized()
	# apply basis to seleted module
	var new_transform = selected_module.global_transform
	new_transform.basis = new_basis
	selected_module.global_transform = new_transform

func calculate_distant_to_face_module(attach_face_vector: Vector3, aabb: AABB) -> float:
	var dir = attach_face_vector.normalized()
	
	# Tìm điểm xa nhất trên AABB theo hướng vector đó
	# support_point là điểm trên AABB nằm xa nhất về hướng dir
	var farthest_point = aabb.get_support(dir)
	
	# Chiếu điểm đó lên vector hướng để lấy khoảng cách dọc trục
	# Vì pivot là (0,0,0) local, nên dot product chính là khoảng cách
	return abs(farthest_point.dot(dir))

func calculate_default_normal(attach_face_vector: Vector3, aabb: AABB):
	var new_normal
	if attach_face_vector == Vector3(1,0,0): 
		new_normal = Vector3.UP
	elif attach_face_vector == Vector3(0,1,0):
		new_normal = Vector3.FORWARD
	elif attach_face_vector == Vector3(0,0,1):
		new_normal = Vector3.RIGHT
	
	return new_normal
	
# Hàm xử lý gắn 2 module với nhau
func attach_to_module(module: Node3D, target: Node3D, attach_point: Vector3):
	# 1. Lưu vị trí trước khi attach
	var selected_module_global_transform = module.global_transform
	
	# 2. Xóa khỏi parent hiện tại (optional)
	var old_parent = module.get_parent()
	if old_parent: old_parent.remove_child(module)
	
	# 3. Gắn vào target module
	target.add_child(module)
	
	# 4. Gán lại global transform cho selected module
	module.global_transform = selected_module_global_transform
	
	# 5. Freeze module để tránh va chạm
	module.freeze = true
	module.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	
	# 6. Tìm và tắt va chạm giữa module và module lớn nhất (như thân tàu)
	var root_rigidBody3D = find_root_rigidBody3D(target)
	if root_rigidBody3D and root_rigidBody3D != module:
		root_rigidBody3D.add_collision_exception_with(module)
		module.add_collision_exception_with(root_rigidBody3D)
	
	# 7. Add vào group attached module	
	# Định nghĩa tên group của module bằng id
	var joint_module_group = "module_group_" + str(target.get_instance_id())
	# Thêm vào nếu chưa có
	if not target.is_in_group(joint_module_group):
		target.add_to_group(joint_module_group)
	# Thêm attach module vào attached group của module này
	module.add_to_group(joint_module_group)

# Hàm tìm node RigidBody3D trên cùng nhất
func find_root_rigidBody3D(node: Node) -> RigidBody3D:
	var current = node
	var last_rigid_node: RigidBody3D = null
	
	# Leo ngược lên cây cho đến khi hết node (gặp root của scene)
	while current:
		if current is RigidBody3D:
			last_rigid_node = current
		# Lên lên 1 node
		current = current.get_parent()
		# Đã duyệt hết thì break
		if current == get_tree().root:
			break
	
	return last_rigid_node
				
#func attach_to_module(selected_module: Node3D, target: Node3D, attach_point: Vector3):
	#var joint = Generic6DOFJoint3D.new()
	#target.add_child(joint)
	#
	#var attach_point_local = target.global_transform.affine_inverse() * attach_point
	#joint.position = attach_point_local
	#
	#joint.set_node_a(selected_module.get_path())
	#joint.set_node_b(target.get_path())
	## Configure joint properties (e.g., lock rotation/translation as needed)
	## Lock linear axes (no translation)
	#joint.set("linear_limit_x/enabled", true)
	#joint.set("linear_limit_x/lower", 0)
	#joint.set("linear_limit_x/upper", 0)
	#joint.set("linear_limit_y/enabled", true)
	#joint.set("linear_limit_y/lower", 0)
	#joint.set("linear_limit_y/upper", 0)
	#joint.set("linear_limit_z/enabled", true)
	#joint.set("linear_limit_z/lower", 0)
	#joint.set("linear_limit_z/upper", 0)
#
	## Lock angular axes (no rotation)
	#joint.set("angular_limit_x/enabled", true)
	#joint.set("angular_limit_x/lower", 0)
	#joint.set("angular_limit_x/upper", 0)
	#joint.set("angular_limit_y/enabled", true)
	#joint.set("angular_limit_y/lower", 0)
	#joint.set("angular_limit_y/upper", 0)
	#joint.set("angular_limit_z/enabled", true)
	#joint.set("angular_limit_z/lower", 0)
	#joint.set("angular_limit_z/upper", 0)
	#
	## Định nghĩa tên group của module bằng id
	#var joint_module_group = "joint_group_" + str(target.get_instance_id())
	## Thêm vào nếu chưa có
	#if not target.is_in_group(joint_module_group):
		#target.add_to_group(joint_module_group)
	## Thêm attach module vào attached group của module này
	#selected_module.add_to_group(joint_module_group)
	#
	## Tắt collision giữa selected_module và target
	#if selected_module is RigidBody3D:
		## Tắt va chạm với tất cả module trong group
		#var attached_module = get_tree().get_nodes_in_group(joint_module_group)
		#for module in attached_module:
			#if module is RigidBody3D:
				#selected_module.add_collision_exception_with(module)
				#module.add_collision_exception_with(selected_module)
	


func create_snap_module(parent: Node3D, position: Vector3, snap_normal_local: Vector3):
	var snap_module = Area3D.new()
	snap_module.name = "Snap_Point_" + str(parent.get_child_count()) # Đặt tên khác nhau
	snap_module.collision_layer = 1 << 7  # Layer 8
	snap_module.collision_mask = 0
	snap_module.position = position
	snap_module.priority = 10
	
	# **GHI METADATA: Pháp tuyến cố định (local space)**
	# Cần ghi meta 'face' nếu muốn dùng trong drag_inventory_item
	snap_module.set_meta("snap_normal_local", snap_normal_local)
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = SphereShape3D.new()
	collision_shape.shape.radius = 0.3
	snap_module.add_child(collision_shape)
	parent.add_child(snap_module)
	
	# Visual cho snap point
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = SphereMesh.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0, 1, 0, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	mesh_instance.mesh.radius = 0.05
	mesh_instance.mesh.height = 0.1
	mesh_instance.position = position
	parent.add_child(mesh_instance)

func switch_module_material(selected_module: Node3D, mode: String):
	var material = module_materials.get(mode, null)
	if not material:
		print("Material mode not found:", mode)
		return
	
	# Tìm và gán vật liệu cho đối tượng được chọn
	var mesh = current_selected_module_mesh
	if mesh:
		mesh.material_override = material

# Hàm này xoay module sao cho mặt 'attach_face' úp vào bề mặt có pháp tuyến 'target_normal'
func align_module_to_target_normal(module: Node3D, target_normal: Vector3, attach_face: Vector3):
	# 1. Hướng mục tiêu: Module cần nhìn ngược lại với pháp tuyến bề mặt (úp vào)
	var look_dir = -target_normal
	
	# 2. Hướng UP tham chiếu: Giữ module thẳng đứng nếu có thể
	var up_dir = Vector3.UP
	
	# Nếu gắn vào trần/sàn (normal gần trùng trục Y), đổi UP sang trục khác để tránh lỗi LookAt
	if abs(target_normal.dot(Vector3.UP)) > 0.95:
		up_dir = Vector3.RIGHT
	
	# 3. Tạo Basis nhìn vào bề mặt (Mặc định dùng trục -Z làm mắt)
	# Hàm này tự động tính toán Right/Up vector chuẩn, không lo méo hình
	var target_basis = Basis.looking_at(look_dir, up_dir)
	
	# 4. Xoay bù (Adjustment) nếu attach_face không phải là mặt trước (-Z)
	# Sau bước 3 thì mặt -Z đã đối mặt với target normal, cần xoay thêm 1 lượng để tới mặt cần dính
	var adjustment = Quaternion.IDENTITY
	
	if attach_face.is_equal_approx(Vector3.FORWARD):   pass # -Z (Chuẩn)
	elif attach_face.is_equal_approx(Vector3.BACK):    adjustment = Quaternion(Vector3.UP, PI) # +Z (180 độ)
	elif attach_face.is_equal_approx(Vector3.RIGHT):   adjustment = Quaternion(Vector3.UP, PI/2) # +X
	elif attach_face.is_equal_approx(Vector3.LEFT):    adjustment = Quaternion(Vector3.UP, -PI/2) # -X
	elif attach_face.is_equal_approx(Vector3.UP):      adjustment = Quaternion(Vector3.RIGHT, -PI/2) # +Y
	elif attach_face.is_equal_approx(Vector3.DOWN):    adjustment = Quaternion(Vector3.RIGHT, PI/2) # -Y
	
	# 5. Áp dụng Basis (Nhân Quaternion vào Basis target)
	module.global_basis = (target_basis * Basis(adjustment)).orthonormalized()

func align_by_normal(xform: Transform3D, normal: Vector3, module_attach_vector: Vector3):
	# 1. Xác định trục chiếm ưu thế của Normal (World Space)
	var new_transform: Transform3D
	match module_attach_vector:
		Vector3(1,0,0): new_transform = align_with_x(xform, normal)
		Vector3(0,1,0): new_transform = align_with_y(xform, normal)
		Vector3(0,0,1): new_transform = align_with_z(xform, normal)
		_: new_transform = align_with_x(xform, normal)
		
	return new_transform

func create_module_material(albedo_color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = albedo_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func get_snap_point_face(snap_point: Node3D):
	if snap_point.has_meta("face"):
		return snap_point.get_meta("face")
	# Get local position of snap_point
	var local_position = snap_point.position
	var parent_node = snap_point.owner
	var mesh_instance = parent_node.find_child("*", true, false) as MeshInstance3D
	var aabb = mesh_instance.get_aabb() if mesh_instance else AABB() # fallback empty
	var size = aabb.size
	
	# Find the most abs scale
	var norm_pos = Vector3(
		local_position.x / size.x if size.x > 0 else local_position.x,
		local_position.y / size.y if size.y > 0 else local_position.y,
		local_position.z / size.z if size.z > 0 else local_position.z
	)

	var abs_x = abs(norm_pos.x)
	var abs_y = abs(norm_pos.y)
	var abs_z = abs(norm_pos.z)
	
	if abs_x > abs_y and abs_x > abs_z:
		return "RIGHT" if norm_pos.x > 0 else "LEFT"
	elif abs_y > abs_x and abs_y > abs_z:
		return "UP" if norm_pos.y > 0 else "DOWN"
	else:
		# Trong Godot: -Z là FRONT, +Z là BACK
		return "BACK" if norm_pos.z > 0 else "FRONT"

func get_snap_point_local_normal(snap_point: Node3D) -> Vector3:
	# Nếu đã cache trong meta thì lấy ra luôn
	if snap_point.has_meta("local_normal"):
		return snap_point.get_meta("local_normal")

	var local_pos = snap_point.position
	var parent_node = snap_point.get_parent()
	var mesh_instance = parent_node.find_child("*", true, false) as MeshInstance3D
	var size = mesh_instance.get_aabb().size if mesh_instance else Vector3.ONE

	# Tìm trục chiếm ưu thế
	var nx = local_pos.x / size.x
	var ny = local_pos.y / size.y
	var nz = local_pos.z / size.z
	
	var local_normal = Vector3.ZERO
	if abs(nx) > abs(ny) and abs(nx) > abs(nz):
		local_normal = Vector3(sign(nx), 0, 0)
	elif abs(ny) > abs(nx) and abs(ny) > abs(nz):
		local_normal = Vector3(0, sign(ny), 0)
	else:
		local_normal = Vector3(0, 0, sign(nz))
	
	# Cache lại để dùng lần sau
	snap_point.set_meta("local_normal", local_normal)
	return local_normal
	
