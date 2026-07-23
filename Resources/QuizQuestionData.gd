@tool
extends Resource
class_name QuizQuestionData

enum Answer {
	UNANSWERED,
	TRUTH,
	PHILOSOPHY,
	NOT_LEARNED,
	DONT_CARE,
}

const ANSWER_LABELS := {
	Answer.TRUTH: "Truth",
	Answer.PHILOSOPHY: "Philosophy",
	Answer.NOT_LEARNED: "I haven't learned this yet",
	Answer.DONT_CARE: "I don't care",
}

@export var order: int
@export var skill_id: StringName
@export var skill: SkillData
@export_multiline var claim: String
@export var gated_by_skill_ids: Array[StringName] = []
@export var answer: Answer = Answer.UNANSWERED


func gates_are_open(answers: Dictionary[StringName, int]) -> bool:
	for gate_id in gated_by_skill_ids:
		var gate_answer: int = answers.get(gate_id, Answer.UNANSWERED)
		if gate_answer != Answer.TRUTH and gate_answer != Answer.PHILOSOPHY:
			return false
	return true


static func get_answer_label(answer_value: Answer) -> String:
	return ANSWER_LABELS.get(answer_value, "Unanswered")
