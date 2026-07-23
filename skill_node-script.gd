@tool
extends Control
class_name skill_node

signal skill_selected(skill: SkillData)

const DEFAULT_MARKER_FLOW_ANGLE := 90.0
const DISABLED_SKILL_STATUS := 3
const MARKER_CENTER := Vector2(120.0, 120.0)
const BASE_POSITION_META := &"skill_node_base_marker_position_v2"

@export var data: SkillData
@export var progress: SkillProgress:
	set(value):
		if progress != null and progress.changed.is_connected(refresh):
			progress.changed.disconnect(refresh)
		progress = value
		if progress != null and not progress.changed.is_connected(refresh):
			progress.changed.connect(refresh)
		if is_node_ready():
			refresh()
var _marker_flow_angle_degrees := DEFAULT_MARKER_FLOW_ANGLE

@onready var billboard_visuals: Control = $BillboardVisuals
@onready var skill_name_label 		:Label= $"BillboardVisuals/VBoxContainer/Skill Name Label"
@onready var skill_icon				:TextureRect= $BillboardVisuals/VBoxContainer/TextureRect
@onready var skill_unlocked_label	:Label= $"BillboardVisuals/VBoxContainer/Unlock Status Label"
@onready var skill_unlocked_icon	:TextureButton= $"BillboardVisuals/Unlocked Button"
@onready var main_button			:Button= $BillboardVisuals/Button
@onready var disabled_skill_visual	:Control= $BillboardVisuals/DisabledSkillVisual

@onready var skill_background_colorRect: ColorRect = $BillboardVisuals/ColorRect

var unlock_status_colors: Array[Color] = [Color("262626"), Color("156a8c")]


func _ready() -> void:
	set_process(true)
	if not main_button.pressed.is_connected(_on_skill_selected):
		main_button.pressed.connect(_on_skill_selected)
	_update_billboard()
	_update_marker_rotation()
	refresh()


func _process(_delta: float) -> void:
	_update_billboard()
	_update_marker_rotation()


func _update_billboard() -> void:
	if not is_node_ready() or billboard_visuals == null:
		return
	# Counteract every rotation inherited by the skill root. Marker2D children
	# remain outside this container and therefore keep the branch rotation.
	billboard_visuals.rotation = -get_global_transform_with_canvas().get_rotation()


func set_marker_flow_angle(angle_degrees: float) -> void:
	_marker_flow_angle_degrees = angle_degrees
	_update_marker_rotation()


func get_connection_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for child in find_children("*", "Marker2D", true, false):
		var marker := child as Marker2D
		if marker != null:
			markers.append(marker)
	return markers


func _update_marker_rotation() -> void:
	if not is_inside_tree():
		return
	var rotation_delta := deg_to_rad(_marker_flow_angle_degrees - DEFAULT_MARKER_FLOW_ANGLE)
	var markers := get_connection_markers()
	for marker in markers:
		if not marker.has_meta(BASE_POSITION_META):
			marker.set_meta(BASE_POSITION_META, marker.position)
		var base_position: Vector2 = marker.get_meta(BASE_POSITION_META, marker.position)
		var bounded_position := _marker_position_on_billboard(marker, base_position, rotation_delta)
		if not marker.position.is_equal_approx(bounded_position):
			marker.position = bounded_position
		if not is_equal_approx(marker.rotation, rotation_delta):
			marker.rotation = rotation_delta


func _marker_position_on_billboard(
	marker: Marker2D,
	base_position: Vector2,
	rotation_delta: float
) -> Vector2:
	if billboard_visuals == null:
		return MARKER_CENTER + (base_position - MARKER_CENTER).rotated(rotation_delta)

	var direction_in_node := (base_position - MARKER_CENTER).rotated(rotation_delta)
	if direction_in_node.is_zero_approx():
		direction_in_node = Vector2.UP.rotated(rotation_delta)

	var node_canvas_transform := get_global_transform_with_canvas()
	var direction_in_canvas := (
		node_canvas_transform * direction_in_node
		- node_canvas_transform.origin
	)
	var direction := direction_in_canvas.normalized()
	var visual_canvas_transform := billboard_visuals.get_global_transform_with_canvas()
	var visual_corners := PackedVector2Array([
		visual_canvas_transform * Vector2.ZERO,
		visual_canvas_transform * Vector2(billboard_visuals.size.x, 0.0),
		visual_canvas_transform * billboard_visuals.size,
		visual_canvas_transform * Vector2(0.0, billboard_visuals.size.y),
	])
	var minimum := visual_corners[0]
	var maximum := visual_corners[0]
	for corner in visual_corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	var box_center := (minimum + maximum) * 0.5
	var half_size := (maximum - minimum) * 0.5
	var horizontal_scale := (
		half_size.x / absf(direction.x)
		if not is_zero_approx(direction.x)
		else INF
	)
	var vertical_scale := (
		half_size.y / absf(direction.y)
		if not is_zero_approx(direction.y)
		else INF
	)
	var edge_point_in_canvas := box_center + direction * minf(horizontal_scale, vertical_scale)
	var marker_parent := marker.get_parent() as CanvasItem
	if marker_parent == null:
		return edge_point_in_canvas
	return marker_parent.get_global_transform_with_canvas().affine_inverse() * edge_point_in_canvas


func refresh() -> void:
	if data == null:
		push_warning("Skill node has no SkillData resource assigned.")
		return
	set_skill_name()
	set_disabled_cross()
	set_unlock_status_label()
	set_unlock_status_color()
	set_unlock_icon()


func get_unlock_status() -> SkillProgress.Status:
	if progress == null or data == null:
		return SkillProgress.Status.LOCKED
	# Resource instances can temporarily be editor placeholders while a tool
	# scene is rebuilding. Exported properties remain safe to read, whereas
	# calling a method on a placeholder does not.
	return progress.statuses.get(data.id, SkillProgress.Status.LOCKED)


func set_disabled_cross():
	disabled_skill_visual.visible = (
		data.disabled
		or get_unlock_status() == DISABLED_SKILL_STATUS
	)

func set_skill_name():
	skill_name_label.text = data.display_name
	
func set_unlock_status_label():
	var _unlock_status_texts: Array[String] = ["Locked", "Unlocked", "Skilled", "Disabled"]
	skill_unlocked_label.text = _unlock_status_texts[get_unlock_status()]

func set_unlock_status_color():
	var status := get_unlock_status()
	if status == SkillProgress.Status.UNLOCKED or status == SkillProgress.Status.SKILLED:
		skill_background_colorRect.color = unlock_status_colors[1]
	else:
		skill_background_colorRect.color = unlock_status_colors[0]
	
func set_unlock_icon():
	var status := get_unlock_status()
	if status == SkillProgress.Status.SKILLED:
		change_skill_unlocked_icon()
	else:
		skill_unlocked_icon.set_texture_normal(null)

func change_skill_unlocked_icon():
	if get_unlock_status() == SkillProgress.Status.SKILLED:
		skill_unlocked_icon.set_texture_normal(RandomImageProvider.get_random_image())
	else:
		skill_unlocked_icon.set_texture_normal(null)


func _on_skill_selected() -> void:
	if data != null:
		skill_selected.emit(data)
