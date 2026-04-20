extends Node2D

const WOOD_WORKER_BUILDING_SCENE := preload("res://scenes/buildings/wood_worker_building.tscn")
const FOOD_WORKER_BUILDING_SCENE := preload("res://scenes/buildings/food_worker_building.tscn")
const MINER_WORKER_BUILDING_SCENE := preload("res://scenes/buildings/miner_worker_building.tscn")
const WOOD_WORKER_SCENE := preload("res://scenes/character/wood_worker.tscn")
const FOOD_WORKER_SCENE := preload("res://scenes/character/food_worker.tscn")
const GOLD_WORKER_SCENE := preload("res://scenes/character/gold_worker.tscn")
const TREE_RESOURCE_SCENE := preload("res://scenes/resources/tree_resource.tscn")
const SHEEP_RESOURCE_SCENE := preload("res://scenes/resources/sheep_resource.tscn")
const GOLD_RESOURCE_SCENE := preload("res://scenes/resources/gold_resource.tscn")

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
const BUILDING_SELL_REFUND_RATIO: float = 0.6
const BUILDING_UPGRADE_COST_BASE_RATIO: float = 0.65
const BUILDING_UPGRADE_COST_GROWTH: float = 1.4
const BUILDING_MAX_UPGRADE_LEVEL: int = 5
const BUILDING_UPGRADE_HARVEST_RADIUS_BONUS: float = 80.0
const BUILDING_UPGRADE_WORKER_MOVE_SPEED_BONUS: float = 12.0
const WOOD_WORKER_BASE_MOVE_SPEED: float = 120.0
const WORKER_HOME_TELEPORT_OFFSET := Vector2(28.0, 14.0)
const TREE_REPLACEMENT_MIN_RADIUS: float = 120.0
const TREE_REPLACEMENT_MAX_RADIUS: float = 280.0
const TREE_REPLACEMENT_RANDOM_ATTEMPTS: int = 56
const TREE_WARNING_REFRESH_INTERVAL: float = 0.4
const RESOURCE_BORDER_CLEARANCE: float = 120.0

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
@export var wood_tree_edge_clearance_radius: float = 34.0
@export var building_edge_clearance_radius: float = 34.0
@export var spawn_random_food_sheep: bool = true
@export_range(1, 200, 1) var random_food_sheep_count: int = 20
@export var replace_existing_food_sheep: bool = true
@export var food_sheep_min_spacing: float = 60.0
@export var food_sheep_jitter: float = 8.0
@export var spawn_random_gold_stones: bool = true
@export_range(1, 200, 1) var random_gold_stone_count: int = 20
@export var replace_existing_gold_stones: bool = true
@export var gold_stone_min_spacing: float = 70.0
@export var gold_stone_jitter: float = 6.0

@onready var player: CharacterBody2D = $CharacterScene
@onready var ui_manager: CanvasLayer = $UI/UIManager
@onready var main_building_root: Node = $"Main Building"
@onready var top_ground_layer: TileMapLayer = $GroundLayer/TopGround
@onready var bottom_ground_layer: TileMapLayer = $GroundLayer/BottomGround
@onready var wood_resources_root: Node2D = get_node_or_null("WoodResources") as Node2D
@onready var food_resources_root: Node2D = get_node_or_null("FoodResources") as Node2D
@onready var gold_resources_root: Node2D = get_node_or_null("GoldResources") as Node2D

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
var moving_building: Node2D
var moving_building_original_position: Vector2 = Vector2.ZERO
var pending_upgrade_building: Node2D
var pending_upgrade_cost: int = 0
var pending_upgrade_radius_bonus: float = 0.0
var pending_upgrade_worker_speed_bonus: float = 0.0
var tree_warning_refresh_accum: float = 0.0

# Weighted tier table for gold stone spawning.
# Smaller stones are more common, bigger ones are rarer.
const GOLD_STONE_TIER_WEIGHTS := {
	3: 40,
	4: 30,
	5: 20,
	6: 10,
}

func _ready() -> void:
	_build_bottom_ground_regions()
	_spawn_initial_wood_trees()
	_spawn_initial_food_sheep()
	_spawn_initial_gold_stones()
	_register_existing_tree_resources()
	_register_existing_sheep_resources()
	_register_existing_gold_resources()

	resources[&"wood"] = starting_wood
	resources[&"food"] = starting_food
	resources[&"gold"] = starting_gold

	for building_id in WORKER_BUILDINGS.keys():
		owned_buildings[building_id] = 0
		ui_manager.call("set_building_quantity", building_id, 0)
		ui_manager.call("set_building_gold_cost", building_id, WORKER_BUILDINGS[building_id]["gold_cost"])

	ui_manager.call("set_resource_amount", &"wood", resources[&"wood"])
	ui_manager.call("set_resource_amount", &"food", resources[&"food"])
	ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])
	ui_manager.building_requested.connect(_on_building_requested)
	_refresh_building_availability()
	_refresh_worker_tree_warnings()

func _process(_delta: float) -> void:
	_update_worker_tree_warnings(_delta)

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

func _update_worker_tree_warnings(delta: float) -> void:
	tree_warning_refresh_accum += delta
	if tree_warning_refresh_accum < TREE_WARNING_REFRESH_INTERVAL:
		return
	tree_warning_refresh_accum = 0.0
	_refresh_worker_tree_warnings()

func _refresh_worker_tree_warnings() -> void:
	for building_variant in get_tree().get_nodes_in_group("worker_building"):
		var building := building_variant as Node2D
		if building == null:
			continue

		var building_id: StringName = building.get("building_id") as StringName
		if building_id == &"worker_wood":
			var home_position: Vector2 = building.global_position
			var harvest_radius: float = float(building.get("harvest_radius"))
			var has_resource: bool = _has_reachable_resource_for_home(home_position, harvest_radius, "wood_resource")
			building.call("set_tree_warning_visible", not has_resource)
		elif building_id == &"worker_meat":
			var home_position: Vector2 = building.global_position
			var harvest_radius: float = float(building.get("harvest_radius"))
			var has_resource: bool = _has_reachable_resource_for_home(home_position, harvest_radius, "food_resource")
			building.call("set_tree_warning_visible", not has_resource, "No Sheep")
		elif building_id == &"worker_gold":
			var home_position: Vector2 = building.global_position
			var harvest_radius: float = float(building.get("harvest_radius"))
			var has_resource: bool = _has_reachable_resource_for_home(home_position, harvest_radius, "gold_resource")
			building.call("set_tree_warning_visible", not has_resource, "No Gold")
		else:
			building.call("set_tree_warning_visible", false)

func _has_reachable_resource_for_home(home_position: Vector2, harvest_radius: float, resource_group: String) -> bool:
	var worker_region: int = -1
	if has_method("get_bottom_ground_region_id"):
		worker_region = get_bottom_ground_region_id(home_position)

	for tree_variant in get_tree().get_nodes_in_group(resource_group):
		var tree := tree_variant as Node2D
		if tree == null or not is_instance_valid(tree):
			continue
		if tree.has_method("is_depleted") and bool(tree.call("is_depleted")):
			continue
		if home_position.distance_to(tree.global_position) > harvest_radius:
			continue

		if worker_region != -1 and has_method("get_bottom_ground_region_id"):
			var tree_region: int = get_bottom_ground_region_id(tree.global_position)
			if tree_region == -1 or tree_region != worker_region:
				continue

		return true

	return false

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

	if building_id == &"worker_wood":
		active_preview = WOOD_WORKER_BUILDING_SCENE.instantiate()
	elif building_id == &"worker_meat":
		active_preview = FOOD_WORKER_BUILDING_SCENE.instantiate()
	elif building_id == &"worker_gold":
		active_preview = MINER_WORKER_BUILDING_SCENE.instantiate()
	if active_preview == null:
		return
	active_preview.call("configure", _get_building_config(building_id))
	active_preview.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(active_preview)
	active_preview.call("set_preview_mode", true)
	_update_preview_position()

func _cancel_active_preview() -> void:
	if active_preview != null:
		if _is_moving_existing_building():
			moving_building.global_position = moving_building_original_position
			moving_building.call("set_preview_mode", false)
		else:
			active_preview.queue_free()
	active_preview = null
	active_building_id = &""
	waiting_for_confirm_release = false
	moving_building = null
	moving_building_original_position = Vector2.ZERO
	_set_placement_pause_state(false)
	ui_manager.call("set_shop_toggle_enabled", true)

func _confirm_active_preview() -> void:
	var placement_position: Vector2 = active_preview.global_position
	if _is_moving_existing_building():
		var moved_building: Node2D = moving_building
		active_preview = null
		active_building_id = &""
		waiting_for_confirm_release = false
		moving_building = null
		moving_building_original_position = Vector2.ZERO
		_set_placement_pause_state(false)
		ui_manager.call("set_shop_toggle_enabled", true)

		moved_building.global_position = placement_position
		moved_building.call("set_preview_mode", false)
		_update_workers_assigned_house_position(moved_building)
		_teleport_workers_assigned_to_building(moved_building)
		_refresh_all_worker_building_collisions()
		return

	var building_id: StringName = active_building_id
	_cancel_active_preview()
	var building_config: Dictionary = _get_building_config(building_id)

	var building: Node2D
	if building_id == &"worker_wood":
		building = WOOD_WORKER_BUILDING_SCENE.instantiate() as Node2D
	elif building_id == &"worker_meat":
		building = FOOD_WORKER_BUILDING_SCENE.instantiate() as Node2D
	elif building_id == &"worker_gold":
		building = MINER_WORKER_BUILDING_SCENE.instantiate() as Node2D
	if building == null:
		return
	building.call("configure", building_config)
	building.global_position = placement_position
	building.connect("upgrade_requested", Callable(self, "_on_worker_building_upgrade_requested"))
	building.connect("upgrade_confirmed", Callable(self, "_on_worker_building_upgrade_confirmed"))
	building.connect("upgrade_canceled", Callable(self, "_on_worker_building_upgrade_canceled"))
	building.connect("move_requested", Callable(self, "_on_worker_building_move_requested"))
	building.connect("sell_requested", Callable(self, "_on_worker_building_sell_requested"))
	main_building_root.add_child(building)
	_spawn_worker_for_building(building_id, building)
	_refresh_all_worker_building_collisions()

	owned_buildings[building_id] += 1
	resources[&"gold"] -= int(building_config["gold_cost"])
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
		if not _is_bottom_ground_with_clearance(sample_point, building_edge_clearance_radius):
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

func _set_placement_pause_state(_is_paused: bool) -> void:
	# Placement mode should not pause active gameplay.
	# Keep time scale at normal speed regardless of placement state.
	Engine.time_scale = 1.0

func _spawn_worker_for_building(building_id: StringName, building: Node2D) -> void:
	if building_id == &"worker_wood":
		var worker: CharacterBody2D = WOOD_WORKER_SCENE.instantiate() as CharacterBody2D
		worker.global_position = building.global_position + WORKER_HOME_TELEPORT_OFFSET
		main_building_root.add_child(worker)
		worker.call("set_assigned_house_position", building.global_position)
		worker.call("set_assigned_house", building)
		var harvest_radius: float = float(building.get("harvest_radius"))
		worker.call("set_harvest_radius", harvest_radius)
		worker.connect("wood_collected", Callable(self, "_on_wood_worker_collected"))
		worker.connect("tree_availability_changed", Callable(self, "_on_worker_tree_availability_changed").bind(building))
		building.call("set_tree_warning_visible", not bool(worker.call("has_reachable_tree_target")))
	elif building_id == &"worker_meat":
		var worker: CharacterBody2D = FOOD_WORKER_SCENE.instantiate() as CharacterBody2D
		worker.global_position = building.global_position + WORKER_HOME_TELEPORT_OFFSET
		main_building_root.add_child(worker)
		worker.call("set_assigned_house_position", building.global_position)
		worker.call("set_assigned_house", building)
		var harvest_radius: float = float(building.get("harvest_radius"))
		worker.call("set_harvest_radius", harvest_radius)
		worker.connect("food_collected", Callable(self, "_on_food_worker_collected"))
		worker.connect("tree_availability_changed", Callable(self, "_on_worker_tree_availability_changed").bind(building))
		building.call("set_tree_warning_visible", not bool(worker.call("has_reachable_tree_target")), "No Sheep")
	elif building_id == &"worker_gold":
		var worker: CharacterBody2D = GOLD_WORKER_SCENE.instantiate() as CharacterBody2D
		worker.global_position = building.global_position + WORKER_HOME_TELEPORT_OFFSET
		main_building_root.add_child(worker)
		worker.call("set_assigned_house_position", building.global_position)
		worker.call("set_assigned_house", building)
		var harvest_radius: float = float(building.get("harvest_radius"))
		worker.call("set_harvest_radius", harvest_radius)
		worker.connect("gold_collected", Callable(self, "_on_gold_worker_collected"))
		worker.connect("resource_availability_changed", Callable(self, "_on_worker_tree_availability_changed").bind(building))
		building.call("set_tree_warning_visible", not bool(worker.call("has_reachable_resource_target")), "No Gold")

func _on_worker_tree_availability_changed(has_reachable: bool, building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	var b_id: StringName = building.get("building_id") as StringName
	if b_id == &"worker_meat":
		building.call("set_tree_warning_visible", not has_reachable, "No Sheep")
	elif b_id == &"worker_gold":
		building.call("set_tree_warning_visible", not has_reachable, "No Gold")
	else:
		building.call("set_tree_warning_visible", not has_reachable)

func _get_building_config(building_id: StringName) -> Dictionary:
	return WORKER_BUILDINGS[building_id].duplicate()

func _refresh_all_worker_building_collisions() -> void:
	var workers: Array = get_tree().get_nodes_in_group("worker_npc")
	var building_bodies: Array[PhysicsBody2D] = _get_worker_building_bodies()
	var tree_bodies: Array[PhysicsBody2D] = _get_tree_resource_bodies()

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

		for tree_body in tree_bodies:
			worker_body.add_collision_exception_with(tree_body)

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

func _get_tree_resource_bodies() -> Array[PhysicsBody2D]:
	var bodies: Array[PhysicsBody2D] = []
	for tree_variant in get_tree().get_nodes_in_group("wood_resource"):
		var tree_body := tree_variant as PhysicsBody2D
		if tree_body != null:
			bodies.append(tree_body)
	for tree_variant in get_tree().get_nodes_in_group("food_resource"):
		var tree_body := tree_variant as PhysicsBody2D
		if tree_body != null:
			bodies.append(tree_body)
	for gold_variant in get_tree().get_nodes_in_group("gold_resource"):
		var gold_body := gold_variant as PhysicsBody2D
		if gold_body != null:
			bodies.append(gold_body)
	return bodies

func _on_wood_worker_collected(amount: int) -> void:
	resources[&"wood"] += amount
	ui_manager.call("set_resource_amount", &"wood", resources[&"wood"])

func _on_food_worker_collected(amount: int) -> void:
	resources[&"food"] += amount
	ui_manager.call("set_resource_amount", &"food", resources[&"food"])

func _on_gold_worker_collected(amount: int) -> void:
	resources[&"gold"] += amount
	ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])

func _on_worker_building_upgrade_requested(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	if active_preview != null:
		return

	var building_id: StringName = building.get("building_id") as StringName
	if not WORKER_BUILDINGS.has(building_id):
		return

	var current_level: int = int(building.get("upgrade_level"))
	if current_level >= BUILDING_MAX_UPGRADE_LEVEL:
		_clear_pending_upgrade()
		building.call(
			"show_upgrade_popup",
			"Level %d" % current_level,
			"MAX",
			"Building is already max level (%d)." % BUILDING_MAX_UPGRADE_LEVEL,
			false,
			true
		)
		return

	var next_level: int = current_level + 1
	var upgrade_cost: int = _get_upgrade_cost(building_id, next_level)
	var current_harvest_radius: float = float(building.get("harvest_radius"))
	var next_harvest_radius: float = current_harvest_radius + BUILDING_UPGRADE_HARVEST_RADIUS_BONUS

	var workers: Array[CharacterBody2D] = _get_workers_assigned_to_building(building)
	var current_worker_speed: float = WOOD_WORKER_BASE_MOVE_SPEED + (float(current_level) * BUILDING_UPGRADE_WORKER_MOVE_SPEED_BONUS)
	if not workers.is_empty():
		current_worker_speed = float(workers[0].get("move_speed"))
	var next_worker_speed: float = current_worker_speed + BUILDING_UPGRADE_WORKER_MOVE_SPEED_BONUS

	pending_upgrade_building = building
	pending_upgrade_cost = upgrade_cost
	pending_upgrade_radius_bonus = BUILDING_UPGRADE_HARVEST_RADIUS_BONUS
	pending_upgrade_worker_speed_bonus = BUILDING_UPGRADE_WORKER_MOVE_SPEED_BONUS

	var affordability_text := "Affordable" if resources[&"gold"] >= upgrade_cost else "Not enough gold"
	var dark_text_color := "#2E2419"
	var old_value_color := "#C44B4B"
	var new_value_color := "#2EA65F"
	var status_color := new_value_color if resources[&"gold"] >= upgrade_cost else old_value_color
	var radius_label: String = "Hunt Radius:" if building_id == &"worker_meat" else "Harvest Radius:"
	var upgrade_details := (
		"[center][b][color=%s]Current Lv [/color][color=%s]%d[/color][color=%s] -> Next Lv [/color][color=%s]%d[/color][/b][/center]\n\n"
		+ "[b][color=%s]%s[/color][/b] [color=%s]%.0f[/color][color=%s] -> [/color][color=%s]%.0f[/color] ([color=%s]+%.0f[/color])\n\n"
		+ "[b][color=%s]Move Speed:[/color][/b] [color=%s]%.0f[/color][color=%s] -> [/color][color=%s]%.0f[/color] ([color=%s]+%.0f[/color])\n\n"
		+ "[b][color=%s]Status:[/color][/b] [color=%s]%s[/color]"
	) % [
		dark_text_color,
		old_value_color,
		current_level,
		dark_text_color,
		new_value_color,
		next_level,
		dark_text_color,
		radius_label,
		old_value_color,
		current_harvest_radius,
		dark_text_color,
		new_value_color,
		next_harvest_radius,
		new_value_color,
		pending_upgrade_radius_bonus,
		dark_text_color,
		old_value_color,
		current_worker_speed,
		dark_text_color,
		new_value_color,
		next_worker_speed,
		new_value_color,
		pending_upgrade_worker_speed_bonus,
		dark_text_color,
		status_color,
		affordability_text,
	]
	building.call(
		"show_upgrade_popup",
		"Level %d" % next_level,
		"%d" % upgrade_cost,
		upgrade_details,
		resources[&"gold"] >= upgrade_cost,
		false
	)

func _on_worker_building_move_requested(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	if active_preview != null:
		return
	if building == pending_upgrade_building:
		_clear_pending_upgrade()
		building.call("hide_upgrade_popup")

	moving_building = building
	moving_building_original_position = building.global_position
	active_preview = building
	active_building_id = building.get("building_id") as StringName
	waiting_for_confirm_release = Input.is_action_pressed("attack")
	ui_manager.call("close_shop_immediately")
	_set_placement_pause_state(true)
	ui_manager.call("set_shop_toggle_enabled", false)
	get_tree().call_group("worker_building", "_set_selected", false)
	active_preview.call("set_preview_mode", true)
	_update_preview_position()

func _on_worker_building_sell_requested(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	if building == pending_upgrade_building:
		_clear_pending_upgrade()

	var building_id: StringName = building.get("building_id") as StringName
	if WORKER_BUILDINGS.has(building_id):
		var original_gold_cost: int = int(WORKER_BUILDINGS[building_id]["gold_cost"])
		var refund_gold: int = int(round(float(original_gold_cost) * BUILDING_SELL_REFUND_RATIO))
		resources[&"gold"] += refund_gold
		ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])

	if owned_buildings.has(building_id):
		owned_buildings[building_id] = maxi(int(owned_buildings[building_id]) - 1, 0)
		ui_manager.call("set_building_quantity", building_id, owned_buildings[building_id])

	_remove_assigned_workers_for_building(building)
	building.queue_free()
	_refresh_building_availability()
	call_deferred("_refresh_all_worker_building_collisions")

func _remove_assigned_workers_for_building(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return

	var building_body: PhysicsBody2D = building.get_node_or_null("StaticBody2D") as PhysicsBody2D
	if building_body == null:
		return

	for worker_variant in get_tree().get_nodes_in_group("worker_npc"):
		var worker: CharacterBody2D = worker_variant as CharacterBody2D
		if worker == null or not worker.has_method("get_assigned_house_body"):
			continue
		var assigned_house_body: PhysicsBody2D = worker.call("get_assigned_house_body") as PhysicsBody2D
		if assigned_house_body == building_body:
			worker.queue_free()

func _update_workers_assigned_house_position(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return

	var building_body: PhysicsBody2D = building.get_node_or_null("StaticBody2D") as PhysicsBody2D
	if building_body == null:
		return

	for worker_variant in get_tree().get_nodes_in_group("worker_npc"):
		var worker: CharacterBody2D = worker_variant as CharacterBody2D
		if worker == null or not worker.has_method("get_assigned_house_body"):
			continue
		var assigned_house_body: PhysicsBody2D = worker.call("get_assigned_house_body") as PhysicsBody2D
		if assigned_house_body != building_body:
			continue
		if worker.has_method("set_assigned_house_position"):
			worker.call("set_assigned_house_position", building.global_position)

func _get_workers_assigned_to_building(building: Node2D) -> Array[CharacterBody2D]:
	var workers: Array[CharacterBody2D] = []
	if building == null or not is_instance_valid(building):
		return workers

	var building_body: PhysicsBody2D = building.get_node_or_null("StaticBody2D") as PhysicsBody2D
	if building_body == null:
		return workers

	for worker_variant in get_tree().get_nodes_in_group("worker_npc"):
		var worker: CharacterBody2D = worker_variant as CharacterBody2D
		if worker == null or not worker.has_method("get_assigned_house_body"):
			continue
		var assigned_house_body: PhysicsBody2D = worker.call("get_assigned_house_body") as PhysicsBody2D
		if assigned_house_body == building_body:
			workers.append(worker)
	return workers

func _teleport_workers_assigned_to_building(building: Node2D) -> void:
	for worker in _get_workers_assigned_to_building(building):
		worker.global_position = building.global_position + WORKER_HOME_TELEPORT_OFFSET
		worker.velocity = Vector2.ZERO

func _is_moving_existing_building() -> bool:
	return moving_building != null and active_preview == moving_building and is_instance_valid(moving_building)

func _on_worker_building_upgrade_confirmed(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		_clear_pending_upgrade()
		return
	if building != pending_upgrade_building:
		return
	if resources[&"gold"] < pending_upgrade_cost:
		return

	var next_level: int = int(building.get("upgrade_level")) + 1
	resources[&"gold"] -= pending_upgrade_cost
	ui_manager.call("set_resource_amount", &"gold", resources[&"gold"])
	building.set("upgrade_level", next_level)
	building.set("harvest_radius", float(building.get("harvest_radius")) + pending_upgrade_radius_bonus)

	for worker in _get_workers_assigned_to_building(building):
		worker.set("move_speed", float(worker.get("move_speed")) + pending_upgrade_worker_speed_bonus)
		if worker.has_method("set_harvest_radius"):
			worker.call("set_harvest_radius", float(building.get("harvest_radius")))

	_refresh_building_availability()
	building.call("hide_upgrade_popup")
	_clear_pending_upgrade()

func _on_worker_building_upgrade_canceled(building: Node2D) -> void:
	if building == pending_upgrade_building:
		_clear_pending_upgrade()

func _clear_pending_upgrade() -> void:
	pending_upgrade_building = null
	pending_upgrade_cost = 0
	pending_upgrade_radius_bonus = 0.0
	pending_upgrade_worker_speed_bonus = 0.0

func _get_upgrade_cost(building_id: StringName, next_level: int) -> int:
	if not WORKER_BUILDINGS.has(building_id):
		return 0
	var base_cost: float = float(WORKER_BUILDINGS[building_id]["gold_cost"]) * BUILDING_UPGRADE_COST_BASE_RATIO
	var growth_multiplier: float = pow(BUILDING_UPGRADE_COST_GROWTH, float(maxi(next_level - 1, 0)))
	return maxi(int(round(base_cost * growth_multiplier)), 1)

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
		_register_tree_resource(tree)
		spawned_positions.append(jittered_position)

func _register_existing_tree_resources() -> void:
	for tree_variant in get_tree().get_nodes_in_group("wood_resource"):
		var tree_node := tree_variant as Node2D
		if tree_node != null:
			_register_tree_resource(tree_node)

func _register_tree_resource(tree: Node2D) -> void:
	if tree == null or not is_instance_valid(tree):
		return
	_refresh_enemy_tree_collision_exceptions(tree)
	if tree.has_signal("depleted"):
		var callback := Callable(self, "_on_tree_resource_depleted")
		if not tree.is_connected("depleted", callback):
			tree.connect("depleted", callback)

func _refresh_enemy_tree_collision_exceptions(tree: Node2D) -> void:
	var tree_body := tree as PhysicsBody2D
	if tree_body == null:
		return

	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy_body := enemy_variant as PhysicsBody2D
		if enemy_body != null:
			enemy_body.add_collision_exception_with(tree_body)

func _on_tree_resource_depleted(tree: Node2D) -> void:
	var depleted_position: Vector2 = tree.global_position if tree != null and is_instance_valid(tree) else Vector2.ZERO
	call_deferred("_spawn_replacement_wood_tree", depleted_position)

func _spawn_replacement_wood_tree(preferred_position: Vector2) -> void:
	if TREE_RESOURCE_SCENE == null:
		return
	if wood_resources_root == null:
		wood_resources_root = get_node_or_null("WoodResources") as Node2D
	if wood_resources_root == null:
		wood_resources_root = Node2D.new()
		wood_resources_root.name = "WoodResources"
		add_child(wood_resources_root)

	var spawn_position := _find_valid_tree_spawn_near(preferred_position)
	if spawn_position == Vector2.INF:
		return

	var new_tree: Node2D = TREE_RESOURCE_SCENE.instantiate() as Node2D
	new_tree.global_position = spawn_position
	wood_resources_root.add_child(new_tree)
	_register_tree_resource(new_tree)
	call_deferred("_refresh_all_worker_building_collisions")

func _find_valid_tree_spawn_near(origin: Vector2) -> Vector2:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return Vector2.INF

	# Prefer random respawn offsets with spacing, not nearest replacement.
	var min_radius: float = maxf(TREE_REPLACEMENT_MIN_RADIUS, wood_tree_min_spacing + 24.0)
	var max_radius: float = maxf(TREE_REPLACEMENT_MAX_RADIUS, min_radius + 80.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in TREE_REPLACEMENT_RANDOM_ATTEMPTS:
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var candidate := origin + Vector2(cos(angle), sin(angle)) * radius
		if _is_valid_bottom_tree_position(candidate):
			return candidate

	# Fallback: deterministic rings in a broader radius to avoid failed replacement.
	var ring_steps: int = 24
	var fallback_radius: float = min_radius
	var fallback_max_radius: float = max_radius + 240.0
	while fallback_radius <= fallback_max_radius:
		for step in ring_steps:
			var angle := TAU * float(step) / float(ring_steps)
			var candidate := origin + Vector2(cos(angle), sin(angle)) * fallback_radius
			if _is_valid_bottom_tree_position(candidate):
				return candidate
		fallback_radius += 40.0

	return Vector2.INF

func _spawn_initial_food_sheep() -> void:
	if not spawn_random_food_sheep:
		return
	if bottom_ground_layer == null:
		return

	if food_resources_root == null:
		food_resources_root = Node2D.new()
		food_resources_root.name = "FoodResources"
		add_child(food_resources_root)

	if replace_existing_food_sheep:
		for child in food_resources_root.get_children():
			child.queue_free()

	var candidate_positions: Array[Vector2] = _get_bottom_ground_candidate_positions()
	if candidate_positions.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var spawned_positions: Array[Vector2] = []
	var target_count: int = max(random_food_sheep_count, 0)
	var attempts_left: int = candidate_positions.size()

	while spawned_positions.size() < target_count and attempts_left > 0 and not candidate_positions.is_empty():
		attempts_left -= 1
		var index: int = rng.randi_range(0, candidate_positions.size() - 1)
		var base_position: Vector2 = candidate_positions[index]
		candidate_positions.remove_at(index)

		var jittered_position := base_position + Vector2(
			rng.randf_range(-food_sheep_jitter, food_sheep_jitter),
			rng.randf_range(-food_sheep_jitter, food_sheep_jitter)
		)
		if not _is_valid_bottom_tree_position(jittered_position):
			continue

		var can_place_here: bool = true
		for existing_position in spawned_positions:
			var existing_vec: Vector2 = existing_position
			if existing_vec.distance_to(jittered_position) < food_sheep_min_spacing:
				can_place_here = false
				break
		if not can_place_here:
			continue

		var sheep: Node2D = SHEEP_RESOURCE_SCENE.instantiate() as Node2D
		sheep.global_position = jittered_position
		food_resources_root.add_child(sheep)
		_register_sheep_resource(sheep)
		spawned_positions.append(jittered_position)

func _register_existing_sheep_resources() -> void:
	for sheep_variant in get_tree().get_nodes_in_group("food_resource"):
		var sheep_node := sheep_variant as Node2D
		if sheep_node != null:
			_register_sheep_resource(sheep_node)

func _register_sheep_resource(sheep: Node2D) -> void:
	if sheep == null or not is_instance_valid(sheep):
		return
	_refresh_enemy_sheep_collision_exceptions(sheep)
	if sheep.has_signal("depleted"):
		var callback := Callable(self, "_on_sheep_resource_depleted")
		if not sheep.is_connected("depleted", callback):
			sheep.connect("depleted", callback)

func _refresh_enemy_sheep_collision_exceptions(sheep: Node2D) -> void:
	var sheep_body := sheep as PhysicsBody2D
	if sheep_body == null:
		return

	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy_body := enemy_variant as PhysicsBody2D
		if enemy_body != null:
			enemy_body.add_collision_exception_with(sheep_body)

func _on_sheep_resource_depleted(sheep: Node2D) -> void:
	var depleted_position: Vector2 = sheep.global_position if sheep != null and is_instance_valid(sheep) else Vector2.ZERO
	call_deferred("_spawn_replacement_food_sheep", depleted_position)

func _spawn_replacement_food_sheep(preferred_position: Vector2) -> void:
	if SHEEP_RESOURCE_SCENE == null:
		return
	if food_resources_root == null:
		food_resources_root = get_node_or_null("FoodResources") as Node2D
	if food_resources_root == null:
		food_resources_root = Node2D.new()
		food_resources_root.name = "FoodResources"
		add_child(food_resources_root)

	var spawn_position := _find_valid_tree_spawn_near(preferred_position)
	if spawn_position == Vector2.INF:
		return

	var new_sheep: Node2D = SHEEP_RESOURCE_SCENE.instantiate() as Node2D
	new_sheep.global_position = spawn_position
	food_resources_root.add_child(new_sheep)
	_register_sheep_resource(new_sheep)
	call_deferred("_refresh_all_worker_building_collisions")

func _spawn_initial_gold_stones() -> void:
	if not spawn_random_gold_stones:
		return
	if bottom_ground_layer == null:
		return

	if gold_resources_root == null:
		gold_resources_root = Node2D.new()
		gold_resources_root.name = "GoldResources"
		add_child(gold_resources_root)

	if replace_existing_gold_stones:
		for child in gold_resources_root.get_children():
			child.queue_free()

	var candidate_positions: Array[Vector2] = _get_bottom_ground_candidate_positions()
	if candidate_positions.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var spawned_positions: Array[Vector2] = []
	var target_count: int = max(random_gold_stone_count, 0)
	var attempts_left: int = candidate_positions.size()

	while spawned_positions.size() < target_count and attempts_left > 0 and not candidate_positions.is_empty():
		attempts_left -= 1
		var index: int = rng.randi_range(0, candidate_positions.size() - 1)
		var base_position: Vector2 = candidate_positions[index]
		candidate_positions.remove_at(index)

		var jittered_position := base_position + Vector2(
			rng.randf_range(-gold_stone_jitter, gold_stone_jitter),
			rng.randf_range(-gold_stone_jitter, gold_stone_jitter)
		)
		if not _is_valid_gold_stone_position(jittered_position):
			continue

		var can_place_here: bool = true
		for existing_position in spawned_positions:
			var existing_vec: Vector2 = existing_position
			if existing_vec.distance_to(jittered_position) < gold_stone_min_spacing:
				can_place_here = false
				break
		if not can_place_here:
			continue

		var gold_stone: Node2D = GOLD_RESOURCE_SCENE.instantiate() as Node2D
		var tier: int = _pick_weighted_gold_tier(rng)
		gold_stone.set("stone_tier", tier)
		gold_stone.global_position = jittered_position
		gold_resources_root.add_child(gold_stone)
		_register_gold_resource(gold_stone)
		spawned_positions.append(jittered_position)

# Minimum clearance distances for gold stone placement.
const GOLD_STONE_TREE_OBSTACLE_CLEARANCE: float = 100.0
const GOLD_STONE_RESOURCE_CLEARANCE: float = 80.0
const GOLD_STONE_BUILDING_CLEARANCE: float = 90.0

func _is_valid_gold_stone_position(world_position: Vector2) -> bool:
	# Must pass the standard bottom-ground check (no cliffs, no edge tiles).
	if not _is_valid_bottom_tree_position(world_position):
		return false

	# Must not be near any tree_obstacle (border trees AND wood resource trees).
	for obstacle_variant in get_tree().get_nodes_in_group("tree_obstacle"):
		var obstacle := obstacle_variant as Node2D
		if obstacle != null and world_position.distance_to(obstacle.global_position) < RESOURCE_BORDER_CLEARANCE:
			return false

	# Must not be near other gold stones.
	for gold_variant in get_tree().get_nodes_in_group("gold_resource"):
		var gold := gold_variant as Node2D
		if gold != null and world_position.distance_to(gold.global_position) < gold_stone_min_spacing:
			return false

	# Must not be near sheep.
	for sheep_variant in get_tree().get_nodes_in_group("food_resource"):
		var sheep := sheep_variant as Node2D
		if sheep != null and world_position.distance_to(sheep.global_position) < GOLD_STONE_RESOURCE_CLEARANCE:
			return false

	# Must not be near buildings or the castle base.
	for building_variant in get_tree().get_nodes_in_group("worker_building"):
		var building := building_variant as Node2D
		if building != null and world_position.distance_to(building.global_position) < GOLD_STONE_BUILDING_CLEARANCE:
			return false
	for base_variant in get_tree().get_nodes_in_group("base"):
		var base_node := base_variant as Node2D
		if base_node != null and world_position.distance_to(base_node.global_position) < GOLD_STONE_BUILDING_CLEARANCE:
			return false

	return true

func _pick_weighted_gold_tier(rng: RandomNumberGenerator) -> int:
	var total_weight: int = 0
	for tier_key in GOLD_STONE_TIER_WEIGHTS.keys():
		total_weight += int(GOLD_STONE_TIER_WEIGHTS[tier_key])

	var roll: int = rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for tier_key in GOLD_STONE_TIER_WEIGHTS.keys():
		cumulative += int(GOLD_STONE_TIER_WEIGHTS[tier_key])
		if roll <= cumulative:
			return int(tier_key)

	return 3

func _register_existing_gold_resources() -> void:
	for gold_variant in get_tree().get_nodes_in_group("gold_resource"):
		var gold_node := gold_variant as Node2D
		if gold_node != null:
			_register_gold_resource(gold_node)

func _register_gold_resource(gold_stone: Node2D) -> void:
	if gold_stone == null or not is_instance_valid(gold_stone):
		return
	_refresh_enemy_gold_collision_exceptions(gold_stone)
	if gold_stone.has_signal("depleted"):
		var callback := Callable(self, "_on_gold_resource_depleted")
		if not gold_stone.is_connected("depleted", callback):
			gold_stone.connect("depleted", callback)

func _refresh_enemy_gold_collision_exceptions(gold_stone: Node2D) -> void:
	var gold_body := gold_stone as PhysicsBody2D
	if gold_body == null:
		return

	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy_body := enemy_variant as PhysicsBody2D
		if enemy_body != null:
			enemy_body.add_collision_exception_with(gold_body)

func _on_gold_resource_depleted(gold_stone: Node2D) -> void:
	var depleted_position: Vector2 = gold_stone.global_position if gold_stone != null and is_instance_valid(gold_stone) else Vector2.ZERO
	call_deferred("_spawn_replacement_gold_stone", depleted_position)

func _spawn_replacement_gold_stone(preferred_position: Vector2) -> void:
	if GOLD_RESOURCE_SCENE == null:
		return
	if gold_resources_root == null:
		gold_resources_root = get_node_or_null("GoldResources") as Node2D
	if gold_resources_root == null:
		gold_resources_root = Node2D.new()
		gold_resources_root.name = "GoldResources"
		add_child(gold_resources_root)

	var spawn_position := _find_valid_gold_spawn_near(preferred_position)
	if spawn_position == Vector2.INF:
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var new_gold: Node2D = GOLD_RESOURCE_SCENE.instantiate() as Node2D
	var tier: int = _pick_weighted_gold_tier(rng)
	new_gold.set("stone_tier", tier)
	new_gold.global_position = spawn_position
	gold_resources_root.add_child(new_gold)
	_register_gold_resource(new_gold)
	call_deferred("_refresh_all_worker_building_collisions")

func _find_valid_gold_spawn_near(origin: Vector2) -> Vector2:
	# Similar to tree spawn near but uses stricter gold-specific validation.
	var min_radius: float = 140.0
	var max_radius: float = 320.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in 64:
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var candidate := origin + Vector2(cos(angle), sin(angle)) * radius
		if _is_valid_gold_stone_position(candidate):
			return candidate

	# Fallback deterministic search
	var ring_steps: int = 32
	var fallback_radius: float = min_radius
	while fallback_radius <= max_radius + 300.0:
		for step in ring_steps:
			var angle := TAU * float(step) / float(ring_steps)
			var candidate := origin + Vector2(cos(angle), sin(angle)) * fallback_radius
			if _is_valid_gold_stone_position(candidate):
				return candidate
		fallback_radius += 50.0

	return Vector2.INF

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
		if not _is_bottom_ground_with_clearance(sample, wood_tree_edge_clearance_radius):
			return false

	# Ensure clearance from border trees and wood resources
	for obstacle_variant in get_tree().get_nodes_in_group("tree_obstacle"):
		var obstacle := obstacle_variant as Node2D
		if obstacle != null and world_position.distance_to(obstacle.global_position) < RESOURCE_BORDER_CLEARANCE:
			return false

	if not _is_position_far_enough(world_position, 80.0):
		return false

	return true

func _is_position_far_enough(pos: Vector2, min_distance: float) -> bool:
	var distance_sq := min_distance * min_distance
	for building_variant in get_tree().get_nodes_in_group("worker_building"):
		var building := building_variant as Node2D
		if building != null and pos.distance_squared_to(building.global_position) < distance_sq:
			return false
	for base_variant in get_tree().get_nodes_in_group("base"):
		var base_node := base_variant as Node2D
		if base_node != null and pos.distance_squared_to(base_node.global_position) < distance_sq:
			return false
	for tree_variant in get_tree().get_nodes_in_group("wood_resource"):
		var tree := tree_variant as Node2D
		if tree != null and pos.distance_squared_to(tree.global_position) < distance_sq:
			return false
	for tree_variant in get_tree().get_nodes_in_group("food_resource"):
		var tree := tree_variant as Node2D
		if tree != null and pos.distance_squared_to(tree.global_position) < distance_sq:
			return false
	for gold_variant in get_tree().get_nodes_in_group("gold_resource"):
		var gold := gold_variant as Node2D
		if gold != null and pos.distance_squared_to(gold.global_position) < distance_sq:
			return false
	return true


func _is_bottom_ground_with_clearance(center: Vector2, clearance_radius: float) -> bool:
	if get_ground_class_at_world(center) != 2:
		return false

	var radius: float = maxf(clearance_radius, 0.0)
	if radius <= 0.0:
		return true

	var ring_samples: Array[Vector2] = [
		center + Vector2(radius, 0.0),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(0.0, -radius),
		center + Vector2(radius, radius) * 0.70710678,
		center + Vector2(radius, -radius) * 0.70710678,
		center + Vector2(-radius, radius) * 0.70710678,
		center + Vector2(-radius, -radius) * 0.70710678,
	]

	for sample in ring_samples:
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
