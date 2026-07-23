@tool
extends Resource
class_name SkillProgress

enum Status {
	LOCKED,
	UNLOCKED,
	SKILLED,
	DISABLED,
}

@export var statuses: Dictionary[StringName, int] = {}


func get_status(skill_id: StringName) -> Status:
	return statuses.get(skill_id, Status.LOCKED)


func set_status(skill_id: StringName, status: Status) -> void:
	statuses[skill_id] = status
	emit_changed()


func prerequisites_met(skill: SkillData) -> bool:
	if skill == null:
		return false
	for prerequisite_id in skill.prerequisite_ids:
		var status := get_status(prerequisite_id)
		if status != Status.UNLOCKED and status != Status.SKILLED:
			return false
	return true
