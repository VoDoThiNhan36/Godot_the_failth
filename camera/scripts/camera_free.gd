extends Camera3D

@export var camera_lerp_speed := 10.0
#@onready var spring_position: Node3D = $"../SpringArm3D/Spring_Position"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#var current_spring_position := spring_position.position
	#current_spring_position.z = clamp(current_spring_position.z, 2.0, 20.0)
	#position = lerp(position, current_spring_position, delta * camera_lerp_speed)
	pass
