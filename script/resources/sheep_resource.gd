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
var is_dying: bool = false
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
	
	var distance := randf_range(50.0, 100.0)
	target_position = _get_valid_roam_target(distance, random_walk_radius)
	
	# Fallback timer
	state_timer.start(3.0)

func _get_valid_roam_target(distance: float, max_radius: float) -> Vector2:
	var world := get_tree().current_scene
	var tree_obstacles := get_tree().get_nodes_in_group("tree_obstacle")
	
	for i in 15:
		var angle := randf() * TAU
		var d := randf_range(distance * 0.5, distance)
		var candidate = global_position + Vector2(cos(angle), sin(angle)) * d
		
		if candidate.distance_to(home_position) > max_radius:
			candidate = home_position + (candidate - home_position).normalized() * max_radius
			
		if world != null and world.has_method("get_ground_class_at_world"):
			if world.call("get_ground_class_at_world", candidate) != 2:
				continue
				
		var too_close := false
		for tree_obj in tree_obstacles:
			var tree := tree_obj as Node2D
			if tree != null and candidate.distance_squared_to(tree.global_position) < 14400.0: # 120px clearance
				too_close = true
				break
				
		if not too_close:
			return candidate

	return global_position

func _physics_process(delta: float) -> void:
	if is_dying or not is_moving or current_health <= 0:
		return
		
	var speed := run_speed if is_running else normal_walk_speed
	var to_target := target_position - global_position
	var distance := to_target.length()
	
	if distance < 1.0:
		_start_idle()
	else:
		var move_step := to_target.normalized() * speed * delta
		if move_step.length() > distance:
			move_step = move_step.normalized() * distance
			
		var collision = move_and_collide(move_step)
		if collision != null:
			_start_idle()
		else:
			# Depending on godot version, move_and_collide actually moves the body so we don't need +=
			pass
			
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
	if is_dying or current_health <= 0:
		return 0

	current_health -= max(harvest_power, 1)
	var gained_food: int = max(food_per_harvest, 0)
	
	if current_health > 0:
		_trigger_run_away()
		_flash_red()
	else:
		depleted.emit(self)
		_play_death_animation()

	return gained_food

func _play_death_animation() -> void:
	is_dying = true
	sprite.scale = Vector2(1.0, 1.0) # Reset scale so the meat isn't gigantic
	var tex = preload("res://assets/Tiny Swords (Update 010)/Resources/Resources/M_Spawn.png")
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

func _flash_red() -> void:
	var tween := create_tween()
	sprite.modulate = Color(1.0, 0.3, 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.25)

func _trigger_run_away() -> void:
	is_moving = true
	is_running = true
	sprite.play("run")
	var runaway_distance := randf_range(20.0, 50.0)
	target_position = _get_valid_roam_target(runaway_distance, random_walk_radius + 60.0)
		
	state_timer.start(1.5)

func is_depleted() -> bool:
	return current_health <= 0
