@tool
extends Resource
class_name RandomImageProvider

const TRAINING_IMAGES: Array[Texture2D] = [
	preload("res://Resources/image_proxy.jpeg"),
	preload("res://Resources/image_proxy (1).jpeg"),
]

static func get_random_image() -> Texture2D:
	return TRAINING_IMAGES.pick_random()
