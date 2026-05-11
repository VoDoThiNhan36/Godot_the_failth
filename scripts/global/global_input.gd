extends Node

enum GameState {MENU, PLAY}
enum InputState {NONE, SEQUENCE_MOVE, SHIFT_MOVE}
var current_game_state: GameState
var current_input_state: InputState

# Input exclude
var camera_exclude_input_list = ["sequence_move", "direction_shift_move"]

func _input(event: InputEvent) -> void:
	## ESCAPE
	# for menu
	if event.is_action_pressed("menu"):
		if current_game_state == GameState.MENU:
			current_game_state = GameState.PLAY
			get_viewport().set_input_as_handled()
			return
	
	# Toggle mouse capture / release
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		
	# Camera input
	if _input_active_camera(event):
		get_viewport().set_input_as_handled()
		return
		
func _unhandled_input(event: InputEvent) -> void:
	## ESCAPE
	# for menu
	if event.is_action_pressed("menu"):
		if current_game_state != GameState.MENU:
			current_game_state = GameState.MENU
		get_viewport().set_input_as_handled()
	
func _input_active_camera(event: InputEvent) -> bool:
	if Global_Camera.current_rig == null:
		return false
	
	Global_Camera._input(event)

	return false
	
# Hàm để đổi phím (Ví dụ đơn giản)
func remap_action(action_name: String, new_event: InputEvent):
	# Xóa phím cũ
	InputMap.action_erase_events(action_name)
	# Thêm phím mới
	InputMap.action_add_event(action_name, new_event)
