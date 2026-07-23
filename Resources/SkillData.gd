@tool
extends Resource
class_name SkillData

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export_multiline var claim: String
## A standalone scene used in the quiz and skill-detail popup. The scene root
## must inherit Control so either host can resize it to the available area.
@export var visual_scene: PackedScene:
	set(value):
		if visual_scene == value:
			return
		visual_scene = value
		emit_changed()
@export var tier: int = 1
@export var prerequisite_ids: Array[StringName] = []
@export var disabled: bool = false
