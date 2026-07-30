@tool
extends Node2D
class_name SkillTree2DComponent

signal texture_rebuilt(texture: ImageTexture, world_bounds: Rect2)

const MULTIPLE_IMAGES_SKILL_ID := &"multipleimages"
const VELOCITY_AND_ACCELERATION_SKILL_ID := &"velocityandacceleration"
const STORY_IN_ORDER_SKILL_ID := &"storyinorder"

const INSTRUCTION_PANEL_MINIMUM_WIDTH := 360.0
const INSTRUCTION_PANEL_DASH_WIDTH := 730.0
const INSTRUCTION_PANEL_HORIZONTAL_PADDING := 28.0
const INSTRUCTION_PANEL_VERTICAL_PADDING := 24.0
const INSTRUCTION_TITLE_HEIGHT := 31.0
const INSTRUCTION_ROW_HEIGHT := 25.0
const DASH_TELEMETRY_POSITION := Vector2(300.0, 78.0)
const DASH_TELEMETRY_SIZE := Vector2(414.0, 48.0)
const TELEMETRY_REFRESH_SECONDS := 0.08

const BASE_INSTRUCTION_LINES: Array[String] = [
	"[color=#ffd166][b]SPACE[/b][/color]  Jump",
	"[color=#ffd166][b]ARROW KEYS[/b][/color]  Move around",
]
const DASH_INSTRUCTION_LINES: Array[String] = [
	"[color=#ffd166][b]SHIFT[/b][/color]  Press repeatedly to dash",
]

@export var branch_colors: Array[Color] = [
	Color(0.93, 0.29, 0.36, 0.42),
	Color(0.20, 0.72, 0.48, 0.42),
	Color(0.25, 0.55, 0.95, 0.42),
	Color(0.76, 0.42, 0.95, 0.42),
	Color(0.96, 0.68, 0.22, 0.42),
]
@export_range(0.01, 4.0, 0.01, "or_greater") var pixels_per_world_unit := 0.2
@export_range(64, 8192, 1, "or_greater") var maximum_texture_dimension := 2048

@export_group("Builder")
@export var rebuild_now := false:
	set(value):
		rebuild_now = false
		if value:
			queue_rebuild()

@onready var texture_rect: TextureRect = $TextureRect
@onready var explanation_panel: Panel = get_node_or_null(
	"../camera_component/Camera2D/ExplanationPanel"
) as Panel
@onready var explanation_label: RichTextLabel = get_node_or_null(
	"../camera_component/Camera2D/ExplanationPanel/RichTextLabel"
) as RichTextLabel

var map_bounds := Rect2()
var shoreline_polygon := PackedVector2Array()
var actual_pixels_per_world_unit := 0.0
@export var skill_activation_states: Dictionary[StringName, bool] = {}
var _rebuild_queued := false
var _observed_areas: Array[BranchArea2DComponent] = []
var _dash_telemetry_label: RichTextLabel
var _telemetry_character: SkillTreeCharacter
var _telemetry_refresh_elapsed := 0.0
var _base_explanation_panel_width := INSTRUCTION_PANEL_MINIMUM_WIDTH


func _ready() -> void:
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.z_index = -100
	_setup_explanation_panel()
	_update_world_feature_states()
	queue_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_dash_telemetry(delta)


func queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred(&"_run_queued_rebuild")


func _run_queued_rebuild() -> void:
	_rebuild_queued = false
	rebuild()


func compile_skill_activation_states(skill_nodes: Array[skill_node]) -> void:
	skill_activation_states.clear()
	for node in skill_nodes:
		if node == null or node.data == null or node.data.id.is_empty():
			continue
		skill_activation_states[node.data.id] = node.activated
	if is_node_ready():
		_update_world_feature_states()


func is_skill_activated(skill_id: StringName) -> bool:
	return skill_activation_states.get(skill_id, false)


func _on_skill_activation_changed(skill_id: StringName, enabled: bool) -> void:
	skill_activation_states[skill_id] = enabled
	print("Skill activation changed: id=%s enabled=%s" % [skill_id, enabled])
	_update_world_feature_states()


func _update_world_feature_states() -> void:
	var animations_enabled := is_skill_activated(MULTIPLE_IMAGES_SKILL_ID)
	var dash_enabled := is_skill_activated(VELOCITY_AND_ACCELERATION_SKILL_ID)
	for descendant in find_children("*", "", true, false):
		if descendant.is_in_group(&"skill_tree_characters"):
			descendant.set(&"animations_enabled", animations_enabled)
			descendant.set(&"dash_enabled", dash_enabled)
		if descendant.is_in_group(&"skill_tree_world_feature_visuals"):
			var activation_skill_id: StringName = descendant.get(
				&"activation_skill_id"
			)
			descendant.set(
				&"enabled",
				is_skill_activated(activation_skill_id)
			)
			descendant.set(&"animations_enabled", animations_enabled)
	_update_explanation_panel()


func _setup_explanation_panel() -> void:
	if explanation_panel == null or explanation_label == null:
		return

	explanation_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	explanation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	explanation_label.bbcode_enabled = true
	explanation_label.scroll_active = false
	explanation_label.fit_content = false
	explanation_label.add_theme_color_override(&"default_color", Color("dce8f5"))
	explanation_label.add_theme_font_size_override(&"normal_font_size", 16)
	_base_explanation_panel_width = maxf(
		explanation_panel.size.x,
		INSTRUCTION_PANEL_MINIMUM_WIDTH
	)

	_dash_telemetry_label = RichTextLabel.new()
	_dash_telemetry_label.name = "DashTelemetry"
	_dash_telemetry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash_telemetry_label.bbcode_enabled = true
	_dash_telemetry_label.scroll_active = false
	_dash_telemetry_label.fit_content = false
	_dash_telemetry_label.position = DASH_TELEMETRY_POSITION
	_dash_telemetry_label.size = DASH_TELEMETRY_SIZE
	_dash_telemetry_label.add_theme_color_override(&"default_color", Color("dce8f5"))
	_dash_telemetry_label.add_theme_font_size_override(&"normal_font_size", 13)
	explanation_panel.add_child(_dash_telemetry_label)
	_dash_telemetry_label.hide()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.052, 0.075, 0.96)
	panel_style.border_color = Color("4c7896")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	panel_style.shadow_size = 8
	explanation_panel.add_theme_stylebox_override(&"panel", panel_style)


func _update_explanation_panel() -> void:
	if explanation_panel == null or explanation_label == null:
		return

	# Story in Order is the master unlock for the instructions UI. Other
	# skills may add rows, but they must never reveal the pane themselves.
	if not is_skill_activated(STORY_IN_ORDER_SKILL_ID):
		explanation_panel.hide()
		explanation_label.text = ""
		_reset_dash_telemetry()
		return

	var instruction_lines: Array[String] = BASE_INSTRUCTION_LINES.duplicate()
	var dash_instructions_enabled := is_skill_activated(
		VELOCITY_AND_ACCELERATION_SKILL_ID
	)
	if dash_instructions_enabled:
		instruction_lines.append_array(DASH_INSTRUCTION_LINES)

	explanation_panel.show()
	if is_instance_valid(_dash_telemetry_label):
		_dash_telemetry_label.visible = dash_instructions_enabled
	if not dash_instructions_enabled:
		_reset_dash_telemetry()

	explanation_label.text = (
		"[font_size=20][color=#77bdf2][b]INSTRUCTIONS[/b][/color][/font_size]\n"
		+ "\n".join(instruction_lines)
	)

	var panel_width := (
		INSTRUCTION_PANEL_DASH_WIDTH
		if dash_instructions_enabled
		else _base_explanation_panel_width
	)
	var panel_height := (
		INSTRUCTION_PANEL_VERTICAL_PADDING
		+ INSTRUCTION_TITLE_HEIGHT
		+ INSTRUCTION_ROW_HEIGHT * instruction_lines.size()
	)
	explanation_panel.size = Vector2(panel_width, panel_height)
	explanation_label.position = Vector2(
		INSTRUCTION_PANEL_HORIZONTAL_PADDING * 0.5,
		INSTRUCTION_PANEL_VERTICAL_PADDING * 0.5
	)
	explanation_label.size = Vector2(
		(
			DASH_TELEMETRY_POSITION.x
			- INSTRUCTION_PANEL_HORIZONTAL_PADDING
			if dash_instructions_enabled
			else panel_width - INSTRUCTION_PANEL_HORIZONTAL_PADDING
		),
		panel_height - INSTRUCTION_PANEL_VERTICAL_PADDING
	)


func _update_dash_telemetry(delta: float) -> void:
	var telemetry_enabled := (
		is_skill_activated(STORY_IN_ORDER_SKILL_ID)
		and is_skill_activated(VELOCITY_AND_ACCELERATION_SKILL_ID)
		and explanation_panel != null
		and explanation_panel.visible
		and is_instance_valid(_dash_telemetry_label)
	)
	if not telemetry_enabled:
		if (
			is_instance_valid(_telemetry_character)
			or (
				is_instance_valid(_dash_telemetry_label)
				and _dash_telemetry_label.visible
			)
		):
			_reset_dash_telemetry()
		return

	if not is_instance_valid(_telemetry_character):
		_telemetry_character = _find_telemetry_character()
	if not is_instance_valid(_telemetry_character):
		_set_dash_telemetry_text(Vector2.ZERO, Vector2.ZERO)
		return

	_telemetry_refresh_elapsed += delta
	if _telemetry_refresh_elapsed < TELEMETRY_REFRESH_SECONDS:
		return
	_telemetry_refresh_elapsed = 0.0
	_set_dash_telemetry_text(
		_telemetry_character.velocity,
		_telemetry_character.current_acceleration
	)


func _find_telemetry_character() -> SkillTreeCharacter:
	for descendant in find_children("*", "", true, false):
		if (
			descendant is SkillTreeCharacter
			and descendant.is_in_group(&"skill_tree_characters")
		):
			return descendant as SkillTreeCharacter
	return null


func _set_dash_telemetry_text(
	current_velocity: Vector2,
	current_acceleration: Vector2
) -> void:
	if not is_instance_valid(_dash_telemetry_label):
		return
	_dash_telemetry_label.text = (
		"[color=#77bdf2][b]VELOCITY[/b][/color]"
		+ "     X  %6.0f    Y  %6.0f\n" % [
			current_velocity.x,
			current_velocity.y,
		]
		+ "[color=#f47b76][b]ACCELERATION[/b][/color]"
		+ "  X  %6.0f    Y  %6.0f" % [
			current_acceleration.x,
			current_acceleration.y,
		]
	)


func _reset_dash_telemetry() -> void:
	_telemetry_character = null
	_telemetry_refresh_elapsed = 0.0
	if is_instance_valid(_dash_telemetry_label):
		_dash_telemetry_label.hide()
		_set_dash_telemetry_text(Vector2.ZERO, Vector2.ZERO)


func rebuild() -> void:
	if not is_node_ready() or texture_rect == null:
		return

	_refresh_area_connections()
	var polygons: Array[PackedVector2Array] = []
	var colors: Array[Color] = []
	var shoreline_points := PackedVector2Array()
	var has_bounds := false
	var combined_bounds := Rect2()
	var component_inverse := get_global_transform_with_canvas().affine_inverse()
	var tree := get_parent() as skill_tree

	if tree == null:
		push_warning("SkillTree2DComponent must be a direct child of a skill_tree.")
		_clear_texture()
		return

	var branch_index := 0
	for child in tree.get_children():
		var branch := child as skill_branch
		if branch == null:
			continue
		var area := branch.get_node_or_null(
			"area_2d_component"
		) as BranchArea2DComponent
		if area == null or area.collision_shape == null or area.collision_shape.disabled:
			branch_index += 1
			continue
		var rectangle := area.collision_shape.shape as RectangleShape2D
		if rectangle == null:
			branch_index += 1
			continue

		var half_size := rectangle.size * 0.5
		var shape_to_component := (
			component_inverse
			* area.collision_shape.get_global_transform_with_canvas()
		)
		var polygon := PackedVector2Array([
			shape_to_component * Vector2(-half_size.x, -half_size.y),
			shape_to_component * Vector2(half_size.x, -half_size.y),
			shape_to_component * Vector2(half_size.x, half_size.y),
			shape_to_component * Vector2(-half_size.x, half_size.y),
		])
		polygons.append(polygon)
		colors.append(_get_branch_color(branch_index))
		shoreline_points.append_array(polygon)
		branch_index += 1

		for point in polygon:
			if not has_bounds:
				combined_bounds = Rect2(point, Vector2.ZERO)
				has_bounds = true
			else:
				combined_bounds = combined_bounds.expand(point)

	if not has_bounds or polygons.is_empty():
		_clear_texture()
		return

	shoreline_polygon = Geometry2D.convex_hull(shoreline_points)
	map_bounds = combined_bounds
	actual_pixels_per_world_unit = _get_safe_pixel_scale(map_bounds.size)
	var image_width := maxi(
		1,
		ceili(map_bounds.size.x * actual_pixels_per_world_unit)
	)
	var image_height := maxi(
		1,
		ceili(map_bounds.size.y * actual_pixels_per_world_unit)
	)
	var image := Image.create(
		image_width,
		image_height,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)

	for y in image_height:
		for x in image_width:
			var sample_point := map_bounds.position + Vector2(
				(float(x) + 0.5) / actual_pixels_per_world_unit,
				(float(y) + 0.5) / actual_pixels_per_world_unit
			)
			if not Geometry2D.is_point_in_polygon(
				sample_point,
				shoreline_polygon
			):
				continue

			var mixed_color := Color(0.0, 0.0, 0.0, 0.0)
			var overlap_count := 0
			for index in polygons.size():
				if Geometry2D.is_point_in_polygon(sample_point, polygons[index]):
					mixed_color += colors[index]
					overlap_count += 1
			if overlap_count > 0:
				image.set_pixel(x, y, mixed_color / float(overlap_count))
			else:
				var nearest_index := _find_nearest_polygon(
					sample_point,
					polygons
				)
				image.set_pixel(x, y, colors[nearest_index])

	var generated_texture := ImageTexture.create_from_image(image)
	texture_rect.texture = generated_texture
	texture_rect.position = map_bounds.position
	texture_rect.size = Vector2(
		float(image_width) / actual_pixels_per_world_unit,
		float(image_height) / actual_pixels_per_world_unit
	)
	texture_rebuilt.emit(generated_texture, map_bounds)


func _get_branch_color(branch_index: int) -> Color:
	if branch_index < branch_colors.size():
		return branch_colors[branch_index]
	# Keep additional branches distinct even when the authored palette runs out.
	var hue := fmod(float(branch_index) * 0.61803398875, 1.0)
	return Color.from_hsv(hue, 0.68, 0.95, 0.42)


func _get_safe_pixel_scale(world_size: Vector2) -> float:
	var safe_scale := maxf(pixels_per_world_unit, 0.01)
	if world_size.x > 0.0:
		safe_scale = minf(
			safe_scale,
			float(maximum_texture_dimension) / world_size.x
		)
	if world_size.y > 0.0:
		safe_scale = minf(
			safe_scale,
			float(maximum_texture_dimension) / world_size.y
		)
	return maxf(safe_scale, 0.0001)


func _find_nearest_polygon(
	point: Vector2,
	polygons: Array[PackedVector2Array]
) -> int:
	var nearest_index := 0
	var nearest_distance_squared := INF
	for polygon_index in polygons.size():
		var polygon := polygons[polygon_index]
		for point_index in polygon.size():
			var edge_start := polygon[point_index]
			var edge_end := polygon[(point_index + 1) % polygon.size()]
			var distance_squared := _distance_squared_to_segment(
				point,
				edge_start,
				edge_end
			)
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				nearest_index = polygon_index
	return nearest_index


func _distance_squared_to_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2
) -> float:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if is_zero_approx(segment_length_squared):
		return point.distance_squared_to(segment_start)
	var amount := clampf(
		(point - segment_start).dot(segment) / segment_length_squared,
		0.0,
		1.0
	)
	var closest_point := segment_start + segment * amount
	return point.distance_squared_to(closest_point)


func _refresh_area_connections() -> void:
	for area in _observed_areas:
		if (
			is_instance_valid(area)
			and area.bounds_changed.is_connected(queue_rebuild)
		):
			area.bounds_changed.disconnect(queue_rebuild)
	_observed_areas.clear()

	var tree := get_parent() as skill_tree
	if tree == null:
		return
	for child in tree.get_children():
		var branch := child as skill_branch
		if branch == null:
			continue
		var area := branch.get_node_or_null(
			"area_2d_component"
		) as BranchArea2DComponent
		if area == null:
			continue
		_observed_areas.append(area)
		area.bounds_changed.connect(queue_rebuild)


func _clear_texture() -> void:
	map_bounds = Rect2()
	shoreline_polygon = PackedVector2Array()
	actual_pixels_per_world_unit = 0.0
	texture_rect.texture = null
	texture_rect.position = Vector2.ZERO
	texture_rect.size = Vector2.ZERO
