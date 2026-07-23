@tool
extends Control
class_name skill_path

@export var data: SkillPathData
@export var color := Color("708090"):
	set(value):
		color = value
		_update_texture()
@export var overlap_color := Color("ff4d4d"):
	set(value):
		overlap_color = value
		_update_texture()
@export_range(1.0, 20.0, 0.5) var width := 4.0:
	set(value):
		width = value
		_update_texture()
@export var overlapping_skill_ids: Array[StringName] = []

var source_node: skill_node
var destination_node: skill_node

@onready var edge_texture: TextureRect = $EdgeTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_texture()


func connect_nodes(from_node: skill_node, to_node: skill_node) -> void:
	source_node = from_node
	destination_node = to_node
	visible = source_node != null and destination_node != null
	_update_texture()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and source_node != null and destination_node != null:
		_update_texture()


func _update_texture() -> void:
	if not is_node_ready() or edge_texture == null:
		return
	if source_node == null or destination_node == null:
		edge_texture.hide()
		overlapping_skill_ids = []
		return
	if not is_instance_valid(source_node) or not is_instance_valid(destination_node):
		edge_texture.hide()
		overlapping_skill_ids = []
		return

	var endpoints := _closest_endpoints(source_node, destination_node)
	var start: Vector2 = endpoints[0]
	var finish: Vector2 = endpoints[1]
	var offset := finish - start
	var length := offset.length()
	if is_zero_approx(length):
		edge_texture.hide()
		return

	edge_texture.show()
	var detected_overlaps := _find_overlapping_skills(start, finish)
	if detected_overlaps != overlapping_skill_ids:
		overlapping_skill_ids = detected_overlaps
	edge_texture.modulate = overlap_color if not overlapping_skill_ids.is_empty() else color
	edge_texture.position = start - Vector2(0.0, width * 0.5)
	edge_texture.size = Vector2(length, width)
	edge_texture.pivot_offset = Vector2(0.0, width * 0.5)
	edge_texture.rotation = offset.angle()


func _find_overlapping_skills(start: Vector2, finish: Vector2) -> Array[StringName]:
	var overlaps: Array[StringName] = []
	var branch := get_parent()
	if branch == null:
		return overlaps

	for child in branch.get_children():
		var node := child as skill_node
		if node == null or node == source_node or node == destination_node:
			continue
		var polygon := _node_polygon(node)
		if _segment_intersects_polygon(start, finish, polygon):
			overlaps.append(node.data.id if node.data != null else StringName(node.name))
	return overlaps


func _node_polygon(node: skill_node) -> PackedVector2Array:
	var visual := node.billboard_visuals
	if visual == null:
		visual = node
	var transform := visual.get_global_transform_with_canvas()
	var visual_size := visual.size
	return PackedVector2Array([
		_canvas_to_local(transform * Vector2.ZERO),
		_canvas_to_local(transform * Vector2(visual_size.x, 0.0)),
		_canvas_to_local(transform * visual_size),
		_canvas_to_local(transform * Vector2(0.0, visual_size.y)),
	])


func _segment_intersects_polygon(start: Vector2, finish: Vector2, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(start, polygon) or Geometry2D.is_point_in_polygon(finish, polygon):
		return true
	for index in polygon.size():
		var edge_start := polygon[index]
		var edge_finish := polygon[(index + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(start, finish, edge_start, edge_finish) != null:
			return true
	return false


func _closest_endpoints(from_node: skill_node, to_node: skill_node) -> Array[Vector2]:
	var from_points := _marker_points_in_canvas(from_node)
	var to_points := _marker_points_in_canvas(to_node)
	var closest_from: Vector2 = from_points[0]
	var closest_to: Vector2 = to_points[0]
	var shortest_distance_squared := INF

	for from_point in from_points:
		for to_point in to_points:
			var distance_squared := from_point.distance_squared_to(to_point)
			if distance_squared < shortest_distance_squared:
				shortest_distance_squared = distance_squared
				closest_from = from_point
				closest_to = to_point

	return [
		_canvas_to_local(closest_from),
		_canvas_to_local(closest_to),
	]


func _marker_points_in_canvas(node: skill_node) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for marker in node.get_connection_markers():
		points.append(marker.get_global_transform_with_canvas().origin)

	if points.is_empty():
		points.append(node.get_global_transform_with_canvas() * (node.size * 0.5))
	return points


func _canvas_to_local(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * point
