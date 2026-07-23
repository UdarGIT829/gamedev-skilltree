extends CharacterBody2D
class_name SkillTreeCharacter

@export_group("Movement")
@export var speed := 100.0
@export var acceleration := 1000.0
@export var deceleration := 800.0

@export_group("Dash")
@export var dash_enabled := false:
	set(value):
		dash_enabled = value
		if not dash_enabled:
			_dash_time_remaining = 0.0
@export_range(0.05, 2.0, 0.05, "or_greater") var dash_duration := 0.2
@export_range(0.0, 10000.0, 10.0, "or_greater") var dash_acceleration := 1200.0

@export_group("Jump")
@export_range(0.05, 5.0, 0.05, "or_greater") var jump_duration := 0.5
@export_range(0.0, 256.0, 1.0, "or_greater") var jump_height := 24.0
@export_flags_2d_physics var landing_query_collision_mask := 1
@export_range(1, 256, 1, "or_greater") var landing_query_max_results := 32

@export_group("Animation")
@export var animations_enabled := false:
	set(value):
		animations_enabled = value
		if is_node_ready():
			_update_sprite()
@export var static_frame_coords := Vector2i.ZERO
@export_range(1, 64, 1, "or_greater") var walking_frame_count := 4
@export_range(1.0, 30.0, 0.5) var walking_frames_per_second := 8.0

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var movement_direction := Vector2.ZERO
var _facing_direction := Vector2.DOWN
var _walking_frame := 0.0
var _dash_direction := Vector2.ZERO
var _dash_time_remaining := 0.0
var _is_jumping := false
var _jump_elapsed := 0.0
var _sprite_ground_position := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"skill_tree_characters")
	_sprite_ground_position = sprite.position
	_update_sprite()


func _physics_process(delta: float) -> void:
	var direction := movement_direction

	if _dash_time_remaining > 0.0:
		_facing_direction = _dash_direction
		velocity += _dash_direction * dash_acceleration * delta
		_dash_time_remaining = maxf(_dash_time_remaining - delta, 0.0)
		_advance_walking_animation(delta)
	elif direction.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		_walking_frame = 0.0
	else:
		_facing_direction = direction
		velocity = velocity.move_toward(
			direction * speed,
			acceleration * delta
		)
		_advance_walking_animation(delta)

	move_and_slide()
	_update_jump(delta)
	_update_sprite()


func set_movement_direction(direction: Vector2) -> void:
	movement_direction = direction.limit_length()


func request_dash() -> void:
	if not dash_enabled or _dash_time_remaining > 0.0:
		return

	var direction := velocity.normalized()
	if direction.is_zero_approx():
		direction = movement_direction.normalized()
	if direction.is_zero_approx():
		return

	_dash_direction = direction
	_dash_time_remaining = dash_duration


func _advance_walking_animation(delta: float) -> void:
	if animations_enabled:
		_walking_frame = fmod(
			_walking_frame + walking_frames_per_second * delta,
			float(walking_frame_count)
		)
	else:
		_walking_frame = 0.0


func request_jump() -> void:
	if _is_jumping:
		return
	_is_jumping = true
	_jump_elapsed = 0.0


func _update_jump(delta: float) -> void:
	if not _is_jumping:
		return

	_jump_elapsed += delta
	var jump_progress := minf(_jump_elapsed / jump_duration, 1.0)
	sprite.position = (
		_sprite_ground_position
		+ Vector2.UP * sin(jump_progress * PI) * jump_height
	)

	if jump_progress < 1.0:
		return

	_is_jumping = false
	sprite.position = _sprite_ground_position
	_print_landing_overlaps()


func _print_landing_overlaps() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = landing_query_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var excluded_rids: Array[RID] = [get_rid()]
	query.exclude = excluded_rids

	var hits := get_world_2d().direct_space_state.intersect_shape(
		query,
		landing_query_max_results
	)
	var hit_descriptions: Array[String] = []
	var seen_colliders: Dictionary = {}
	for hit: Dictionary in hits:
		var collider := hit.get("collider") as CollisionObject2D
		if not is_instance_valid(collider):
			continue
		var collider_id := collider.get_instance_id()
		if seen_colliders.has(collider_id):
			continue
		seen_colliders[collider_id] = true
		var hit_skill := _find_skill_node_ancestor(collider)
		if hit_skill != null:
			hit_skill.toggle_activated()
		hit_descriptions.append(_describe_landing_collider(collider, hit_skill))

	print(
		"%s landed at %s; objects underneath: %s"
		% [name, global_position, hit_descriptions]
	)


func _find_skill_node_ancestor(node: Node) -> skill_node:
	var ancestor := node
	while ancestor != null:
		var hit_skill := ancestor as skill_node
		if hit_skill != null:
			return hit_skill
		ancestor = ancestor.get_parent()
	return null


func _describe_landing_collider(
	collider: CollisionObject2D,
	hit_skill: skill_node
) -> String:
	if hit_skill != null:
		var title: String = (
			hit_skill.data.display_name
			if hit_skill.data != null
			else str(hit_skill.name)
		)
		return 'Skill Node "%s" (activated: %s)' % [
			title,
			hit_skill.activated,
		]

	return "%s (%s)" % [collider.get_path(), collider.get_class()]


func _update_sprite() -> void:
	if not animations_enabled:
		sprite.frame_coords = static_frame_coords
		return
	sprite.frame_coords = Vector2i(
		_direction_to_column(_facing_direction),
		floori(_walking_frame)
	)


func _direction_to_column(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return 3 if direction.x > 0.0 else 2
	return 0 if direction.y > 0.0 else 1
