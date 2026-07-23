@tool
extends Resource
class_name SkillTreeData

@export var branches: Array[SkillBranchData] = []


func get_branch(branch_id: StringName) -> SkillBranchData:
	for branch in branches:
		if branch != null and branch.id == branch_id:
			return branch
	return null


func get_skill(skill_id: StringName) -> SkillData:
	for branch in branches:
		if branch == null:
			continue
		var skill := branch.get_skill(skill_id)
		if skill != null:
			return skill
	return null
