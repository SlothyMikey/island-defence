extends CharacterBody2D

# Enemy logic: move toward the base, flash on hit, and spawn damage text.
@export var speed: float = 200.0
@export var max_health: int = 100
@export var damage_text_scene: PackedScene = preload("res://scenes/other/damage_text.tscn")
@export var waypoint_reached_distance: float = 24.0
@export var stun_duration: float = 0.25 
@export var explosion_damage: int = 20 

## NEW: How long the enemy waits at the base before blowing up (in seconds)
@export var detonate_delay: float = .5 

var current_health: int
var stun_time_left: float = 0.0 
var is_detonating: bool = false 

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_spawn_point: Marker2D = $DamageSpawnPoint

var target: Node2D = null
var route_points: Array[Vector2] = []
var current_route_index: int = 0

func _ready() -> void:
	current_health = max_health
	target = get_tree().get_first_node_in_group("base")
	
	if target == null:
		print("ERROR: I spawned, but I cannot find anything in the 'base' group!")
		return

	call_deferred("_build_route")

func _build_route() -> void:
	if target == null:
		return

	route_points.clear()
	current_route_index = 0

	var current_scene := get_tree().current_scene
	if current_scene == null:
		route_points.append(target.global_position)
		return

	var right_approach := current_scene.get_node_or_null("EnemyRoute/RightApproach") as Node2D
	var ladder_bottom := current_scene.get_node_or_null("EnemyRoute/LadderBottom") as Node2D
	var ladder_top := current_scene.get_node_or_null("EnemyRoute/LadderTop") as Node2D

	if ladder_top != null and ladder_bottom != null:
		var ladder_route_x := minf(ladder_top.global_position.x, ladder_bottom.global_position.x)
		var route_needs_ladder := global_position.x > ladder_route_x + waypoint_reached_distance
		if route_needs_ladder:
			if right_approach != null and global_position.x > right_approach.global_position.x:
				route_points.append(right_approach.global_position)
			route_points.append(ladder_bottom.global_position)
			route_points.append(ladder_top.global_position)

	route_points.append(target.global_position)

func _physics_process(_delta: float) -> void:
	if is_detonating:
		return

	if stun_time_left > 0.0:
		stun_time_left -= _delta
		return 
		
	if target == null:
		return

	if route_points.is_empty():
		velocity = Vector2.ZERO
		return

	route_points[route_points.size() - 1] = target.global_position
	var current_target: Vector2 = route_points[current_route_index]

	# 1. Apply velocity and move with physics
	var direction := global_position.direction_to(current_target)
	velocity = direction * speed
	move_and_slide() 

	# NEW 2. Check if we physically crashed into the base!
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		# If the thing we bumped into is in the 'base' group, blow up!
		if collider != null and collider.is_in_group("base"):
			velocity = Vector2.ZERO
			detonate()
			return

	# 3. Normal distance check for intermediate waypoints
	if global_position.distance_to(current_target) <= waypoint_reached_distance:
		if current_route_index < route_points.size() - 1:
			current_route_index += 1
		else:
			velocity = Vector2.ZERO
			detonate() 
			return


func take_damage(amount: int) -> void:
	if is_detonating:
		return

	current_health -= amount
	stun_time_left = stun_duration
	
	var flash_tween = create_tween()
	animated_sprite.modulate = Color.RED
	flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.2)
	
	if damage_text_scene != null:
		var text_instance = damage_text_scene.instantiate()
		get_tree().current_scene.add_child(text_instance)
		text_instance.global_position = damage_spawn_point.global_position
		text_instance.set_damage_value(amount)
	
	if current_health <= 0:
		die()

func detonate() -> void:
	## 1. Immediately flag as detonating to stop movement and taking damage
	is_detonating = true
	
	## NEW: 2. Wait for the delay timer to finish (the "fuse")
	await get_tree().create_timer(detonate_delay).timeout
	
	## 3. Play the animation and deal damage
	animated_sprite.play("detonate")
	
	if target.has_method("take_damage"):
		target.take_damage(explosion_damage)
	
	## 4. Wait for the animation to finish before deleting
	await animated_sprite.animation_finished
	die()

func die() -> void:
	queue_free()
