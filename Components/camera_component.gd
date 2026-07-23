extends Node
class_name CameraComponent

@export_group("Pan")
@export var pan_speed := 1.0

@export_group("Zoom")
@export_range(0.01, 100.0, 0.01, "or_greater") var minimum_zoom := 0.2
@export_range(0.01, 100.0, 0.01, "or_greater") var maximum_zoom := 3.0
@export_range(1.01, 4.0, 0.01) var zoom_step := 1.15

@export_group("Character Follow")
@export var character_focus_target: Node2D
@export_range(0.0, 5.0, 0.05, "or_greater") var focus_transition_duration := 0.5

@export_group("Minimap")
@export var minimap_enabled := true
@export var minimap_center := Vector2.ZERO
@export_range(0.001, 10.0, 0.001, "or_greater") var minimap_zoom := 0.045

@onready var camera: Camera2D = $Camera2D
@onready var minimap_layer: CanvasLayer = $MinimapLayer
@onready var minimap_panel: PanelContainer = $MinimapLayer/MinimapPanel
@onready var minimap_viewport: SubViewport = $MinimapLayer/MinimapPanel/SubViewportContainer/SubViewport
@onready var overview_camera: Camera2D = $MinimapLayer/MinimapPanel/SubViewportContainer/SubViewport/OverviewCamera
@onready var camera_view_indicator: Panel = $MinimapLayer/CameraViewIndicator

var _following_character := false
var _focus_tween: Tween


func _ready() -> void:
	camera.enabled = true
	_setup_minimap()


func _process(_delta: float) -> void:
	if minimap_enabled:
		_update_camera_view_indicator()


func _setup_minimap() -> void:
	minimap_layer.visible = minimap_enabled
	if not minimap_enabled:
		return
	# A SubViewport normally owns a separate 2D world. Sharing the main world
	# lets its overview camera render the same skill tree a second time.
	minimap_viewport.world_2d = get_viewport().world_2d
	overview_camera.position = minimap_center
	overview_camera.zoom = Vector2.ONE * minimap_zoom
	overview_camera.enabled = true
	_update_camera_view_indicator()


func set_minimap_visible(value: bool) -> void:
	if not is_node_ready():
		return
	minimap_layer.visible = minimap_enabled and value
	if minimap_layer.visible:
		_update_camera_view_indicator()


func _update_camera_view_indicator() -> void:
	if not minimap_enabled or not is_instance_valid(camera_view_indicator):
		return

	var main_view_size := camera.get_viewport_rect().size
	var safe_zoom := Vector2(
		maxf(camera.zoom.x, 0.0001),
		maxf(camera.zoom.y, 0.0001)
	)
	var visible_world_size := main_view_size / safe_zoom
	var visible_world_rect := Rect2(
		camera.get_screen_center_position() - visible_world_size * 0.5,
		visible_world_size
	)

	var minimap_size := Vector2(minimap_viewport.size)
	var overview_center := overview_camera.get_screen_center_position()
	var minimap_top_left_world := overview_center - minimap_size * 0.5 / overview_camera.zoom
	var indicator_rect := Rect2(
		(visible_world_rect.position - minimap_top_left_world) * overview_camera.zoom,
		visible_world_rect.size * overview_camera.zoom
	)
	var clipped_rect := indicator_rect.intersection(Rect2(Vector2.ZERO, minimap_size))
	camera_view_indicator.visible = clipped_rect.has_area()
	if not clipped_rect.has_area():
		return
	camera_view_indicator.position = minimap_panel.position + clipped_rect.position
	camera_view_indicator.size = clipped_rect.size


func _on_pan_requested(screen_delta: Vector2) -> void:
	# Moving the pointer right should pull the world right, so the camera moves
	# left. Dividing by zoom keeps the drag locked to screen pixels.
	var safe_zoom := Vector2(
		maxf(camera.zoom.x, 0.0001),
		maxf(camera.zoom.y, 0.0001)
	)
	camera.global_position -= screen_delta / safe_zoom * pan_speed


func _on_character_follow_requested(enabled: bool) -> void:
	_following_character = enabled
	_stop_focus_tween()
	if not enabled:
		if camera.get_parent() != self:
			camera.reparent(self, true)
		return
	if not is_instance_valid(character_focus_target):
		return

	if camera.get_parent() != character_focus_target:
		camera.reparent(character_focus_target, true)
	if is_zero_approx(focus_transition_duration):
		camera.position = Vector2.ZERO
		return

	_focus_tween = create_tween()
	_focus_tween.set_trans(Tween.TRANS_QUAD)
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(
		camera,
		^"position",
		Vector2.ZERO,
		focus_transition_duration
	)
	_focus_tween.finished.connect(_on_focus_tween_finished)


func _stop_focus_tween() -> void:
	if is_instance_valid(_focus_tween):
		_focus_tween.kill()
	_focus_tween = null


func _on_focus_tween_finished() -> void:
	_focus_tween = null


func _on_zoom_requested(steps: float, screen_position: Vector2) -> void:
	if is_zero_approx(steps):
		return

	var viewport_center := camera.get_viewport_rect().size * 0.5
	var cursor_offset := screen_position - viewport_center
	var old_zoom := camera.zoom.x
	var multiplier := pow(zoom_step, steps)
	var new_zoom := clampf(old_zoom * multiplier, minimum_zoom, maximum_zoom)
	if is_equal_approx(old_zoom, new_zoom):
		return

	if _following_character:
		camera.zoom = Vector2.ONE * new_zoom
		camera.position = Vector2.ZERO
		return

	# Preserve the world point under the cursor while changing magnification.
	var world_under_cursor := camera.global_position + cursor_offset / old_zoom
	camera.zoom = Vector2.ONE * new_zoom
	camera.global_position = world_under_cursor - cursor_offset / new_zoom
