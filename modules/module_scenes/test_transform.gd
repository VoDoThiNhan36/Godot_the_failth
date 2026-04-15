extends RigidBody3D

@onready var prow_01_root: RigidBody3D = $"."
#var angular_speed: float = deg_to_rad(90)  # 90 độ/giây -> rad/s
#var radius: float = 5.0  # Bán kính cố định
#var center: Vector3 = Vector3(0, 0, 0)  # Tâm (origin)
#var angle: float = 0.0  # Góc ban đầu
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.transform = self.transform.rotated(Vector3.UP, deg_to_rad(90))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	rotate_module(prow_01_root, 90, delta)

func rotate_module(module: RigidBody3D, deg: int, delta: float):
	#module.transform = module.transform.rotated(Vector3.UP, deg_to_rad(deg) * delta)
	module.position += Vector3.FORWARD * delta
	
	
	#angle += angular_speed * delta  # Tăng góc
	#var x = center.x + radius * cos(angle)
	#var z = center.z + radius * sin(angle)  # Hoặc -sin nếu muốn hướng ngược
	#global_position = Vector3(x, center.y, z)
	
