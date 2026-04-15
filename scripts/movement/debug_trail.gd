extends MeshInstance3D

@export var max_points := 200 # Lưu tối đa 200 điểm (độ dài của đuôi)
@export var min_distance := 0.2 # Tàu đi được 0.2m thì chấm 1 điểm

var path_points: Array[Vector3] = []

func _ready() -> void:
	# CỰC KỲ QUAN TRỌNG: Lệnh này giúp đường vẽ tách rời khỏi tàu.
	# Nếu tàu xoay, đường vẽ KHÔNG BỊ XOAY THEO, nó sẽ ghim chặt vào không gian thế giới.
	top_level = true 
	
	# Khởi tạo cọ vẽ
	mesh = ImmediateMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW # Màu vàng chóe
	mat.flags_unshaded = true # Sáng bất chấp bóng tối
	mat.no_depth_test = true # Nhìn xuyên tường/xuyên qua thân tàu
	material_override = mat

func _physics_process(_delta: float) -> void:
	# Lấy tọa độ CHÍNH XÁC của cái CharacterBody3D (Node cha)
	var current_pos = get_parent().global_position
	
	# Nếu danh sách rỗng, hoặc tàu đã đi đủ xa khỏi điểm cuối cùng -> Chấm thêm điểm mới
	if path_points.is_empty() or path_points.back().distance_to(current_pos) > min_distance:
		path_points.append(current_pos)
		
		# Xóa điểm cũ nhất nếu đuôi quá dài
		if path_points.size() > max_points:
			path_points.pop_front()
			
		_update_trail_mesh()

func _update_trail_mesh() -> void:
	var m = mesh as ImmediateMesh
	m.clear_surfaces()
	
	# Cần ít nhất 2 điểm mới vẽ được 1 đoạn thẳng
	if path_points.size() < 2: return 
	
	m.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in path_points:
		m.surface_add_vertex(p)
	m.surface_end()
