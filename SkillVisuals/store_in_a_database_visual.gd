extends Control

## A recipe database is represented by the three cards in the kitchen.
## Customers request a recipe by ID at the register. The kitchen retrieves the
## matching structured record and uses its other fields to prepare the meal.
@export var recipe_records: Array[Dictionary] = [
	{
		"id": "tomato_soup",
		"customer": "Maya",
		"meal": "Tomato Soup",
		"price": 8,
		"cook_seconds": 3,
		"color": Color("d95f45"),
	},
	{
		"id": "veggie_wrap",
		"customer": "Noah",
		"meal": "Veggie Wrap",
		"price": 10,
		"cook_seconds": 2,
		"color": Color("69a84f"),
	},
	{
		"id": "berry_pie",
		"customer": "Iris",
		"meal": "Berry Pie",
		"price": 6,
		"cook_seconds": 4,
		"color": Color("a85b86"),
	},
]

@export_group("Timing")
## Multiplies every movement and pause. Higher values make the demonstration slower.
@export_range(0.25, 4.0, 0.05, "or_greater") var timing_scale := 1.25
@export_range(0.2, 3.0, 0.05, "or_greater") var camera_pan_seconds := 1.0

const REGISTER_CAMERA_POSITION := Vector2(150.0, 150.0)
const KITCHEN_CAMERA_POSITION := Vector2(520.0, 150.0)
const CUSTOMER_OFFSCREEN_POSITION := Vector2(-105.0, 102.0)
const CUSTOMER_COUNTER_POSITION := Vector2(35.0, 102.0)
const CUSTOMER_EXIT_POSITION := Vector2(-105.0, 102.0)
const CHEF_HOME_POSITION := Vector2(380.0, 48.0)
const CHEF_WORK_POSITION := Vector2(405.0, 48.0)
const CARD_NORMAL_COLORS: Array[Color] = [
	Color("f2c764"),
	Color("96c785"),
	Color("db6647"),
]
const CARD_GLOW_COLOR := Color("fff19a")
const TEXT_COLOR := Color("f5f0df")
const ACCENT_COLOR := Color("ffd166")
const SUCCESS_COLOR := Color("7ce7a7")
const DECK_POSITION := Vector2(515.0, 72.0)
const DECK_CARD_SIZE := Vector2(112.0, 76.0)

@onready var world: Control = $VisualViewportContainer/VisualViewport/RestaurantWorld
@onready var visual_camera: Camera2D = $VisualViewportContainer/VisualViewport/VisualCamera
@onready var customer: TextureRect = $VisualViewportContainer/VisualViewport/RestaurantWorld/customer
@onready var chef: TextureRect = $VisualViewportContainer/VisualViewport/RestaurantWorld/chef
@onready var interior: Control = $VisualViewportContainer/VisualViewport/RestaurantWorld/RestaurantInterior
@onready var register_screen: ColorRect = $VisualViewportContainer/VisualViewport/RestaurantWorld/RestaurantInterior/Register/RegisterScreen
@onready var price_display: Label = $VisualViewportContainer/VisualViewport/RestaurantWorld/RestaurantInterior/Register/PriceDisplay
@onready var timer_display: Label = $VisualViewportContainer/VisualViewport/RestaurantWorld/RestaurantInterior/KitchenTimer/TimerDisplay

var _recipe_slots: Array[ColorRect] = []
var _overlay: Control
var _customer_name: Label
var _speech_panel: ColorRect
var _speech_text: Label
var _request_card: ColorRect
var _request_id: Label
var _database_panel: ColorRect
var _database_title: Label
var _database_fields: Label
var _status_left: Label
var _status_right: Label
var _meal: ColorRect
var _meal_label: Label
var _deck_cards: Array[ColorRect] = []


func _ready() -> void:
	_recipe_slots = [
		interior.get_node("RecipeBox/RecipeCardSlot0") as ColorRect,
		interior.get_node("RecipeBox/RecipeCardSlot1") as ColorRect,
		interior.get_node("RecipeBox/RecipeCardSlot2") as ColorRect,
	]
	_build_runtime_visuals()
	_reset_demo()
	call_deferred(&"_run_demo")


func _run_demo() -> void:
	if recipe_records.is_empty():
		push_warning("The database visual needs at least one recipe record.")
		return

	while is_inside_tree():
		_reset_demo()
		for index in recipe_records.size():
			if not is_inside_tree():
				return
			await _demonstrate_record(recipe_records[index], index)
		await _show_database_summary()
		await _wait(2.0)


func _demonstrate_record(record: Dictionary, index: int) -> void:
	var recipe_id := str(record.get("id", "unknown_recipe"))
	var customer_name := str(record.get("customer", "Customer"))
	var meal_name := str(record.get("meal", "Meal"))
	var price := int(record.get("price", 0))
	var cook_seconds := maxi(int(record.get("cook_seconds", 1)), 1)
	var meal_color: Color = record.get("color", Color("d95f45"))

	await _move_camera_to(REGISTER_CAMERA_POSITION)
	_prepare_customer(customer_name)
	_status_left.text = "1. Request a recipe by its unique ID"
	_status_left.show()
	await _enter_customer()

	_speech_text.text = "Can I have\n%s?" % meal_name
	_speech_panel.show()
	await _wait(0.9)

	_request_id.text = "ID\n%s" % recipe_id
	_request_card.position = Vector2(137.0, 91.0)
	_request_card.show()
	_status_left.text = "SEARCH  id = \"%s\"" % recipe_id
	await _wait(0.6)
	await _move_request_to_register()

	price_display.text = "$%d" % price
	await _flash_control(register_screen, ACCENT_COLOR)
	_status_left.text = "Request sent — the ID finds one record"
	await _wait(0.7)
	await _exit_customer()
	_speech_panel.hide()
	_request_card.hide()

	await _move_camera_to(KITCHEN_CAMERA_POSITION)
	_status_right.text = "2. Find the matching recipe record"
	_status_right.show()
	await _reveal_database_record(record, index)

	_status_right.text = "3. Use the fields stored in that record"
	await _cook_meal(meal_name, meal_color, cook_seconds)
	_database_title.text = "✓  RECORD COMPLETE"
	_database_title.add_theme_color_override(&"font_color", SUCCESS_COLOR)
	_status_right.text = "%s is ready!" % meal_name
	await _wait(0.9)

	await _move_camera_to(REGISTER_CAMERA_POSITION)
	_prepare_customer(customer_name)
	await _enter_customer()
	_speech_text.text = "That is my\n%s!" % meal_name
	_speech_panel.show()
	_meal.position = Vector2(225.0, 128.0)
	_meal.show()
	var return_meal := create_tween().set_parallel(true)
	return_meal.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return_meal.tween_property(_meal, "position", Vector2(92.0, 132.0), _duration(0.7))
	return_meal.tween_property(_meal, "rotation", -0.08, _duration(0.7))
	await return_meal.finished
	_status_left.text = "The right data returned to %s" % customer_name
	await _wait(0.7)

	var exit := create_tween().set_parallel(true)
	exit.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	exit.tween_property(customer, "position", CUSTOMER_EXIT_POSITION, _duration(0.55))
	exit.tween_property(_meal, "position", Vector2(-70.0, 132.0), _duration(0.55))
	await exit.finished
	customer.hide()
	_meal.hide()
	_speech_panel.hide()
	_status_left.hide()
	_database_panel.hide()
	_status_right.hide()
	_reset_recipe_slots()
	await _wait(0.35)


func _show_database_summary() -> void:
	await _move_camera_to(KITCHEN_CAMERA_POSITION)
	_database_panel.position = Vector2(474.0, 53.0)
	_database_panel.size = Vector2(205.0, 102.0)
	_database_title.text = "RECIPE DATABASE"
	_database_title.add_theme_color_override(&"font_color", ACCENT_COLOR)
	var summary_lines: Array[String] = []
	for record in recipe_records:
		summary_lines.append(
			"%s  →  %s" % [
				str(record.get("id", "?")),
				str(record.get("meal", "Meal")),
			]
		)
	_database_fields.text = "\n".join(summary_lines)
	_database_panel.show()
	_status_right.text = "Many structured records, retrieved by ID"
	_status_right.show()
	for index in _recipe_slots.size():
		await _flash_control(_recipe_slots[index], CARD_GLOW_COLOR, 0.22)


func _prepare_customer(customer_name: String) -> void:
	customer.position = CUSTOMER_OFFSCREEN_POSITION
	customer.show()
	customer.modulate = Color.WHITE
	_customer_name.text = customer_name
	_customer_name.position = Vector2(26.0, 83.0)
	_customer_name.show()
	_speech_panel.hide()


func _enter_customer() -> void:
	_customer_name.position = Vector2(-114.0, 83.0)
	var entrance := create_tween().set_parallel(true)
	entrance.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	entrance.tween_property(customer, "position", CUSTOMER_COUNTER_POSITION, _duration(0.6))
	entrance.tween_property(_customer_name, "position", Vector2(26.0, 83.0), _duration(0.6))
	await entrance.finished


func _exit_customer() -> void:
	var exit := create_tween().set_parallel(true)
	exit.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	exit.tween_property(customer, "position", CUSTOMER_EXIT_POSITION, _duration(0.5))
	exit.tween_property(_customer_name, "position", Vector2(-114.0, 83.0), _duration(0.5))
	await exit.finished
	customer.hide()
	_customer_name.hide()


func _move_request_to_register() -> void:
	var request_tween := create_tween()
	request_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	request_tween.tween_property(
		_request_card,
		"position",
		Vector2(236.0, 82.0),
		_duration(0.65)
	)
	await request_tween.finished


func _reveal_database_record(record: Dictionary, index: int) -> void:
	var slot := _recipe_slots[index % _recipe_slots.size()]
	_reset_recipe_slots()
	await _shuffle_recipe_deck(index)
	await _pulse_recipe_slot(slot)

	_database_panel.position = Vector2(478.0, 48.0)
	_database_panel.size = Vector2(201.0, 107.0)
	_database_title.text = "FOUND  %s" % str(record.get("id", "?"))
	_database_title.add_theme_color_override(&"font_color", ACCENT_COLOR)
	_database_fields.text = (
		"meal:  %s\nprice:  $%d\ncook_seconds:  %d"
		% [
			str(record.get("meal", "Meal")),
			int(record.get("price", 0)),
			int(record.get("cook_seconds", 1)),
		]
	)
	_database_panel.show()

	# The selected physical card moves toward the record display, making the
	# relationship between the stored card and its structured data explicit.
	var original_position := slot.position
	var card_tween := create_tween()
	card_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_tween.tween_property(slot, "position", original_position + Vector2(0.0, -11.0), _duration(0.3))
	card_tween.tween_interval(_duration(0.35))
	card_tween.tween_property(slot, "position", original_position, _duration(0.3))
	await card_tween.finished


func _shuffle_recipe_deck(target_index: int) -> void:
	if _deck_cards.is_empty():
		return

	_database_panel.hide()
	_status_right.text = "Searching through the recipe records…"
	for index in _deck_cards.size():
		var card := _deck_cards[index]
		card.position = DECK_POSITION + Vector2(index * 3.0, index * -2.0)
		card.scale = Vector2.ONE
		card.rotation = deg_to_rad(-3.0 + index * 3.0)
		card.z_index = 4 + index
		card.show()
	await _wait(0.35)

	# Pull the top record aside, inspect it, and put it on the back of the
	# stack. Repeating the pass makes the lookup read as a physical card search.
	var pass_count := maxi(_deck_cards.size() * 2, 4)
	for pass_index in pass_count:
		var card_index := (target_index + 1 + pass_index) % _deck_cards.size()
		var card := _deck_cards[card_index]
		var side := -1.0 if pass_index % 2 == 0 else 1.0
		_status_right.text = "Checking  %s" % str(card.get_meta(&"recipe_id", "?"))
		card.z_index = 30

		var check := create_tween()
		check.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		check.tween_property(
			card,
			"position",
			DECK_POSITION + Vector2(48.0 * side, 8.0),
			_duration(0.2)
		)
		check.parallel().tween_property(
			card,
			"rotation",
			0.13 * side,
			_duration(0.2)
		)
		check.tween_interval(_duration(0.06))
		check.tween_property(
			card,
			"position",
			DECK_POSITION + Vector2(0.0, 3.0),
			_duration(0.18)
		)
		check.parallel().tween_property(card, "rotation", 0.0, _duration(0.18))
		await check.finished
		card.z_index = 3

	var target_card := _deck_cards[target_index % _deck_cards.size()]
	target_card.z_index = 40
	_status_right.text = "FOUND  %s" % str(target_card.get_meta(&"recipe_id", "?"))
	var found := create_tween()
	found.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	found.tween_property(
		target_card,
		"position",
		DECK_POSITION + Vector2(-56.0, 4.0),
		_duration(0.38)
	)
	found.parallel().tween_property(target_card, "scale", Vector2(1.1, 1.1), _duration(0.38))
	found.parallel().tween_property(target_card, "rotation", -0.06, _duration(0.38))
	await found.finished
	await _flash_control(target_card, CARD_GLOW_COLOR, 0.18)
	await _wait(0.45)
	_hide_recipe_deck()


func _cook_meal(meal_name: String, meal_color: Color, seconds: int) -> void:
	_meal.color = meal_color
	_meal_label.text = meal_name
	_meal.position = Vector2(390.0, 117.0)
	_meal.rotation = 0.0
	_meal.show()

	var chef_to_stove := create_tween()
	chef_to_stove.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	chef_to_stove.tween_property(chef, "position", CHEF_WORK_POSITION, _duration(0.45))
	await chef_to_stove.finished

	for remaining in range(seconds, -1, -1):
		timer_display.text = "00:%02d" % remaining
		if remaining > 0:
			_meal.rotation = -0.05 if remaining % 2 == 0 else 0.05
			await _wait(0.55)
	timer_display.text = "READY"

	var serve := create_tween().set_parallel(true)
	serve.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	serve.tween_property(_meal, "position", Vector2(459.0, 119.0), _duration(0.65))
	serve.tween_property(_meal, "rotation", 0.0, _duration(0.65))
	serve.tween_property(chef, "position", CHEF_HOME_POSITION, _duration(0.65))
	await serve.finished


func _move_camera_to(target: Vector2) -> void:
	if visual_camera.position.is_equal_approx(target):
		return
	_database_panel.hide()
	_status_left.hide()
	_status_right.hide()
	var pan := create_tween()
	pan.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	pan.tween_property(
		visual_camera,
		"position",
		target,
		_duration(camera_pan_seconds)
	)
	await pan.finished


func _pulse_recipe_slot(slot: ColorRect) -> void:
	var pulse := create_tween()
	pulse.set_loops(2)
	pulse.tween_property(slot, "color", CARD_GLOW_COLOR, _duration(0.2))
	pulse.tween_property(slot, "color", slot.color, _duration(0.2))
	await pulse.finished
	slot.color = CARD_GLOW_COLOR


func _flash_control(control: ColorRect, flash_color: Color, seconds := 0.3) -> void:
	var original_color := control.color
	var flash := create_tween()
	flash.tween_property(control, "color", flash_color, _duration(seconds))
	flash.tween_property(control, "color", original_color, _duration(seconds))
	await flash.finished


func _reset_demo() -> void:
	visual_camera.position = REGISTER_CAMERA_POSITION
	customer.position = CUSTOMER_OFFSCREEN_POSITION
	customer.hide()
	chef.position = CHEF_HOME_POSITION
	chef.show()
	price_display.text = "$0"
	timer_display.text = "00:00"
	_customer_name.hide()
	_speech_panel.hide()
	_request_card.hide()
	_database_panel.hide()
	_status_left.hide()
	_status_right.hide()
	_meal.hide()
	_meal.rotation = 0.0
	_hide_recipe_deck()
	_reset_recipe_slots()


func _reset_recipe_slots() -> void:
	for index in _recipe_slots.size():
		_recipe_slots[index].color = CARD_NORMAL_COLORS[index % CARD_NORMAL_COLORS.size()]


func _build_runtime_visuals() -> void:
	_overlay = Control.new()
	_overlay.name = "DatabaseAnimation"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 10
	world.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_customer_name = _make_label(Vector2(26.0, 83.0), Vector2(104.0, 20.0), 11)
	_customer_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_customer_name.add_theme_color_override(&"font_color", TEXT_COLOR)

	_speech_panel = _make_panel(Vector2(10.0, 43.0), Vector2(185.0, 45.0), Color("18242ce8"))
	_speech_text = _make_label(Vector2(6.0, 3.0), Vector2(173.0, 39.0), 11, _speech_panel)
	_speech_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_request_card = _make_panel(Vector2(137.0, 91.0), Vector2(91.0, 55.0), Color("263b4df2"))
	_request_id = _make_label(Vector2(4.0, 3.0), Vector2(83.0, 49.0), 9, _request_card)
	_request_id.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_request_id.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_request_id.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_database_panel = _make_panel(Vector2(478.0, 48.0), Vector2(201.0, 107.0), Color("162a26f2"))
	_database_title = _make_label(Vector2(7.0, 5.0), Vector2(187.0, 22.0), 10, _database_panel)
	_database_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_database_fields = _make_label(Vector2(10.0, 29.0), Vector2(181.0, 72.0), 10, _database_panel)
	_database_fields.add_theme_color_override(&"font_color", TEXT_COLOR)
	_build_recipe_deck()

	_status_left = _make_label(Vector2(8.0, 268.0), Vector2(284.0, 25.0), 10)
	_status_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_left.add_theme_color_override(&"font_color", ACCENT_COLOR)
	_status_right = _make_label(Vector2(378.0, 268.0), Vector2(314.0, 25.0), 10)
	_status_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_right.add_theme_color_override(&"font_color", ACCENT_COLOR)

	_meal = _make_panel(Vector2(390.0, 117.0), Vector2(72.0, 27.0), Color("d95f45"))
	_meal_label = _make_label(Vector2(3.0, 2.0), Vector2(66.0, 23.0), 8, _meal)
	_meal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_meal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_recipe_deck() -> void:
	_deck_cards.clear()
	for record in recipe_records:
		var recipe_color: Color = record.get("color", Color("537681"))
		var card := _make_panel(DECK_POSITION, DECK_CARD_SIZE, recipe_color.darkened(0.45))
		card.pivot_offset = DECK_CARD_SIZE * 0.5
		card.set_meta(&"recipe_id", str(record.get("id", "?")))

		var heading := _make_label(Vector2(6.0, 5.0), Vector2(100.0, 18.0), 9, card)
		heading.text = "RECIPE RECORD"
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_color_override(&"font_color", ACCENT_COLOR)

		var card_text := _make_label(Vector2(7.0, 25.0), Vector2(98.0, 45.0), 8, card)
		card_text.text = "id: %s\n%s" % [
			str(record.get("id", "?")),
			str(record.get("meal", "Meal")),
		]
		card_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.hide()
		_deck_cards.append(card)


func _hide_recipe_deck() -> void:
	for card in _deck_cards:
		card.hide()
		card.scale = Vector2.ONE
		card.rotation = 0.0


func _make_panel(panel_position: Vector2, panel_size: Vector2, panel_color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.color = panel_color
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(panel)
	return panel


func _make_label(
	label_position: Vector2,
	label_size: Vector2,
	font_size: int,
	parent: Control = null
) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", TEXT_COLOR)
	label.add_theme_color_override(&"font_shadow_color", Color("101417cc"))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	(parent if parent != null else _overlay).add_child(label)
	return label


func _duration(base_seconds: float) -> float:
	return base_seconds * maxf(timing_scale, 0.01)


func _wait(base_seconds: float) -> void:
	await get_tree().create_timer(_duration(base_seconds), false).timeout
