extends Node2D

const WORKER_BUILDING_SCENE := preload("res://scenes/building/worker_building.tscn")
const WOOD_WORKER_SCENE := preload("res://scenes/character/wood_worker.tscn")
const TREE_RESOURCE_SCENE := preload("res://scenes/building/tree_resource.tscn")
const WOOD_RESOURCE_ICON := preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Wood Resource/Wood Resource.png")
const FOOD_RESOURCE_ICON := preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Meat/Meat Resource/Meat Resource.png")
const GOLD_RESOURCE_ICON := preload("res://assets/Tiny Swords (Free Pack)/Terrain/Resources/Gold/Gold Resource/Gold_Resource.png")

const WORKER_BUILDINGS := {
	&"worker_wood": {
		"building_id": &"worker_wood",
		"building_name": "Wood Worker",
		"building_texture": preload("res://assets/Tiny Swords (Free Pack)/Buildings/Blue Buildings/House1.png"),
		"gold_cost": 75,
		"sprite_offset": Vector2(0, -18),
	},
	&"worker_meat": {
		"building_id": &"worker_meat",
		"building_name": "Food Worker",
		"building_texture": preload("res://assets/Tiny Swords (Free Pack)/Buildings/Red Buildings/House1.png"),
		"gold_cost": 100,
		"sprite_offset": Vector2(0, -18),
	},
	&"worker_gold": {
		"building_id": &"worker_gold",
		"building_name": "Gold Worker",
		"building_texture": preload("res://assets/Tiny Swords (Free Pack)/Buildings/Yellow Buildings/House1.png"),
		"gold_cost": 125,
		"sprite_offset": Vector2(0, -18),
	},
}

@export var starting_wood: int = 0
@export var starting_food: int = 0
@export var starting_gold: int = 150
@export var placement_grid_size: int = 16
@export var enforce_stable_ground: bool = true
@export_range(0.1, 1.0, 0.05) var footprint_sample_ratio: float = 0.85
@export var spawn_random_wood_trees: bool = true
@export_range(1, 200, 1) var random_wood_tree_count: int = 20
@export var replace_existing_wood_trees: bool = true
@export var wood_tree_min_spacing: float = 80.0
@export var wood_tree_jitter: float = 6.0
@export var wood_tree_ground_check_radius: float = 22.0

@onready var player: CharacterBody2D = $CharacterScene
@onready var ui_manager: CanvasLayer = $UI/UIManager
@onready var main_building_root: Node = $"Main Building"
@onready var top_ground_layer: TileMapLayer = $GroundLayer/TopGround
@onready var bottom_ground_layer: TileMapLayer = $GroundLayer/BottomGround
@onready var wood_resources_root: Node2D = get_node_or_null("WoodResources") as Node2D

var bottom_ground_regions: Dictionary = {}

var resources := {
	&"wood": 0,
	&"food": 0,
	&"gold": 0,
}
var owned_buildings := {}
var active_preview: Node2D
var active_building_id: StringName = &""
var waiting_for_confirm_release := false

func _ready() -> void:
	_spawn_initial_wood_trees()
	_build_bottom_ground_regions()

	resources[&"wood"] = starting_wood
	resources[&"food"] = starting_food
	resources[&"gold"] = starting_gold

	for building_id in WORKER_BUILDINGS.keys():
		owned_buildings[building_id] = 0
		ui_manager.call("set_building_quantity", building_id, 0)
		ui_manager.call("set_building_gold_cost", building_id, WORKER_BUILDINGS[building_id]["gold_cost"])

	ui_manager.call("set_resource_icon", &"wood", WOOD_RESOURCE_ICON)
	ui_manager.call("set_resource_icon", &"food", FOOD_RESOURCE_ICON)
	ui_manager.call("set_resource_icon", &"gold", GOLD_RESOURCE_ICON)
	ui_manager.call("set_resource_amount", &"wood", resources[&"wood"])
	ui_manager.call("set_resource_amount", &"food", resources[&"food"])
	ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])
	ui_manager.building_requested.connect(_on_building_requested)
	_refresh_building_availability()

func _process(_delta: float) -> void:
	if active_preview == null:
		return

	_update_preview_position()
	var can_place: bool = _can_place_active_preview()
	active_preview.call("set_placement_valid", can_place)

	if waiting_for_confirm_release:
		if not Input.is_action_pressed("attack"):
			waiting_for_confirm_release = false
		return

	if Input.is_action_just_pressed("defend"):
		_cancel_active_preview()
		return

	if Input.is_action_just_pressed("attack") and can_place and not _is_pointer_over_ui():
		_confirm_active_preview()

func _on_building_requested(building_id: StringName, _gold_cost: int) -> void:
	if not WORKER_BUILDINGS.has(building_id):
		return
	if resources[&"gold"] < WORKER_BUILDINGS[building_id]["gold_cost"]:
		return

	_begin_placement(building_id)

func _begin_placement(building_id: StringName) -> void:
	_cancel_active_preview()
	active_building_id = building_id
	waiting_for_confirm_release = Input.is_action_pressed("attack")
	ui_manager.call("close_shop_immediately")
	_set_placement_pause_state(true)
	ui_manager.call("set_shop_toggle_enabled", false)
	player.call("set_input_locked", true)

	active_preview = WORKER_BUILDING_SCENE.instantiate()
	active_preview.call("configure", WORKER_BUILDINGS[building_id])
	active_preview.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(active_preview)
	active_preview.call("set_preview_mode", true)
	_update_preview_position()

func _cancel_active_preview() -> void:
	if active_preview != null:
		active_preview.queue_free()
	active_preview = null
	active_building_id = &""
	waiting_for_confirm_release = false
	_set_placement_pause_state(false)
	ui_manager.call("set_shop_toggle_enabled", true)
	player.call("set_input_locked", false)

func _confirm_active_preview() -> void:
	var building_id: StringName = active_building_id
	var placement_position: Vector2 = active_preview.global_position
	_cancel_active_preview()

	var building: Node2D = WORKER_BUILDING_SCENE.instantiate() as Node2D
	building.call("configure", WORKER_BUILDINGS[building_id])
	building.global_position = placement_position
	main_building_root.add_child(building)
	_spawn_worker_for_building(building_id, building)
	_refresh_all_worker_building_collisions()

	owned_buildings[building_id] += 1
	resources[&"gold"] -= WORKER_BUILDINGS[building_id]["gold_cost"]
	ui_manager.call("set_building_quantity", building_id, owned_buildings[building_id])
	ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])
	_refresh_building_availability()

func _refresh_building_availability() -> void:
	for building_id in WORKER_BUILDINGS.keys():
		var can_afford: bool = resources[&"gold"] >= int(WORKER_BUILDINGS[building_id]["gold_cost"])
		ui_manager.call("set_building_purchase_enabled", building_id, can_afford)

func _update_preview_position() -> void:
	var mouse_position := get_global_mouse_position()
	active_preview.global_position = Vector2(
		snappedf(mouse_position.x, placement_grid_size),
		snappedf(mouse_position.y, placement_grid_size)
	)

func _can_place_active_preview() -> bool:
	if active_preview == null:
		return false
	if _is_pointer_over_ui():
		return false
	if enforce_stable_ground and not _is_on_stable_ground():
		return false

	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = active_preview.call("get_placement_shape") as Shape2D
	shape_query.transform = active_preview.call("get_placement_transform") as Transform2D
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = true

	var collisions: Array = get_world_2d().direct_space_state.intersect_shape(shape_query, 16)
	return not _has_invalid_placement_collision(collisions)

func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _has_invalid_placement_collision(collisions: Array) -> bool:
	for hit_variant in collisions:
		var hit: Dictionary = hit_variant as Dictionary
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == null:
			continue

		if collider_obj is PhysicsBody2D:
			return true

		if collider_obj is Area2D and (collider_obj as Area2D).is_in_group("no_build_zone"):
			return true

	return false

func _is_on_stable_ground() -> bool:
	if top_ground_layer == null or bottom_ground_layer == null:
		return true

	var sample_points: Array[Vector2] = _get_preview_sample_points()

	for sample_point in sample_points:
		var ground_class: int = get_ground_class_at_world(sample_point)
		# Worker buildings are allowed only on BottomGround (class 2),
		# not on TopGround or mixed top+bottom cells.
		if ground_class != 2:
			return false

	return true

func _get_preview_sample_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if active_preview == null:
		return points

	var center: Vector2 = active_preview.global_position
	points.append(center)

	var shape: Shape2D = active_preview.call("get_placement_shape") as Shape2D
	if shape is RectangleShape2D:
		var half_size: Vector2 = (shape as RectangleShape2D).size * 0.5 * footprint_sample_ratio
		points.append(center + Vector2(-half_size.x, -half_size.y))
		points.append(center + Vector2(half_size.x, -half_size.y))
		points.append(center + Vector2(-half_size.x, half_size.y))
		points.append(center + Vector2(half_size.x, half_size.y))
	elif shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius * footprint_sample_ratio
		points.append(center + Vector2(radius, 0.0))
		points.append(center + Vector2(-radius, 0.0))
		points.append(center + Vector2(0.0, radius))
		points.append(center + Vector2(0.0, -radius))

	return points

func get_ground_class_at_world(world_position: Vector2) -> int:
	var top_cell: Vector2i = top_ground_layer.local_to_map(top_ground_layer.to_local(world_position))
	var bottom_cell: Vector2i = bottom_ground_layer.local_to_map(bottom_ground_layer.to_local(world_position))

	var top_source_id: int = top_ground_layer.get_cell_source_id(top_cell)
	var bottom_source_id: int = bottom_ground_layer.get_cell_source_id(bottom_cell)
	var has_top: bool = top_source_id != -1
	var has_bottom: bool = bottom_source_id != -1

	if has_top and not has_bottom:
		return 1
	if has_bottom and not has_top:
		return 2
	if has_top and has_bottom:
		return 3
	return 0

func get_bottom_ground_region_id(world_position: Vector2) -> int:
	if top_ground_layer == null or bottom_ground_layer == null:
		return -1

	var bottom_cell: Vector2i = bottom_ground_layer.local_to_map(bottom_ground_layer.to_local(world_position))
	if not _is_bottom_only_cell(bottom_cell):
		return -1

	if not bottom_ground_regions.has(bottom_cell):
		return -1

	return int(bottom_ground_regions[bottom_cell])

func _set_placement_pause_state(is_paused: bool) -> void:
	# Placement freeze uses time_scale so global tree pause remains dedicated to shop pause.
	Engine.time_scale = 0.0 if is_paused else 1.0

func _spawn_worker_for_building(building_id: StringName, building: Node2D) -> void:
	if building_id != &"worker_wood":
		return

	var worker: CharacterBody2D = WOOD_WORKER_SCENE.instantiate() as CharacterBody2D
	worker.global_position = building.global_position + Vector2(28.0, 14.0)
	main_building_root.add_child(worker)
	# Use the building center as the worker home target to avoid edge/cliff oscillation.
	worker.call("set_assigned_house_position", building.global_position)
	worker.call("set_assigned_house", building)
	worker.connect("wood_collected", Callable(self, "_on_wood_worker_collected"))

func _refresh_all_worker_building_collisions() -> void:
	var workers: Array = get_tree().get_nodes_in_group("worker_npc")
	var building_bodies: Array[PhysicsBody2D] = _get_worker_building_bodies()

	for worker_variant in workers:
		var worker_body := worker_variant as CharacterBody2D
		if worker_body == null:
			continue

		worker_body.add_collision_exception_with(player)

		for enemy_variant in get_tree().get_nodes_in_group("enemies"):
			var enemy_body := enemy_variant as PhysicsBody2D
			if enemy_body != null:
				worker_body.add_collision_exception_with(enemy_body)

		for other_worker_variant in workers:
			var other_worker := other_worker_variant as CharacterBody2D
			if other_worker != null and other_worker != worker_body:
				worker_body.add_collision_exception_with(other_worker)

		for house_body in building_bodies:
			worker_body.add_collision_exception_with(house_body)

func _get_worker_building_bodies() -> Array[PhysicsBody2D]:
	var bodies: Array[PhysicsBody2D] = []
	for child in main_building_root.get_children():
		var building_node := child as Node
		if building_node == null:
			continue
		var body := building_node.get_node_or_null("StaticBody2D") as PhysicsBody2D
		if body != null:
			bodies.append(body)
	return bodies

func _on_wood_worker_collected(amount: int) -> void:
	resources[&"wood"] += amount
	ui_manager.call("set_resource_amount", &"wood", resources[&"wood"])

func _spawn_initial_wood_trees() -> void:
	if not spawn_random_wood_trees:
		return
	if bottom_ground_layer == null:
		return

	if wood_resources_root == null:
		wood_resources_root = Node2D.new()
		wood_resources_root.name = "WoodResources"
		add_child(wood_resources_root)

	if replace_existing_wood_trees:
		for child in wood_resources_root.get_children():
			child.queue_free()

	var candidate_positions: Array[Vector2] = _get_bottom_ground_candidate_positions()
	if candidate_positions.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var spawned_positions: Array[Vector2] = []
	var target_count: int = max(random_wood_tree_count, 0)
	var attempts_left: int = candidate_positions.size()

	while spawned_positions.size() < target_count and attempts_left > 0 and not candidate_positions.is_empty():
		attempts_left -= 1
		var index: int = rng.randi_range(0, candidate_positions.size() - 1)
		var base_position: Vector2 = candidate_positions[index]
		candidate_positions.remove_at(index)

		var jittered_position := base_position + Vector2(
			rng.randf_range(-wood_tree_jitter, wood_tree_jitter),
			rng.randf_range(-wood_tree_jitter, wood_tree_jitter)
		)
		if not _is_valid_bottom_tree_position(jittered_position):
			continue

		var can_place_here: bool = true
		for existing_position in spawned_positions:
			var existing_vec: Vector2 = existing_position
			if existing_vec.distance_to(jittered_position) < wood_tree_min_spacing:
				can_place_here = false
				break
		if not can_place_here:
			continue

		var tree: Node2D = TREE_RESOURCE_SCENE.instantiate() as Node2D
		tree.global_position = jittered_position
		wood_resources_root.add_child(tree)
		spawned_positions.append(jittered_position)

func _get_bottom_ground_candidate_positions() -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	var used_cells: Array = bottom_ground_layer.get_used_cells()
	for cell_variant in used_cells:
		var cell: Vector2i = cell_variant as Vector2i
		if top_ground_layer != null and top_ground_layer.get_cell_source_id(cell) != -1:
			continue

		var local_pos: Vector2 = bottom_ground_layer.map_to_local(cell)
		var world_pos: Vector2 = bottom_ground_layer.to_global(local_pos)
		candidates.append(world_pos)

	return candidates

func _is_valid_bottom_tree_position(world_position: Vector2) -> bool:
	var sample_radius: float = maxf(wood_tree_ground_check_radius, 0.0)
	var samples: Array[Vector2] = [
		world_position,
		world_position + Vector2(sample_radius, 0.0),
		world_position + Vector2(-sample_radius, 0.0),
		world_position + Vector2(0.0, sample_radius),
		world_position + Vector2(0.0, -sample_radius),
	]

	for sample in samples:
		# 2 means: bottom layer present and top layer absent.
		if get_ground_class_at_world(sample) != 2:
			return false

	return true

func _build_bottom_ground_regions() -> void:
	bottom_ground_regions.clear()
	if top_ground_layer == null or bottom_ground_layer == null:
		return

	var visited: Dictionary = {}
	var region_id: int = 0
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

	for cell_variant in bottom_ground_layer.get_used_cells():
		var start_cell: Vector2i = cell_variant as Vector2i
		if visited.has(start_cell):
			continue
		if not _is_bottom_only_cell(start_cell):
			continue

		var queue: Array[Vector2i] = [start_cell]
		var queue_index: int = 0
		visited[start_cell] = true
		bottom_ground_regions[start_cell] = region_id

		while queue_index < queue.size():
			var current_cell: Vector2i = queue[queue_index]
			queue_index += 1

			for direction in directions:
				var neighbor: Vector2i = current_cell + direction
				if visited.has(neighbor):
					continue
				if not _is_bottom_only_cell(neighbor):
					continue

				visited[neighbor] = true
				bottom_ground_regions[neighbor] = region_id
				queue.append(neighbor)

		region_id += 1

func _is_bottom_only_cell(cell: Vector2i) -> bool:
	if bottom_ground_layer == null:
		return false

	var bottom_source_id: int = bottom_ground_layer.get_cell_source_id(cell)
	if bottom_source_id == -1:
		return false

	if top_ground_layer == null:
		return true

	var top_source_id: int = top_ground_layer.get_cell_source_id(cell)
	return top_source_id == -1
