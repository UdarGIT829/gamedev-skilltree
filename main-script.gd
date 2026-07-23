extends Control

@export var reset_quiz_on_start := true

@onready var skill_tree_view: skill_tree = $SkillTree
@onready var quiz_view: QuizView = $Quiz
@onready var tree_camera_component: CameraComponent = $SkillTree/camera_component
@onready var tree_camera: Camera2D = $SkillTree/camera_component/Camera2D


func _ready() -> void:
	skill_tree_view.quiz_input_received.connect(_on_quiz_input_received)
	quiz_view.answer_selected.connect(_on_quiz_answer_selected)
	quiz_view.quiz_finished.connect(_on_quiz_finished)
	_show_quiz()

	if reset_quiz_on_start:
		skill_tree_view.reset_quiz()
	else:
		skill_tree_view.request_quiz_input()


func _show_quiz() -> void:
	skill_tree_view.hide()
	skill_tree_view.process_mode = Node.PROCESS_MODE_DISABLED
	tree_camera.enabled = false
	tree_camera_component.set_minimap_visible(false)
	quiz_view.show()
	quiz_view.process_mode = Node.PROCESS_MODE_INHERIT


func _show_skill_tree() -> void:
	quiz_view.hide()
	quiz_view.process_mode = Node.PROCESS_MODE_DISABLED
	skill_tree_view.show()
	skill_tree_view.process_mode = Node.PROCESS_MODE_INHERIT
	tree_camera.enabled = true
	tree_camera_component.set_minimap_visible(true)


func _on_quiz_input_received(input: QuizInputContract) -> void:
	quiz_view.load_quiz_input(input)


func _on_quiz_answer_selected(skill_id: StringName, answer: QuizQuestionData.Answer) -> void:
	skill_tree_view.set_quiz_answer(skill_id, answer)


func _on_quiz_finished(output: QuizOutputContract) -> void:
	if output == null or not output.complete:
		return
	skill_tree_view.set_quiz_output(output)
	_show_skill_tree()
