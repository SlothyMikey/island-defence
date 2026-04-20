extends StaticBody2D

# Castle base logic: tracks health and updates the on-screen health bar.
@export var max_health: int = 500
var current_health: int

@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	current_health = max_health
	update_health_bar()

func take_damage(amount: int) -> void:
	current_health -= amount
	
	if current_health < 0:
		current_health = 0
		
	update_health_bar()
	
	if current_health <= 0:
		print("Base Destroyed! Game Over.")

func update_health_bar() -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	
	if get_tree() != null:
		var world := get_tree().current_scene
		if world != null and "ui_manager" in world and world.ui_manager != null:
			if world.ui_manager.has_method("set_base_health"):
				world.ui_manager.call("set_base_health", current_health, max_health)
	
	var percentage := float(current_health) / float(max_health)
	
	var fill_style := StyleBoxFlat.new()
	
	if percentage > 0.6:
		fill_style.bg_color = Color.html("#4cbb17") 
	elif percentage > 0.3:
		fill_style.bg_color = Color.html("#e1ad01") 
	else:
		fill_style.bg_color = Color.html("#c21807")
		
	health_bar.add_theme_stylebox_override("fill", fill_style)
