extends Area3D

# Biến này sẽ được parse vào từ Resource lúc khởi tạo
var allowed_types: Array[Global_Enums.ModuleType] = []
# Biến check xem snap point đã được dùng chưa
var is_occupied: bool = false

# Biến chứa mesh instance và collision shape của snap point, để cho việc hiển thị
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

# Hàm kiểm tra module attach có khớp không
func can_accept_module(incoming_type: Global_Enums.ModuleType) -> bool:
	if is_occupied: return false	# Đã được dùng
	if allowed_types.is_empty():
		return true # Không cấm ai cả
	return incoming_type in allowed_types

# Hảm xử lý hiển thị khi module hiện tại phù hợp gắn vào
func check_and_show_visual(holding_type: Global_Enums.ModuleType):
	if can_accept_module(holding_type):
		mesh_instance_3d.visible = true
	else:
		hide_visual()
		
# Hàm ẩn hiển thị
func hide_visual():
	mesh_instance_3d.visible = false

# Hàm set snap point sang trạng thái đã được sử dụng
func set_to_occupied():
	is_occupied = true	# Đổi sang đã được dùng
	collision_shape_3d.set_deferred("disabled", true)	# Tắt va chạm, set_deferred để an toàn khi đổi property
	hide_visual() # Ẩn đi

# Hàm set snap point trở lại chưa sử dụng
func set_to_available():
	is_occupied = false	# Đổi sang đã được dùng
	collision_shape_3d.set_deferred("disabled", false)	# Tắt va chạm, set_deferred để an toàn khi đổi property
	
