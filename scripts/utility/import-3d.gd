@tool
extends EditorScript

func _run():
	var imported_scene_path = "res://assets/blender/ship_part.glb"  # Thay bằng path scene của bạn
	var output_dir = "res://modules/module_scenes/"  # Thư mục lưu scene mới
	
	var scene = load(imported_scene_path).instantiate()
	
	for child in scene.get_children():
		if child is MeshInstance3D:
			print("Processing object: ", child.name)
			var new_root = RigidBody3D.new()
			new_root.name = child.name + "_Root"
			
			var script_ref = load("res://scripts/module/module_component.gd") # Đường dẫn đến file script
			new_root.set_script(script_ref)
			
			var mesh_copy = child.duplicate()
			mesh_copy.transform = Transform3D.IDENTITY  # Reset position, rotation, scale
			
			new_root.add_child(mesh_copy)
			mesh_copy.owner = new_root
			
			# Duyệt sâu để tìm StaticBody3D và CollisionShape3D
			var col_shape = CollisionShape3D.new()
			var has_col_static = false
			for col_child in child.get_children():
				print("Child: ", col_child.name, " - Type: ", col_child.get_class())
				for grand_child in col_child.get_children():
					print("  Grandchild: ", grand_child.name, " - Type: ", grand_child.get_class())
					if grand_child is StaticBody3D and grand_child.get_child_count() > 0:
						var static_body_col_shape = grand_child.get_child(0) as CollisionShape3D
						if static_body_col_shape:
							# Sao chép shape và chuyển đổi sang convex nếu cần
							if static_body_col_shape.shape is ConcavePolygonShape3D:
								col_shape.shape = mesh_copy.mesh.create_convex_shape()  # Tạo convex từ mesh gốc
								print("Converted concave to convex shape for: ", child.name)
							else:
								col_shape.shape = static_body_col_shape.shape.duplicate()
								print("Copied shape (non-concave) for: ", child.name)
							col_shape.transform = static_body_col_shape.transform
							has_col_static = true
							print("Found and copied collision from StaticBody3D for: ", child.name)
							break
				if has_col_static:
					break
			
			# Nếu không có StaticBody3D, tạo convex shape từ mesh gốc
			if not has_col_static:
				col_shape.shape = mesh_copy.mesh.create_convex_shape()
				print("Created convex shape from mesh: ", child.name)
			
			new_root.add_child(col_shape)
			col_shape.owner = new_root
			col_shape.transform = Transform3D.IDENTITY  # Reset transform về (0,0,0)
			
			# Pack và lưu
			var new_scene = PackedScene.new()
			new_scene.pack(new_root)
			var save_path = output_dir + child.name + ".tscn"
			var error = ResourceSaver.save(new_scene, save_path)
			if error == OK:
				print("Saved scene: " + save_path)
			else:
				print("Error saving scene: " + str(error))
	
	scene.queue_free()
