extends CameraRigBase

@export_group("Character Camera Settings")
@export var min_zoom := 6.0
@export var max_zoom := 20.0
@export var zoom_step := 1.0
@export var min_vertical_angle := -PI/4
@export var max_vertical_angle := PI/4
@export var max_horizontal_angle := PI/2   # Giới hạn xoay trái/phải (rad), 0 = không giới hạn

func _ready() -> void:
	super._ready()
	deactivate()

func _process(delta: float) -> void:
	super._process(delta)
	
