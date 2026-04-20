extends CharacterBody2D

signal gold_collected(amount: int)
signal resource_availability_changed(has_reachable_resource: bool)

@export var move_speed: float = 120.0
@export var resource_search_radius: float = 420.0
@export var harvest_radius_from_home: float = 560.0
@export var resource_reach_distance: float = 52.0
@export var home_reach_distance: float = 24.0
@export var waypoint_reached_distance: float = 12.0
@export var gather_interval: float = 1.0
@export var mine_power: int = 1
@export var stuck_progress_epsilon: float = 0.9
@export var stuck_repath_delay: float = 0.45
@export var evade_duration: float = 0.3
@export var evade_speed_multiplier: float = 0.8
@export var detour_distance: float = 64.0
@export_range(0.0, 1.0, 0.05) var detour_forward_weight: float = 0.3
@export var wall_backoff_distance: float = 56.0
@export var stuck_free_field_radius: float = 128.0
@export var stuck_free_field_step: float = 24.0
@export var stuck_free_field_angles: int = 16
@export var use_resource_staging_point: bool = false
@export var resource_staging_point_path: NodePath = ^""

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var gather_timer: Timer = $GatherTimer
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

var home_position: Vector2 = Vector2.ZERO
var home_building_body: PhysicsBody2D
var current_resource: Node2D
var route_points: Array[Vector2] = []
var current_route_index: int = 0
var carried_gold: int = 0
var stuck_time_accum: float = 0.0
var evade_time_left: float = 0.0
var evade_direction: Vector2 = Vector2.ZERO
var resource_staging_point: Node2D
var heading_to_staging_point: bool = false
var has_reachable_resource: bool = true

enum WorkerState {
	GOING_TO_RESOURCE,
	MINING_RESOURCE,
	RETURNING_HOME,
}

var state: WorkerState = WorkerState.GOING_TO_RESOURCE

const ANIM_IDLE: StringName = &"idle"
const ANIM_RUN: StringName = &"run"
const ANIM_MINE: StringName = &"mine_animation"
const ANIM_GOLD_CARRY: StringName = &"gold_carry_animation"

func _ready() -> void:
	add_to_group("worker_npc")
	home_position = global_position
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and resource_staging_point_path != ^"":
		resource_staging_point = current_scene.get_node_or_null(resource_staging_point_path) as Node2D
	gather_timer.wait_time = gather_interval
	gather_timer.timeout.connect(_on_gather_timer_timeout)
	_start_resource_search_cycle()
	_play_idle()

func has_reachable_resource_target() -> bool:
	return has_reachable_resource

func _physics_process(delta: float) -> void:
	match state:
		WorkerState.GOING_TO_RESOURCE:
			_process_going_to_resource(delta)
		WorkerState.MINING_RESOURCE:
			_process_mining_resource()
		WorkerState.RETURNING_HOME:
			_process_returning_home(delta)

func set_home_position(new_home_position: Vector2) -> void:
	home_position = new_home_position
	route_points.clear()
	current_route_index = 0
	if is_node_ready():
		_start_resource_search_cycle()

func set_assigned_house_position(new_house_position: Vector2) -> void:
	set_home_position(new_house_position)

func set_assigned_house(building: Node) -> void:
	if building == null:
		home_building_body = null
		return
	home_building_body = building.get_node_or_null("StaticBody2D") as PhysicsBody2D

func set_harvest_radius(new_radius: float) -> void:
	harvest_radius_from_home = maxf(new_radius, 0.0)

func get_assigned_house_body() -> PhysicsBody2D:
	return home_building_body

func _on_gather_timer_timeout() -> void:
	if state != WorkerState.MINING_RESOURCE:
		return
	if not _is_resource_valid(current_resource):
		_enter_returning_home_state()
		return

	var harvested_amount: int = int(current_resource.call("harvest", mine_power))
	if harvested_amount > 0:
		carried_gold += harvested_amount

	if not _is_resource_valid(current_resource):
		_enter_returning_home_state()

func _find_nearest_resource() -> Node2D:
	return _find_nearest_resource_from(global_position)

func _find_nearest_resource_from(origin_position: Vector2) -> Node2D:
	var nearest_resource: Node2D
	var nearest_distance_sq: float = INF
	var nearest_resource_any_distance: Node2D
	var nearest_any_distance_sq: float = INF
	var all_resources: Array = get_tree().get_nodes_in_group("gold_resource")

	for resource_variant in all_resources:
		var resource := resource_variant as Node2D
		if not _is_resource_valid(resource):
			continue
		if not _is_resource_reachable(resource):
			continue

		var distance_sq: float = origin_position.distance_squared_to(resource.global_position)
		if distance_sq < nearest_any_distance_sq:
			nearest_any_distance_sq = distance_sq
			nearest_resource_any_distance = resource

		if distance_sq > resource_search_radius * resource_search_radius:
			continue
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_resource = resource

	# Fallback: if no resource is inside radius, still take the globally nearest.
	if nearest_resource != null:
		return nearest_resource
	return nearest_resource_any_distance

func _is_resource_valid(resource_ref: Variant) -> bool:
	var resource: Node2D = _get_live_resource(resource_ref)
	if resource == null or not is_instance_valid(resource):
		return false
	if not resource.is_in_group("gold_resource"):
		return false
	if resource.has_method("is_depleted") and bool(resource.call("is_depleted")):
		return false
	return true

func _process_going_to_resource(delta: float) -> void:
	if heading_to_staging_point and _has_valid_staging_point():
		_follow_route(delta)
		if global_position.distance_to(resource_staging_point.global_position) <= waypoint_reached_distance:
			heading_to_staging_point = false
			current_resource = _find_nearest_resource_from(resource_staging_point.global_position)
			_set_resource_availability(current_resource != null)
			_rebuild_route_to(current_resource.global_position if current_resource != null else home_position)
		return

	if not _is_resource_valid(current_resource) or not _is_resource_reachable(current_resource):
		current_resource = _find_nearest_resource_from(global_position)
		_set_resource_availability(current_resource != null)
		_rebuild_route_to(current_resource.global_position if current_resource != null else home_position)

	if not _is_resource_valid(current_resource) or not _is_resource_reachable(current_resource):
		velocity = Vector2.ZERO
		_play_idle()
		move_and_slide()
		return

	_follow_route(delta)
	if _can_start_mining(current_resource):
		state = WorkerState.MINING_RESOURCE
		_reset_movement_recovery()

func _process_mining_resource() -> void:
	_reset_movement_recovery()
	velocity = Vector2.ZERO
	_play_mine()
	if gather_timer.is_stopped():
		gather_timer.start()
	move_and_slide()

	if not _is_resource_valid(current_resource):
		_enter_returning_home_state()

func _process_returning_home(delta: float) -> void:
	_follow_route(delta)
	if global_position.distance_to(home_position) <= home_reach_distance:
		if carried_gold > 0:
			gold_collected.emit(carried_gold)
			carried_gold = 0
		_start_resource_search_cycle()
		state = WorkerState.GOING_TO_RESOURCE

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
	var resource_ground_class: int = 0
	if world_script.has_method("get_ground_class_at_world"):
		worker_ground_class = int(world_script.call("get_ground_class_at_world", global_position))
		resource_ground_class = int(world_script.call("get_ground_class_at_world", target_position))

	var ladder_top := current_scene.get_node_or_null("EnemyRoute/LadderTop") as Node2D
	var ladder_bottom := current_scene.get_node_or_null("EnemyRoute/LadderBottom") as Node2D

	var worker_on_upper: bool = worker_ground_class == 1 or worker_ground_class == 3
	var worker_on_lower: bool = worker_ground_class == 2
	var resource_on_upper: bool = resource_ground_class == 1 or resource_ground_class == 3
	var resource_on_lower: bool = resource_ground_class == 2

	if ladder_top != null and ladder_bottom != null:
		if worker_on_upper and resource_on_lower:
			route_points.append(ladder_top.global_position)
			route_points.append(ladder_bottom.global_position)
		elif worker_on_lower and resource_on_upper:
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

func _can_start_mining(resource_ref: Variant) -> bool:
	var resource: Node2D = _get_live_resource(resource_ref)
	if not _is_resource_valid(resource):
		return false
	if global_position.distance_to(resource.global_position) <= resource_reach_distance:
		return true
	return _is_colliding_with_resource(resource)

func _is_colliding_with_resource(resource_ref: Variant) -> bool:
	var resource: Node2D = _get_live_resource(resource_ref)
	if resource == null:
		return false
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue
		var collider_node: Node = collision.get_collider() as Node
		if collider_node == resource:
			return true
	return false

func _is_resource_reachable(resource_ref: Variant) -> bool:
	var resource: Node2D = _get_live_resource(resource_ref)
	if resource == null:
		return false
	if home_position.distance_to(resource.global_position) > harvest_radius_from_home:
		return false

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return true

	if current_scene.has_method("get_bottom_ground_region_id"):
		var worker_region: int = int(current_scene.call("get_bottom_ground_region_id", global_position))
		var resource_region: int = int(current_scene.call("get_bottom_ground_region_id", resource.global_position))
		if worker_region == -1 or resource_region == -1:
			return false
		return worker_region == resource_region

	return true

func _get_live_resource(resource_ref: Variant) -> Node2D:
	if resource_ref == null:
		return null
	if not is_instance_valid(resource_ref):
		return null
	return resource_ref as Node2D

func _start_resource_search_cycle() -> void:
	current_resource = null
	_reset_movement_recovery()

	if use_resource_staging_point and _has_valid_staging_point():
		heading_to_staging_point = true
		current_resource = _find_nearest_resource_from(resource_staging_point.global_position)
		_set_resource_availability(current_resource != null)
		_rebuild_route_to(resource_staging_point.global_position)
		return

	heading_to_staging_point = false
	current_resource = _find_nearest_resource_from(global_position)
	_set_resource_availability(current_resource != null)
	_rebuild_route_to(current_resource.global_position if current_resource != null else home_position)

func _set_resource_availability(has_resource: bool) -> void:
	if has_reachable_resource == has_resource:
		return
	has_reachable_resource = has_resource
	resource_availability_changed.emit(has_reachable_resource)

func _has_valid_staging_point() -> bool:
	return resource_staging_point != null and is_instance_valid(resource_staging_point)

func _find_nearby_free_field(preferred_position: Vector2) -> Vector2:
	if _is_position_free_for_worker(preferred_position):
		return preferred_position

	var max_radius: float = maxf(stuck_free_field_radius, 0.0)
	var step: float = maxf(stuck_free_field_step, 8.0)
	var angle_count: int = maxi(stuck_free_field_angles, 8)

	var radius: float = step
	while radius <= max_radius:
		for i in angle_count:
			var angle: float = (TAU * float(i)) / float(angle_count)
			var candidate := global_position + Vector2(cos(angle), sin(angle)) * radius
			if _is_position_free_for_worker(candidate):
				return candidate
		radius += step

	return preferred_position

func _is_position_free_for_worker(candidate_position: Vector2) -> bool:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_ground_class_at_world"):
		var ground_class: int = int(current_scene.call("get_ground_class_at_world", candidate_position))
		if ground_class != 2:
			return false

	if current_scene != null and current_scene.has_method("get_bottom_ground_region_id"):
		var worker_region: int = int(current_scene.call("get_bottom_ground_region_id", global_position))
		var candidate_region: int = int(current_scene.call("get_bottom_ground_region_id", candidate_position))
		if worker_region == -1 or candidate_region == -1 or worker_region != candidate_region:
			return false

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
		if collider_obj == current_resource:
			continue
		return false

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

func _play_mine() -> void:
	if _has_animation(ANIM_MINE):
		if sprite.animation != ANIM_MINE:
			sprite.play(ANIM_MINE)
		return

	_play_idle()

func _play_move_animation() -> void:
	if state == WorkerState.RETURNING_HOME and carried_gold > 0 and _has_animation(ANIM_GOLD_CARRY):
		if sprite.animation != ANIM_GOLD_CARRY:
			sprite.play(ANIM_GOLD_CARRY)
		return
	_play_run()

func _has_animation(animation_name: StringName) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name)
