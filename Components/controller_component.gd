extends Node
class_name ControllerComponent

signal pan_requested(screen_delta: Vector2)
signal zoom_requested(steps: float, screen_position: Vector2)
signal drag_state_changed(dragging: bool)
signal movement_requested(direction: Vector2)
signal character_follow_requested(enabled: bool)

@export var right_mouse_pans := true
@export var mouse_wheel_zooms := true

var _dragging := false
var _mouse_position_before_capture := Vector2.ZERO
var _mouse_mode_before_capture := Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	movement_requested.emit(Input.get_vector(
		&"ui_left",
		&"ui_right",
		&"ui_up",
		&"ui_down"
	))


func _exit_tree() -> void:
	_end_pan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_pan()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		character_follow_requested.emit(false)
		pan_requested.emit(event.relative)
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and _is_directional_event(event)
	):
		character_follow_requested.emit(true)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if right_mouse_pans and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_begin_pan()
		else:
			_end_pan()
		get_viewport().set_input_as_handled()
		return

	if not mouse_wheel_zooms or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_requested.emit(event.factor, event.position)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_requested.emit(-event.factor, event.position)
		get_viewport().set_input_as_handled()


func _begin_pan() -> void:
	if _dragging:
		return
	_dragging = true
	character_follow_requested.emit(false)
	_mouse_position_before_capture = get_viewport().get_mouse_position()
	_mouse_mode_before_capture = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	drag_state_changed.emit(true)


func _end_pan() -> void:
	if not _dragging:
		return
	_dragging = false
	Input.mouse_mode = _mouse_mode_before_capture
	if _mouse_mode_before_capture != Input.MOUSE_MODE_CAPTURED:
		Input.warp_mouse(_mouse_position_before_capture)
	drag_state_changed.emit(false)


func _is_directional_event(event: InputEvent) -> bool:
	return (
		event.is_action(&"ui_left")
		or event.is_action(&"ui_right")
		or event.is_action(&"ui_up")
		or event.is_action(&"ui_down")
	)
