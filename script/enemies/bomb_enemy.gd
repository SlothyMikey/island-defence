extends CharacterBody2D

# Enemy logic: move toward the base, flash on hit, and spawn damage text.
@export var speed: float = 200.0
@export var max_health: int = 100
@export var damage_text_scene: PackedScene = preload("res://scenes/other/damage_text.tscn")
@export var waypoint_reached_distance: float = 24.0
@export var stun_duration: float = 0.25 
@export var explosion_damage: int = 20 
@export var gold_drop_amount: int = 15 
@export var stuck_progress_epsilon: float = 0.9
@export var stuck_repath_delay: float = 0.4
@export var evade_duration: float = 0.25
@export var evade_speed_multiplier: float = 0.85
@export var detour_distance: float = 56.0
@export_range(0.0, 1.0, 0.05) var detour_forward_weight: float = 0.25
@export var wall_backoff_distance: float = 48.0
@export var stuck_free_field_radius: float = 128.0
@export var stuck_free_field_step: float = 24.0
@export var stuck_free_field_angles: int = 16

## NEW: How long the enemy waits at the base before blowing up (in seconds)
@export var detonate_delay: float = .5 

var current_health: int
var stun_time_left: float = 0.0 
var is_detonating: bool = false 

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_spawn_point: Marker2D = $DamageSpawnPoint
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

var target: Node2D = null
var route_points: Array[Vector2] = []
var current_route_index: int = 0
var stuck_time_accum: float = 0.0
var evade_time_left: float = 0.0
var evade_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	current_health = max_health
	target = get_tree().get_first_node_in_group("base")
	_ignore_resource_collisions()
	
	if target == null:
		print("ERROR: I spawned, but I cannot find anything in the 'base' group!")
		return

	call_deferred("_build_route")

func _ignore_resource_collisions() -> void:
	for tree_variant in get_tree().get_nodes_in_group("tree_obstacle"):
		var tree_body := tree_variant as PhysicsBody2D
		if tree_body != null:
			add_collision_exception_with(tree_body)
			
	for sheep_variant in get_tree().get_nodes_in_group("food_resource"):
		var sheep_body := sheep_variant as PhysicsBody2D
		if sheep_body != null:
			add_collision_exception_with(sheep_body)

	for gold_variant in get_tree().get_nodes_in_group("gold_resource"):
		var gold_body := gold_variant as PhysicsBody2D
		if gold_body != null:
			add_collision_exception_with(gold_body)

func _build_route() -> void:
	if target == null:
		return

	route_points.clear()
	current_route_index = 0
	stuck_time_accum = 0.0
	evade_time_left = 0.0
	evade_direction = Vector2.ZERO

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
	var distance_before_move: float = global_position.distance_to(current_target)
	var collision_normal: Vector2 = Vector2.ZERO

	# 1. Apply velocity and move with physics
	var direction: Vector2 = global_position.direction_to(current_target)
	if evade_time_left > 0.0:
		evade_time_left = maxf(evade_time_left - _delta, 0.0)
		velocity = evade_direction * speed * evade_speed_multiplier
	else:
		velocity = direction * speed
	move_and_slide() 

	# NEW 2. Check if we physically crashed into the base!
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision_normal == Vector2.ZERO and collision != null:
			collision_normal = collision.get_normal()
		var collider_node: Node = collision.get_collider() as Node
		
		# If the thing we bumped into is in the 'base' group, blow up!
		if collider_node != null and collider_node.is_in_group("base"):
			velocity = Vector2.ZERO
			detonate()
			return

	_update_stuck_recovery(_delta, current_target, distance_before_move, direction, collision_normal)

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
		is_detonating = true # Stop movement and prevent double damage
		
		# Give player gold
		var world := get_tree().current_scene
		if world != null and "resources" in world:
			world.resources[&"gold"] += gold_drop_amount
			if "ui_manager" in world and world.ui_manager != null:
				world.ui_manager.call("set_resource_amount", &"gold", world.resources[&"gold"])
			if world.has_method("_refresh_building_availability"):
				world.call("_refresh_building_availability")
		
		# Play death animation before freeing
		animated_sprite.play("death")
		await animated_sprite.animation_finished
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

func _update_stuck_recovery(delta: float, current_target: Vector2, distance_before_move: float, move_direction: Vector2, collision_normal: Vector2) -> void:
	if evade_time_left > 0.0:
		return

	var distance_after_move: float = global_position.distance_to(current_target)
	var moved_toward_target: float = distance_before_move - distance_after_move
	var is_blocked: bool = get_slide_collision_count() > 0

	if is_blocked and moved_toward_target <= stuck_progress_epsilon:
		stuck_time_accum += delta
	else:
		stuck_time_accum = 0.0

	if stuck_time_accum < stuck_repath_delay:
		return

	stuck_time_accum = 0.0
	_start_evade(move_direction, collision_normal)

func _start_evade(move_direction: Vector2, collision_normal: Vector2) -> void:
	var backoff_direction: Vector2 = _compute_backoff_direction(move_direction, collision_normal)
	var detour_direction: Vector2 = _compute_detour_direction(move_direction, collision_normal)
	evade_direction = backoff_direction
	evade_time_left = evade_duration
	_insert_escape_waypoints(backoff_direction, detour_direction)

func _compute_backoff_direction(move_direction: Vector2, collision_normal: Vector2) -> Vector2:
	if collision_normal.length_squared() > 0.0001:
		return collision_normal.normalized()
	if move_direction.length_squared() > 0.0001:
		return (-move_direction).normalized()
	return Vector2.LEFT

func _compute_detour_direction(move_direction: Vector2, collision_normal: Vector2) -> Vector2:
	if collision_normal.length_squared() > 0.0001:
		var tangent := Vector2(-collision_normal.y, collision_normal.x)
		if tangent.dot(move_direction) < 0.0:
			tangent = -tangent
		var blended := tangent + (collision_normal * 0.5) + (move_direction * detour_forward_weight)
		if blended.length_squared() > 0.0001:
			return blended.normalized()

	var side_sign: float = -1.0 if randf() < 0.5 else 1.0
	var fallback := Vector2(-move_direction.y, move_direction.x) * side_sign
	if fallback.length_squared() <= 0.0001:
		fallback = Vector2.LEFT
	return fallback.normalized()

func _insert_detour_waypoint(direction: Vector2) -> void:
	if route_points.is_empty():
		return
	var detour_point: Vector2 = global_position + direction * detour_distance
	if current_route_index < route_points.size():
		route_points.insert(current_route_index, detour_point)
	else:
		route_points.append(detour_point)

func _insert_escape_waypoints(backoff_direction: Vector2, detour_direction: Vector2) -> void:
	if route_points.is_empty():
		return

	var backoff_point: Vector2 = global_position + backoff_direction * wall_backoff_distance
	var detour_point: Vector2 = backoff_point + detour_direction * detour_distance
	var safe_backoff_point: Vector2 = _find_nearby_free_field(backoff_point)
	var safe_detour_point: Vector2 = _find_nearby_free_field(detour_point)

	if current_route_index < route_points.size():
		route_points.insert(current_route_index, safe_detour_point)
		route_points.insert(current_route_index, safe_backoff_point)
	else:
		route_points.append(safe_backoff_point)
		route_points.append(safe_detour_point)

func _find_nearby_free_field(preferred_position: Vector2) -> Vector2:
	if _is_position_free_for_enemy(preferred_position):
		return preferred_position

	var max_radius: float = maxf(stuck_free_field_radius, 0.0)
	var step: float = maxf(stuck_free_field_step, 8.0)
	var angle_count: int = maxi(stuck_free_field_angles, 8)

	var radius: float = step
	while radius <= max_radius:
		for i in angle_count:
			var angle: float = (TAU * float(i)) / float(angle_count)
			var candidate := global_position + Vector2(cos(angle), sin(angle)) * radius
			if _is_position_free_for_enemy(candidate):
				return candidate
		radius += step

	return preferred_position

func _is_position_free_for_enemy(candidate_position: Vector2) -> bool:
	if body_collision_shape == null or body_collision_shape.shape == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_collision_shape.shape
	var shape_offset: Vector2 = body_collision_shape.position.rotated(global_rotation)
	query.transform = Transform2D(global_rotation, candidate_position + shape_offset)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [self]

	var hits: Array = get_world_2d().direct_space_state.intersect_shape(query, 8)
	for hit_variant in hits:
		var hit: Dictionary = hit_variant as Dictionary
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == null:
			continue
		return false

	return true

