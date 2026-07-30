extends Control

## Demonstrates a story as an ordered queue of text and game events. Each beat
## completes before the next one starts, so the same cause-and-effect chain is
## visible in both the storyboard and the event log.

@export_range(0.25, 3.0, 0.05, "or_greater") var animation_speed := 1.0

const DESIGN_SIZE := Vector2(460.0, 460.0)
const BEAT_SECONDS := 2.6
const SUMMARY_SECONDS := 2.2
const TOTAL_SECONDS := BEAT_SECONDS * 3.0 + SUMMARY_SECONDS

const BACKGROUND := Color("0b1019")
const PANEL := Color("121b29")
const PANEL_BORDER := Color("344861")
const SKY := Color("162a41")
const TEXT := Color("eef5ff")
const MUTED := Color("8292a8")
const BLUE := Color("77bdf2")
const GOLD := Color("ffd166")
const GREEN := Color("62d6a8")
const RED := Color("f47b76")
const GROUND := Color("23384a")
const DARK := Color("081018")

const CARD_RECTS: Array[Rect2] = [
	Rect2(14.0, 74.0, 138.0, 178.0),
	Rect2(161.0, 74.0, 138.0, 178.0),
	Rect2(308.0, 74.0, 138.0, 178.0),
]

const STORY_LINES: Array[String] = [
	"01  TEXT     \"A key!\"",
	"02  EVENT    Gate opens",
	"03  TEXT     \"The tower is safe.\"",
]

var _elapsed := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta * maxf(animation_speed, 0.01), TOTAL_SECONDS)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var visual_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	if visual_scale <= 0.0:
		return
	var visual_offset := (size - DESIGN_SIZE * visual_scale) * 0.5
	draw_set_transform(visual_offset, 0.0, Vector2.ONE * visual_scale)

	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), BACKGROUND)
	_draw_header()

	var beat := mini(int(_elapsed / BEAT_SECONDS), 3)
	var beat_progress := 1.0
	if beat < 3:
		beat_progress = _ease(clampf(fmod(_elapsed, BEAT_SECONDS) / BEAT_SECONDS, 0.0, 1.0))

	for index in 3:
		var progress := 0.0
		if index < beat or beat == 3:
			progress = 1.0
		elif index == beat:
			progress = beat_progress
		_draw_story_card(index, progress, index == beat)

	_draw_connectors(beat, beat_progress)
	_draw_story_queue(beat, beat_progress)


func _draw_header() -> void:
	_draw_text("STORY IN ORDER", Rect2(16.0, 15.0, 428.0, 25.0), BLUE, 18, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(
		"Text and events play one beat at a time",
		Rect2(16.0, 43.0, 428.0, 20.0),
		MUTED,
		12,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_story_card(index: int, progress: float, is_active: bool) -> void:
	var card := CARD_RECTS[index]
	var lift := -3.0 * sin(progress * PI) if is_active else 0.0
	card.position.y += lift

	var pulse := (sin(_elapsed * 5.0) + 1.0) * 0.5
	var border_color := PANEL_BORDER
	if is_active:
		border_color = BLUE.lerp(GOLD, pulse * 0.45)
	elif progress >= 1.0:
		border_color = GREEN

	_draw_rounded_rect(card, PANEL, border_color, 8.0, 2.0)
	_draw_step_badge(card.position + Vector2(13.0, 14.0), index + 1, progress, is_active)

	match index:
		0:
			_draw_key_scene(card, progress)
			_draw_card_caption(card, "FIND THE KEY", "\"A key!\"", progress)
		1:
			_draw_gate_scene(card, progress)
			_draw_card_caption(card, "UNLOCK GATE", "Gate opens", progress)
		2:
			_draw_tower_scene(card, progress)
			_draw_card_caption(card, "REACH TOWER", "\"The tower is safe.\"", progress)


func _draw_step_badge(center: Vector2, number: int, progress: float, is_active: bool) -> void:
	var fill := Color("24364a")
	if progress >= 1.0:
		fill = GREEN
	elif is_active:
		fill = GOLD
	draw_circle(center, 10.0, fill)
	var number_color := DARK if is_active or progress >= 1.0 else TEXT
	_draw_text(str(number), Rect2(center.x - 10.0, center.y - 8.0, 20.0, 16.0), number_color, 11, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_key_scene(card: Rect2, progress: float) -> void:
	var scene := Rect2(card.position + Vector2(8.0, 32.0), Vector2(card.size.x - 16.0, 83.0))
	draw_rect(scene, SKY)
	draw_rect(Rect2(scene.position + Vector2(0.0, 60.0), Vector2(scene.size.x, 23.0)), GROUND)

	# A simple forest silhouette frames the discovery.
	for tree_x in [12.0, 103.0]:
		draw_rect(Rect2(scene.position + Vector2(tree_x, 25.0), Vector2(7.0, 39.0)), Color("172a31"))
		draw_circle(scene.position + Vector2(tree_x + 3.5, 21.0), 15.0, Color("1d4650"))

	var hero_x := lerpf(scene.position.x + 31.0, scene.position.x + 48.0, progress)
	_draw_hero(Vector2(hero_x, scene.position.y + 59.0), 0.92)

	var key_position := scene.position + Vector2(88.0, 49.0 - sin(_elapsed * 4.0) * 2.0)
	var glow_alpha := 0.12 + progress * 0.22
	draw_circle(key_position, 15.0 + sin(_elapsed * 4.0) * 1.5, _with_alpha(GOLD, glow_alpha))
	_draw_key(key_position, progress)


func _draw_gate_scene(card: Rect2, progress: float) -> void:
	var scene := Rect2(card.position + Vector2(8.0, 32.0), Vector2(card.size.x - 16.0, 83.0))
	draw_rect(scene, SKY)
	draw_rect(Rect2(scene.position + Vector2(0.0, 63.0), Vector2(scene.size.x, 20.0)), GROUND)

	var gate_center_x := scene.position.x + 77.0
	var opening := progress * 14.0
	draw_rect(Rect2(Vector2(gate_center_x - 29.0 - opening, scene.position.y + 15.0), Vector2(25.0, 52.0)), Color("435570"))
	draw_rect(Rect2(Vector2(gate_center_x + 4.0 + opening, scene.position.y + 15.0), Vector2(25.0, 52.0)), Color("435570"))
	draw_line(Vector2(gate_center_x, scene.position.y + 12.0), Vector2(gate_center_x, scene.position.y + 68.0), PANEL_BORDER, 3.0)
	for bar_offset in [-20.0, -10.0, 10.0, 20.0]:
		var shifted_offset: float = bar_offset + signf(bar_offset) * opening
		draw_line(
			Vector2(gate_center_x + shifted_offset, scene.position.y + 18.0),
			Vector2(gate_center_x + shifted_offset, scene.position.y + 64.0),
			Color("72819a"),
			2.0
		)

	_draw_hero(scene.position + Vector2(25.0 + progress * 13.0, 62.0), 0.92)
	_draw_key(scene.position + Vector2(50.0, 48.0), 1.0 - progress)
	if progress > 0.62:
		_draw_burst(Vector2(gate_center_x, scene.position.y + 43.0), (progress - 0.62) / 0.38, GREEN)


func _draw_tower_scene(card: Rect2, progress: float) -> void:
	var scene := Rect2(card.position + Vector2(8.0, 32.0), Vector2(card.size.x - 16.0, 83.0))
	draw_rect(scene, SKY)
	draw_circle(scene.position + Vector2(98.0, 18.0), 9.0, _with_alpha(GOLD, 0.7))
	draw_rect(Rect2(scene.position + Vector2(0.0, 65.0), Vector2(scene.size.x, 18.0)), GROUND)

	var tower_rect := Rect2(scene.position + Vector2(66.0, 20.0), Vector2(42.0, 48.0))
	draw_rect(tower_rect, Color("50627d"))
	draw_polygon(
		PackedVector2Array([
			tower_rect.position + Vector2(-5.0, 1.0),
			tower_rect.position + Vector2(21.0, -15.0),
			tower_rect.position + Vector2(47.0, 1.0),
		]),
		PackedColorArray([RED])
	)
	draw_rect(Rect2(tower_rect.position + Vector2(17.0, 27.0), Vector2(10.0, 21.0)), DARK)

	var hero_x := lerpf(scene.position.x + 24.0, scene.position.x + 72.0, progress)
	_draw_hero(Vector2(hero_x, scene.position.y + 64.0), 0.92)
	if progress > 0.68:
		var reveal := (progress - 0.68) / 0.32
		_draw_burst(tower_rect.position + Vector2(21.0, 17.0), reveal, GOLD)


func _draw_card_caption(card: Rect2, heading: String, event_text: String, progress: float) -> void:
	var heading_color := TEXT if progress > 0.08 else MUTED
	var event_color := GREEN if progress >= 0.72 else MUTED
	_draw_text(
		heading,
		Rect2(card.position + Vector2(7.0, 122.0), Vector2(card.size.x - 14.0, 20.0)),
		heading_color,
		11,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_text(
		event_text,
		Rect2(card.position + Vector2(7.0, 146.0), Vector2(card.size.x - 14.0, 19.0)),
		event_color,
		10,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_connectors(beat: int, beat_progress: float) -> void:
	for index in 2:
		var from := Vector2(CARD_RECTS[index].end.x + 2.0, 158.0)
		var to := Vector2(CARD_RECTS[index + 1].position.x - 2.0, 158.0)
		var connector_progress := 0.0
		if beat > index:
			connector_progress = 1.0
		elif beat == index:
			connector_progress = clampf((beat_progress - 0.72) / 0.28, 0.0, 1.0)
		var color := GREEN if connector_progress >= 1.0 else PANEL_BORDER
		draw_line(from, to, color, 3.0)
		var arrow_tip := to
		draw_polygon(
			PackedVector2Array([
				arrow_tip,
				arrow_tip + Vector2(-6.0, -4.0),
				arrow_tip + Vector2(-6.0, 4.0),
			]),
			PackedColorArray([color])
		)


func _draw_story_queue(beat: int, beat_progress: float) -> void:
	var queue_rect := Rect2(14.0, 269.0, 432.0, 174.0)
	_draw_rounded_rect(queue_rect, Color("0e1723"), PANEL_BORDER, 8.0, 1.0)
	_draw_text("STORY QUEUE", Rect2(28.0, 280.0, 180.0, 20.0), BLUE, 12)
	_draw_text("plays top to bottom", Rect2(238.0, 281.0, 190.0, 18.0), MUTED, 10, HORIZONTAL_ALIGNMENT_RIGHT)

	for index in 3:
		var row := Rect2(27.0, 310.0 + index * 37.0, 406.0, 29.0)
		var row_progress := 0.0
		if index < beat or beat == 3:
			row_progress = 1.0
		elif index == beat:
			row_progress = beat_progress
		var row_fill := Color("151f2d")
		var row_border := Color("26384c")
		if index == beat:
			row_fill = Color("1a2b3d")
			row_border = GOLD
		elif row_progress >= 1.0:
			row_border = GREEN
		_draw_rounded_rect(row, row_fill, row_border, 5.0, 1.0)

		var indicator_color := MUTED
		if row_progress >= 1.0:
			indicator_color = GREEN
		elif index == beat:
			indicator_color = GOLD
		draw_circle(row.position + Vector2(13.0, 14.5), 4.0, indicator_color)

		var visible_characters := int(ceil(STORY_LINES[index].length() * clampf(row_progress * 1.7, 0.0, 1.0)))
		var visible_text := STORY_LINES[index].substr(0, visible_characters)
		_draw_text(visible_text, Rect2(row.position + Vector2(25.0, 5.0), Vector2(371.0, 19.0)), TEXT, 11)

	if beat == 3:
		var completion_alpha := clampf((_elapsed - BEAT_SECONDS * 3.0) / 0.45, 0.0, 1.0)
		var message_rect := Rect2(119.0, 416.0, 222.0, 20.0)
		_draw_rounded_rect(
			message_rect,
			_with_alpha(Color("183c35"), completion_alpha),
			_with_alpha(GREEN, completion_alpha),
			6.0,
			1.0
		)
		_draw_text(
			"STORY COMPLETE - CLEAR ORDER",
			Rect2(119.0, 420.0, 222.0, 14.0),
			_with_alpha(GREEN, completion_alpha),
			10,
			HORIZONTAL_ALIGNMENT_CENTER
		)


func _draw_hero(feet: Vector2, hero_scale: float) -> void:
	var body_color := BLUE
	draw_circle(feet + Vector2(0.0, -25.0) * hero_scale, 7.0 * hero_scale, Color("f2c6a0"))
	draw_rect(
		Rect2(feet + Vector2(-6.0, -20.0) * hero_scale, Vector2(12.0, 15.0) * hero_scale),
		body_color
	)
	draw_line(feet + Vector2(-3.0, -6.0) * hero_scale, feet + Vector2(-6.0, 0.0), TEXT, 2.0)
	draw_line(feet + Vector2(3.0, -6.0) * hero_scale, feet + Vector2(6.0, 0.0), TEXT, 2.0)


func _draw_key(center: Vector2, visibility: float) -> void:
	var alpha := clampf(visibility, 0.0, 1.0)
	var color := _with_alpha(GOLD, alpha)
	draw_arc(center + Vector2(-4.0, 0.0), 5.0, 0.0, TAU, 18, color, 2.5)
	draw_line(center + Vector2(1.0, 0.0), center + Vector2(12.0, 0.0), color, 3.0)
	draw_line(center + Vector2(8.0, 0.0), center + Vector2(8.0, 5.0), color, 2.5)
	draw_line(center + Vector2(12.0, 0.0), center + Vector2(12.0, 4.0), color, 2.5)


func _draw_burst(center: Vector2, progress: float, color: Color) -> void:
	var amount := clampf(progress, 0.0, 1.0)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var inner := center + Vector2.from_angle(angle) * 7.0
		var outer := center + Vector2.from_angle(angle) * (7.0 + 9.0 * amount)
		draw_line(inner, outer, _with_alpha(color, amount), 2.0)


func _draw_rounded_rect(
	rect: Rect2,
	fill_color: Color,
	border_color: Color,
	radius: float,
	border_width: float
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(int(border_width))
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)


func _draw_text(
	value: String,
	rect: Rect2,
	color: Color,
	font_size: int,
	alignment := HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	draw_string(
		_font,
		rect.position + Vector2(0.0, font_size),
		value,
		alignment,
		rect.size.x,
		font_size,
		color
	)


func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
