extends Resource

class_name Module

@export var module_id: = "" 
@export var name: = ""
@export var mass: = 10
@export var scene_path: = ""
@export var texture_2d: Texture2D
@export var attach_face_vector: Vector3 = Vector3(1, 0, 0)
@export var category: Global_Enums.Category
@export var module_type: Global_Enums.ModuleType
@export var snap_points: Array[SnapPoint] = []

func create_node_3d_scene_instance() -> Node3D:
	# 1. Load base module scene
	var instance = load(scene_path).instantiate()
	
	# 2. Set resource data to base module
	instance.set("module_data", self)
	
	return instance
