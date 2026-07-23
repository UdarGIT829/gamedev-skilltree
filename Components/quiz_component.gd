@tool
extends Node
class_name QuizComponent

const DISABLED_SKILL_STATUS := 3

signal quiz_input_ready(input: QuizInputContract)
signal quiz_output_ready(output: QuizOutputContract)
signal answer_changed(skill_id: StringName, answer: QuizQuestionData.Answer)

@export var questions: Array[QuizQuestionData] = []
@export var answers: Dictionary[StringName, int] = {}
@export var input_contract: QuizInputContract
@export var output_contract: QuizOutputContract

var _tree_data: SkillTreeData
var _progress: SkillProgress


func _ready() -> void:
	var tree := get_parent() as skill_tree
	if tree != null:
		configure(tree.tree_data, tree.progress)


func configure(tree_data: SkillTreeData, progress: SkillProgress) -> void:
	_tree_data = tree_data
	_progress = progress
	_compile_questions()
	_refresh_contracts()


func request_quiz_input() -> void:
	_refresh_contracts()
	quiz_input_ready.emit(input_contract)


func set_quiz_answer(skill_id: StringName, answer: int) -> void:
	var question := _get_question(skill_id)
	if question == null:
		push_warning("Cannot answer unknown quiz skill '%s'." % skill_id)
		return
	if answer < QuizQuestionData.Answer.UNANSWERED or answer > QuizQuestionData.Answer.DONT_CARE:
		push_warning("Quiz answer for '%s' is outside the valid answer range." % skill_id)
		return
	if not question.gates_are_open(answers) and answer != QuizQuestionData.Answer.UNANSWERED:
		push_warning("Quiz question '%s' is still gated." % skill_id)
		return

	question.answer = answer
	if answer == QuizQuestionData.Answer.UNANSWERED:
		answers.erase(skill_id)
	else:
		answers[skill_id] = answer

	_update_progress_for_answer(skill_id, answer)
	_clear_answers_behind_closed_gates()
	answer_changed.emit(skill_id, answer)
	_refresh_contracts()
	quiz_input_ready.emit(input_contract)
	quiz_output_ready.emit(output_contract)


func request_quiz_output() -> void:
	_refresh_contracts()
	quiz_output_ready.emit(output_contract)


func set_quiz_input(input: QuizInputContract) -> void:
	if input != null:
		_load_answers(input.answers)


func set_quiz_output(output: QuizOutputContract) -> void:
	if output != null:
		_load_answers(output.answers)


func reset_quiz() -> void:
	answers.clear()
	for question in questions:
		question.answer = QuizQuestionData.Answer.UNANSWERED
		_update_progress_for_answer(question.skill_id, QuizQuestionData.Answer.UNANSWERED)
	_refresh_contracts()
	quiz_input_ready.emit(input_contract)
	quiz_output_ready.emit(output_contract)


func _load_answers(saved_answers: Dictionary) -> void:
	answers.clear()
	for question in questions:
		question.answer = QuizQuestionData.Answer.UNANSWERED
		_update_progress_for_answer(question.skill_id, QuizQuestionData.Answer.UNANSWERED)

	var pending: Dictionary[StringName, int] = {}
	for question in questions:
		var saved_answer: int = saved_answers.get(question.skill_id, QuizQuestionData.Answer.UNANSWERED)
		if saved_answer > QuizQuestionData.Answer.UNANSWERED and saved_answer <= QuizQuestionData.Answer.DONT_CARE:
			pending[question.skill_id] = saved_answer

	# Restore in passes so cross-branch gates work even when their prerequisite
	# appears later in the authored branch order.
	var restored_something := true
	while restored_something:
		restored_something = false
		for question in questions:
			if not pending.has(question.skill_id) or not question.gates_are_open(answers):
				continue
			var saved_answer := pending[question.skill_id]
			question.answer = saved_answer
			answers[question.skill_id] = saved_answer
			_update_progress_for_answer(question.skill_id, saved_answer)
			pending.erase(question.skill_id)
			restored_something = true

	_refresh_contracts()
	quiz_input_ready.emit(input_contract)
	quiz_output_ready.emit(output_contract)


func _compile_questions() -> void:
	var previous_answers := answers.duplicate(true)
	questions.clear()
	answers.clear()
	if _tree_data == null:
		return

	var order := 0
	for branch in _tree_data.branches:
		if branch == null:
			continue
		for skill in branch.skills:
			if skill == null or skill.id.is_empty() or skill.claim.is_empty():
				continue
			var question := QuizQuestionData.new()
			question.order = order
			question.skill_id = skill.id
			question.skill = skill
			question.claim = skill.claim
			question.gated_by_skill_ids = skill.prerequisite_ids.duplicate()
			question.answer = previous_answers.get(skill.id, QuizQuestionData.Answer.UNANSWERED)
			questions.append(question)
			if question.answer != QuizQuestionData.Answer.UNANSWERED:
				answers[skill.id] = question.answer
			order += 1

	_clear_answers_behind_closed_gates()


func _make_quiz_input() -> QuizInputContract:
	var input := QuizInputContract.new()
	for question in questions:
		input.questions.append(question.duplicate(true) as QuizQuestionData)
		if question.gates_are_open(answers):
			input.available_skill_ids.append(question.skill_id)
	input.answers = answers.duplicate(true)
	input.answer_options = [
		QuizAnswerOptionData.create(QuizQuestionData.Answer.TRUTH, "Truth"),
		QuizAnswerOptionData.create(QuizQuestionData.Answer.PHILOSOPHY, "Philosophy"),
		QuizAnswerOptionData.create(QuizQuestionData.Answer.NOT_LEARNED, "I haven't learned this yet"),
		QuizAnswerOptionData.create(QuizQuestionData.Answer.DONT_CARE, "I don't care"),
	]
	return input


func _refresh_contracts() -> void:
	input_contract = _make_quiz_input()
	output_contract = _make_quiz_output()


func _make_quiz_output() -> QuizOutputContract:
	var output := QuizOutputContract.new()
	var has_available_unanswered := false
	for question in questions:
		match question.answer:
			QuizQuestionData.Answer.TRUTH:
				output.truth_skill_ids.append(question.skill_id)
			QuizQuestionData.Answer.PHILOSOPHY:
				output.philosophy_skill_ids.append(question.skill_id)
			QuizQuestionData.Answer.NOT_LEARNED:
				output.not_learned_skill_ids.append(question.skill_id)
			QuizQuestionData.Answer.DONT_CARE:
				output.dont_care_skill_ids.append(question.skill_id)
			_:
				output.unanswered_skill_ids.append(question.skill_id)
				if question.gates_are_open(answers):
					has_available_unanswered = true
				else:
					output.gated_skill_ids.append(question.skill_id)
	output.answers = answers.duplicate(true)
	output.complete = not has_available_unanswered
	return output


func _get_question(skill_id: StringName) -> QuizQuestionData:
	for question in questions:
		if question.skill_id == skill_id:
			return question
	return null


func _clear_answers_behind_closed_gates() -> void:
	var changed := true
	while changed:
		changed = false
		for question in questions:
			if question.answer == QuizQuestionData.Answer.UNANSWERED:
				continue
			if question.gates_are_open(answers):
				continue
			question.answer = QuizQuestionData.Answer.UNANSWERED
			answers.erase(question.skill_id)
			_update_progress_for_answer(question.skill_id, QuizQuestionData.Answer.UNANSWERED)
			changed = true


func _update_progress_for_answer(skill_id: StringName, answer: int) -> void:
	if _progress == null:
		return
	match answer:
		QuizQuestionData.Answer.TRUTH:
			_progress.set_status(skill_id, SkillProgress.Status.SKILLED)
		QuizQuestionData.Answer.PHILOSOPHY:
			_progress.set_status(skill_id, SkillProgress.Status.UNLOCKED)
		QuizQuestionData.Answer.DONT_CARE:
			# Use the serialized value directly so this tool script remains safe
			# while Godot refreshes its global enum-class cache.
			_progress.statuses[skill_id] = DISABLED_SKILL_STATUS
			_progress.emit_changed()
		_:
			_progress.set_status(skill_id, SkillProgress.Status.LOCKED)
