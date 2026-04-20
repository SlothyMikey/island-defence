extends StaticBody2D

signal depleted(tree: Node2D)

@export var max_health: int = 5
@export var wood_per_chop: int = 2

var current_health: int = 0

func _ready() -> void:
	current_health = max(max_health, 1)

func harvest(chop_power: int = 1) -> int:
	if current_health <= 0:
		return 0

	current_health -= max(chop_power, 1)
	var gained_wood: int = max(wood_per_chop, 0)

	if current_health <= 0:
		depleted.emit(self)
		queue_free()

	return gained_wood

func is_depleted() -> bool:
	return current_health <= 0
