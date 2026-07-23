@tool
extends Resource
class_name QuizInputContract

const VERSION := 1

@export var version := VERSION
@export var questions: Array[QuizQuestionData] = []
@export var available_skill_ids: Array[StringName] = []
@export var answers: Dictionary[StringName, int] = {}
@export var answer_options: Array[QuizAnswerOptionData] = []


func get_question(skill_id: StringName) -> QuizQuestionData:
	for question in questions:
		if question.skill_id == skill_id:
			return question
	return null


func is_available(skill_id: StringName) -> bool:
	return skill_id in available_skill_ids
