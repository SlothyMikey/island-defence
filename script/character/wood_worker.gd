extends CharacterBody2D

signal wood_collected(amount: int)

@export var move_speed: float = 120.0
@export var tree_search_radius: float = 420.0
@export var tree_reach_distance: float = 52.0
@export var home_reach_distance: float = 24.0
@export var waypoint_reached_distance: float = 12.0
@export var gather_interval: float = 1.0
@export var chop_power: int = 1
@export var stuck_progress_epsilon: float = 0.9
@export var stuck_repath_delay: float = 0.45
@export var evade_duration: float = 0.3
@export var evade_speed_multiplier: float = 0.8
@export var detour_distance: float = 64.0
@export_range(0.0, 1.0, 0.05) var detour_forward_weight: float = 0.3
@export var wall_backoff_distance: float = 56.0

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var gather_timer: Timer = $GatherTimer

var home_position: Vector2 = Vector2.ZERO
var home_building_body: PhysicsBody2D
var current_tree: Node2D
var route_points: Array[Vector2] = []
var current_route_index: int = 0
var carried_wood: int = 0
var stuck_time_accum: float = 0.0
var evade_time_left: float = 0.0
var evade_direction: Vector2 = Vector2.ZERO

enum WorkerState {
	GOING_TO_TREE,
	CHOPPING_TREE,
	RETURNING_HOME,
}

var state: WorkerState = WorkerState.GOING_TO_TREE

const ANIM_IDLE: StringName = &"idle"
const ANIM_RUN: StringName = &"run"
const ANIM_CHOP: StringName = &"axed_animation"
const ANIM_WOOD_CARRY: StringName = &"wood_carry_animation"

func _ready() -> void:
	add_to_group("worker_npc")
	home_position = global_position
	gather_timer.wait_time = gather_interval
	gather_timer.timeout.connect(_on_gather_timer_timeout)
	_play_idle()

func _physics_process(delta: float) -> void:
	match state:
		WorkerState.GOING_TO_TREE:
			_process_going_to_tree(delta)
		WorkerState.CHOPPING_TREE:
			_process_chopping_tree()
		WorkerState.RETURNING_HOME:
			_process_returning_home(delta)

func set_home_position(new_home_position: Vector2) -> void:
	home_position = new_home_position
	global_position = new_home_position
	route_points.clear()
	current_route_index = 0

func set_assigned_house_position(new_house_position: Vector2) -> void:
	set_home_position(new_house_position)

func set_assigned_house(building: Node) -> void:
	if building == null:
		home_building_body = null
		return
	home_building_body = building.get_node_or_null("StaticBody2D") as PhysicsBody2D

func get_assigned_house_body() -> PhysicsBody2D:
	return home_building_body

func _on_gather_timer_timeout() -> void:
	if state != WorkerState.CHOPPING_TREE:
		return
	if not _is_tree_valid(current_tree):
		_enter_returning_home_state()
		return

	var harvested_amount: int = int(current_tree.call("harvest", chop_power))
	if harvested_amount > 0:
		carried_wood += harvested_amount

	if not _is_tree_valid(current_tree):
		_enter_returning_home_state()

func _find_nearest_tree() -> Node2D:
	var nearest_tree: Node2D
	var nearest_distance_sq: float = INF
	var nearest_tree_any_distance: Node2D
	var nearest_any_distance_sq: float = INF
	var all_trees: Array = get_tree().get_nodes_in_group("wood_resource")

	for tree_variant in all_trees:
		var tree := tree_variant as Node2D
		if not _is_tree_valid(tree):
			continue
		if not _is_tree_reachable(tree):
			continue

		var distance_sq: float = global_position.distance_squared_to(tree.global_position)
		if distance_sq < nearest_any_distance_sq:
			nearest_any_distance_sq = distance_sq
			nearest_tree_any_distance = tree

		if distance_sq > tree_search_radius * tree_search_radius:
			continue
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_tree = tree

	# Fallback: if no tree is inside radius, still take the globally nearest tree.
	if nearest_tree != null:
		return nearest_tree
	return nearest_tree_any_distance

func _is_tree_valid(tree: Node2D) -> bool:
	if tree == null or not is_instance_valid(tree):
		return false
	if not tree.is_in_group("wood_resource"):
		return false
	if tree.has_method("is_depleted") and bool(tree.call("is_depleted")):
		return false
	return true

func _process_going_to_tree(delta: float) -> void:
	if not _is_tree_valid(current_tree) or not _is_tree_reachable(current_tree):
		current_tree = _find_nearest_tree()
		_rebuild_route_to(current_tree.global_position if current_tree != null else home_position)

	if not _is_tree_valid(current_tree) or not _is_tree_reachable(current_tree):
		velocity = Vector2.ZERO
		_play_idle()
		move_and_slide()
		return

	_follow_route(delta)
	if _can_start_chopping(current_tree):
		state = WorkerState.CHOPPING_TREE
		_reset_movement_recovery()

func _process_chopping_tree() -> void:
	_reset_movement_recovery()
	velocity = Vector2.ZERO
	_play_chop()
	if gather_timer.is_stopped():
		gather_timer.start()
	move_and_slide()

	if not _is_tree_valid(current_tree):
		_enter_returning_home_state()

func _process_returning_home(delta: float) -> void:
	_follow_route(delta)
	if global_position.distance_to(home_position) <= home_reach_distance:
		if carried_wood > 0:
			wood_collected.emit(carried_wood)
			carried_wood = 0
		current_tree = _find_nearest_tree()
		state = WorkerState.GOING_TO_TREE
		_rebuild_route_to(current_tree.global_position if current_tree != null else home_position)

func _enter_returning_home_state() -> void:
	gather_timer.stop()
	state = WorkerState.RETURNING_HOME
	_reset_movement_recovery()
	_rebuild_route_to(home_position)

func _follow_route(delta: float) -> void:
	if route_points.is_empty():
		_reset_movement_recovery()
		velocity = Vector2.ZERO
		_play_idle()
		move_and_slide()
		return

	var current_target: Vector2 = route_points[current_route_index]
	if global_position.distance_to(current_target) <= waypoint_reached_distance:
		if current_route_index < route_points.size() - 1:
			current_route_index += 1
			current_target = route_points[current_route_index]

	if evade_time_left > 0.0:
		evade_time_left = maxf(evade_time_left - delta, 0.0)
		velocity = evade_direction * move_speed * evade_speed_multiplier
		_play_move_animation()
		move_and_slide()
		return

	var to_target: Vector2 = current_target - global_position
	if to_target.length() <= 0.001:
		_reset_movement_recovery()
		velocity = Vector2.ZERO
		_play_idle()
		move_and_slide()
		return

	var distance_before_move: float = global_position.distance_to(current_target)
	velocity = to_target.normalized() * move_speed
	if velocity.x < 0.0:
		sprite.flip_h = true
	elif velocity.x > 0.0:
		sprite.flip_h = false
	_play_move_animation()
	move_and_slide()
	var collision_normal: Vector2 = Vector2.ZERO
	if get_slide_collision_count() > 0:
		var collision: KinematicCollision2D = get_slide_collision(0)
		if collision != null:
			collision_normal = collision.get_normal()
	_update_stuck_recovery(delta, current_target, distance_before_move, to_target.normalized(), collision_normal)

func _rebuild_route_to(target_position: Vector2) -> void:
	route_points.clear()
	current_route_index = 0

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		route_points.append(target_position)
		return

	var world_script: Object = current_scene
	var worker_ground_class: int = 0
	var tree_ground_class: int = 0
	if world_script.has_method("get_ground_class_at_world"):
		worker_ground_class = int(world_script.call("get_ground_class_at_world", global_position))
		tree_ground_class = int(world_script.call("get_ground_class_at_world", target_position))

	var ladder_top := current_scene.get_node_or_null("EnemyRoute/LadderTop") as Node2D
	var ladder_bottom := current_scene.get_node_or_null("EnemyRoute/LadderBottom") as Node2D

	var worker_on_upper: bool = worker_ground_class == 1 or worker_ground_class == 3
	var worker_on_lower: bool = worker_ground_class == 2
	var tree_on_upper: bool = tree_ground_class == 1 or tree_ground_class == 3
	var tree_on_lower: bool = tree_ground_class == 2

	if ladder_top != null and ladder_bottom != null:
		if worker_on_upper and tree_on_lower:
			route_points.append(ladder_top.global_position)
			route_points.append(ladder_bottom.global_position)
		elif worker_on_lower and tree_on_upper:
			route_points.append(ladder_bottom.global_position)
			route_points.append(ladder_top.global_position)

	route_points.append(target_position)

func _update_stuck_recovery(delta: float, current_target: Vector2, distance_before_move: float, target_direction: Vector2, collision_normal: Vector2) -> void:
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
	_start_evade(target_direction, collision_normal)

func _start_evade(target_direction: Vector2, collision_normal: Vector2) -> void:
	var backoff_direction: Vector2 = _compute_backoff_direction(target_direction, collision_normal)
	var detour_direction: Vector2 = _compute_detour_direction(target_direction, collision_normal)
	evade_direction = backoff_direction
	evade_time_left = evade_duration
	_insert_escape_waypoints(backoff_direction, detour_direction)

func _compute_backoff_direction(target_direction: Vector2, collision_normal: Vector2) -> Vector2:
	if collision_normal.length_squared() > 0.0001:
		return collision_normal.normalized()
	if target_direction.length_squared() > 0.0001:
		return (-target_direction).normalized()
	return Vector2.LEFT

func _compute_detour_direction(target_direction: Vector2, collision_normal: Vector2) -> Vector2:
	if collision_normal.length_squared() > 0.0001:
		var tangent := Vector2(-collision_normal.y, collision_normal.x)
		if tangent.dot(target_direction) < 0.0:
			tangent = -tangent
		var blended := tangent + (collision_normal * 0.55) + (target_direction * detour_forward_weight)
		if blended.length_squared() > 0.0001:
			return blended.normalized()

	var side_sign: float = -1.0 if randf() < 0.5 else 1.0
	var fallback := Vector2(-target_direction.y, target_direction.x) * side_sign
	if fallback.length_squared() <= 0.0001:
		fallback = Vector2.RIGHT
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

	if current_route_index < route_points.size():
		route_points.insert(current_route_index, detour_point)
		route_points.insert(current_route_index, backoff_point)
	else:
		route_points.append(backoff_point)
		route_points.append(detour_point)

func _can_start_chopping(tree: Node2D) -> bool:
	if not _is_tree_valid(tree):
		return false
	if global_position.distance_to(tree.global_position) <= tree_reach_distance:
		return true
	return _is_colliding_with_tree(tree)

func _is_colliding_with_tree(tree: Node2D) -> bool:
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue
		var collider_node: Node = collision.get_collider() as Node
		if collider_node == tree:
			return true
	return false

func _is_tree_reachable(tree: Node2D) -> bool:
	if tree == null:
		return false

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return true

	# Trees must be in the same connected BottomGround region as the worker.
	# This avoids picking trees across cliff-separated areas.
	if current_scene.has_method("get_bottom_ground_region_id"):
		var worker_region: int = int(current_scene.call("get_bottom_ground_region_id", global_position))
		var tree_region: int = int(current_scene.call("get_bottom_ground_region_id", tree.global_position))
		if worker_region == -1 or tree_region == -1:
			return false
		return worker_region == tree_region

	return true

func _reset_movement_recovery() -> void:
	stuck_time_accum = 0.0
	evade_time_left = 0.0
	evade_direction = Vector2.ZERO

func _play_idle() -> void:
	if _has_animation(ANIM_IDLE):
		if sprite.animation != ANIM_IDLE:
			sprite.play(ANIM_IDLE)
		return

	if _has_animation(ANIM_RUN) and sprite.animation != ANIM_RUN:
		sprite.play(ANIM_RUN)

func _play_run() -> void:
	if _has_animation(ANIM_RUN) and sprite.animation != ANIM_RUN:
		sprite.play(ANIM_RUN)

func _play_chop() -> void:
	if _has_animation(ANIM_CHOP):
		if sprite.animation != ANIM_CHOP:
			sprite.play(ANIM_CHOP)
		return

	_play_idle()

func _play_move_animation() -> void:
	if state == WorkerState.RETURNING_HOME and carried_wood > 0 and _has_animation(ANIM_WOOD_CARRY):
		if sprite.animation != ANIM_WOOD_CARRY:
			sprite.play(ANIM_WOOD_CARRY)
		return
	_play_run()

func _has_animation(animation_name: StringName) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name)
