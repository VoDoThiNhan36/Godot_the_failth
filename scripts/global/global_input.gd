extends Node

enum GameState {MENU, PLAY}
enum InputState {NONE, SEQUENCE_MOVE, SHIFT_MOVE}
var current_game_state: GameState
var current_input_state: InputState

# Input exclude
var camera_exclude_input_list = ["sequence_move", "direction_shift_move"]
var camera_exclude_state_list = [InputState.SEQUENCE_MOVE, InputState.SHIFT_MOVE]

func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	## ESCAPE
	# for menu
	if event.is_action_pressed("menu"):
		if current_game_state == GameState.MENU:
			current_game_state = GameState.PLAY
			return true
	
	# Toggle mouse capture / release
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return true
		
	# Camera input
	if _input_camera(event):
		return true
	
	# Return false nếu không có input nào được xử lý, để các node khác có thể nhận input này
	return false
		
func _unhandled_input(event: InputEvent) -> void:
	## ESCAPE
	# for menu
	if event.is_action_pressed("menu"):
		if current_game_state != GameState.MENU:
			current_game_state = GameState.MENU
		get_viewport().set_input_as_handled()
		return

func _input_camera(event: InputEvent) -> bool:
	if Global_Camera.handle_input(event):
		return true
	return false
	
# Hàm để đổi phím (Ví dụ đơn giản)
func remap_action(action_name: String, new_event: InputEvent):
	# Xóa phím cũ
	InputMap.action_erase_events(action_name)
	# Thêm phím mới
	InputMap.action_add_event(action_name, new_event)

# Hàm để set Input state từ các node khác
func change_input_state(new_state: InputState) -> void:
	if current_input_state == new_state: return

	current_input_state = new_state
