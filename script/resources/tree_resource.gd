extends StaticBody2D

signal depleted(tree: Node2D)

@export var max_health: int = 5
@export var wood_per_chop: int = 2

@onready var sprite: AnimatedSprite2D = $Sprite2D

var current_health: int = 0
var is_dying: bool = false

func _ready() -> void:
	current_health = max(max_health, 1)

func harvest(chop_power: int = 1) -> int:
	if is_dying or current_health <= 0:
		return 0

	current_health -= max(chop_power, 1)
	var gained_wood: int = max(wood_per_chop, 0)

	if current_health <= 0:
		depleted.emit(self)
		_play_death_animation()

	return gained_wood

func _play_death_animation() -> void:
	is_dying = true
	var tex = preload("res://assets/Tiny Swords (Update 010)/Resources/Resources/W_Spawn.png")
	var frames = sprite.sprite_frames
	if not frames.has_animation("death"):
		frames.add_animation("death")
		frames.set_animation_speed("death", 10.0)
		frames.set_animation_loop("death", false)
		for i in 7:
			var atlas = AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * 128, 0, 128, 128)
			frames.add_frame("death", atlas)
	
	sprite.play("death")
	await sprite.animation_finished
	queue_free()

func is_depleted() -> bool:
	return current_health <= 0
