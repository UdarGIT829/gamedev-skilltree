@tool
extends Resource
class_name SkillBranchData

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var skills: Array[SkillData] = []
@export var paths: Array[SkillPathData] = []


func get_skill(skill_id: StringName) -> SkillData:
	for skill in skills:
		if skill != null and skill.id == skill_id:
			return skill
	return null
