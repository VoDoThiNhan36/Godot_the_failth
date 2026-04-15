extends Control

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_module_inventory"):
		if self.visible:
			close()
		else:
			open()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func close():
	self.visible = false

func open():
	self.visible = true
