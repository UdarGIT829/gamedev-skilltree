@tool
extends Resource
class_name QuizAnswerOptionData

@export var value: QuizQuestionData.Answer = QuizQuestionData.Answer.UNANSWERED
@export var label: String


static func create(answer_value: QuizQuestionData.Answer, answer_label: String) -> QuizAnswerOptionData:
	var option := QuizAnswerOptionData.new()
	option.value = answer_value
	option.label = answer_label
	return option
