@tool
extends Node
class_name SkillTreeBuilder

enum BranchPlacement { HORIZONTAL, VERTICAL, RADIAL }

const SKILL_BRANCH_SCENE: PackedScene = preload("res://skill_branch.tscn")
const GENERATED_META := &"skill_tree_builder_generated"
const BRANCH_ID_META := &"branch_id"

@export var preview_in_editor := true:
	set(value):
		preview_in_editor = value
		queue_sync()
@export var placement: BranchPlacement = BranchPlacement.RADIAL:
	set(value):
		placement = value
		queue_sync()

@export_group("Branch Layout")
@export var branch_preview_in_editor := true:
	set(value):
		branch_preview_in_editor = value
		queue_sync()
@export var branch_graph_layout := true:
	set(value):
		branch_graph_layout = value
		queue_sync()
@export_range(-360.0, 360.0, 1.0) var branch_flow_angle_degrees := 90.0:
	set(value):
		branch_flow_angle_degrees = value
		queue_sync()
@export var branch_layout_center := Vector2.ZERO:
	set(value):
		branch_layout_center = value
		queue_sync()
@export_range(0.0, 5000.0, 10.0, "or_greater") var branch_tier_spacing := 330.0:
	set(value):
		branch_tier_spacing = value
		queue_sync()
@export_range(0.0, 5000.0, 10.0, "or_greater") var branch_sibling_spacing := 300.0:
	set(value):
		branch_sibling_spacing = value
		queue_sync()
@export var branch_center_children_on_parent := true:
	set(value):
		branch_center_children_on_parent = value
		queue_sync()
@export var branch_manual_spacing := Vector2(260.0, 0.0):
	set(value):
		branch_manual_spacing = value
		queue_sync()
@export var branch_build_paths_from_prerequisites := true:
	set(value):
		branch_build_paths_from_prerequisites = value
		queue_sync()

@export_group("Linear Placement")
@export var branch_spacing := 900.0:
	set(value):
		branch_spacing = value
		queue_sync()

@export_group("Radial Placement")
@export var radial_center := Vector2.ZERO:
	set(value):
		radial_center = value
		queue_sync()
@export_range(0.0, 10000.0, 10.0, "or_greater") var radial_radius := 900.0:
	set(value):
		radial_radius = value
		queue_sync()
@export_range(-360.0, 360.0, 1.0) var radial_start_angle_degrees := -90.0:
	set(value):
		radial_start_angle_degrees = value
		queue_sync()
@export_range(-360.0, 360.0, 1.0) var radial_sweep_degrees := 360.0:
	set(value):
		radial_sweep_degrees = value
		queue_sync()
@export var radial_rotate_branches := true:
	set(value):
		radial_rotate_branches = value
		queue_sync()
@export_range(-360.0, 360.0, 1.0) var radial_rotation_offset_degrees := 0.0:
	set(value):
		radial_rotation_offset_degrees = value
		queue_sync()

@export_group("Builder")
@export var rebuild_now := false:
	set(value):
		rebuild_now = false
		if value:
			queue_sync()

var _observed_tree_data: SkillTreeData
var _observed_branches: Array[SkillBranchData] = []
var _observed_skills: Array[SkillData] = []
var _sync_queued := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_refresh_resource_connections()
		queue_sync()
	else:
		set_process(false)
		sync_tree()


func _process(_delta: float) -> void:
	var tree := get_parent() as skill_tree
	var current_data: SkillTreeData = tree.tree_data if tree != null else null
	if current_data != _observed_tree_data:
		_refresh_resource_connections()
		queue_sync()


func queue_sync() -> void:
	if not is_inside_tree() or _sync_queued:
		return
	_sync_queued = true
	call_deferred(&"_run_queued_sync")


func _run_queued_sync() -> void:
	_sync_queued = false
	sync_tree()


func sync_tree() -> void:
	var tree := get_parent() as skill_tree
	if tree == null:
		push_warning("SkillTreeBuilder must be a direct child of a skill_tree.")
		return
	if Engine.is_editor_hint() and not preview_in_editor:
		_remove_generated_branches(tree)
		tree.claims = []
		tree.claim_skill_ids = []
		_compile_quiz(tree)
		_queue_2d_component_rebuild(tree)
		return

	var branch_data_list: Array[SkillBranchData] = []
	if tree.tree_data != null:
		branch_data_list = tree.tree_data.branches
	var existing := _get_generated_branches(tree)
	var used_branches: Array[Node] = []
	var ordered_claims: Array[String] = []
	var ordered_skill_ids: Array[StringName] = []

	for index in branch_data_list.size():
		var branch_data := branch_data_list[index]
		if branch_data == null:
			continue
		var branch_instance: skill_branch = existing.get(branch_data.id)
		if branch_instance == null:
			branch_instance = SKILL_BRANCH_SCENE.instantiate() as skill_branch
			tree.add_child(branch_instance)
			branch_instance.owner = _get_scene_owner(tree)
		branch_instance.set_meta(GENERATED_META, true)
		branch_instance.set_meta(BRANCH_ID_META, branch_data.id)
		branch_instance.name = _branch_name(branch_data, index)
		branch_instance.data = branch_data
		branch_instance.progress = tree.progress
		branch_instance.position = _branch_position(index, branch_data_list.size())
		used_branches.append(branch_instance)

		var branch_builder := branch_instance.get_node_or_null("builder_component") as SkillBranchBuilder
		_configure_branch_builder(branch_builder)
		branch_instance.rotation = _branch_rotation(index, branch_data_list.size(), branch_builder)
		if branch_builder != null:
			branch_builder.sync_skill_nodes()
		ordered_claims.append_array(branch_instance.claims)
		ordered_skill_ids.append_array(branch_instance.claim_skill_ids)

	for child in tree.get_children():
		if child.get_meta(GENERATED_META, false) and child not in used_branches:
			child.queue_free()
	tree.claims = ordered_claims
	tree.claim_skill_ids = ordered_skill_ids
	_compile_quiz(tree)
	_refresh_resource_connections()
	_queue_2d_component_rebuild(tree)


func _queue_2d_component_rebuild(tree: skill_tree) -> void:
	var component := tree.get_node_or_null(
		"2d-component"
	) as SkillTree2DComponent
	if component != null:
		component.queue_rebuild()


func _compile_quiz(tree: skill_tree) -> void:
	var quiz := tree.get_node_or_null("quiz_component") as QuizComponent
	if quiz != null:
		quiz.configure(tree.tree_data, tree.progress)


func _configure_branch_builder(branch_builder: SkillBranchBuilder) -> void:
	if branch_builder == null:
		return
	branch_builder.preview_in_editor = branch_preview_in_editor
	branch_builder.graph_layout = branch_graph_layout
	branch_builder.flow_angle_degrees = branch_flow_angle_degrees
	branch_builder.layout_center = branch_layout_center
	branch_builder.tier_spacing = branch_tier_spacing
	branch_builder.sibling_spacing = branch_sibling_spacing
	branch_builder.center_children_on_parent = branch_center_children_on_parent
	branch_builder.spacing = branch_manual_spacing
	branch_builder.build_paths_from_prerequisites = branch_build_paths_from_prerequisites


func _branch_position(index: int, branch_count: int) -> Vector2:
	match placement:
		BranchPlacement.HORIZONTAL:
			return Vector2(branch_spacing * index, 0.0)
		BranchPlacement.VERTICAL:
			return Vector2(0.0, branch_spacing * index)
		BranchPlacement.RADIAL:
			if branch_count <= 1:
				return radial_center
			var closes_circle := is_equal_approx(absf(radial_sweep_degrees), 360.0)
			var divisor := branch_count if closes_circle else branch_count - 1
			var angle_step := radial_sweep_degrees / float(maxi(divisor, 1))
			var angle := deg_to_rad(radial_start_angle_degrees + angle_step * index)
			return radial_center + Vector2.from_angle(angle) * radial_radius
	return Vector2.ZERO


func _branch_rotation(index: int, branch_count: int, branch_builder: SkillBranchBuilder) -> float:
	if placement != BranchPlacement.RADIAL or not radial_rotate_branches:
		return 0.0
	var closes_circle := is_equal_approx(absf(radial_sweep_degrees), 360.0)
	var divisor := branch_count if closes_circle else maxi(branch_count - 1, 1)
	var angle_step := radial_sweep_degrees / float(maxi(divisor, 1))
	var radial_angle := radial_start_angle_degrees + angle_step * index
	var branch_flow_angle := branch_builder.flow_angle_degrees if branch_builder != null else 90.0
	return deg_to_rad(radial_angle - branch_flow_angle + radial_rotation_offset_degrees)


func _refresh_resource_connections() -> void:
	_disconnect_resources()
	var tree := get_parent() as skill_tree
	if tree == null:
		return
	_observed_tree_data = tree.tree_data
	if _observed_tree_data == null:
		return
	_observed_tree_data.changed.connect(queue_sync)
	for branch_data in _observed_tree_data.branches:
		if branch_data == null or branch_data in _observed_branches:
			continue
		_observed_branches.append(branch_data)
		branch_data.changed.connect(queue_sync)
		for skill in branch_data.skills:
			if skill == null or skill in _observed_skills:
				continue
			_observed_skills.append(skill)
			skill.changed.connect(queue_sync)


func _disconnect_resources() -> void:
	if _observed_tree_data != null and _observed_tree_data.changed.is_connected(queue_sync):
		_observed_tree_data.changed.disconnect(queue_sync)
	for branch_data in _observed_branches:
		if branch_data != null and branch_data.changed.is_connected(queue_sync):
			branch_data.changed.disconnect(queue_sync)
	_observed_branches.clear()
	for skill in _observed_skills:
		if skill != null and skill.changed.is_connected(queue_sync):
			skill.changed.disconnect(queue_sync)
	_observed_skills.clear()
	_observed_tree_data = null


func _get_generated_branches(tree: skill_tree) -> Dictionary:
	var result: Dictionary = {}
	for child in tree.get_children():
		if not child.get_meta(GENERATED_META, false):
			continue
		var branch_id: StringName = child.get_meta(BRANCH_ID_META, &"")
		if not branch_id.is_empty():
			result[branch_id] = child
	return result


func _remove_generated_branches(tree: skill_tree) -> void:
	for child in tree.get_children():
		if child.get_meta(GENERATED_META, false):
			child.queue_free()


func _get_scene_owner(tree: Node) -> Node:
	if Engine.is_editor_hint() and tree.get_tree() != null:
		return tree.get_tree().edited_scene_root
	return tree.owner


func _branch_name(branch_data: SkillBranchData, index: int) -> String:
	if not branch_data.id.is_empty():
		return String(branch_data.id)
	return "SkillBranch%d" % (index + 1)
