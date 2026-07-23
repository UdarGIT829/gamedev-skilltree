@tool
extends Node2D
class_name SkillTree2DComponent

signal texture_rebuilt(texture: ImageTexture, world_bounds: Rect2)

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

var map_bounds := Rect2()
var shoreline_polygon := PackedVector2Array()
var actual_pixels_per_world_unit := 0.0
var _rebuild_queued := false
var _observed_areas: Array[BranchArea2DComponent] = []


func _ready() -> void:
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.z_index = -100
	queue_rebuild()


func queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred(&"_run_queued_rebuild")


func _run_queued_rebuild() -> void:
	_rebuild_queued = false
	rebuild()


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
