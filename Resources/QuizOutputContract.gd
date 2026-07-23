@tool
extends Resource
class_name QuizOutputContract

const VERSION := 1

@export var version := VERSION
@export var answers: Dictionary[StringName, int] = {}
@export var truth_skill_ids: Array[StringName] = []
@export var philosophy_skill_ids: Array[StringName] = []
@export var not_learned_skill_ids: Array[StringName] = []
@export var dont_care_skill_ids: Array[StringName] = []
@export var unanswered_skill_ids: Array[StringName] = []
@export var gated_skill_ids: Array[StringName] = []
@export var complete := false
