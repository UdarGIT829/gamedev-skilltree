extends CanvasLayer
class_name SkillDetailPopup

signal closed

@onready var overlay: Control = $Overlay
@onready var close_button: Button = $Overlay/Center/Panel/Margin/Content/Header/CloseButton
@onready var title_label: Label = $Overlay/Center/Panel/Margin/Content/Header/Title
@onready var claim_label: Label = $Overlay/Center/Panel/Margin/Content/Body/Information/Claim
@onready var description_label: Label = $Overlay/Center/Panel/Margin/Content/Body/Information/DescriptionScroll/Description
@onready var preview_host: Control = $Overlay/Center/Panel/Margin/Content/Body/PreviewFrame/PreviewCenter/PreviewHost
@onready var empty_preview_label: Label = $Overlay/Center/Panel/Margin/Content/Body/PreviewFrame/PreviewCenter/PreviewHost/EmptyPreview

var _preview_visual: Control


func _ready() -> void:
	close_button.pressed.connect(close)
	overlay.hide()


func show_skill(skill: SkillData) -> void:
	if skill == null:
		return
	title_label.text = skill.display_name
	claim_label.text = skill.claim if not skill.claim.strip_edges().is_empty() else "No claim provided."
	description_label.text = (
		skill.description
		if not skill.description.strip_edges().is_empty()
		else "No description has been written for this skill yet."
	)
	_show_visual(skill)
	overlay.show()
	close_button.grab_focus()


func close() -> void:
	if not overlay.visible:
		return
	overlay.hide()
	_clear_preview()
	closed.emit()


func is_open() -> bool:
	return overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if not overlay.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _show_visual(skill: SkillData) -> void:
	_clear_preview()
	empty_preview_label.visible = skill.visual_scene == null
	if skill.visual_scene == null:
		return

	var instance := skill.visual_scene.instantiate()
	if not instance is Control:
		push_warning(
			"Skill visual scene for '%s' must have a Control root." % skill.display_name
		)
		instance.free()
		empty_preview_label.text = "This visual cannot be displayed here."
		empty_preview_label.show()
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
	empty_preview_label.text = "No visual has been created for this skill yet."


func _disable_preview_input(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_preview_input(child)
