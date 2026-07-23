extends CharacterBody2D
class_name NinjaBlue

@export_group("Movement")
@export var speed := 100.0
@export var acceleration := 1000.0
@export var deceleration := 800.0

@export_group("Animation")
@export_range(1.0, 30.0, 0.5) var walking_frames_per_second := 8.0

@onready var sprite: Sprite2D = $Sprite

var movement_direction := Vector2.ZERO
var _facing_direction := Vector2.DOWN
var _walking_frame := 0.0


func _physics_process(delta: float) -> void:
	var direction := movement_direction

	if direction.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		_walking_frame = 0.0
	else:
		_facing_direction = direction
		velocity = velocity.move_toward(
			direction * speed,
			acceleration * delta
		)
		_walking_frame = fmod(
			_walking_frame + walking_frames_per_second * delta,
			4.0
		)

	move_and_slide()
	_update_sprite()


func set_movement_direction(direction: Vector2) -> void:
	movement_direction = direction.limit_length()


func _update_sprite() -> void:
	sprite.frame_coords = Vector2i(
		_direction_to_column(_facing_direction),
		floori(_walking_frame)
	)


func _direction_to_column(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return 3 if direction.x > 0.0 else 2
	return 0 if direction.y > 0.0 else 1
