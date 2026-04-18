@tool
extends Area2D

@export var zone_size: Vector2 = Vector2(220, 110):
	set(value):
		zone_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_sync_collision_shape()

func _ready() -> void:
	_sync_collision_shape()

func _enter_tree() -> void:
	_sync_collision_shape()

func _process(_delta: float) -> void:
	# Keep editor instances visually in sync even when property updates are delayed.
	if Engine.is_editor_hint():
		_sync_collision_shape()

func _sync_collision_shape() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null:
		return

	var rectangle_shape := collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		rectangle_shape = RectangleShape2D.new()
		collision_shape.shape = rectangle_shape

	rectangle_shape.size = zone_size
