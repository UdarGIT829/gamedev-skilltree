extends Control

const QUESTIONS := [
	"Give me a name.",
	"What are they carrying?",
	"Where are they going?",
]
const ANSWERS := ["Taylor", "a turkey sandwich", "Dodgers Stadium"]
const TYPE_INTERVAL := 0.065
const FLOAT_DURATION := 0.65
const FLOATING_ANSWER_SIZE := Vector2(118.0, 42.0)
const NORMAL_COLOR := Color("c8d2e3")
const DIM_COLOR := Color("728096")
const ACTIVE_COLOR := Color("ffd166")
const FILLED_COLOR := Color("62d6a8")

@onready var animation_timer: Timer = %AnimationTimer
@onready var question_stage: Control = %QuestionStage
@onready var story_stage: Control = %StoryStage
@onready var question_count: Label = %QuestionCount
@onready var question_label: Label = %QuestionLabel
@onready var answer_text: Label = %AnswerText
@onready var status_label: Label = %StatusLabel
@onready var floating_answer: Label = %FloatingAnswer

@onready var array_slots: Array[Label] = [
	%ArraySlot0,
	%ArraySlot1,
	%ArraySlot2,
]
@onready var story_targets: Array[Label] = [
	%StoryTarget0,
	%StoryTarget1,
	%StoryTarget2,
]

var _question_index := 0
var _typed_characters := 0
var _story_index := 0
var _scheduled_callback := Callable()
var _after_float_callback := Callable()
var _active_tween: Tween


func _ready() -> void:
	animation_timer.timeout.connect(_on_animation_timer_timeout)
	call_deferred(&"_begin_cycle")


func _begin_cycle() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	floating_answer.hide()
	question_stage.show()
	story_stage.hide()
	_question_index = 0
	_story_index = 0
	for index in array_slots.size():
		array_slots[index].text = "[%d]  —" % index
		_set_label_color(array_slots[index], DIM_COLOR)
	for index in story_targets.size():
		story_targets[index].text = "[%d]  _____" % index
		_set_label_color(story_targets[index], DIM_COLOR)
	status_label.text = "Collect answers into the array"
	_begin_question()


func _begin_question() -> void:
	question_count.text = "QUESTION %d OF %d" % [_question_index + 1, QUESTIONS.size()]
	question_label.text = QUESTIONS[_question_index]
	answer_text.text = ""
	_typed_characters = 0
	status_label.text = "Typing an answer…"
	_schedule(0.4, _type_next_character)


func _type_next_character() -> void:
	var answer: String = ANSWERS[_question_index]
	if _typed_characters < answer.length():
		_typed_characters += 1
		answer_text.text = answer.substr(0, _typed_characters) + "▌"
		_schedule(TYPE_INTERVAL, _type_next_character)
		return
	answer_text.text = answer
	status_label.text = "Answer ready"
	_schedule(0.5, _store_current_answer)


func _store_current_answer() -> void:
	status_label.text = "Store it at index %d" % _question_index
	_set_label_color(array_slots[_question_index], ACTIVE_COLOR)
	_float_value(
		ANSWERS[_question_index],
		answer_text,
		array_slots[_question_index],
		_on_answer_stored
	)
	answer_text.text = ""


func _on_answer_stored() -> void:
	array_slots[_question_index].text = "[%d]  %s" % [
		_question_index,
		ANSWERS[_question_index],
	]
	_set_label_color(array_slots[_question_index], FILLED_COLOR)
	_question_index += 1
	if _question_index < QUESTIONS.size():
		_schedule(0.45, _begin_question)
	else:
		status_label.text = "Three answers stored in order"
		_schedule(0.8, _show_story)


func _show_story() -> void:
	question_stage.hide()
	story_stage.show()
	_story_index = 0
	status_label.text = "Now rebuild the story"
	_schedule(0.8, _light_next_story_number)


func _light_next_story_number() -> void:
	_set_label_color(array_slots[_story_index], ACTIVE_COLOR)
	_set_label_color(story_targets[_story_index], ACTIVE_COLOR)
	status_label.text = "Read index %d" % _story_index
	_schedule(0.45, _move_value_into_story)


func _move_value_into_story() -> void:
	_float_value(
		ANSWERS[_story_index],
		array_slots[_story_index],
		story_targets[_story_index],
		_on_story_value_placed
	)


func _on_story_value_placed() -> void:
	story_targets[_story_index].text = ANSWERS[_story_index]
	_set_label_color(story_targets[_story_index], FILLED_COLOR)
	_set_label_color(array_slots[_story_index], NORMAL_COLOR)
	_story_index += 1
	if _story_index < ANSWERS.size():
		_schedule(0.55, _light_next_story_number)
	else:
		status_label.text = "The array rebuilt the story!"
		_schedule(2.5, _begin_cycle)


func _schedule(delay: float, callback: Callable) -> void:
	_scheduled_callback = callback
	animation_timer.start(delay)


func _on_animation_timer_timeout() -> void:
	var callback := _scheduled_callback
	_scheduled_callback = Callable()
	if callback.is_valid():
		callback.call()


func _float_value(
	value: String,
	from_control: Control,
	to_control: Control,
	finished_callback: Callable
) -> void:
	floating_answer.text = value
	# Keep long values from changing the visual's minimum width. The floating
	# token gets a predictable two-line box and wraps inside it.
	floating_answer.size = FLOATING_ANSWER_SIZE
	floating_answer.position = _control_center(from_control) - floating_answer.size * 0.5
	floating_answer.show()
	_after_float_callback = finished_callback
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(
		floating_answer,
		"position",
		_control_center(to_control) - floating_answer.size * 0.5,
		FLOAT_DURATION
	)
	_active_tween.finished.connect(_on_float_finished, CONNECT_ONE_SHOT)


func _on_float_finished() -> void:
	floating_answer.hide()
	var callback := _after_float_callback
	_after_float_callback = Callable()
	if callback.is_valid():
		callback.call()


func _control_center(control: Control) -> Vector2:
	var center_in_canvas := control.get_global_transform_with_canvas() * (control.size * 0.5)
	return get_global_transform_with_canvas().affine_inverse() * center_in_canvas


func _set_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override(&"font_color", color)
