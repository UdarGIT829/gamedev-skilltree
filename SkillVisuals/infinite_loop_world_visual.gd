extends Control
class_name InfiniteLoopWorldVisual

const MAX_SMALL_ROCKS := 48
const WORLD_FEATURE_GROUP := &"skill_tree_world_feature_visuals"
const LEFT_GROUND_POSITION := Vector2(45.0, 190.0)
const RIGHT_GROUND_POSITION := Vector2(205.0, 190.0)
const ROCK_TOP_POSITION := Vector2(145.0, 119.0)
const SMALL_ROCK_SPAWN_POSITION := Vector2(145.0, 139.0)
const SMALL_ROCK_GROUND_Y := 207.0

@export_group("Feature State")
@export var activation_skill_id := &"createwithloops"
@export var enabled := false:
	set(value):
		enabled = value
		_apply_enabled_state()
@export var animations_enabled := false:
	set(value):
		animations_enabled = value
		_update_ninja_visual()
@export var static_frame_coords := Vector2i.ZERO

@export_group("Loop Timing")
@export_range(0.1, 2.0, 0.05, "or_greater") var jump_to_rock_seconds := 0.55
@export_range(0.1, 2.0, 0.05, "or_greater") var jump_to_ground_seconds := 0.5
@export_range(0.0, 1.0, 0.01, "or_greater") var impact_pause_seconds := 0.1
@export_range(0.0, 5.0, 0.05, "or_greater") var repeat_delay_seconds := 1.0

@export_group("Jump Shape")
@export_range(0.0, 160.0, 1.0, "or_greater") var jump_to_rock_height := 54.0
@export_range(0.0, 160.0, 1.0, "or_greater") var jump_to_ground_height := 42.0

@export_group("Small Rock Physics")
@export_range(0.0, 1000.0, 10.0, "or_greater") var small_rock_gravity := 330.0
@export_range(0.0, 500.0, 5.0, "or_greater") var minimum_side_speed := 45.0
@export_range(0.0, 500.0, 5.0, "or_greater") var maximum_side_speed := 80.0
@export_range(0.0, 500.0, 5.0, "or_greater") var minimum_upward_speed := 70.0
@export_range(0.0, 500.0, 5.0, "or_greater") var maximum_upward_speed := 115.0

@onready var ninja: Sprite2D = $World/NinjaBlueVisual
@onready var small_rocks: MultiMeshInstance2D = $World/SmallRocks
@onready var loop_timer: Timer = $LoopTimer

var _rng := RandomNumberGenerator.new()
var _rock_positions: Array[Vector2] = []
var _rock_velocities: Array[Vector2] = []
var _rock_rotations: Array[float] = []
var _rock_angular_velocities: Array[float] = []
var _rock_scales: Array[float] = []
var _rock_active: Array[bool] = []
var _active_rock_count := 0
var _next_rock_index := 0
var _traveling_right := true
var _ninja_facing_column := 3
var _ninja_animation_frame := 0


func _ready() -> void:
	add_to_group(WORLD_FEATURE_GROUP)
	_rng.randomize()
	_setup_small_rock_multimesh()
	ninja.position = LEFT_GROUND_POSITION
	_set_ninja_facing(Vector2.RIGHT)
	_apply_enabled_state()
	_run_infinite_loop.call_deferred()


func _process(delta: float) -> void:
	for index in _active_rock_count:
		if not _rock_active[index]:
			continue
		var velocity := _rock_velocities[index]
		if not velocity.is_zero_approx():
			velocity.y += small_rock_gravity * delta
			_rock_positions[index] += velocity * delta
			_rock_rotations[index] += _rock_angular_velocities[index] * delta
			if _rock_positions[index].y >= SMALL_ROCK_GROUND_Y:
				_rock_positions[index].y = SMALL_ROCK_GROUND_Y
				velocity = Vector2.ZERO
				_rock_angular_velocities[index] = 0.0
			_rock_velocities[index] = velocity
		_update_small_rock_transform(index)


func _apply_enabled_state() -> void:
	visible = enabled
	process_mode = (
		Node.PROCESS_MODE_INHERIT
		if enabled
		else Node.PROCESS_MODE_DISABLED
	)


func _setup_small_rock_multimesh() -> void:
	var multimesh := small_rocks.multimesh
	multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.instance_count = MAX_SMALL_ROCKS
	multimesh.visible_instance_count = 0

	_rock_positions.resize(MAX_SMALL_ROCKS)
	_rock_velocities.resize(MAX_SMALL_ROCKS)
	_rock_rotations.resize(MAX_SMALL_ROCKS)
	_rock_angular_velocities.resize(MAX_SMALL_ROCKS)
	_rock_scales.resize(MAX_SMALL_ROCKS)
	_rock_active.resize(MAX_SMALL_ROCKS)
	for index in MAX_SMALL_ROCKS:
		_rock_positions[index] = Vector2.ZERO
		_rock_velocities[index] = Vector2.ZERO
		_rock_rotations[index] = 0.0
		_rock_angular_velocities[index] = 0.0
		_rock_scales[index] = 0.02
		_rock_active[index] = false


func _run_infinite_loop() -> void:
	while is_inside_tree():
		var ground_target := (
			RIGHT_GROUND_POSITION
			if _traveling_right
			else LEFT_GROUND_POSITION
		)

		_set_ninja_facing(ROCK_TOP_POSITION - ninja.position)
		await _jump_ninja_to(
			ROCK_TOP_POSITION,
			jump_to_rock_height,
			jump_to_rock_seconds
		)
		if not is_inside_tree():
			return

		_spawn_small_rock()
		_set_ninja_animation_frame(0)
		await _wait_for_loop_time(impact_pause_seconds)
		if not is_inside_tree():
			return

		_set_ninja_facing(ground_target - ninja.position)
		await _jump_ninja_to(
			ground_target,
			jump_to_ground_height,
			jump_to_ground_seconds
		)
		if not is_inside_tree():
			return

		_set_ninja_animation_frame(0)
		_traveling_right = not _traveling_right
		await _wait_for_loop_time(repeat_delay_seconds)


func _wait_for_loop_time(duration: float) -> void:
	if duration <= 0.0:
		return
	loop_timer.start(duration)
	await loop_timer.timeout


func _jump_ninja_to(
	target: Vector2,
	jump_height: float,
	duration: float
) -> void:
	var start := ninja.position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(progress: float) -> void:
			ninja.position = (
				start.lerp(target, progress)
				+ Vector2.UP * sin(progress * PI) * jump_height
			)
			_set_ninja_animation_frame(clampi(
				floori(progress * 4.0),
				0,
				3
			)),
		0.0,
		1.0,
		duration
	)
	await tween.finished
	ninja.position = target


func _set_ninja_facing(direction: Vector2) -> void:
	_ninja_facing_column = 3 if direction.x >= 0.0 else 2
	_update_ninja_visual()


func _set_ninja_animation_frame(frame_index: int) -> void:
	_ninja_animation_frame = frame_index
	_update_ninja_visual()


func _update_ninja_visual() -> void:
	if not is_node_ready():
		return
	ninja.frame_coords = (
		Vector2i(_ninja_facing_column, _ninja_animation_frame)
		if animations_enabled
		else static_frame_coords
	)


func _spawn_small_rock() -> void:
	var index := _next_rock_index
	_next_rock_index = (_next_rock_index + 1) % MAX_SMALL_ROCKS
	_active_rock_count = mini(_active_rock_count + 1, MAX_SMALL_ROCKS)

	var side := -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
	_rock_positions[index] = SMALL_ROCK_SPAWN_POSITION
	_rock_velocities[index] = Vector2(
		side * _rng.randf_range(minimum_side_speed, maximum_side_speed),
		-_rng.randf_range(minimum_upward_speed, maximum_upward_speed)
	)
	_rock_rotations[index] = _rng.randf_range(-PI, PI)
	_rock_angular_velocities[index] = _rng.randf_range(-5.0, 5.0)
	_rock_scales[index] = _rng.randf_range(0.016, 0.023)
	_rock_active[index] = true
	small_rocks.multimesh.visible_instance_count = _active_rock_count
	_update_small_rock_transform(index)


func _update_small_rock_transform(index: int) -> void:
	var transform := Transform2D(
		_rock_rotations[index],
		Vector2.ONE * _rock_scales[index],
		0.0,
		_rock_positions[index]
	)
	small_rocks.multimesh.set_instance_transform_2d(index, transform)
