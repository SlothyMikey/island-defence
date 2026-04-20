extends StaticBody2D

signal depleted(sheep: Node2D)

@export var max_health: int = 9
@export var food_per_harvest: int = 5
@export var random_walk_radius: float = 100.0
@export var normal_walk_speed: float = 15.0
@export var run_speed: float = 150.0

@onready var sprite: AnimatedSprite2D = $Sprite2D

var current_health: int = 0
var home_position: Vector2
var target_position: Vector2
var is_moving: bool = false
var is_running: bool = false
var state_timer: Timer

func _ready() -> void:
	current_health = max(max_health, 1)
	home_position = global_position
	target_position = global_position
	
	state_timer = Timer.new()
	state_timer.one_shot = true
	state_timer.timeout.connect(_on_state_timer_timeout)
	add_child(state_timer)
	
	_start_idle()

func _start_idle() -> void:
	is_moving = false
	is_running = false
	sprite.play("default") # Normal ambient "idle" serves as casual walk
	state_timer.start(randf_range(1.5, 4.0))

func _start_random_walk() -> void:
	is_moving = true
	is_running = false
	sprite.play("default")
	
	var angle := randf() * TAU
	# Wander distance (50 to 100 pixels)
	var distance := randf_range(50.0, 100.0)
	target_position = global_position + Vector2(cos(angle), sin(angle)) * distance
	
	# Confine to home radius
	if target_position.distance_to(home_position) > random_walk_radius:
		target_position = home_position + (target_position - home_position).normalized() * random_walk_radius
		
	# Fallback timer in case it takes too long
	state_timer.start(3.0)

func _physics_process(delta: float) -> void:
	if not is_moving or current_health <= 0:
		return
		
	var speed := run_speed if is_running else normal_walk_speed
	var to_target := target_position - global_position
	var distance := to_target.length()
	
	if distance < 1.0:
		_start_idle()
	else:
		var move_step := to_target.normalized() * speed * delta
		if move_step.length() > distance:
			global_position = target_position
		else:
			global_position += move_step
			
		# Flip sprite depending on walk direction
		if to_target.x < 0:
			sprite.flip_h = true
		elif to_target.x > 0:
			sprite.flip_h = false

func _on_state_timer_timeout() -> void:
	if current_health <= 0:
		return
	if is_running:
		_start_idle()
	elif is_moving:
		_start_idle()
	else:
		_start_random_walk()

func harvest(harvest_power: int = 1) -> int:
	if current_health <= 0:
		return 0

	current_health -= max(harvest_power, 1)
	var gained_food: int = max(food_per_harvest, 0)
	
	if current_health > 0:
		_trigger_run_away()
		_flash_red()

	if current_health <= 0:
		depleted.emit(self)
		queue_free()

	return gained_food

func _flash_red() -> void:
	var tween := create_tween()
	sprite.modulate = Color(1.0, 0.3, 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.25)

func _trigger_run_away() -> void:
	is_moving = true
	is_running = true
	sprite.play("run")
	var angle := randf() * TAU
	var runaway_distance := randf_range(20.0, 50.0)
	target_position = global_position + Vector2(cos(angle), sin(angle)) * runaway_distance
	
	# Clamp to a slightly larger radius so it can run away but doesn't go off map forever
	if target_position.distance_to(home_position) > random_walk_radius + 60.0:
		target_position = home_position + (target_position - home_position).normalized() * (random_walk_radius + 60.0)
		
	state_timer.start(1.5)

func is_depleted() -> bool:
	return current_health <= 0
