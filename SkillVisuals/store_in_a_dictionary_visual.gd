extends Control

@export var customer_names: Array[String] = ["Taylor", "Morgan", "Riley"]
@export var garment_colors: Array[Color] = [
	Color("315f9f"),
	Color("b63868"),
	Color("d08a2f"),
]
@export_group("Timing")
## Multiplies every animation and pause duration. Higher values are slower.
@export_range(0.25, 4.0, 0.05, "or_greater") var timing_scale := 1.5

const PERSON_OFFSCREEN := Vector2(-112.0, 158.0)
const PERSON_AT_COUNTER := Vector2(-4.0, 158.0)
const GARMENT_OFFSCREEN := Vector2(-92.0, 108.0)
const GARMENT_AT_COUNTER := Vector2(59.0, 102.0)
const GARMENT_THROWN_OFFSCREEN := Vector2(330.0, -92.0)
const GARMENT_WITH_CUSTOMER := Vector2(48.0, 133.0)
const ENTRY_GARMENT_SCALE := Vector2(0.48, 0.48)
const PICKUP_GARMENT_SCALE := Vector2(0.42, 0.42)
const NORMAL_LABEL_COLOR := Color("f4f7fb")
const GLOW_LABEL_COLOR := Color("ffe36b")
const GLOW_OUTLINE_COLOR := Color("d77822")

@onready var tuxedo_template: Control = $tuxedo
@onready var dress_template: Control = $dress
@onready var person: Control = $person
@onready var person_name_label: Label = $person/Label

# This is the idea being visualized: a name is the key used to retrieve the
# correct garment, regardless of the order customers return in.
var _clothes_by_name: Dictionary = {}
var _generated_garments: Array[Control] = []
var _active_names: Array[String] = []
var _landed_garment_count := 0


func _ready() -> void:
	randomize()
	tuxedo_template.hide()
	dress_template.hide()
	person.hide()
	call_deferred(&"_run_demo")


func _run_demo() -> void:
	_build_active_name_list()
	if _active_names.is_empty():
		push_warning("The dictionary visual needs at least one unique customer name.")
		return

	while is_inside_tree():
		_reset_cycle()
		await _run_dropoff_phase()
		await _wait(0.9)
		await _run_pickup_phase()
		await _wait(1.8)


func _build_active_name_list() -> void:
	_active_names.clear()
	for customer_name in customer_names:
		var cleaned_name := customer_name.strip_edges()
		if cleaned_name.is_empty() or cleaned_name in _active_names:
			continue
		_active_names.append(cleaned_name)


func _reset_cycle() -> void:
	for garment in _generated_garments:
		if is_instance_valid(garment):
			garment.free()
	_generated_garments.clear()
	_clothes_by_name.clear()
	_landed_garment_count = 0
	person.hide()
	person.position = PERSON_OFFSCREEN
	_set_name_glow(person_name_label, false)


func _run_dropoff_phase() -> void:
	var hanger_scale := _get_hanger_scale()
	for index in _active_names.size():
		var customer_name := _active_names[index]
		var garment := _create_customer_garment(customer_name, index)
		var hanger_position := _get_hanger_position(index, garment, hanger_scale)

		person_name_label.text = customer_name
		person.position = PERSON_OFFSCREEN
		person.show()
		garment.position = GARMENT_OFFSCREEN
		garment.scale = ENTRY_GARMENT_SCALE
		garment.rotation = 0.0
		garment.show()

		var entrance := create_tween().set_parallel(true)
		entrance.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		entrance.tween_property(person, "position", PERSON_AT_COUNTER, _duration(0.55))
		entrance.tween_property(garment, "position", GARMENT_AT_COUNTER, _duration(0.55))
		await entrance.finished
		await _wait(0.28)

		# The cleaner throws the garment out of view. Its delayed landing runs
		# independently, allowing the next customer to enter immediately.
		var throw_direction := -0.5 if index % 2 == 0 else 0.5
		var garment_throw := create_tween().set_parallel(true)
		garment_throw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		garment_throw.tween_property(
			garment,
			"position",
			GARMENT_THROWN_OFFSCREEN,
			_duration(0.38)
		)
		garment_throw.tween_property(
			garment,
			"rotation",
			throw_direction,
			_duration(0.38)
		)

		var customer_exit := create_tween()
		customer_exit.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		customer_exit.tween_property(person, "position", PERSON_OFFSCREEN, _duration(0.45))
		_land_garment_after_one_second(garment, hanger_position, hanger_scale)
		await customer_exit.finished
		person.hide()

	while _landed_garment_count < _active_names.size():
		await _wait(0.05)


func _run_pickup_phase() -> void:
	var pickup_order := _active_names.duplicate()
	pickup_order.shuffle()
	# A valid shuffle can occasionally return the original order. Rotate that
	# case so the demonstration always visibly proves that name lookup, rather
	# than arrival position, selects the garment.
	if pickup_order.size() > 1 and pickup_order == _active_names:
		pickup_order.push_back(pickup_order.pop_front())

	for customer_name in pickup_order:
		var garment: Control = _clothes_by_name.get(customer_name)
		if not is_instance_valid(garment):
			continue
		var garment_name_label := _get_garment_name_label(garment)

		person_name_label.text = customer_name
		person.position = PERSON_OFFSCREEN
		person.show()
		var entrance := create_tween()
		entrance.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		entrance.tween_property(person, "position", PERSON_AT_COUNTER, _duration(0.5))
		await entrance.finished

		_set_name_glow(person_name_label, true)
		_set_name_glow(garment_name_label, true)
		await _pulse_matching_names(person_name_label, garment_name_label)

		var return_tween := create_tween().set_parallel(true)
		return_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		return_tween.tween_property(
			garment,
			"position",
			GARMENT_WITH_CUSTOMER,
			_duration(0.65)
		)
		return_tween.tween_property(
			garment,
			"scale",
			PICKUP_GARMENT_SCALE,
			_duration(0.65)
		)
		return_tween.tween_property(garment, "rotation", 0.0, _duration(0.65))
		await return_tween.finished
		await _wait(0.22)

		_set_name_glow(person_name_label, false)
		_set_name_glow(garment_name_label, false)
		var exit_tween := create_tween().set_parallel(true)
		exit_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(person, "position", PERSON_OFFSCREEN, _duration(0.52))
		exit_tween.tween_property(garment, "position", GARMENT_OFFSCREEN, _duration(0.52))
		await exit_tween.finished
		person.hide()
		garment.hide()
		await _wait(0.2)


func _create_customer_garment(customer_name: String, index: int) -> Control:
	var template := tuxedo_template if index % 2 == 0 else dress_template
	var garment := template.duplicate() as Control
	garment.name = "Garment_%s" % customer_name.validate_node_name()
	garment.z_index = 1
	add_child(garment)
	_generated_garments.append(garment)
	_clothes_by_name[customer_name] = garment

	var name_label := _get_garment_name_label(garment)
	name_label.text = customer_name
	_set_name_glow(name_label, false)
	_apply_garment_color(garment, _get_customer_color(index))
	return garment


func _land_garment_after_one_second(
	garment: Control,
	hanger_position: Vector2,
	hanger_scale: Vector2
) -> void:
	# 0.55 plus 0.45 equals one base timing unit from throw to hanger. The
	# exported timing_scale stretches that unit along with the rest of the demo.
	await _wait(0.55)
	if not is_instance_valid(garment):
		return
	var landing := create_tween().set_parallel(true)
	landing.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	landing.tween_property(garment, "position", hanger_position, _duration(0.45))
	landing.tween_property(garment, "scale", hanger_scale, _duration(0.45))
	landing.tween_property(garment, "rotation", 0.0, _duration(0.45))
	await landing.finished
	_landed_garment_count += 1


func _get_hanger_scale() -> Vector2:
	var scale_value := clampf(1.25 / float(_active_names.size()), 0.22, 0.42)
	return Vector2.ONE * scale_value


func _get_hanger_position(index: int, garment: Control, hanger_scale: Vector2) -> Vector2:
	var slot_width := 258.0 / float(_active_names.size())
	var slot_center_x := 21.0 + slot_width * (float(index) + 0.5)
	var garment_center_x := 65.0 if garment.get_meta(&"garment_type") == &"tuxedo" else 53.0
	return Vector2(slot_center_x - garment_center_x * hanger_scale.x, 47.0)


func _get_customer_color(index: int) -> Color:
	if garment_colors.is_empty():
		return Color("497db8")
	return garment_colors[index % garment_colors.size()]


func _apply_garment_color(garment: Control, color: Color) -> void:
	for child in garment.find_children("*", "ColorRect", true, false):
		var color_rect := child as ColorRect
		if color_rect != null and color_rect.get_meta(&"color_channel", &"") == &"fabric":
			color_rect.color = color


func _get_garment_name_label(garment: Control) -> Label:
	return garment.get_node("Label") as Label


func _set_name_glow(label: Label, enabled: bool) -> void:
	if not is_instance_valid(label):
		return
	label.modulate = Color.WHITE
	label.add_theme_color_override(
		&"font_color",
		GLOW_LABEL_COLOR if enabled else NORMAL_LABEL_COLOR
	)
	label.add_theme_color_override(&"font_outline_color", GLOW_OUTLINE_COLOR)
	label.add_theme_constant_override(&"outline_size", 4 if enabled else 0)


func _pulse_matching_names(person_label: Label, garment_label: Label) -> void:
	var pulse := create_tween().set_loops(2)
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(
		person_label,
		"modulate",
		Color(1.0, 0.78, 0.3, 1.0),
		_duration(0.18)
	)
	pulse.parallel().tween_property(
		garment_label,
		"modulate",
		Color(1.0, 0.78, 0.3, 1.0),
		_duration(0.18)
	)
	pulse.tween_property(person_label, "modulate", Color.WHITE, _duration(0.18))
	pulse.parallel().tween_property(
		garment_label,
		"modulate",
		Color.WHITE,
		_duration(0.18)
	)
	await pulse.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(_duration(seconds)).timeout


func _duration(base_seconds: float) -> float:
	return base_seconds * maxf(timing_scale, 0.01)
