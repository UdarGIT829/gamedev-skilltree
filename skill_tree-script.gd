@tool
extends Control
class_name skill_tree

signal quiz_input_requested
signal quiz_input_set(input: QuizInputContract)
signal quiz_answer_set(skill_id: StringName, answer: int)
signal quiz_output_requested
signal quiz_output_set(output: QuizOutputContract)
signal quiz_reset_requested
signal quiz_input_received(input: QuizInputContract)
signal quiz_output_received(output: QuizOutputContract)
signal skill_selected(skill: SkillData)

@export var tree_data: SkillTreeData
@export var progress: SkillProgress
@export var claims: Array[String] = []
@export var claim_skill_ids: Array[StringName] = []

@onready var controller_component: ControllerComponent = $controller_component
@onready var skill_detail_popup: SkillDetailPopup = $SkillDetailPopup


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	skill_detail_popup.closed.connect(_on_skill_popup_closed)
	_connect_skill_nodes()


func _connect_skill_nodes() -> void:
	for descendant in find_children("*", "", true, false):
		if not descendant is skill_node:
			continue
		var node := descendant as skill_node
		if not node.skill_selected.is_connected(_on_skill_node_selected):
			node.skill_selected.connect(_on_skill_node_selected)


func _on_skill_node_selected(skill: SkillData) -> void:
	skill_selected.emit(skill)
	controller_component.set_process_input(false)
	skill_detail_popup.show_skill(skill)


func _on_skill_popup_closed() -> void:
	controller_component.set_process_input(true)


func get_skill(skill_id: StringName) -> SkillData:
	if tree_data == null:
		return null
	return tree_data.get_skill(skill_id)


func request_quiz_input() -> void:
	quiz_input_requested.emit()


func set_quiz_answer(skill_id: StringName, answer: int) -> void:
	quiz_answer_set.emit(skill_id, answer)


func set_quiz_input(input: QuizInputContract) -> void:
	quiz_input_set.emit(input)


func request_quiz_output() -> void:
	quiz_output_requested.emit()


func set_quiz_output(output: QuizOutputContract) -> void:
	quiz_output_set.emit(output)


func reset_quiz() -> void:
	quiz_reset_requested.emit()


func _on_quiz_input_ready(input: QuizInputContract) -> void:
	quiz_input_received.emit(input)


func _on_quiz_output_ready(output: QuizOutputContract) -> void:
	quiz_output_received.emit(output)
