extends Node3D

@export var snap_distance: float = 0.2  # Khoảng cách để snap

var selected_module: Node3D = null  # Module đang kéo
var drag_offset: Vector3
var modules = []  # Danh sách module đã ghép
var module_resources = []  # Danh sách resource module

func _ready():
	# Load tất cả resource từ thư mục
	var dir = DirAccess.open("res://module_UI/module_resources/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			print("Found file: ", file_name)  # Debug
			if file_name.ends_with(".tres"):
				var resource = load("res://module_UI/module_resources/" + file_name)
				if resource is ModuleInventoryItem:
					module_resources.append(resource)
					print("Loaded resource: ", resource.name)  # Debug
			file_name = dir.get_next()
	# Thiết lập Inventory UI
	var inventory = $UI/Inventory
	if inventory:
		inventory.clear()
		for resource in module_resources:
			inventory.add_item(resource.name, resource.texture)  # Sử dụng 'name' và 'texture'
		inventory.item_selected.connect(_on_inventory_item_selected)
	else:
		print("Error: Inventory node not found!")

func _input(event):
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("Error: No active Camera3D found! Please add a Camera3D and set 'Current' to true.")
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var from = camera.project_ray_origin(event.position)
			var to = from + camera.project_ray_normal(event.position) * 100
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(from, to)
			var result = space_state.intersect_ray(query)
			if result and result.collider is Node3D and result.collider in modules:
				selected_module = result.collider
				drag_offset = selected_module.global_transform.origin - result.position
		else:
			if selected_module:
				try_snap(selected_module)
				selected_module = null

	if event is InputEventMouseMotion and selected_module:
		var mouse_pos = get_viewport().get_mouse_position()
		var from = camera.project_ray_origin(mouse_pos)
		var dir = camera.project_ray_normal(mouse_pos)
		var plane = Plane(Vector3(0, 1, 0), 0)  # Giả sử kéo trên mặt phẳng XZ
		var intersect = plane.intersects_ray(from, dir)
		if intersect:
			selected_module.global_transform.origin = intersect + drag_offset

func try_snap(module: Node3D):
	for other_module in modules:
		if other_module == module: continue
		for snap in module.get_children():
			if snap is Marker3D and snap.name.begins_with("Snap_"):
				for other_snap in other_module.get_children():
					if other_snap is Marker3D and other_snap.name.begins_with("Snap_"):
						var distance = snap.global_transform.origin.distance_to(other_snap.global_transform.origin)
						if distance < snap_distance:
							module.global_transform = other_snap.global_transform * snap.transform.affine_inverse()
							var joint = PinJoint3D.new()
							joint.node_a = module.get_path()
							joint.node_b = other_module.get_path()
							add_child(joint)
							joint.owner = self
							print("Snapped: " + module.name + " to " + other_module.name)
							return

func _on_inventory_item_selected(index):
	print("Item selected: ", index)
	if index >= 0 and index < module_resources.size():
		var resource = module_resources[index]
		var new_module = load(resource.scene_path).instantiate()
		add_child(new_module)
		new_module.owner = self
		new_module.global_transform.origin = Vector3(0, 0, 0)  # Spawn tại gốc
		modules.append(new_module)
		print("Added module: " + new_module.name)
	else:
		print("Error: Invalid index for module resource!")
		
		
func place_inventory_item():
	if not selected_module:
		return

	# Get raycast and mesh instance for visual feedback
	var raycast_node = selected_module.find_child("raycast", true, false) as RayCast3D
	var mesh_instance = selected_module.find_child("*", true, false) as MeshInstance3D

	# Check if the module is colliding and within snap distance
	if raycast_node and raycast_node.is_colliding():
		var collision_point = raycast_node.get_collision_point()
		var collider = raycast_node.get_collider()
		var normal = raycast_node.get_collision_normal()
		var distance = selected_module.global_position.distance_to(collision_point)

		if distance > snap_distance:
			print("Error: Module too far from surface to snap (distance: ", distance, ")")
			cancel_inventory_item()
			change_state(State.NONE)
			return

		# Determine the face of the collider
		var collider_face = check_raycast_face_collide(raycast_node)
		if collider_face == "face_off":
			print("Error: Invalid surface for placement")
			cancel_inventory_item()
			change_state(State.NONE)
			return

		# Snap module to the collision point, offset by normal and module size
		var module_aabb = mesh_instance.get_aabb() if mesh_instance else AABB()
		var offset = normal * (module_aabb.size.y * 0.5)  # Adjust based on module size (Y-axis for height)
		selected_module.global_position = collision_point + offset

		# Align module based on the target face
		match collider_face:
			"up":
				selected_module.global_transform = align_with_y(selected_module.global_transform, normal)
			"down", "left", "right", "front", "back":
				selected_module.global_transform = align_with_x(selected_module.global_transform, normal)
				# Optionally, use align_with_z for specific faces if needed

		# Perform overlap check to prevent invalid placement
		if check_for_overlap():
			print("Error: Module overlaps with another object")
			cancel_inventory_item()
			change_state(State.NONE)
			return

		# Finalize placement
		# Restore physics properties
		selected_module.collision_layer = 1  # Restore collision layer (adjust as needed)
		selected_module.collision_mask = 1  # Restore collision mask
		selected_module.freeze = false  # Enable physics if applicable

		# Remove ghost material
		if mesh_instance and mesh_instance.material_override:
			mesh_instance.material_override = null  # Reset to default material

		# Remove raycast and visual
		var ray_visual = selected_module.find_child("ray_visual", true, false)
		if ray_visual:
			ray_visual.queue_free()
		if raycast_node:
			raycast_node.queue_free()

		# Optionally attach to the collider (e.g., using a joint)
		if collider and collider.is_in_group("modules"):  # Assuming placed modules are in "modules" group
			attach_to_module(collider)

		# Add to placed modules list
		modules_placed.append(selected_module)
		print("Module placed successfully at ", selected_module.global_position)

	else:
		print("Error: No valid surface for placement")
		cancel_inventory_item()

	# Reset state
	selected_module = null
	current_selected_index = -1  # Reset index to allow new selection
	current_collision_info = {}
	change_state(State.NONE)

# Helper function to check for overlaps
func check_for_overlap() -> bool:
	var area = Area3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	var mesh_instance = selected_module.find_child("*", true, false) as MeshInstance3D
	var aabb = mesh_instance.get_aabb() if mesh_instance else AABB()
	shape.extents = aabb.size * 0.5
	collision_shape.shape = shape
	area.add_child(collision_shape)
	selected_module.add_child(area)
	area.global_transform = selected_module.global_transform

	# Check for overlapping bodies
	var overlapping = false
	for body in area.get_overlapping_bodies():
		if body != selected_module and body.is_in_group("modules"):
			overlapping = true
			break

	# Clean up
	area.queue_free()
	return overlapping

# Helper function to attach to another module (optional)
func attach_to_module(target: Node3D):
	var joint = Generic6DOFJoint.new()
	add_child(joint)
	joint.set_node_a(selected_module.get_path())
	joint.set_node_b(target.get_path())
	# Configure joint properties (e.g., lock rotation/translation as needed)
	joint.set("linear_limit_x/enabled", true)
	joint.set("linear_limit_y/enabled", true)
	joint.set("linear_limit_z/enabled", true)
	joint.set("angular_limit_x/enabled", true)
	joint.set("angular_limit_y/enabled", true)
	joint.set("angular_limit_z/enabled", true)
