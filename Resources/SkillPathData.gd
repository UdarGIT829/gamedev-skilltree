@tool
extends Resource
class_name SkillPathData

@export var source: SkillData
@export var destination: SkillData


func get_id() -> StringName:
	if source == null or destination == null:
		return &""
	return StringName("%s->%s" % [source.id, destination.id])
