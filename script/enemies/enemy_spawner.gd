extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/bomb_enemy.tscn")
@export var enemies_parent_path: NodePath = ^".."
@export var border_trees_path: NodePath = ^"../../BorderTree"
@export var spawn_interval: float = 3.5
@export var max_active_enemies: int = 6
@export var initial_spawn_count: int = 2
@export var spawn_offset_toward_base: float = 88.0
@export var spawn_sideways_jitter: float = 24.0
@export var minimum_spawn_distance_from_base: float = 900.0
@export var source_tree_count: int = 24

@onready var spawn_timer: Timer = $SpawnTimer

var spawn_points: Array[Vector2] = []

func _ready() -> void:
	call_deferred("_initialize_spawner")

func _initialize_spawner() -> void:
	randomize()
	collect_spawn_points()
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.wait_time = maxf(spawn_interval, 0.1)
	print("EnemySpawner ready. spawn_points=", spawn_points.size())

	for _spawn_index in range(initial_spawn_count):
		spawn_enemy()

	if enemy_scene != null and not spawn_points.is_empty():
		spawn_timer.start()
	else:
		print("EnemySpawner could not start. enemy_scene=", enemy_scene, " spawn_points=", spawn_points.size())

func collect_spawn_points() -> void:
	spawn_points.clear()

	var border_trees: Node = resolve_border_trees()
	var base := get_tree().get_first_node_in_group("base") as Node2D

	if border_trees == null:
		push_warning("EnemySpawner could not find the border tree container.")
		return

	if base == null:
		push_warning("EnemySpawner could not find a node in the 'base' group.")
		return

	var candidate_trees: Array[Node2D] = gather_candidate_trees(border_trees)
	for tree in candidate_trees:
		var direction_to_base: Vector2 = tree.global_position.direction_to(base.global_position)
		if direction_to_base == Vector2.ZERO:
			continue

		var sideways: Vector2 = Vector2(-direction_to_base.y, direction_to_base.x) * randf_range(-spawn_sideways_jitter, spawn_sideways_jitter)
		var spawn_position: Variant = find_valid_spawn_position(
			tree.global_position,
			direction_to_base,
			sideways,
			base.global_position
		)

		if spawn_position != null:
			spawn_points.append(spawn_position)

	if spawn_points.is_empty():
		var fallback_position: Variant = find_fallback_spawn_position(base.global_position)
		if fallback_position != null:
			spawn_points.append(fallback_position)

	if spawn_points.is_empty():
		push_warning("EnemySpawner did not generate any spawn points from the border trees.")
	else:
		print("EnemySpawner collected spawn points: ", spawn_points.size())

func spawn_enemy() -> void:
	if enemy_scene == null or spawn_points.is_empty():
		return

	var enemies_parent: Node = resolve_enemies_parent()
	if enemies_parent == null:
		push_warning("EnemySpawner could not find the enemies container.")
		return

	if enemies_parent.get_child_count() >= max_active_enemies:
		return

	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_warning("EnemySpawner enemy_scene must instantiate to a Node2D.")
		return

	var spawn_position: Vector2 = spawn_points.pick_random()
	enemies_parent.add_child(enemy)
	enemy.global_position = spawn_position
	print("EnemySpawner spawned enemy at ", spawn_position)

func _on_spawn_timer_timeout() -> void:
	spawn_enemy()

func resolve_enemies_parent() -> Node:
	if get_parent() != null and get_parent().name == "Enemies":
		return get_parent()

	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var scene_enemies: Node = current_scene.get_node_or_null("Enemies")
		if scene_enemies != null:
			return scene_enemies

	var configured_parent: Node = get_node_or_null(enemies_parent_path)
	if configured_parent != null:
		return configured_parent

	return null

func resolve_border_trees() -> Node:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var scene_border_trees: Node = current_scene.get_node_or_null("BorderTree")
		if scene_border_trees != null:
			return scene_border_trees

	var configured_border_trees: Node = get_node_or_null(border_trees_path)
	if configured_border_trees != null:
		return configured_border_trees

	return null

func gather_candidate_trees(border_trees: Node) -> Array[Node2D]:
	var trees: Array[Node2D] = []
	for child in border_trees.get_children():
		var tree: Node2D = child as Node2D
		if tree != null:
			trees.append(tree)

	trees.sort_custom(_sort_tree_by_distance_to_spawner)

	if trees.size() > source_tree_count:
		trees.resize(source_tree_count)

	return trees

func _sort_tree_by_distance_to_spawner(a: Node2D, b: Node2D) -> bool:
	return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position)

func find_valid_spawn_position(
	tree_position: Vector2,
	direction_to_base: Vector2,
	sideways: Vector2,
	base_position: Vector2
) -> Variant:
	var candidate: Vector2 = tree_position + direction_to_base * spawn_offset_toward_base + sideways
	if candidate.distance_to(base_position) < minimum_spawn_distance_from_base:
		return null

	return candidate

func find_fallback_spawn_position(base_position: Vector2) -> Variant:
	var direction_to_base: Vector2 = global_position.direction_to(base_position)
	if direction_to_base == Vector2.ZERO:
		return null

	var sideways: Vector2 = Vector2(-direction_to_base.y, direction_to_base.x) * randf_range(-spawn_sideways_jitter, spawn_sideways_jitter)
	return find_valid_spawn_position(global_position, direction_to_base, sideways, base_position)
