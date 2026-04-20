extends Node2D

signal upgrade_requested(building: Node2D)
signal upgrade_confirmed(building: Node2D)
signal upgrade_canceled(building: Node2D)
signal move_requested(building: Node2D)
signal sell_requested(building: Node2D)

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
@export var harvest_radius: float = 540.0:
	set(value):
		harvest_radius = maxf(value, 0.0)
		queue_redraw()
@export var upgrade_level: int = 0:
	set(value):
		upgrade_level = maxi(value, 0)

@onready var sprite: Sprite2D = $Sprite2D
@onready var status_notification: Node2D = $StatusNotification
@onready var status_notification_label: Label = $StatusNotification/Label
@onready var collision_shape: CollisionShape2D = $StaticBody2D/CollisionShape2D
@onready var building_body: StaticBody2D = $StaticBody2D
@onready var placement_markers: Node2D = $PlacementMarkers
@onready var top_left_marker: Sprite2D = $PlacementMarkers/TopLeft
@onready var top_right_marker: Sprite2D = $PlacementMarkers/TopRight
@onready var bottom_left_marker: Sprite2D = $PlacementMarkers/BottomLeft
@onready var bottom_right_marker: Sprite2D = $PlacementMarkers/BottomRight
@onready var action_ui: Control = $ActionUI
@onready var action_panel: Panel = $ActionUI/ActionPanel
@onready var upgrade_button: Button = $ActionUI/ActionPanel/ActionButtons/UpgradeButton
@onready var move_button: Button = $ActionUI/ActionPanel/ActionButtons/MoveButton
@onready var sell_button: Button = $ActionUI/ActionPanel/ActionButtons/RemoveButton
@onready var upgrade_overlay_root: Control = $UpgradeOverlay/UpgradeRoot
@onready var upgrade_popup: NinePatchRect = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel
@onready var upgrade_title_label: Label = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/LevelLabel
@onready var upgrade_building_name_label: Label = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/LevelLabel2
@onready var upgrade_building_icon: TextureRect = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/BuildingIcon
@onready var upgrade_cost_label: Label = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/CostRow/CostLabel
@onready var upgrade_info_label: RichTextLabel = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/DetailsPanel/DetailsLabel
@onready var upgrade_confirm_button: TextureButton = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/UpgradeButton
@onready var upgrade_cancel_button: TextureButton = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/CloseButton
@onready var upgrade_button_label: Label = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/UpgradeContent/UpgradeButton/UpgradeButtonLabel
@onready var close_button_icon: TextureRect = $UpgradeOverlay/UpgradeRoot/UpgradeCenter/UpgradePanel/CloseButton/TextureRect

const DEFAULT_ACTION_ICON := preload("res://icon.svg")

const VALID_MARKER_COLOR := Color(0.46, 1.0, 0.56, 1.0)
const INVALID_MARKER_COLOR := Color(1.0, 0.38, 0.38, 1.0)
const PREVIEW_SPRITE_COLOR := Color(1.0, 1.0, 1.0, 0.72)
const INVALID_PREVIEW_SPRITE_COLOR := Color(1.0, 0.82, 0.82, 0.72)
const PLACED_SPRITE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const RANGE_FILL_COLOR := Color(0.28, 0.95, 0.62, 0.08)
const RANGE_OUTLINE_COLOR := Color(0.35, 1.0, 0.68, 0.45)
const RANGE_OUTLINE_COLOR_INVALID := Color(1.0, 0.4, 0.4, 0.45)
const SELECTED_RANGE_FILL_COLOR := Color(0.36, 0.86, 1.0, 0.08)
const SELECTED_RANGE_OUTLINE_COLOR := Color(0.50, 0.90, 1.0, 0.5)
const BUTTON_PRESS_OFFSET_Y := 2.0

var is_preview_mode := false
var is_placement_valid := true
var marker_tween: Tween
var is_selected := false
var is_tree_warning_visible: bool = false
var tree_warning_message: String = "No Trees"
var upgrade_button_label_default_pos: Vector2
var close_button_icon_default_pos: Vector2

func _ready() -> void:
	add_to_group("worker_building")
	upgrade_button_label_default_pos = upgrade_button_label.position
	close_button_icon_default_pos = close_button_icon.position
	_update_visuals()
	_update_upgrade_header()
	set_tree_warning_visible(false)
	_update_markers_from_collision_shape()
	_setup_action_ui()
	set_preview_mode(is_preview_mode)
	set_placement_valid(is_placement_valid)

func configure(config: Dictionary) -> void:
	building_id = config.get("building_id", building_id)
	building_name = config.get("building_name", building_name)
	building_texture = config.get("building_texture", building_texture)
	sprite_offset = config.get("sprite_offset", sprite_offset)
	harvest_radius = float(config.get("harvest_radius", harvest_radius))
	upgrade_level = int(config.get("upgrade_level", upgrade_level))
	_update_upgrade_header()

func _update_upgrade_header() -> void:
	if not is_node_ready():
		return
	if upgrade_building_name_label == null:
		return
	upgrade_building_name_label.text = _get_upgrade_building_name()

func _get_upgrade_building_name() -> String:
	var name_text := building_name.strip_edges()
	if name_text == "":
		return "Worker Building"
	return name_text

func set_tree_warning_visible(is_visible: bool, message: String = "No Trees") -> void:
	is_tree_warning_visible = is_visible
	tree_warning_message = message
	_apply_tree_warning_visual()

func _apply_tree_warning_visual() -> void:
	if not is_node_ready():
		return
	if status_notification == null or status_notification_label == null:
		return
	status_notification.visible = is_tree_warning_visible and not is_preview_mode
	status_notification_label.text = tree_warning_message

func set_preview_mode(value: bool) -> void:
	is_preview_mode = value
	if value:
		is_selected = false
	if not is_node_ready():
		return

	placement_markers.visible = value
	action_ui.visible = false
	_hide_upgrade_popup()
	collision_shape.disabled = value
	_apply_tree_warning_visual()
	if value:
		_start_marker_animation()
	else:
		_stop_marker_animation()
	sprite.modulate = PREVIEW_SPRITE_COLOR if value else PLACED_SPRITE_COLOR
	queue_redraw()

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
	queue_redraw()

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

func _draw() -> void:
	if not is_preview_mode and not is_selected:
		return
	if harvest_radius <= 0.0:
		return

	var fill_color: Color = RANGE_FILL_COLOR
	var outline_color: Color = RANGE_OUTLINE_COLOR if is_placement_valid else RANGE_OUTLINE_COLOR_INVALID
	if not is_preview_mode and is_selected:
		fill_color = SELECTED_RANGE_FILL_COLOR
		outline_color = SELECTED_RANGE_OUTLINE_COLOR

	draw_circle(Vector2.ZERO, harvest_radius, fill_color)
	draw_arc(Vector2.ZERO, harvest_radius, 0.0, TAU, 96, outline_color, 2.0, true)

func _unhandled_input(event: InputEvent) -> void:
	if is_preview_mode:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	if _is_mouse_over_building():
		get_tree().call_group("worker_building", "_set_selected", false)
		_set_selected(true)
	elif _is_mouse_over_action_ui():
		return
	elif is_selected:
		_set_selected(false)

func _set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	action_ui.visible = is_selected and not is_preview_mode
	action_panel.visible = is_selected and not is_preview_mode
	if not is_selected:
		_hide_upgrade_popup()
	queue_redraw()

func _is_mouse_over_building() -> bool:
	if building_body == null:
		return false

	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits: Array = get_world_2d().direct_space_state.intersect_point(query, 16)
	for hit_variant in hits:
		var hit: Dictionary = hit_variant as Dictionary
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == building_body:
			return true

	return false

func _setup_action_ui() -> void:
	if action_ui == null:
		return

	action_ui.visible = false
	if upgrade_button.icon == null:
		upgrade_button.icon = DEFAULT_ACTION_ICON
	if move_button.icon == null:
		move_button.icon = DEFAULT_ACTION_ICON
	if sell_button.icon == null:
		sell_button.icon = DEFAULT_ACTION_ICON
	if sell_button.tooltip_text == "":
		sell_button.tooltip_text = "Sell (60%)"
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	move_button.pressed.connect(_on_move_button_pressed)
	sell_button.pressed.connect(_on_sell_button_pressed)
	upgrade_confirm_button.pressed.connect(_on_upgrade_confirm_button_pressed)
	upgrade_cancel_button.pressed.connect(_on_upgrade_cancel_button_pressed)
	upgrade_confirm_button.button_down.connect(_on_upgrade_confirm_button_down)
	upgrade_confirm_button.button_up.connect(_on_upgrade_confirm_button_up)
	upgrade_confirm_button.mouse_exited.connect(_on_upgrade_confirm_button_up)
	upgrade_cancel_button.button_down.connect(_on_upgrade_cancel_button_down)
	upgrade_cancel_button.button_up.connect(_on_upgrade_cancel_button_up)
	upgrade_cancel_button.mouse_exited.connect(_on_upgrade_cancel_button_up)
	_hide_upgrade_popup()

func _is_mouse_over_action_ui() -> bool:
	if action_ui == null or not action_ui.visible:
		if upgrade_overlay_root == null or not upgrade_overlay_root.visible:
			return false
		return upgrade_overlay_root.get_global_rect().has_point(get_viewport().get_mouse_position())
	if action_ui.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return true
	if upgrade_overlay_root != null and upgrade_overlay_root.visible:
		return upgrade_overlay_root.get_global_rect().has_point(get_viewport().get_mouse_position())
	return false

func _on_upgrade_button_pressed() -> void:
	upgrade_requested.emit(self)

func _on_move_button_pressed() -> void:
	move_requested.emit(self)

func _on_sell_button_pressed() -> void:
	sell_requested.emit(self)

func show_upgrade_popup(title_text: String, cost_text: String, details_text: String, can_upgrade: bool, is_maxed: bool) -> void:
	if not is_node_ready():
		return
	if not is_selected:
		_set_selected(true)
	action_ui.visible = true
	action_panel.visible = false
	upgrade_overlay_root.visible = true
	upgrade_popup.visible = true
	upgrade_title_label.text = title_text
	upgrade_building_name_label.text = _get_upgrade_building_name()
	upgrade_building_icon.texture = building_texture
	upgrade_cost_label.text = cost_text
	upgrade_info_label.text = details_text
	upgrade_confirm_button.visible = not is_maxed
	upgrade_confirm_button.disabled = not can_upgrade

func hide_upgrade_popup() -> void:
	_hide_upgrade_popup()

func _hide_upgrade_popup() -> void:
	if not is_node_ready():
		return
	_on_upgrade_confirm_button_up()
	_on_upgrade_cancel_button_up()
	upgrade_overlay_root.visible = false
	upgrade_popup.visible = false
	action_panel.visible = is_selected and not is_preview_mode

func _on_upgrade_confirm_button_pressed() -> void:
	upgrade_confirmed.emit(self)

func _on_upgrade_cancel_button_pressed() -> void:
	upgrade_canceled.emit(self)
	_hide_upgrade_popup()

func _on_upgrade_confirm_button_down() -> void:
	_set_upgrade_button_pressed_visual(true)

func _on_upgrade_confirm_button_up() -> void:
	_set_upgrade_button_pressed_visual(false)

func _on_upgrade_cancel_button_down() -> void:
	_set_close_button_pressed_visual(true)

func _on_upgrade_cancel_button_up() -> void:
	_set_close_button_pressed_visual(false)

func _set_upgrade_button_pressed_visual(is_pressed: bool) -> void:
	if upgrade_button_label == null:
		return
	upgrade_button_label.position = upgrade_button_label_default_pos + Vector2(0.0, BUTTON_PRESS_OFFSET_Y if is_pressed else 0.0)

func _set_close_button_pressed_visual(is_pressed: bool) -> void:
	if close_button_icon == null:
		return
	close_button_icon.position = close_button_icon_default_pos + Vector2(0.0, BUTTON_PRESS_OFFSET_Y if is_pressed else 0.0)
