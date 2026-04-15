extends RigidBody3D

class_name ModuleComponent

# Biến chứa dữ liệu từ module resource
var module_data: Module

# Load template của Snap Point
var snap_template = preload("res://modules/module_scenes/snap_point.tscn")

func _ready() -> void:
	# Kiểm tra an toàn
	if not module_data:
		return
	
	# Khởi tạo các điểm gắn
	spawn_snap_points()

# Hàm tự động sinh ra các Area3D Snap Point dựa trên dữ liệu từ Resource
func spawn_snap_points():
	for i in range(module_data.snap_points.size()):
		var snap_data = module_data.snap_points[i]
		var snap_node = snap_template.instantiate()
		add_child(snap_node)
		
		# Đặt tên để Raycast của hàm drag_inventory_item nhận diện được
		snap_node.name = "Snap_Point_" + str(i)
		
		# Set thông số từ Resource (sp_data) sang Node (sp_node)
		snap_node.transform.origin = snap_data.position
		
		# Xoay mặt Snap Point theo hướng normal (Quan trọng để Slerp nó ���p đúng mặt)
		#var look_target = sp_node.position + sp_data.normal
		#if look_target != sp_node.position: # Chống lỗi bị trùng vector
			#sp_node.look_at(look_target)
			
		snap_node.allowed_types = snap_data.allowed_types
		snap_node.add_to_group("builder_snap_points")

# Hàm hỗ trợ cho builder
func get_module_type() -> Global_Enums.ModuleType:
	if module_data:
		return module_data.module_type
	return Global_Enums.ModuleType.HULL # Mặc định
