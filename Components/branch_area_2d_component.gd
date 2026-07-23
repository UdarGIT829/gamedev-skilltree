@tool
extends Area2D
class_name BranchArea2DComponent

signal bounds_changed(bounds: Rect2)

@export var padding := Vector2(80.0, 80.0):
	set(value):
		padding = value.max(Vector2.ZERO)
		queue_rebuild()

@export_group("Builder")
@export var rebuild_now := false:
	set(value):
		rebuild_now = false
		if value:
			queue_rebuild()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var branch_bounds := Rect2()
var _rebuild_queued := false


func _ready() -> void:
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
	if not is_node_ready() or collision_shape == null:
		return

	var branch := get_parent() as skill_branch
	if branch == null:
		push_warning("BranchArea2DComponent must be a direct child of a skill_branch.")
		collision_shape.disabled = true
		return

	var has_bounds := false
	var calculated_bounds := Rect2()
	var area_inverse := get_global_transform_with_canvas().affine_inverse()

	for child in branch.get_children():
		var node := child as skill_node
		if node == null:
			continue

		var visual: Control = node.billboard_visuals
		if visual == null:
			visual = node
		var visual_to_area := area_inverse * visual.get_global_transform_with_canvas()
		var corners := PackedVector2Array([
			visual_to_area * Vector2.ZERO,
			visual_to_area * Vector2(visual.size.x, 0.0),
			visual_to_area * visual.size,
			visual_to_area * Vector2(0.0, visual.size.y),
		])

		for corner in corners:
			if not has_bounds:
				calculated_bounds = Rect2(corner, Vector2.ZERO)
				has_bounds = true
			else:
				calculated_bounds = calculated_bounds.expand(corner)

	if not has_bounds:
		branch_bounds = Rect2()
		collision_shape.disabled = true
		bounds_changed.emit(branch_bounds)
		return

	calculated_bounds.position -= padding
	calculated_bounds.size += padding * 2.0
	branch_bounds = calculated_bounds

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision_shape.shape = rectangle
	rectangle.size = branch_bounds.size.max(Vector2.ONE)
	collision_shape.position = branch_bounds.get_center()
	collision_shape.disabled = false
	bounds_changed.emit(branch_bounds)

