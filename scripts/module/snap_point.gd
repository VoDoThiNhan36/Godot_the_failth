extends Resource

class_name SnapPoint

@export var position: Vector3 = Vector3.ZERO
@export var normal: Vector3 = Vector3(0, 0, 1) # Hướng mặt gắn
@export var allowed_types: Array[Global_Enums.ModuleType] = []
