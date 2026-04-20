extends StaticBody2D

signal depleted(stone: Node2D)

@export_range(3, 6) var stone_tier: int = 3:
	set(value):
		stone_tier = clampi(value, 3, 6)
		_apply_tier_config()

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var current_health: int = 0
var gold_per_harvest: int = 1
var is_dying: bool = false

# Tier → max_health (larger = tougher)
const TIER_HEALTH := {
	3: 8,
	4: 12,
	5: 16,
	6: 20,
}

# Tier → gold per pickaxe hit
const TIER_GOLD := {
	3: 2,
	4: 2,
	5: 3,
	6: 3,
}

# Tier → collision circle radius
const TIER_COLLISION_RADIUS := {
	3: 16.0,
	4: 18.0,
	5: 22.0,
	6: 24.0,
}

# Tier → sprite Y offset
const TIER_SPRITE_OFFSET_Y := {
	3: -12.0,
	4: -14.0,
	5: -18.0,
	6: -20.0,
}

# All Highlight sheets are 768×128 = 6 frames of 128×128.
const FRAME_WIDTH: int = 128
const FRAME_HEIGHT: int = 128
const FRAME_COUNT: int = 6
const ANIM_SPEED: float = 8.0

const GOLD_HIGHLIGHT_TEXTURES := {
	3: preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Gold/Gold Stones/Gold Stone 3_Highlight.png"),
	4: preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Gold/Gold Stones/Gold Stone 4_Highlight.png"),
	5: preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Gold/Gold Stones/Gold Stone 5_Highlight.png"),
	6: preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Gold/Gold Stones/Gold Stone 6_Highlight.png"),
}

func _ready() -> void:
	_apply_tier_config()

func _apply_tier_config() -> void:
	var tier: int = clampi(stone_tier, 3, 6)

	current_health = TIER_HEALTH.get(tier, 8)
	gold_per_harvest = TIER_GOLD.get(tier, 1)

	if not is_node_ready():
		return

	# Build a fresh SpriteFrames (don't mutate the shared scene resource).
	var tex: Texture2D = GOLD_HIGHLIGHT_TEXTURES.get(tier)
	if tex != null:
		var frames := SpriteFrames.new()
		# SpriteFrames.new() already contains a "default" animation — just configure it.
		frames.set_animation_speed(&"default", ANIM_SPEED)
		frames.set_animation_loop(&"default", true)
		# Clear the one placeholder frame that SpriteFrames creates automatically.
		frames.clear(&"default")
		for i in FRAME_COUNT:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
			frames.add_frame(&"default", atlas)
		sprite.sprite_frames = frames
		sprite.play(&"default")

	sprite.position.y = TIER_SPRITE_OFFSET_Y.get(tier, -8.0)

	# Scale sprite slightly larger for bigger tiers.
	var scale_factor: float = 0.8 + (float(tier - 3) * 0.1)
	sprite.scale = Vector2(scale_factor, scale_factor)

	# Resize collision circle.
	var circle_shape := collision_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = TIER_COLLISION_RADIUS.get(tier, 12.0)

func harvest(mine_power: int = 1) -> int:
	if is_dying or current_health <= 0:
		return 0

	current_health -= max(mine_power, 1)
	var gained_gold: int = max(gold_per_harvest, 0)

	if current_health > 0:
		_flash_hit()
	else:
		depleted.emit(self)
		_play_death_animation()

	return gained_gold

func _flash_hit() -> void:
	var tween := create_tween()
	sprite.modulate = Color(1.0, 0.85, 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)

func _play_death_animation() -> void:
	is_dying = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(0.05, 0.05), 0.35).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "rotation", randf_range(-0.5, 0.5), 0.35)
	tween.chain().tween_callback(queue_free)

func is_depleted() -> bool:
	return current_health <= 0
