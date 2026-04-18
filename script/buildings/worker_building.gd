extends Node2D

@export var building_id: StringName = &"worker_wood"
@export var building_name: String = "Worker Building"
@export var building_texture: Texture2D:
	set(value):
		building_texture = value
		_update_visuals()
@export var sprite_offset: Vector2 = Vector2(0, -18):
	set(value):
		sprite_offset = value
		_update_visuals()

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $StaticBody2D/CollisionShape2D
@onready var placement_markers: Node2D = $PlacementMarkers
@onready var top_left_marker: Sprite2D = $PlacementMarkers/TopLeft
@onready var top_right_marker: Sprite2D = $PlacementMarkers/TopRight
@onready var bottom_left_marker: Sprite2D = $PlacementMarkers/BottomLeft
@onready var bottom_right_marker: Sprite2D = $PlacementMarkers/BottomRight

const VALID_MARKER_COLOR := Color(0.46, 1.0, 0.56, 1.0)
const INVALID_MARKER_COLOR := Color(1.0, 0.38, 0.38, 1.0)
const PREVIEW_SPRITE_COLOR := Color(1.0, 1.0, 1.0, 0.72)
const INVALID_PREVIEW_SPRITE_COLOR := Color(1.0, 0.82, 0.82, 0.72)
const PLACED_SPRITE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var is_preview_mode := false
var is_placement_valid := true
var marker_tween: Tween

func _ready() -> void:
	_update_visuals()
	_update_markers_from_collision_shape()
	set_preview_mode(is_preview_mode)
	set_placement_valid(is_placement_valid)

func configure(config: Dictionary) -> void:
	building_id = config.get("building_id", building_id)
	building_name = config.get("building_name", building_name)
	building_texture = config.get("building_texture", building_texture)
	sprite_offset = config.get("sprite_offset", sprite_offset)

func set_preview_mode(value: bool) -> void:
	is_preview_mode = value
	if not is_node_ready():
		return

	placement_markers.visible = value
	collision_shape.disabled = value
	if value:
		_start_marker_animation()
	else:
		_stop_marker_animation()
	sprite.modulate = PREVIEW_SPRITE_COLOR if value else PLACED_SPRITE_COLOR

func set_placement_valid(value: bool) -> void:
	is_placement_valid = value
	if not is_node_ready():
		return

	var marker_color := VALID_MARKER_COLOR if value else INVALID_MARKER_COLOR
	for marker in placement_markers.get_children():
		(marker as Sprite2D).modulate = marker_color
	if is_preview_mode:
		sprite.modulate = PREVIEW_SPRITE_COLOR if value else INVALID_PREVIEW_SPRITE_COLOR
	else:
		sprite.modulate = PLACED_SPRITE_COLOR

func get_placement_shape() -> Shape2D:
	return collision_shape.shape

func get_placement_transform() -> Transform2D:
	return collision_shape.global_transform

func _update_visuals() -> void:
	if not is_node_ready():
		return

	sprite.texture = building_texture
	sprite.position = sprite_offset

func _update_markers_from_collision_shape() -> void:
	if not is_node_ready():
		return

	var rectangle_shape := collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		return

	var half_size := rectangle_shape.size * 0.5
	top_left_marker.position = Vector2(-half_size.x, -half_size.y)
	top_right_marker.position = Vector2(half_size.x, -half_size.y)
	bottom_left_marker.position = Vector2(-half_size.x, half_size.y)
	bottom_right_marker.position = Vector2(half_size.x, half_size.y)

func _start_marker_animation() -> void:
	_stop_marker_animation()
	placement_markers.scale = Vector2.ONE
	placement_markers.modulate.a = 1.0

	marker_tween = create_tween()
	marker_tween.set_ignore_time_scale(true)
	marker_tween.set_loops()
	marker_tween.tween_property(placement_markers, "scale", Vector2(1.08, 1.08), 0.35)
	marker_tween.parallel().tween_property(placement_markers, "modulate:a", 0.7, 0.35)
	marker_tween.tween_property(placement_markers, "scale", Vector2.ONE, 0.35)
	marker_tween.parallel().tween_property(placement_markers, "modulate:a", 1.0, 0.35)

func _stop_marker_animation() -> void:
	if marker_tween != null and marker_tween.is_valid():
		marker_tween.kill()
	marker_tween = null
	placement_markers.scale = Vector2.ONE
	placement_markers.modulate.a = 1.0
