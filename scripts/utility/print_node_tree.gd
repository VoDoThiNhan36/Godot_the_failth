# PrintNodeTree.gd
@tool
extends EditorScript

@export_file("*.tscn") var scene_path: String = "res://scenes/ship_player.tscn"

func _run() -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		printerr("❌ Vui lòng chọn đúng đường dẫn .tscn trong Inspector!")
		return
	
	print_scene_tree(scene_path)


func print_scene_tree(path: String) -> void:
	var packed_scene: PackedScene = ResourceLoader.load(path)
	if not packed_scene:
		printerr("❌ Không load được scene: ", path)
		return
	
	var root: Node = packed_scene.instantiate()
	if not root:
		printerr("❌ Không instantiate được scene!")
		return
	
	print("\n" + "=".repeat(80))
	print("🌳 CÂU TRÚC CÂY NODE - Godot 4.5")
	print("📁 Scene: ", path)
	print("=".repeat(80))
	
	_print_recursive(root, "", true)
	
	print("=".repeat(80) + "\n")
	
	root.queue_free()


func _print_recursive(node: Node, prefix: String, is_last: bool) -> void:
	if node == null:
		return
	
	var connector = "└── " if is_last else "├── "
	var line = prefix + connector + node.name
	
	var type_name = node.get_class()
	if type_name != "Node":
		line += "  (%s)" % type_name
	
	print(line)
	
	var children = node.get_children()
	var count = children.size()
	
	for i in range(count):
		var new_prefix = prefix + ("    " if is_last else "│   ")
		var is_child_last = (i == count - 1)
		_print_recursive(children[i], new_prefix, is_child_last)
