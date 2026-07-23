extends Control
class_name QuizView

signal answer_selected(skill_id: StringName, answer: QuizQuestionData.Answer)
signal quiz_output_changed(output: QuizOutputContract)
signal quiz_finished(output: QuizOutputContract)

@export var input_contract: QuizInputContract:
	set(value):
		input_contract = value
		if is_node_ready():
			_apply_quiz_input(value)

@onready var preview_host: Control = %PreviewHost
@onready var progress_label: Label = %ProgressLabel
@onready var claim_label: Label = %ClaimLabel
@onready var status_label: Label = %StatusLabel
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var finish_button: Button = %FinishButton

@onready var answer_buttons: Array[Button] = [
	%TruthButton,
	%PhilosophyButton,
	%NotLearnedButton,
	%DontCareButton,
]

var _working_answers: Dictionary[StringName, int] = {}
var _available_questions: Array[QuizQuestionData] = []
var _current_index := 0
var _preview_visual: Control
var _pending_skill_id: StringName
var _pending_answer: int = QuizQuestionData.Answer.UNANSWERED
var _first_pass_completed := false


func _ready() -> void:
	answer_buttons[0].pressed.connect(_select_answer.bind(QuizQuestionData.Answer.TRUTH))
	answer_buttons[1].pressed.connect(_select_answer.bind(QuizQuestionData.Answer.PHILOSOPHY))
	answer_buttons[2].pressed.connect(_select_answer.bind(QuizQuestionData.Answer.NOT_LEARNED))
	answer_buttons[3].pressed.connect(_select_answer.bind(QuizQuestionData.Answer.DONT_CARE))
	previous_button.pressed.connect(_move_question.bind(-1))
	next_button.pressed.connect(_move_question.bind(1))
	finish_button.pressed.connect(_finish_quiz)
	_apply_quiz_input(input_contract)


func load_quiz_input(input: QuizInputContract) -> void:
	input_contract = input


func _apply_quiz_input(input: QuizInputContract) -> void:
	var preferred_skill_id := _get_current_skill_id()
	_working_answers.clear()
	if input != null:
		_working_answers.assign(input.answers)
	if input == null or input.answers.is_empty():
		_first_pass_completed = false
	_clear_pending_answer()
	_current_index = 0
	_rebuild_available_questions(preferred_skill_id)
	_update_first_pass_state()
	if not _first_pass_completed:
		_select_first_unanswered_question()
	_show_current_question()


func get_quiz_output() -> QuizOutputContract:
	return _build_output()


func _rebuild_available_questions(preferred_skill_id: StringName = &"") -> void:
	_available_questions.clear()
	if input_contract == null:
		return
	for question in input_contract.questions:
		if question.gates_are_open(_working_answers):
			_available_questions.append(question)

	if not preferred_skill_id.is_empty():
		for index in _available_questions.size():
			if _available_questions[index].skill_id == preferred_skill_id:
				_current_index = index
				break
	_current_index = clampi(_current_index, 0, maxi(_available_questions.size() - 1, 0))


func _show_current_question() -> void:
	if _available_questions.is_empty():
		progress_label.text = "Quiz complete" if input_contract != null else "Quiz"
		claim_label.text = "No unanswered paths remain." if input_contract != null else "Waiting for quiz input."
		status_label.text = ""
		_set_answers_enabled(false)
		_clear_preview()
		previous_button.disabled = true
		next_button.disabled = true
		_update_navigation_visibility()
		return

	var question := _available_questions[_current_index]
	progress_label.text = "Question %d of %d" % [_current_index + 1, _available_questions.size()]
	claim_label.text = question.claim
	previous_button.disabled = _current_index == 0
	next_button.disabled = _current_index >= _available_questions.size() - 1
	_set_answers_enabled(true)
	_update_answer_buttons(question)
	_show_question_visual(question)
	_update_navigation_visibility()


func _select_answer(answer: QuizQuestionData.Answer) -> void:
	if _available_questions.is_empty():
		return
	var question := _available_questions[_current_index]
	if _pending_skill_id != question.skill_id or _pending_answer != answer:
		_pending_skill_id = question.skill_id
		_pending_answer = answer
		_update_answer_buttons(question)
		return

	_clear_pending_answer()
	question.answer = answer
	_working_answers[question.skill_id] = answer
	_clear_closed_answers()
	var answered_id := question.skill_id
	_rebuild_available_questions(answered_id)
	_update_first_pass_state()
	if not _first_pass_completed:
		_select_first_unanswered_question()
	_show_current_question()

	var output := _build_output()
	quiz_output_changed.emit(output)
	answer_selected.emit(question.skill_id, answer)


func _move_question(offset: int) -> void:
	if _available_questions.is_empty():
		return
	_clear_pending_answer()
	_current_index = clampi(_current_index + offset, 0, _available_questions.size() - 1)
	_show_current_question()


func _finish_quiz() -> void:
	quiz_finished.emit(_build_output())


func _clear_closed_answers() -> void:
	if input_contract == null:
		return
	var changed := true
	while changed:
		changed = false
		for question in input_contract.questions:
			if not _working_answers.has(question.skill_id):
				continue
			if question.gates_are_open(_working_answers):
				continue
			_working_answers.erase(question.skill_id)
			question.answer = QuizQuestionData.Answer.UNANSWERED
			changed = true


func _update_answer_buttons(question: QuizQuestionData) -> void:
	var confirmed_answer: int = _working_answers.get(
		question.skill_id,
		QuizQuestionData.Answer.UNANSWERED
	)
	var has_pending_answer := _pending_skill_id == question.skill_id
	var selected_answer := _pending_answer if has_pending_answer else confirmed_answer
	for index in answer_buttons.size():
		answer_buttons[index].button_pressed = selected_answer == index + 1
	if has_pending_answer:
		status_label.text = "%s — press again to confirm" % QuizQuestionData.get_answer_label(
			selected_answer
		)
	elif confirmed_answer == QuizQuestionData.Answer.UNANSWERED:
		status_label.text = "Unanswered"
	else:
		status_label.text = "%s — confirmed" % QuizQuestionData.get_answer_label(
			confirmed_answer
		)


func _show_question_visual(question: QuizQuestionData) -> void:
	_clear_preview()
	if question.skill == null or question.skill.visual_scene == null:
		return
	var instance := question.skill.visual_scene.instantiate()
	if not instance is Control:
		push_warning(
			"Quiz visual scene for '%s' must have a Control root." % question.skill.display_name
		)
		instance.free()
		return
	_preview_visual = instance as Control
	preview_host.add_child(_preview_visual)
	_preview_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_visual.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_preview_visual.grow_vertical = Control.GROW_DIRECTION_BOTH
	_disable_preview_input(_preview_visual)


func _clear_preview() -> void:
	if is_instance_valid(_preview_visual):
		_preview_visual.free()
	_preview_visual = null


func _disable_preview_input(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_preview_input(child)


func _build_output() -> QuizOutputContract:
	var output := QuizOutputContract.new()
	output.answers = _working_answers.duplicate(true)
	if input_contract == null:
		return output
	var has_available_unanswered := false
	for question in input_contract.questions:
		var answer: int = _working_answers.get(question.skill_id, QuizQuestionData.Answer.UNANSWERED)
		match answer:
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
				if question.gates_are_open(_working_answers):
					has_available_unanswered = true
				else:
					output.gated_skill_ids.append(question.skill_id)
	output.complete = not has_available_unanswered
	return output


func _get_current_skill_id() -> StringName:
	if _available_questions.is_empty() or _current_index >= _available_questions.size():
		return &""
	return _available_questions[_current_index].skill_id


func _clear_pending_answer() -> void:
	_pending_skill_id = &""
	_pending_answer = QuizQuestionData.Answer.UNANSWERED


func _select_first_unanswered_question() -> void:
	for index in _available_questions.size():
		if not _working_answers.has(_available_questions[index].skill_id):
			_current_index = index
			return


func _update_first_pass_state() -> void:
	if _first_pass_completed or input_contract == null:
		return
	for question in input_contract.questions:
		if question.gates_are_open(_working_answers) and not _working_answers.has(question.skill_id):
			return
	_first_pass_completed = true


func _update_navigation_visibility() -> void:
	previous_button.visible = _first_pass_completed
	next_button.visible = _first_pass_completed
	finish_button.visible = _first_pass_completed and _build_output().complete


func _set_answers_enabled(enabled: bool) -> void:
	for button in answer_buttons:
		button.disabled = not enabled
