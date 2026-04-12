extends Marker2D

# Floating damage label that rises, fades, and then removes itself.
@onready var label: Label = $Label

func _ready() -> void:
	call_deferred("_start_popup_tween")

func _start_popup_tween() -> void:
	var start_position := position
	var target_position := start_position + Vector2(0.0, -100.0)
	var tween = create_tween().set_parallel(true)
	
	# Keep the popup very close to the hit point with a slow, readable upward drift.
	tween.tween_property(self, "position", target_position, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)

func set_damage_value(amount: int) -> void:
	label.text = str(amount)
