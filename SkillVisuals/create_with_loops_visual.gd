extends Control

const START_INDEX := 0
const END_INDEX := 8
const STEP_SECONDS := 1.0
const HEADER_LINE_Y := 8.0
const BODY_LINE_Y := 41.0
const DONE_LINE_Y := 74.0
const EMPTY_BLOCK_COLOR := Color("30394a")
const CURRENT_BLOCK_COLOR := Color("ffd166")
const CREATED_BLOCK_COLOR := Color("62d6a8")

enum ExecutionLine {
	LOOP_HEADER,
	CREATE_BLOCK,
	DONE,
}

@onready var step_timer: Timer = %StepTimer
@onready var line_pointer: Label = %LinePointer
@onready var line_highlight: ColorRect = %LineHighlight
@onready var live_counter_value: Label = %LiveCounterValue
@onready var block_row: HBoxContainer = %BlockRow

var _current_index := START_INDEX
var _execution_line := ExecutionLine.LOOP_HEADER
var _blocks: Array[ColorRect] = []


func _ready() -> void:
	for child in block_row.get_children():
		if child is ColorRect:
			_blocks.append(child as ColorRect)
	step_timer.wait_time = STEP_SECONDS
	step_timer.timeout.connect(_advance_code)
	_reset_visual()


func _advance_code() -> void:
	match _execution_line:
		ExecutionLine.LOOP_HEADER:
			_execution_line = ExecutionLine.CREATE_BLOCK
			_set_active_line(BODY_LINE_Y)
			_set_block_color(_current_index, CURRENT_BLOCK_COLOR)
		ExecutionLine.CREATE_BLOCK:
			_set_block_color(_current_index, CREATED_BLOCK_COLOR)
			if _current_index < END_INDEX:
				_current_index += 1
				live_counter_value.text = str(_current_index)
				_execution_line = ExecutionLine.LOOP_HEADER
				_set_active_line(HEADER_LINE_Y)
			else:
				_execution_line = ExecutionLine.DONE
				_set_active_line(DONE_LINE_Y)
		ExecutionLine.DONE:
			_reset_visual()


func _reset_visual() -> void:
	_current_index = START_INDEX
	_execution_line = ExecutionLine.LOOP_HEADER
	live_counter_value.text = str(_current_index)
	for block in _blocks:
		block.color = EMPTY_BLOCK_COLOR
	_set_active_line(HEADER_LINE_Y)


func _set_active_line(line_y: float) -> void:
	line_pointer.position.y = line_y
	line_highlight.position.y = line_y


func _set_block_color(index: int, color: Color) -> void:
	if index >= 0 and index < _blocks.size():
		_blocks[index].color = color
