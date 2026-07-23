@tool
extends Node
class_name SkillBranchBuilder

const SKILL_NODE_SCENE: PackedScene = preload("res://skill_node.tscn")
const SKILL_PATH_SCENE: PackedScene = preload("res://skill_path.tscn")
const GENERATED_META := &"skill_branch_builder_generated"
const SKILL_ID_META := &"skill_id"
const GENERATED_KIND_META := &"generated_kind"
const PATH_ID_META := &"path_id"
const NODE_KIND := &"node"
const PATH_KIND := &"path"
const DEFAULT_SPACING := Vector2(260.0, 0.0)

@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		queue_sync()

@export_group("Graph Layout")
@export var graph_layout: bool = true:
	set(value):
		graph_layout = value
		queue_sync()
@export_range(-360.0, 360.0, 1.0) var flow_angle_degrees := 90.0:
	set(value):
		flow_angle_degrees = value
		queue_sync()
@export var layout_center := Vector2.ZERO:
	set(value):
		layout_center = value
		queue_sync()
@export_range(0.0, 5000.0, 10.0, "or_greater") var tier_spacing := 330.0:
	set(value):
		tier_spacing = value
		queue_sync()
@export_range(0.0, 5000.0, 10.0, "or_greater") var sibling_spacing := 300.0:
	set(value):
		sibling_spacing = value
		queue_sync()
@export var center_children_on_parent := true:
	set(value):
		center_children_on_parent = value
		queue_sync()

@export_group("Manual Layout")
@export var spacing: Vector2 = DEFAULT_SPACING:
	set(value):
		spacing = value
		queue_sync()

@export_group("Connections")
@export var build_paths_from_prerequisites: bool = true:
	set(value):
		build_paths_from_prerequisites = value
		queue_sync()

@export_group("Builder")
@export var rebuild_now: bool = false:
	set(value):
		rebuild_now = false
		if value:
			queue_sync()

var _observed_branch_data: SkillBranchData
var _observed_skills: Array[SkillData] = []
var _observed_paths: Array[SkillPathData] = []
var _sync_queued := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		refresh_resource_connections()
		queue_sync()
	else:
		set_process(false)
		sync_skill_nodes()


func _process(_delta: float) -> void:
	# The parent can receive a different resource through the inspector without
	# notifying this child, so watch that reference while editing the scene.
	var branch := get_parent() as skill_branch
	var current_data: SkillBranchData = branch.data if branch != null else null
	if current_data != _observed_branch_data:
		refresh_resource_connections()
		queue_sync()


func queue_sync() -> void:
	if not is_inside_tree() or _sync_queued:
		return
	_sync_queued = true
	call_deferred(&"_run_queued_sync")


func _run_queued_sync() -> void:
	_sync_queued = false
	sync_skill_nodes()


func refresh_resource_connections() -> void:
	_disconnect_resources()

	var branch := get_parent() as skill_branch
	if branch == null:
		return

	_observed_branch_data = branch.data
	if _observed_branch_data == null:
		return

	_observed_branch_data.changed.connect(queue_sync)
	for skill in _observed_branch_data.skills:
		if skill == null or skill in _observed_skills:
			continue
		_observed_skills.append(skill)
		skill.changed.connect(queue_sync)
	for path in _observed_branch_data.paths:
		if path == null or path in _observed_paths:
			continue
		_observed_paths.append(path)
		path.changed.connect(queue_sync)


func _disconnect_resources() -> void:
	if _observed_branch_data != null and _observed_branch_data.changed.is_connected(queue_sync):
		_observed_branch_data.changed.disconnect(queue_sync)
	for skill in _observed_skills:
		if skill != null and skill.changed.is_connected(queue_sync):
			skill.changed.disconnect(queue_sync)
	_observed_skills.clear()
	for path in _observed_paths:
		if path != null and path.changed.is_connected(queue_sync):
			path.changed.disconnect(queue_sync)
	_observed_paths.clear()
	_observed_branch_data = null


func sync_skill_nodes() -> void:
	var branch := get_parent() as skill_branch
	if branch == null:
		push_warning("SkillBranchBuilder must be a direct child of a skill_branch.")
		return

	if Engine.is_editor_hint() and not preview_in_editor:
		_remove_generated_children(branch)
		_queue_area_rebuild(branch)
		return

	var skills: Array[SkillData] = []
	if branch.data != null:
		skills = branch.data.skills
	_compile_claims(branch, skills)

	var existing := _get_generated_children(branch)
	var used_nodes: Array[Node] = []
	var nodes_by_id: Dictionary = {}
	var skill_positions := _calculate_skill_positions(skills)

	for index in skills.size():
		var skill := skills[index]
		if skill == null:
			continue

		var skill_id := StringName(skill.id)
		var skill_node_instance: skill_node = existing.get(skill_id)
		if skill_node_instance == null:
			skill_node_instance = SKILL_NODE_SCENE.instantiate() as skill_node
			branch.add_child(skill_node_instance)
			skill_node_instance.owner = _get_scene_owner(branch)

		skill_node_instance.set_meta(GENERATED_META, true)
		skill_node_instance.set_meta(GENERATED_KIND_META, NODE_KIND)
		skill_node_instance.set_meta(SKILL_ID_META, skill_id)
		skill_node_instance.name = _node_name_for(skill, index)
		skill_node_instance.data = skill
		skill_node_instance.progress = branch.progress
		skill_node_instance.set_marker_flow_angle(flow_angle_degrees)
		skill_node_instance.position = skill_positions.get(skill_id, spacing * index)
		# During scene instantiation the branch may still be attaching its
		# authored children. Godot rejects an immediate reorder in that window.
		if branch.is_node_ready():
			branch.move_child(skill_node_instance, index)
		else:
			branch.move_child.call_deferred(skill_node_instance, index)
		used_nodes.append(skill_node_instance)
		nodes_by_id[skill_id] = skill_node_instance

		if skill_node_instance.is_node_ready():
			skill_node_instance.refresh()


	var existing_paths := _get_generated_paths(branch)
	var used_paths: Array[Node] = []
	if branch.data != null:
		for path_data in _compile_paths(branch.data, skills):
			if path_data == null or path_data.source == null or path_data.destination == null:
				continue

			# Avoid calling resource methods from editor tools: Godot can retain
			# newly tool-enabled resources as placeholders until a full reload.
			var path_id := StringName("%s->%s" % [
				path_data.source.id,
				path_data.destination.id,
			])
			var path_instance: skill_path = existing_paths.get(path_id)
			if path_instance == null:
				path_instance = SKILL_PATH_SCENE.instantiate() as skill_path
				branch.add_child(path_instance)
				path_instance.owner = _get_scene_owner(branch)

			path_instance.set_meta(GENERATED_META, true)
			path_instance.set_meta(GENERATED_KIND_META, PATH_KIND)
			path_instance.set_meta(PATH_ID_META, path_id)
			path_instance.name = _path_name_for(path_data)
			path_instance.data = path_data
			path_instance.connect_nodes(
				nodes_by_id.get(path_data.source.id),
				nodes_by_id.get(path_data.destination.id)
			)
			used_paths.append(path_instance)

	for child in branch.get_children():
		if child.get_meta(GENERATED_META, false) and child not in used_nodes and child not in used_paths:
			child.queue_free()

	refresh_resource_connections()
	_queue_area_rebuild(branch)


func _queue_area_rebuild(branch: skill_branch) -> void:
	var area_component := branch.get_node_or_null(
		"area_2d_component"
	) as BranchArea2DComponent
	if area_component != null:
		area_component.queue_rebuild()


func _compile_paths(branch_data: SkillBranchData, skills: Array[SkillData]) -> Array[SkillPathData]:
	var compiled_paths: Array[SkillPathData] = []
	var path_ids: Dictionary = {}

	# Explicit paths remain useful for optional, cross-tier, or decorative links.
	for path_data in branch_data.paths:
		if path_data == null or path_data.source == null or path_data.destination == null:
			continue
		var path_id := _path_id(path_data.source, path_data.destination)
		if path_ids.has(path_id):
			continue
		compiled_paths.append(path_data)
		path_ids[path_id] = true

	if not build_paths_from_prerequisites:
		return compiled_paths

	var skills_by_id: Dictionary = {}
	for skill in skills:
		if skill != null and not skill.id.is_empty():
			skills_by_id[skill.id] = skill

	for destination in skills:
		if destination == null:
			continue
		for prerequisite_id in destination.prerequisite_ids:
			var source: SkillData = skills_by_id.get(prerequisite_id)
			if source == null:
				continue
			var path_id := _path_id(source, destination)
			if path_ids.has(path_id):
				continue
			var derived_path := SkillPathData.new()
			derived_path.source = source
			derived_path.destination = destination
			compiled_paths.append(derived_path)
			path_ids[path_id] = true

	return compiled_paths


func _calculate_skill_positions(skills: Array[SkillData]) -> Dictionary:
	var positions: Dictionary = {}
	if not graph_layout:
		for index in skills.size():
			if skills[index] != null:
				positions[skills[index].id] = spacing * index
		return positions

	var skills_by_tier: Dictionary = {}
	var skill_order: Dictionary = {}
	var skills_by_id: Dictionary = {}
	var children_by_parent: Dictionary = {}
	var minimum_tier := 2147483647
	for index in skills.size():
		var skill := skills[index]
		if skill == null:
			continue
		skill_order[skill.id] = index
		skills_by_id[skill.id] = skill
		var tier := maxi(skill.tier, 1)
		minimum_tier = mini(minimum_tier, tier)
		if not skills_by_tier.has(tier):
			skills_by_tier[tier] = []
		skills_by_tier[tier].append(skill)

	# Build sibling groups once for the whole branch. A parent's children may
	# occupy different tiers, but they still belong to the same visual fan.
	for skill in skills:
		if skill == null:
			continue
		for prerequisite_id in skill.prerequisite_ids:
			if not skills_by_id.has(prerequisite_id):
				continue
			if not children_by_parent.has(prerequisite_id):
				children_by_parent[prerequisite_id] = []
			children_by_parent[prerequisite_id].append(skill.id)

	if skills_by_tier.is_empty():
		return positions

	var tiers: Array = skills_by_tier.keys()
	tiers.sort()
	var cross_positions: Dictionary = {}

	for tier in tiers:
		var tier_skills: Array = skills_by_tier[tier]
		var desired_entries: Array[Dictionary] = []

		for tier_index in tier_skills.size():
			var skill: SkillData = tier_skills[tier_index]
			var prerequisite_total := 0.0
			var resolved_prerequisites := 0
			for prerequisite_id in skill.prerequisite_ids:
				if cross_positions.has(prerequisite_id):
					prerequisite_total += float(cross_positions[prerequisite_id])
					resolved_prerequisites += 1

			var desired_cross: float
			if resolved_prerequisites > 0:
				# Continuations keep their lane; convergence lands midway between
				# all of its incoming prerequisite lanes.
				desired_cross = prerequisite_total / resolved_prerequisites
				if center_children_on_parent and resolved_prerequisites == 1:
					var parent_id: StringName = skill.prerequisite_ids[0]
					var siblings: Array = children_by_parent.get(parent_id, [])
					var child_index := siblings.find(skill.id)
					if child_index >= 0:
						var centered_child_index := child_index - (siblings.size() - 1) * 0.5
						desired_cross += centered_child_index * sibling_spacing
			else:
				# Root skills, or skills whose prerequisites live in another
				# branch, begin centered as a group.
				desired_cross = (tier_index - (tier_skills.size() - 1) * 0.5) * sibling_spacing

			desired_entries.append({
				"skill": skill,
				"desired": desired_cross,
				"order": skill_order.get(skill.id, tier_index),
			})

		# Keep connected lanes adjacent. Original resource order provides a
		# stable tie-breaker when siblings share the same parent position.
		desired_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if is_equal_approx(a.desired, b.desired):
				return a.order < b.order
			return a.desired < b.desired
		)

		var actual_crosses: Array[float] = []
		for entry in desired_entries:
			var actual := float(entry.desired)
			if not actual_crosses.is_empty():
				actual = maxf(actual, actual_crosses[-1] + sibling_spacing)
			actual_crosses.append(actual)

		# Collision resolution pushes nodes apart. Recenter that pushed group
		# around its original desired average so divergence remains balanced.
		var desired_average := 0.0
		var actual_average := 0.0
		for entry in desired_entries:
			desired_average += float(entry.desired)
		for actual in actual_crosses:
			actual_average += actual
		if not desired_entries.is_empty():
			desired_average /= desired_entries.size()
			actual_average /= actual_crosses.size()
		var recenter_offset := desired_average - actual_average

		var layer_offset := float(tier - minimum_tier) * tier_spacing
		for entry_index in desired_entries.size():
			var skill: SkillData = desired_entries[entry_index].skill
			var sibling_offset := actual_crosses[entry_index] + recenter_offset
			cross_positions[skill.id] = sibling_offset
			var flow_vector := Vector2.from_angle(deg_to_rad(flow_angle_degrees))
			var cross_vector := flow_vector.orthogonal()
			positions[skill.id] = (
				layout_center
				+ flow_vector * layer_offset
				+ cross_vector * sibling_offset
			)

	return positions
func _path_id(source: SkillData, destination: SkillData) -> StringName:
	return StringName("%s->%s" % [source.id, destination.id])


func _get_generated_children(branch: skill_branch) -> Dictionary:
	var result: Dictionary = {}
	for child in branch.get_children():
		if not child.get_meta(GENERATED_META, false):
			continue
		# Nodes created before path support have no kind metadata, so retain them.
		if child.get_meta(GENERATED_KIND_META, NODE_KIND) != NODE_KIND:
			continue
		var skill_id: StringName = child.get_meta(SKILL_ID_META, &"")
		if not skill_id.is_empty():
			result[skill_id] = child
	return result


func _compile_claims(branch: skill_branch, skills: Array[SkillData]) -> void:
	var ordered_claims: Array[String] = []
	var ordered_skill_ids: Array[StringName] = []
	for skill in skills:
		ordered_claims.append(skill.claim if skill != null else "")
		ordered_skill_ids.append(skill.id if skill != null else &"")
	branch.claims = ordered_claims
	branch.claim_skill_ids = ordered_skill_ids


func _get_generated_paths(branch: skill_branch) -> Dictionary:
	var result: Dictionary = {}
	for child in branch.get_children():
		if not child.get_meta(GENERATED_META, false):
			continue
		if child.get_meta(GENERATED_KIND_META, &"") != PATH_KIND:
			continue
		var path_id: StringName = child.get_meta(PATH_ID_META, &"")
		if not path_id.is_empty():
			result[path_id] = child
	return result


func _remove_generated_children(branch: skill_branch) -> void:
	for child in branch.get_children():
		if child.get_meta(GENERATED_META, false):
			child.queue_free()


func _get_scene_owner(branch: Node) -> Node:
	if Engine.is_editor_hint() and branch.get_tree() != null:
		return branch.get_tree().edited_scene_root
	return branch.owner


func _node_name_for(skill: SkillData, index: int) -> String:
	if not skill.id.is_empty():
		return String(skill.id)
	return "SkillNode%d" % (index + 1)


func _path_name_for(path_data: SkillPathData) -> String:
	return "%s_to_%s" % [path_data.source.id, path_data.destination.id]
