extends  Node

var world_vector: = Vector3.FORWARD

@export var snap_distance: float = 0.2  # snap
var drag_offset: float = 10.0  # offset from raycast mouse
var modules_core = {}	# list chứa các module thuộc về phần thân tàu
var modules_placed = {}  # modules already placed in the scene
var module_resources_array = []  # list of available resource loaded - for UI
var module_resources = {}  # list of available resource loaded - for UI
var camera: Camera3D  # current camera of this scene
var attach_epsilon: float = 0.001

enum State {NONE, SELECT, CANCEL, PLACE, FLIGHT}	# states for selected module
var module_materials: Dictionary = {}  # Module materials

var current_state: State
var current_selected_index:= -1	# selected module index from 0, -1 for init
var current_collision_info = {} # current collision info	
var current_selected_module: Node3D = null  # current selected module
var current_selected_module_type: Global_Enums.ModuleType # current selected module type
var current_selected_module_origin_basis: Basis # current selected module origin basis
var current_selected_module_mesh: MeshInstance3D
var current_selected_module_collision: CollisionShape3D
var current_selected_module_ray_visual: MeshInstance3D
var current_selected_module_raycast: RayCast3D
var current_target_transform: Transform3D	# Transform mà selected module sẽ cần thực hiện (for slerp animation)
var current_snap_point: Area3D
var current_hovered_module: Node3D = null	# current hoverd module (highlight as mouse point)
var is_valid_module_placement: bool = false # Biến check xem hiện tại module có đủ điều kiện để lắp chưa

const LAYER_ENVIRONMENT: int = 1     # 2^0 (Layer 1)
const LAYER_SHIP_MODULE: int = 2     # 2^1 (Layer 2)
const LAYER_SNAP_POINT: int = 128    # 2^7 (Layer 8)

@onready var inventory_ui = $UI/Inventory
@onready var ship_stats_ui: RichTextLabel = $RichTextLabel
@onready var camera_3d_free : Node3D = $Camera_Free
@onready var extra_01_root: RigidBody3D = $extra_01_Root

#---------------------------------------DEAFAULT FUNCTION ---------------------------------
func _ready():
	# set current camera to camera this scene
	Global_Camera.switch_to(camera_3d_free)
	camera = Global_Camera.current_rig.camera_3d
	if not camera:
		print("Error: No active Camera3D found! Please add a Camera3D and set 'Current' to true.")
		return
	
	# load resources vào array
	module_resources_array = read_resource_to_array("res://modules/module_resources/")
	
	# set UI Node
	if inventory_ui:
		inventory_ui.clear()
		for resource in module_resources_array:
			# add items from resource array to inventory items
			inventory_ui.add_item(resource.name, resource.texture_2d)  # display name and texture icon
		inventory_ui.item_selected.connect(_on_inventory_item_selected)  # Kết nối sự kiện chọn item
	else:
		print("Error: Inventory node not found!")
	
	# Load module resource vào list
	for i in range(module_resources_array.size()):
		var module = module_resources_array[i]
		module_resources[module.module_id] = {
			"index": i,
			"module": module
		}
	
	# set init state
	current_state = State.NONE
	
	# init list module materials 
	module_materials["no_collide"] = create_module_material(Color(0.906, 0.948, 1.0, 0.345))
	module_materials["collide_with_common"] = create_module_material(Color(0.0, 0.788, 0.983, 0.345))
	module_materials["collide_with_snap_point"] = create_module_material(Color(0.184, 0.859, 0.027, 0.345))
	module_materials["blocked"] = create_module_material(Color(1.0, 0.2, 0.2, 0.5))
	module_materials["highlight"] = create_module_material(Color(1.0, 1.0, 0.2, 0.4))
	
	# add default module (for test only)
	#modules_placed[extra_01_root.get_instance_id()] = {"module": extra_01_root}
	
	# Update ship stats UI
	update_ship_stats_ui()

func _physics_process(delta: float) -> void:
	# 1. Bắn raycast từ chuột
	var mouse_raycast_data = shoot_mouse_raycast()
	
	# Nếu đang cầm đồ -> chạy Drag (Kéo thả)
	if current_state == State.SELECT and current_selected_module != null:
		# Nhớ xóa highlight nếu đang có
		drag_inventory_item(mouse_raycast_data)
		
	# Nếu đang rảnh tay -> chạy Hover (Rê chuột tìm đồ để Highlight)
	elif current_state == State.NONE:
		highlight_hovered_module(mouse_raycast_data)

func _unhandled_input(event: InputEvent) -> void:
	# =======================================================
	# 1. CAMERA LOGIC (Của bạn)
	# =======================================================
	if event.is_action_pressed("toggle_camera"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	# =======================================================
	# 2. BUILDING LOGIC (Logic cầm/đặt đồ)
	# =======================================================
	match current_state:
		State.NONE:
			# Bấm Chuột Trái + Đã chọn đồ -> Cầm đồ lên
			#if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				#if current_selected_index >= 0:
					#create_selected_module()
					#change_state(State.SELECT)
					
			# Nếu không cầm module nào và đang hover -> Xóa module
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				if current_hovered_module != null && current_selected_module == null:
					delete_placed_module(current_hovered_module)
					
		State.SELECT:
			if event.is_action_pressed("cancel_selection"):
				cancel_inventory_item()
				change_state(State.NONE)
				
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				# Kiểm tra xem trạng thái hiện tại đã đủ điều kiện để gắn
				if is_valid_module_placement:
					place_module()
					change_state(State.NONE)
				else: print("Hell nah bro its stuck something")
				
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				# Nếu cầm module -> Bỏ module
				cancel_inventory_item()
				change_state(State.NONE)

	# =======================================================
	# 3. XOAY MODULE
	# =======================================================
	if current_state == State.SELECT and current_selected_module != null and event.is_action_pressed("rotate_module"):
		current_selected_module.basis = current_selected_module.basis.rotated(current_selected_module.basis.y.normalized(), deg_to_rad(10))
		current_selected_module_origin_basis = current_selected_module.basis 
		if typeof(current_target_transform) != TYPE_NIL: # An toàn check
			current_target_transform.basis = current_selected_module.basis 
		current_collision_info.clear() 
		
	# =======================================================
	# 4. HỆ THỐNG LƯU BẢN THIẾT KẾ (SAVE BLUEPRINT)
	# =======================================================
	if event.is_action_pressed("save_ship"):
		if current_state == State.NONE and current_selected_module == null:
			save_ship_to_blueprint("res://my_awesome_ship.json")
	
	if event.is_action_pressed("load_ship"): # <--- THÊM NÚT LOAD
		if current_state == State.NONE and current_selected_module == null:
			load_ship_from_blueprint("res://my_awesome_ship.json")
	
	# =======================================================
	# 5. CHẠY THỬ SAU KHI BUILD
	# =======================================================
	if event.is_action_pressed("test_flight"):
		if current_state == State.NONE and current_selected_module == null:
			change_to_flight_mode()
#---------------------------------------SIGNAL-------------------------------------------
# Hàm tính toán lại 1 model duy nhất cho ship và vào trạng thái chạy thử
# Gộp thành 1 rigidbody3D duy nhất + reparent toàn bộ collision shape về 1 body
# Công thức tính center_of_mass = Tổng(position * mass) / total mass
func change_to_flight_mode():
	# Check số core module hiện tại có đủ
	if modules_core.size() < 4: 
		print("Hell nah bro not enough part to light ship") 
		return
	
	print("Start packing your ass up...")
	
	# 1. Lấy 1 trong các core làm node gốc
	var core_instance_id = modules_core.keys()[0] # Lấy ID của module gốc đầu tiên
	var core_node = modules_core[core_instance_id]["module"] as RigidBody3D
	
	# Set các biến tính mass và com
	var total_mass: float = 0	# Tổng khối lượng của ship
	var center_of_mass_sum: Vector3 = Vector3.ZERO	
	
	# 2. Compact các module
	for module_instance_id in modules_placed:
		# 1. Lấy node module 
		var data = modules_placed[module_instance_id]
		var module = data["module"] as RigidBody3D
			
		# 2.1 Tính khối lượng
		var mass = module.module_data.mass
		total_mass += mass
		
		# 2.2 Tính vị trị của module so với node core
		# Lấy global transform của module, biến đổi ngược về local transform của Core
		# Tức invert global transform của core, nhân với global transform origin của module
		var local_relative_position = core_node.global_transform.affine_inverse() * module.global_transform.origin
		center_of_mass_sum += local_relative_position * mass
		
		# 2.3 Chuyển collision sang core module
		# Bỏ qua module core đầu tiên đã chọn làm node gốc
		if module != core_node:
			# Turn off các thiết lập vật lý của module
			module.collision_layer = 0
			module.collision_mask = 0
			module.freeze = true
			module.process_mode = Node.PROCESS_MODE_DISABLED	# Tắt tính toán node luôn
			# Duyệt qua các node child trong module
			for child in module.get_children():
				# Xóa hết các node snap point
				if child is Area3D and child.name.begins_with("Snap_Point"):
					child.queue_free()
				# Reparent collision shape về hết cho core module
				if child is CollisionShape3D:
					# Hàm reparent đã hỗ trợ giữ nguyên vị trí cho shape
					child.reparent(core_node, true)
		
	# 3. Thiết lập các thông số mới cho khối regidbody3D duy nhất
	# Tính center of mass
	var final_center_of_mass = center_of_mass_sum / total_mass
	core_node.mass = total_mass	# Gán mass cho rigidbody3D
	core_node.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM	# Để center of mass sang custom mode
	core_node.center_of_mass = final_center_of_mass
	
	# 4. Xóa group metadata snap point
	get_tree().call_group("builder_snap_points", "queue_free")
	
	# 5. Set chuyển động, bỏ lock cho ship
	core_node.freeze = false
	core_node.can_sleep = false     
	core_node.sleeping = false      
	core_node.gravity_scale = 0.5   # Chịu 100% trọng lực
	
	# Xóa tàn dư động lực học cũ
	core_node.linear_velocity = Vector3.ZERO
	core_node.angular_velocity = Vector3.ZERO
		
	# 6. Ẩn UI Xây dựng đi
	if inventory_ui:
		inventory_ui.hide()
	
	# 7. Change state
	change_state(State.FLIGHT)
	print("HỢP THỂ THÀNH CÔNG! TỔNG KHỐI LƯỢNG: ", total_mass, " | TRỌNG TÂM: ", final_center_of_mass)
			
		
# Hàm event khi có 1 item được chọn từ inventory UI
func _on_inventory_item_selected(index):
	print("Item selected: ", index)
	print(module_resources_array[index])
	start_placement(index)

# Hàm xử lý việc kiểm tra module có đang chồng lấn với module khác
func check_module_overlap() -> bool:
	if not current_selected_module:
		return false
		
	# 1. Tìm CollisionShape3D của module đang cầm
	var collision_shape = current_selected_module_collision.shape
	if not collision_shape:
		return true # Nếu không có shape (lỗi data), tạm cho qua
		
	# 2. Setup hệ thống dò tìm (Shape Cast)
	var space_state = get_viewport().find_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	
	query.shape = collision_shape
	query.transform = current_target_transform # Ướm thử vào VỊ TRÍ TƯƠNG LAI
	query.collision_mask = LAYER_SHIP_MODULE # Chỉ check xem có cấn vào module khác không
	
	# 3. LOẠI TRỪ VẬT ĐANG ĐƯỢC GẮN LÊN
	# Tránh lỗi tự va chạm với chính cái bức tường/ổ cắm mà mình đang muốn gắn vào
	var exclude_array = []
	if current_collision_info.has("collider") and current_collision_info["collider"]:
		var target_collider = current_collision_info["collider"]
		if target_collider is CollisionObject3D:
			exclude_array.append(target_collider.get_rid())
			
	query.exclude = exclude_array
	
	# 4. Thực hiện quét (Chỉ cần tìm thấy 1 vật bị cấn là đủ kết luận)
	var overlaps = space_state.intersect_shape(query, 10)
	
	# 5. Duyệt qua từng vật bị đụng trúng
	for overlap in overlaps:
		var hit_collider = overlap.collider
		
		# Tìm gốc (RigidBody) của vật bị đụng
		var root_collider = find_root_rigidBody3D(hit_collider)
		if not root_collider:
			root_collider = hit_collider
			
		# KIỂM TRA: Nó có phải là một module tàu đã đặt không?
		if modules_placed.has(root_collider.get_instance_id()):
			# Phát hiện đâm xuyên vào một module khác của tàu! -> CẤM XÂY
			return false 
			
	# Nếu vòng lặp chạy hết mà chỉ đụng trúng tường, sàn nhà (không có trong modules_placed)
	# -> CHO PHÉP XÂY (Hợp lệ)
	return true

# Hàm xử lý việc kiểm tra module có đang align đúng với attachment
func check_valid_attachment_surface(target_collider: Node) -> bool:
	# - target_collider: Collider hiện tại mà module đang align
	
	# 1. Nếu chỉ vào Sàn nhà/Tường (Environment) -> Hợp lệ (Cho phép đặt lên sàn)
	var root_rigid = find_root_rigidBody3D(target_collider)
	if not root_rigid:
		return true 
		
	# 2. Nếu chỉ vào một Module đã đặt, lấy thông tin của nó ra
	var target_id = target_collider.get_instance_id()
	if modules_placed.has(target_id):
		var target_data = modules_placed[target_id]
		var target_category = target_data.get("module_type") # Thuộc tính Category bạn đã lưu
		
		var holding_category = current_selected_module.module_data.category
		
		# --- LUẬT XÂY DỰNG TẠI ĐÂY ---
		
		# Luật 1: Nếu đang cầm một module KHUNG SƯỜN (Structural - Hull, Corridor)
		# -> Có thể gắn lên bất cứ đâu (Gắn nối tiếp Hull, hoặc làm bệ đỡ) -> HỢP LỆ
		if holding_category == Global_Enums.Category.STRUCTURAL:
			if target_category != Global_Enums.Category.STRUCTURAL:
				return false
			else:
				return true
			
		# Luật 2: Nếu đang cầm PHỤ KIỆN (Surface/Weapon - Turret, Radar)
		# -> CHỈ ĐƯỢC gắn lên KHUNG SƯỜN. Gắn lên Phụ kiện khác -> BỊ CẤM
		if holding_category != Global_Enums.Category.STRUCTURAL:
			if target_category != Global_Enums.Category.STRUCTURAL:
				return false # Bị cấm! (Súng không được đè lên Súng)
				
	return true

# Hàm delete module + child bên trong
func delete_placed_module(module: Node3D):
	# 1. TÌM VÀ XÓA CÁC MODULE CON TRƯỚC (Đệ quy)
	print("bro...")
	for child in module.get_children():
		if child is RigidBody3D and modules_placed.has(child.get_instance_id()):
			delete_placed_module(child) # Gọi lại chính hàm này cho đứa con
			
	# 2. XÓA CHÍNH NÓ
	var instance_id = module.get_instance_id()
	
	if modules_placed.has(instance_id):
		var module_info = modules_placed[instance_id]
		
		# A. Nhả ổ cắm ra (mở khóa Snap Point)
		var attached_snap_point = module_info.get("snap_point")
		# Giả sử trong script snap_point.gd bạn có viết hàm set_to_free() để mở lại
		if attached_snap_point and attached_snap_point.has_method("set_to_available"): 
			attached_snap_point.set_to_available()
		
		# B. Tắt highlight để tránh lỗi truy xuất đồ họa của vật đã bị xóa
		set_module_highlight(module, false)
		
		# C. Xóa khỏi danh sách module đã đặt + core module
		modules_placed.erase(instance_id)
		if module_info.get("module_type") == Global_Enums.Category.STRUCTURAL:
			modules_core.erase(instance_id)
		
		# D. Tắt layer vật lý để Tia Raycast không bao giờ chạm vào nó nữa
		module.collision_layer = 0
		module.collision_mask = 0
		
		# (Tùy chọn) Ẩn nó đi luôn để mắt người chơi không thấy nó bị delay 1 frame
		module.visible = false 
		
		# E. Gọi lệnh Hủy (Godot sẽ tự lo việc xóa nó khỏi Scene, xóa Group Snap point, v.v...)
		module.queue_free()
		
		# F. Reset lại biến chuột đang trỏ
		if current_hovered_module == module:
			current_hovered_module = null
			
		print("Đã đập bỏ module ID: ", instance_id)
		
	# Update ship stats UI
	update_ship_stats_ui()
#---------------------------------------CUSTOM FUNCTION ---------------------------------
func update_ship_stats_ui():
	if not ship_stats_ui:
		return
		
	var total_modules = modules_placed.size()
	var total_mass: float = 0.0
	
	# Vòng lặp tính toán tổng chỉ số
	for instance_id in modules_placed:
		var data = modules_placed[instance_id]
		var module_node = data["module"]
		
		# Tùy thuộc vào việc Resource của bạn có biến mass hay không
		# Giả sử module_node.module_data.mass là khối lượng của 1 khối
		if "mass" in module_node.module_data:
			total_mass += module_node.module_data.mass
		else:
			total_mass += 10.0 # Nếu chưa có data thì cho tạm mỗi cục nặng 10kg
			
	# Sử dụng BBCode để định dạng (Cú pháp giống HTML)
	var ui_text = "[b][color=yellow]--- SHIP STATS ---[/color][/b]\n"
	ui_text += "Total Modules: [color=cyan]%d[/color]\n" % total_modules
	ui_text += "Total Mass: [color=orange]%.1f kg[/color]\n" % total_mass
	ui_text += "[color=red]RAMMING SPEED AHEAD!\n" % total_mass
	# Thêm các dòng khác tùy ý...
	
	# Gán vào RichTextLabel
	ship_stats_ui.text = ui_text
	
# =======================================================
# SAVE & LOAD LOGIC (BLUEPRINT SYSTEM)
# Info needed:
# 1. Which module (reource + scene instance)
# 2. Relationships (parent_id)
# 3. Local position
# 4. Local rotation
# =======================================================
func save_ship_to_blueprint(file_path: String):
	# - file_path: Đường dẫn để lưu file save
	
	# Nếu không có module nào thì không lưu
	if modules_placed.is_empty():
		print("Ship empty, không có gì để lưu!")
		return
		
	var blueprint_data = [] # Mảng chứa dữ liệu của toàn bộ con tàu
	
	# Lặp qua từng module đã được attach
	for instance_id in modules_placed:
		var data = modules_placed[instance_id]	# Lấy dict data
		var module_node = data["module"] as Node3D	# Lấy chính xác node module
		
		# 1. Tìm xem parent của module này là node nào (để lúc load còn biết bề mặt mà gắn vào - add_child())
		var parent_node = module_node.get_parent()
		var parent_id = -1 # Mặc định -1 nghĩa là Module Gốc (Core) không có parent
		
		# Parent node phải có trong danh sách module đã attach
		if parent_node and modules_placed.has(parent_node.get_instance_id()):
			parent_id = parent_node.get_instance_id()
			
		# 2. Lấy vị trí và góc xoay TƯƠNG ĐỐI (Local Transform)
		var pos = module_node.position
		var rot = module_node.rotation
		
		# 3. Lấy snap point name
		var snap_point = data["snap_point"]
		var snap_point_name = ""
		if snap_point != null: 
			snap_point_name = snap_point.name
		
		# 3. Đóng gói dữ liệu thành Dictionary
		var module_info = {
			"id": instance_id,              # ID hiện tại (để làm mốc liên kết)
			"parent_id": parent_id,         # Thuộc về node nào, mặc định -1, tương đương node gốc
			"module_id": data["module_id"],    # Lấy resource nào
			"snap_point_name": snap_point_name,
			# Tách Vector3 ra thành các số Float vì JSON không hiểu Vector3 của Godot
			"pos_x": pos.x, "pos_y": pos.y, "pos_z": pos.z,
			"rot_x": rot.x, "rot_y": rot.y, "rot_z": rot.z
		}
		
		blueprint_data.append(module_info)
		
	# 4. Ghi ra file JSON
	var json_string = JSON.stringify(blueprint_data, "\t") # "\t" giúp file JSON có định dạng thụt lề cho dễ đọc
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("==== ĐÃ LƯU BẢN THIẾT KẾ THÀNH CÔNG TẠI: ", file_path, " ====")
		print("Tổng số module đã lưu: ", blueprint_data.size())
	else:
		print("Lỗi: Không thể tạo file lưu!")

# Hàm dọn dẹp hiện trường trước khi Load tàu mới
func clear_all_placed_modules():
	# Xóa tất cả các module đang có trên màn hình
	# Snap point sẽ tự động xóa theo
	for instance_id in modules_placed:
		var module = modules_placed[instance_id]["module"]
		if is_instance_valid(module):
			module.queue_free()
			
	# Xóa sạch Data trong Dictionary
	modules_placed.clear()
	modules_core.clear()
	current_selected_module = null 
	current_selected_module_mesh = null
	current_selected_module_collision = null
	current_selected_module_origin_basis = Basis()
	current_selected_module_raycast = null
	current_selected_module_ray_visual = null

# Hàm Load và lắp ráp tự động
func load_ship_from_blueprint(file_path: String):
	# -file_path: đường dẫn đến file save
	
	# 1. Kiểm tra và đọc file json
	if not FileAccess.file_exists(file_path):
		print("Không tìm thấy file thiết kế: ", file_path)
		return
	# Mở file và đọc vào dạng text
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	# Parse sang json
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("Lỗi đọc file JSON: ", json.get_error_message())
		return
	# Check định dạng file
	var blueprint_data = json.data
	if typeof(blueprint_data) != TYPE_ARRAY:
		print("Định dạng file không hợp lệ!")
		return
		
	# 2. Xóa các module hiện tại để load module từ file save vào
	clear_all_placed_modules()
	
	# Dictionary tạm để lưu các Node từ JSON
	var temp_nodes = {}
	
	# 3. Tạo lại tất cả module
	for data in blueprint_data:
		var old_instance_id = data["id"]	# Lấy instance id
		var old_module_id = data["module_id"]	# Lấy module id
		
		# Check module id có tồn tại trong list
		if not module_resources.has(old_module_id):
			print("Nah bro no module found for this id")
			continue
		# Lấy resource tương ứng và tạo module instance
		var resource = module_resources[old_module_id]["module"]
		var new_module = resource.create_node_3d_scene_instance()
		
		# Setting lại vật lý
		if new_module is RigidBody3D:
			new_module.freeze = true
			new_module.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		new_module.collision_layer = LAYER_SHIP_MODULE
		new_module.collision_mask = LAYER_ENVIRONMENT + LAYER_SHIP_MODULE
		
		# Phục hồi Tọa độ và Góc xoay (Local Transform)
		new_module.position = Vector3(data["pos_x"], data["pos_y"], data["pos_z"])
		new_module.rotation = Vector3(data["rot_x"], data["rot_y"], data["rot_z"])
		
		# Lưu vào dict tạm
		temp_nodes[old_instance_id] = {
			"node": new_module,
			"data": data
		}
		
	# 4. Setting relationships và load data vào các danh sách module hiện tại
	for old_instance_id in temp_nodes:
		var dict = temp_nodes[old_instance_id]	# Lấy dữ liệu
		var new_module = dict["node"]
		var data = dict["data"]
		var parent_id = data["parent_id"]
		var snap_point_occupied = null	# Biến lưu xem module được gắn vào điểm gắn nào
		
		# 4.1 Thiết lập relationship (parent-child)
		if parent_id == -1:
			# Đây là Module Gốc (Hull-core)
			add_child(new_module)	# Add vào scene
			new_module.owner = self	# Cho owner là chính module, vì là nốt gốc
		else:
			# Đây là Module con (Súng, Cánh,...)
			if temp_nodes.has(parent_id):
				var parent_node = temp_nodes[parent_id]["node"]
				parent_node.add_child(new_module) # Cắm con vào cha
				
				# Tắt va chạm giữa Module Con và Thân Tàu Gốc
				var root_rigid = find_root_rigidBody3D(parent_node)
				if root_rigid and root_rigid != new_module:
					root_rigid.add_collision_exception_with(new_module)
					new_module.add_collision_exception_with(root_rigid)
					
				# Phân lại Group để quản lý
				var joint_group = "module_group_" + str(parent_node.get_instance_id())
				if not parent_node.is_in_group(joint_group):
					parent_node.add_to_group(joint_group)
				new_module.add_to_group(joint_group)
				
				# Xử lý các snap point
				var snap_name = data.get("snap_point_name", "")
				if snap_name != "":
					# Tìm snap_point bên trong parent dựa vào tên (lúc tạo module instance đã gắn tên theo index)
					var snap_node = parent_node.get_node_or_null(snap_name)
					if snap_node:
						snap_point_occupied = snap_node
						# Chuyển thành đã đưuọc dùng như trước khi lưu
						if snap_node.has_method("set_to_occupied"):
							snap_node.set_to_occupied()

		# 4.2 Thêm lại vào list module đã attach
		var new_instance_id = new_module.get_instance_id()	# Set lại instance_id (mỗi lần chạy là 1 id khác)
		var mesh_instance = new_module.find_child("*", true, false) as MeshInstance3D
		
		var module_info = {
			"module": new_module,
			"module_id": data["module_id"],
			"module_type": new_module.module_data.category,
			"mesh": mesh_instance,
			"raycast_node": null,	# null vì raycast node chỉ được tạo khi tương tác trong UI
			"is_snap": (snap_point_occupied != null), 
			"snap_point": snap_point_occupied 
		}
		
		# Thêm vào list
		modules_placed[new_instance_id] = module_info	# list chung
		if new_module.module_data.category == Global_Enums.Category.STRUCTURAL:
			modules_core[new_instance_id] = module_info	# list riêng cho core module

	print("==== ĐÃ TẢI BẢN THIẾT KẾ THÀNH CÔNG! ====")
	print("Tổng số module đã tái tạo: ", modules_placed.size())
	
	# Update ship stats UI
	update_ship_stats_ui()

# Hàm load resource hiện có vào 1 mảng
func read_resource_to_array(path: String) -> Array:
	# - path: Đường dẫn tới thư mục cần đọc
	
	# 1. Mở thư mục theo đường dẫn
	var directory = DirAccess.open(path)
	var resource_arr := []	# Array chứa các resource
	
	# 2. Duyệt thư mục
	if directory:
		directory.list_dir_begin()
		var file_name = directory.get_next()
		while file_name != "":
			# 3. Chỉ lấy các file resource có đuôi .tres
			if file_name.ends_with(".tres"):
				var resource = load(path + file_name)
				# Tất cả resource đều là instance của Module class
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
	if current_selected_module:
		current_selected_module.queue_free()
		current_selected_module = null
		
	# 2. Lấy resource tương ứng từ danh sách đã load + tạo instance
	var resource = module_resources_array[current_selected_index]
	# Tạo 1 instance node 3D - scene 3D từ resource trong script module inventory item
	current_selected_module = resource.create_node_3d_scene_instance()
	add_child(current_selected_module)	# Thêm vào cây node hiện tại
	current_selected_module.owner = self
	
	# 3. Tạo ray node + ray visual để thể hiện mặt cần gắn
	var raycast_created = create_raycast_visual(current_selected_module, current_selected_module.module_data.attach_face_vector, 10.0, Color(1, 0, 0, 0.5))
	
	# 4. Xoay mặt cần gắn về hướng -Z
	align_face_to_direction(current_selected_module, current_selected_module.module_data.attach_face_vector, world_vector)
	
	# 5. Lưu các biến hiện tại để dùng
	current_selected_module_type = current_selected_module.module_data.module_type
	current_selected_module_origin_basis = current_selected_module.basis
	current_selected_module_mesh = current_selected_module.get_child(0) as MeshInstance3D
	current_selected_module_collision = current_selected_module.get_child(1) as CollisionShape3D
	current_selected_module_ray_visual = raycast_created["ray_visual"]
	current_selected_module_raycast = raycast_created["raycast3D"]
	
	# 6. Chuyển visual cho module sang ban đầu là chưa va chạm gì
	switch_module_material(current_selected_module_mesh, "no_collide")
	
	# 7. Tắt các chức năng collistion và set freeze để không bị ảnh hưởng bới các tác nhân khác
	if current_selected_module is RigidBody3D:
		current_selected_module.freeze = true
	current_selected_module.collision_layer = 0  
	current_selected_module.collision_mask = 0  
	current_selected_module.linear_velocity = Vector3.ZERO
	current_selected_module.angular_velocity = Vector3.ZERO
	
	# 8. Gán transform hiện tại
	current_target_transform = current_selected_module.global_transform
	
	# 9. Bật/tắt các snap point tương ứng
	get_tree().call_group("builder_snap_points", "check_and_show_visual", current_selected_module_type)

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

# Hàm tạo raycast từ chuột, trả về dict chứa thông tin raycast và kết quả
func shoot_mouse_raycast() -> Dictionary:
	# Set các biến dùng cho mouse ray
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var to = from + dir * 1000.0
	
	# Tạo 1 query từ vị trí chuột chỉ thẳng đến 1000 đơn vị
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	# === TÙY BIẾN THÔNG SỐ RAYCAST THEO STATE ===
	if current_state == State.SELECT and current_selected_module != null:
		# TRẠNG THÁI CẦM ĐỒ: Cần tìm Snap Point, loại trừ đồ đang cầm
		query.collision_mask = LAYER_ENVIRONMENT + LAYER_SHIP_MODULE + LAYER_SNAP_POINT
		query.collide_with_areas = true
		query.exclude = [current_selected_module, camera]
	else:
		# TRẠNG THÁI RẢNH TAY (Hover): Chỉ tìm khối hình, bỏ qua Snap Point
		query.collision_mask = LAYER_ENVIRONMENT + LAYER_SHIP_MODULE 
		query.collide_with_areas = false
		query.exclude = [camera]
		
	var space_state = get_viewport().find_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)
	
	# Trả về 1 Dictionary chứa tất cả đồ nghề cho các hàm khác xài
	return {
		"result": result,
		"from": from,
		"dir": dir
	}

# Hàm xử lý việc highligh module khi được chuột hover lên
func highlight_hovered_module(mouse_raycast_data: Dictionary):
	# - mouse_raycast_data: dict chứa thông tin raycast bắn từ chuột
	
	# Lấy raycast result
	var result = mouse_raycast_data.result
	
	# Kiểm tra xem raycast có đang point vào module nào không
	if result.has("collider"):
		var hovered_module = result.collider as Node3D
		# Nếu là module đã đưuọc attach thì highlight lên
		if hovered_module is RigidBody3D \
			and modules_placed.has(hovered_module.get_instance_id()):
			# Tắt highlight module cũ nếu đang là module mới
			if hovered_module != current_hovered_module:
				set_module_highlight(current_hovered_module, false)
				current_hovered_module = hovered_module
			
			# Set visual highlight
			set_module_highlight(current_hovered_module, true)
		
		# Nếu đang point vào vật thể khác không phải attach module
		else:
			set_module_highlight(current_hovered_module, false)
	
	# Nếu đang không point bất cữ thứ gì
	else:
		set_module_highlight(current_hovered_module, false)

# Hàm bật/tắt vật liệu Highlight bằng Overlay
func set_module_highlight(module: Node3D, is_highlight: bool):
	# Tìm mesh của module hiện tại thông qua danh sách module đã attach + instance id
	var mesh_instance: MeshInstance3D
	if module:
		mesh_instance = modules_placed[module.get_instance_id()].mesh
		
		if mesh_instance:
			if is_highlight:
				# Dùng material_overlay thay vì material_override
				# Overlay sẽ tạo một lớp phủ màu vàng lên trên màu gốc của module
				mesh_instance.material_overlay = module_materials["highlight"]
			else:
				# Tắt lớp phủ đi
				mesh_instance.material_overlay = null
				# Xóa biến hovered hiện tại
				if current_hovered_module:
					current_hovered_module = null
		
# Hàm handle việc di chuyển module sau khi tạo xong (gồm tự động tương tác với các bề mặt, điểm gắn)
func drag_inventory_item(mouse_raycast_data: Dictionary):
	# - mouse_raycast_data: dict chứa thông tin raycast bắn từ chuột
	
	if not current_selected_module:
		return
	
	# 1. Set kết quả raycast từ chuột
	var from = mouse_raycast_data.from
	var dir = mouse_raycast_data.dir
	var result = mouse_raycast_data.result
	
	# 1. Set các biến liên quan đến selected module
	var mesh_instance = current_selected_module_mesh	# mesh để lấy aabb
	var aabb = mesh_instance.get_aabb() if mesh_instance else AABB() # AABB là hình khối của module (bounding_box)
	
	# 4. Set các biến cho tính toán va chạm tiếp theo
	var is_snap = false		# Check xem có trúng vào điểm gắn nào không
	var distance_to_face: float		# Khoang cách xa nhất từ mặt va chạm đến mặt bên kia (để làm module nổi lên, default bị chìm ngay tâm)
	var epsilon = attach_epsilon		# Sai số để làm cho module không bị khít quá khi gắn trên bề mặt khác
	var attach_face_vector = current_selected_module.module_data.attach_face_vector		# Vector hướng mặt gắn của module, mỗi mặt là 1 vector chuẩn hóa khác nhau
	
	# 5. Xử lý va chạm
	# 5.1 Nếu có va chạm (Nếu có collision xảy ra (properties position sẽ có kết quả))
	if result.has("position"):
		# Lưu thông tin collistion
		var collider = result.collider	# Vật bị va chạm bởi raycast
		var collider_position = result.position		# Position nơi va chạm xảy ra
		var collider_normal = result.normal.normalized()	# Vector pháp tuyến nới va chạm xảy ra
		
		# Biến tạm để lưu kết quả tính toán cuối cùng
		var final_collider = collider
		var final_position = collider_position
		var final_normal = collider_normal
		var final_basis = collider.global_transform.basis
		var final_snap_point = collider
		
		# Tính chiều dài của module theo mặt cần gắn (ví dụ gắn -x thì thính từ -x đến x)
		# default collide at origin (1/2), so distant will be size to avoid immerse module to object
		distance_to_face = calculate_distant_to_face_module(attach_face_vector, aabb)
		
		# --------------------- SNAP POINT ----------------------------------
		# 5.1.1 Xử lý nếu bề mặt va chạm là 1 điểm gắn (snap point), điểm này sẽ có dạng Area3D
		# Cần gắn selected module vào điểm này và phải ứng với hướng của nó (khớp basis)
		if collider is Area3D and collider.name.begins_with("Snap_Point"):
			# Lấy node cha của snap point để tính các transform liên quan
			var snap_parent_node = collider.get_parent()	
			
			# Set snap flag and get basis + position from snap point
			is_snap = true	# flag đã tìm thấy điểm gắn
			current_snap_point = collider
			
			# Tính hướng gắn của snap point
			var snap_face_local_normal = get_snap_point_local_normal(collider) # Tính normal của bề mặt điểm gắn (vector3 1 tới -1 để module attach các mặt ngược nhau)
			var snap_basis = collider.global_transform.basis	# Lấy basis của điểm gắn (collider ở trường hợp này chính là điểm gắn)
			var snap_position = collider.global_transform.origin	# Tương tự set vị trí gắn qua global transform origin của collider
			
			# Tính hướng gắn theo local normal - thực chất là global normal của snap point
			var snap_face_global_normal = snap_basis * snap_face_local_normal
			
			# Set normal hướng gắn và vị trí gắn 
			final_collider = snap_parent_node
			final_normal = snap_face_global_normal.normalized()
			final_position = snap_position
			final_basis = snap_basis
			final_snap_point = collider
		
		# --------------------- NORMAL SURFACE ----------------------------------
		# 5.1.2 Xử lý va chạm nếu là bề mặt thông thường
		# Bề mặt thông thuongf chỉ cần gắn theo bề mặt hiện tại là được(đúng theo normal bề mặt)
		else:
			# Set snap sang false
			is_snap = false
			current_snap_point = null
			
			# Giữ nguyên vị trí raycast va chạm và pháp tuyến bề mặt
			final_collider = collider
			final_position = collider_position 
			final_normal = collider_normal 
			final_basis = Basis(current_selected_module_origin_basis)
			final_snap_point = null
		
		# So sánh với frame trước đó
		var is_same_surface = (
			final_collider.get_instance_id() == current_collision_info.get("collider_id") \
			and is_snap == current_collision_info.get("is_snap") \
			and final_snap_point == current_collision_info.get("snap_point") \
			and final_normal.is_equal_approx(current_collision_info.get("normal")) \
			and final_position.is_equal_approx(current_collision_info.get("position"))
		)
		
		if not is_same_surface:
			# 6. LƯU THÔNG TIN CHO FRAME SAU
			current_collision_info["collider"] = final_collider
			current_collision_info["collider_id"] = final_collider.get_instance_id()
			current_collision_info["position"] = final_position
			current_collision_info["normal"] = final_normal
			current_collision_info["is_snap"] = is_snap
			current_collision_info["snap_point"] = final_snap_point
				
			# 7. Tính toán Transform mục tiêu
			current_target_transform = align_by_normal(attach_face_vector, final_normal, final_basis)
			current_target_transform.origin = final_position + final_normal * distance_to_face - final_normal * epsilon
			
			# 8. Kiểm tra xem trạng thái module có bị chồng lấn không
			# Kiểm tra cấn vật lý
			var is_not_overlapping = check_module_overlap()
			
			# Kiểm tra bộ luật xây dựng (Súng có đè lên súng không?)
			var is_surface_legal = check_valid_attachment_surface(final_collider)
			
			# Phải thỏa mãn CẢ 2 điều kiện mới được place
			is_valid_module_placement = is_not_overlapping and is_surface_legal
		
	else:
		# --- KHÔNG VA CHẠM (RESET) ---
		# Chỉ reset nếu trạng thái trước đó đang có va chạm
		if not current_collision_info.is_empty():
			# Reset xoay về gốc
			current_selected_module.basis = current_selected_module_origin_basis 
			current_collision_info.clear()
			
		# Luôn cập nhật vị trí theo chuột (bay lơ lửng)
		var target_position = from + dir * drag_offset
		current_target_transform.origin = target_position
		current_target_transform.basis = current_selected_module_origin_basis 
	
	# 9. Đổi màu theo trạng thái hiện tại của module
	if not is_valid_module_placement:
		# NẾU BỊ CẤN -> TÔ MÀU ĐỎ ("blocked") BẤT CHẤP TRẠNG THÁI GÌ
		switch_module_material(current_selected_module_mesh, "blocked")
		if current_selected_module_ray_visual:
			current_selected_module_ray_visual.material_override.albedo_color = Color(1, 0, 0) # Tia đỏ
	else:
		# NẾU HỢP LỆ -> Lên màu theo trạng thái hít/va chạm
		if is_snap:
			switch_module_material(current_selected_module_mesh, "collide_with_snap_point")
			if current_selected_module_ray_visual:
				current_selected_module_ray_visual.material_override.albedo_color = Color(0, 1, 0)
		elif result.has("position"):
			switch_module_material(current_selected_module_mesh, "collide_with_common")
			if current_selected_module_ray_visual:
				current_selected_module_ray_visual.material_override.albedo_color = Color(0, 0.7, 1)
		else:
			switch_module_material(current_selected_module_mesh, "no_collide")
			if current_selected_module_ray_visual:
				current_selected_module_ray_visual.material_override.albedo_color = Color(1, 0, 0)
	
	# 9. --- ÁP DỤNG SLERP ĐỂ TẠO ANIMATION ---
	var current_transform = current_selected_module.global_transform
	var delta = get_process_delta_time() # Lấy delta time của _process hiện tại
	var speed = 12.0 # Tốc độ animation (càng nhỏ càng chậm)
	
	# Slerp góc xoay (Basis)
	var current_quat = current_transform.basis.get_rotation_quaternion()
	var target_quat = current_target_transform.basis.get_rotation_quaternion()
	var next_quat = current_quat.slerp(target_quat, speed * delta)
	
	# Lerp vị trí (Origin)
	var next_origin = current_transform.origin.lerp(current_target_transform.origin, speed * delta)
	
	# Áp dụng transform mới và selected module
	current_selected_module.global_transform = Transform3D(Basis(next_quat), next_origin)

# Hàm xử lý tạo module và state khi chọn từ inventory
func start_placement(index: int):
	current_selected_index = index
	
	if current_selected_module != null:
		cancel_inventory_item()
		
	create_selected_module()
	change_state(State.SELECT)

# Hàm handle việc gắn module hiện tại vào 1 module khác
func place_module():
	# 1. Khi thả chuột, đặt module vào scene (bỏ khóa, thêm vào danh sách)
	var current_selected_module_instance_id = current_selected_module.get_instance_id()
	var current_selected_module_data = {
			"module": current_selected_module,
			"module_type": current_selected_module.module_data.category,
			"module_id": current_selected_module.module_data.module_id,
			"instance_id": current_selected_module_instance_id,
			"mesh": current_selected_module_mesh,
			"raycast_node": current_selected_module_raycast,
			"is_snap": current_collision_info.get('is_snap'),
			"snap_point": current_collision_info.get('snap_point')
		}  
	# Thêm vào danh sách module đã đặt
	modules_placed[current_selected_module_instance_id] = current_selected_module_data
	# Thêm module vào list ship core nếu là dạng hull/structure chính
	if current_selected_module.module_data.category == Global_Enums.Category.STRUCTURAL:
		modules_core[current_selected_module_instance_id] = current_selected_module_data
	
	print(modules_core)
	print(modules_placed)
	
	# 2. Restore physics properties
	current_selected_module.collision_layer = LAYER_SHIP_MODULE  # Restore collision layer (adjust as needed)
	current_selected_module.collision_mask = LAYER_ENVIRONMENT + LAYER_SHIP_MODULE  # Restore collision mask
	
	# 3. Reset visual
	var raycast_node = current_selected_module_raycast
	var mesh_instance = current_selected_module_mesh
	# 3.1 Cho module trở lại màu sắc ban đầu
	if mesh_instance and mesh_instance.material_override:
		mesh_instance.material_override = null  # Reset to default material

	# 3.2 Xóa các thành phần ray visual
	var ray_visual = current_selected_module_ray_visual
	if ray_visual:
		ray_visual.queue_free()
	if raycast_node:
		raycast_node.queue_free()
		
	# 4. Gắn module hiện tại vào module khác
	attach_to_module(current_selected_module, current_collision_info.get('collider'))
	
	# 5. Nếu là snap point thì set snap point đã được dùng
	if current_snap_point: 
		current_snap_point.set_to_occupied()
	
	# 6. Ẩn các snap point
	get_tree().call_group("builder_snap_points", "hide_visual")
	
	# 6. Xóa module đang chọn hiện tại
	current_selected_module = null  # Xóa tham chiếu để có thể tạo mới
	current_selected_module_mesh = null
	current_selected_module_collision = null
	current_selected_module_origin_basis = Basis()
	current_selected_module_raycast = null
	current_selected_module_ray_visual = null
	is_valid_module_placement = false
	
	# Update ship stats UI
	update_ship_stats_ui()

# Hàm hủy bỏ module đang chọn hiện tại
func cancel_inventory_item():
	# 1. Xóa selected module khỏi scene hiện tại
	if current_selected_module:
		current_selected_module.queue_free()  # Xóa node (an toàn hơn remove_child)
		current_selected_module = null
	
	# 2. Ẩn các snap point
	get_tree().call_group("builder_snap_points", "hide_visual")

	print("Cancelled placement")

# Hàm handle việc chanfe state giữa các thao tác khi lắp ghép module
func change_state(new_state: State) -> void:
	# - new state: State cần đổi sang
	 
	# Chỉ đổi khi khác state hiện tại
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
	
	# Gán state hiện tại sang state mới
	current_state = new_state
	print("State changed to: ", current_state)

# Hàm hỗ trợ xoay mặt gắn của module sang trục thế giới (FORWARD) 
func align_face_to_direction(node3d: Node3D, local_face: Vector3, world_direction: Vector3):
	# - node3d: node3d của module cần xoay
	# - local_face: mặt cần xoay sang world vector (ví dụ mặt LEFT, cần xoay sang FORWARD)
	# - world_direction: hướng mà mặt gắn sẽ xoay tới (default vector3 FORWARD) 
	
	# Bước 1: Reset xoay để tính toán từ trạng thái gốc
	node3d.rotation = Vector3.ZERO
	
	# Bước 2: Xác định trục nào của module sẽ đóng vai trò là "mắt" để nhìn
	var axis = Vector3.FORWARD # Mặc định Godot nhìn bằng trục -Z
	
	if local_face.is_equal_approx(Vector3(1,0,0)): axis = Vector3.RIGHT
	elif local_face.is_equal_approx(Vector3(-1,0,0)): axis = Vector3.LEFT
	elif local_face.is_equal_approx(Vector3(0,1,0)): axis = Vector3.UP
	elif local_face.is_equal_approx(Vector3(0,-1,0)): axis = Vector3.DOWN
	elif local_face.is_equal_approx(Vector3(0,0,1)): axis = Vector3.BACK
	elif local_face.is_equal_approx(Vector3(0,0,-1)): axis = Vector3.FORWARD

	# Bước 3: Tính toán Quaternion xoay từ "trục mặt gắn" sang "hướng mục tiêu"
	# Đây là công thức toán học chuẩn để xoay vector A trùng vào vector B
	var rotation_quat = Quaternion(axis, world_direction.normalized())
	
	# Bước 4: Áp dụng xoay
	node3d.global_transform.basis = Basis(rotation_quat)

# Hàm xử lý tính toán vector xa nhất từ mặt gắn đến chiều đối diện
# Để phục vụ cho việc gắn nổi module, vì điểm gắn ban đầu sẽ là origin của module
func calculate_distant_to_face_module(attach_face_vector: Vector3, aabb: AABB) -> float:
	# - attach_face_vector: vector mặt gắn của module
	# - aabb: AABB của module cần gắn
	
	# normalize attach vector
	var dir = attach_face_vector.normalized()
	
	# Tìm điểm xa nhất trên AABB theo hướng vector đó
	# support_point là điểm trên AABB nằm xa nhất về hướng dir
	var farthest_point = aabb.get_support(dir)
	
	# Chiếu điểm đó lên vector hướng để lấy khoảng cách dọc trục
	# Vì pivot là (0,0,0) local, nên dot product chính là khoảng cách
	return abs(farthest_point.dot(dir))
	
# Hàm xử lý gắn 2 module với nhau
func attach_to_module(module: Node3D, target: Node3D):
	# - module: module cần gắn (module A)
	# - target: module được gắn (module B)
	
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
	# - node: node bắt đầu duyệt
	
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

# Hàm hỗ trợ chuyển đổi visual của module
func switch_module_material(mesh: MeshInstance3D, mode: String):
	# - mesh: mesh instance của module
	# - mode: mode cần chuyển qua, mỗi mode có visual riêng
	
	# Kiểm tra xem mode truyền vào có tồn tại không
	var material = module_materials.get(mode, null)
	if not material:
		print("Material mode not found:", mode)
		return
	
	# Tìm và gán vật liệu cho đối tượng được chọn
	if mesh:
		mesh.material_override = material

# Hàm xử lý việc align module theo normal bề mặt + snap_point
# Tính basis từ bề mặt, sau đó trả về dưới dạng transform
func align_by_normal(attach_face_vector: Vector3, surface_normal: Vector3, target_basis: Basis) -> Transform3D:
	# attach_face_local: vector mặt gằn của module
	# surface_normal: vector normal của bề mặt cần gắn - có thể là snap point normal
	# target_basis: basis của vật cần gắn, default và basis của chính module, còn không thì là của snap point
	
	# Gán biến basis để bắt đầu tính toán
	var new_basis = target_basis
	
	# BƯỚC 1: Đưa mặt gắn cắm vào bề mặt tường
	var current_face_dir = (new_basis * attach_face_vector).normalized()
	var target_face_dir = -surface_normal.normalized()
	var dot_prod = current_face_dir.dot(target_face_dir)
	
	if dot_prod < -0.999:
		# Lật 180 độ (Lấy trục Y làm chuẩn để giữ nguyên chiều trên/dưới)
		var axis = target_basis.y.normalized()
		if abs(current_face_dir.dot(axis)) > 0.99:
			axis = target_basis.z.normalized()
		new_basis = Basis(Quaternion(axis, PI)) * new_basis
	elif dot_prod < 0.999:
		# Xoay góc ngắn nhất
		var axis = current_face_dir.cross(target_face_dir).normalized()
		var angle = current_face_dir.angle_to(target_face_dir)
		new_basis = Basis(Quaternion(axis, angle)) * new_basis
		
	# BƯỚC 2: SECONDARY ALIGNMENT (Khóa trục Y chống lệch xoay)
	# Trừ phi mặt gắn đang là mặt Trên/Dưới, nếu không ta phải ép trục Y của module khớp với target_basis.y
	if not attach_face_vector.is_equal_approx(Vector3(0, 1, 0)) and not attach_face_vector.is_equal_approx(Vector3(0, -1, 0)):
		
		var current_up = new_basis.y.normalized() # Hướng Lên hiện tại của module
		var target_up = target_basis.y.normalized() # Hướng Lên mong muốn (của Snap Point)
		
		# Chiếu 2 vector Lên này xuống mặt phẳng tường (để loại bỏ độ nghiêng của tường)
		var proj_current_up = (current_up - target_face_dir * current_up.dot(target_face_dir)).normalized()
		var proj_target_up = (target_up - target_face_dir * target_up.dot(target_face_dir)).normalized()
		
		# Tính góc lệch giữa 2 hướng Lên
		var up_dot = proj_current_up.dot(proj_target_up)
		
		# Nếu chưa thẳng hàng, vặn module quanh trục target_face_dir (như vặn đinh ốc)
		if up_dot < 0.999:
			var up_axis = proj_current_up.cross(proj_target_up).normalized()
			var up_angle = proj_current_up.angle_to(proj_target_up)
			
			# Xác định vặn theo chiều kim đồng hồ hay ngược lại
			if up_axis.dot(target_face_dir) < 0:
				up_angle = -up_angle
				
			new_basis = Basis(Quaternion(target_face_dir, up_angle)) * new_basis

	return new_basis.orthonormalized()

# Hàm xử lý việc tạo material cho module
func create_module_material(albedo_color: Color) -> StandardMaterial3D:
	# - albedo_color: mã màu cần tạo cho module
	
	var material = StandardMaterial3D.new()		# Tạo mới 1 instant của material
	material.albedo_color = albedo_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

# Hàm xử lý tính toán snap point đang ở mặt nào
func get_snap_point_local_normal(snap_point: Node3D) -> Vector3:
	# - snap_point: Điểm gắn cần tính
	
	# Nếu đã cache trong meta thì lấy ra luôn
	if snap_point.has_meta("local_normal"):
		return snap_point.get_meta("local_normal")
	
	# Tính các giá trị khỏi đầu
	var local_pos = snap_point.position		# Vị trí local của snap_point so với tâm của parent
	var parent_node = snap_point.get_parent()	# Lấy parent của snap point
	var mesh_instance = parent_node.find_child("*", true, false) as MeshInstance3D	# Lấy mesh của parent
	var size = mesh_instance.get_aabb().size if mesh_instance else Vector3.ONE	# Tính size của aabb mesh

	# Tìm trục chiếm ưu thế
	# Trục nào chiếm nhiều nhất thì snap point đang ở mặt đó
	var nx = local_pos.x / size.x
	var ny = local_pos.y / size.y
	var nz = local_pos.z / size.z
	
	# Tìm local normal, dùng sign() để tự động trả về 1 hoặc -1
	var local_normal = Vector3.ZERO	# gán default
	if abs(nx) > abs(ny) and abs(nx) > abs(nz):
		local_normal = Vector3(sign(nx), 0, 0)
	elif abs(ny) > abs(nx) and abs(ny) > abs(nz):
		local_normal = Vector3(0, sign(ny), 0)
	else:
		local_normal = Vector3(0, 0, sign(nz))
	
	# Cache lại để dùng lần sau
	snap_point.set_meta("local_normal", local_normal)
	return local_normal
