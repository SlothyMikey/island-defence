extends CanvasLayer

@onready var shop_panel: Control = $ShopPanel
@onready var shop_toggle_button: TextureButton = $ShopToggle_Button
@onready var worker_button: TextureButton = $ShopPanel/Table/Workers
@onready var offense_button: TextureButton = $ShopPanel/Table/OffenseBuildings
@onready var defense_button: TextureButton = $ShopPanel/Table/DefenseBuildings
@onready var worker_icon: TextureRect = $ShopPanel/Table/Workers/Icon
@onready var offense_icon: TextureRect = $ShopPanel/Table/OffenseBuildings/Icon
@onready var defense_icon: TextureRect = $ShopPanel/Table/DefenseBuildings/Icon

@onready var worker_panel: Control = $ShopPanel/Table/CategoryPanels/WorkerPanel
@onready var offense_panel: Control = $ShopPanel/Table/CategoryPanels/OffensePanel
@onready var defense_panel: Control = $ShopPanel/Table/CategoryPanels/DefensePanel

var panel_open_pos: Vector2
var button_open_pos: Vector2

var panel_closed_pos: Vector2
var button_closed_pos: Vector2

var is_shop_open: bool = false

const ACTIVE_ICON_MODULATE := Color(0.72, 0.72, 0.72, 1.0)
const INACTIVE_ICON_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const ACTIVE_ICON_OFFSET_Y := 4.0

enum ShopCategory {
	WORKERS,
	OFFENSE,
	DEFENSE,
}

var worker_icon_pos: Vector2
var offense_icon_pos: Vector2
var defense_icon_pos: Vector2

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shop_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	shop_toggle_button.process_mode = Node.PROCESS_MODE_ALWAYS

	# 1. Save the exact editor positions as the "Open" state
	panel_open_pos = shop_panel.position
	button_open_pos = shop_toggle_button.position
	worker_icon_pos = worker_icon.position
	offense_icon_pos = offense_icon.position
	defense_icon_pos = defense_icon.position
	
	# 2. Calculate the "Closed" states independently
	# Push the panel completely above the screen (Size + 20 extra pixels to be safe)
	panel_closed_pos = Vector2(panel_open_pos.x, panel_open_pos.y - shop_panel.size.y - 20)
	
	# Keep the button fixed in its editor position.
	button_closed_pos = button_open_pos
	
	# 3. Start the game with the shop closed
	shop_panel.position = panel_closed_pos
	shop_panel.visible = false
	shop_toggle_button.position = button_closed_pos
	
	# Connect the main shop toggle button.
	shop_toggle_button.pressed.connect(_on_shop_toggle_button_pressed)

	# Connect the category buttons inside the shop.
	worker_button.pressed.connect(_on_worker_button_pressed)
	offense_button.pressed.connect(_on_offense_button_pressed)
	defense_button.pressed.connect(_on_defense_button_pressed)

	_show_shop_category(ShopCategory.WORKERS)

func _on_shop_toggle_button_pressed() -> void:
	is_shop_open = !is_shop_open
	
	var tween = create_tween()
	
	if is_shop_open:
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		shop_panel.visible = true
		get_tree().paused = true
		tween.tween_property(shop_panel, "position", panel_open_pos, 0.5)
	else:
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(shop_panel, "position", panel_closed_pos, 0.35)
		tween.finished.connect(func() -> void:
			shop_panel.visible = false
			get_tree().paused = false
		)

func _on_worker_button_pressed() -> void:
	_show_shop_category(ShopCategory.WORKERS)

func _on_offense_button_pressed() -> void:
	_show_shop_category(ShopCategory.OFFENSE)

func _on_defense_button_pressed() -> void:
	_show_shop_category(ShopCategory.DEFENSE)

func _show_shop_category(category: ShopCategory) -> void:
	worker_panel.visible = category == ShopCategory.WORKERS
	offense_panel.visible = category == ShopCategory.OFFENSE
	defense_panel.visible = category == ShopCategory.DEFENSE

	# Disable the active tab so it shows a distinct state and cannot be clicked again.
	worker_button.disabled = category == ShopCategory.WORKERS
	offense_button.disabled = category == ShopCategory.OFFENSE
	defense_button.disabled = category == ShopCategory.DEFENSE

	_update_category_button_visual(worker_button, worker_icon, worker_icon_pos, category == ShopCategory.WORKERS)
	_update_category_button_visual(offense_button, offense_icon, offense_icon_pos, category == ShopCategory.OFFENSE)
	_update_category_button_visual(defense_button, defense_icon, defense_icon_pos, category == ShopCategory.DEFENSE)

func _update_category_button_visual(button: TextureButton, icon: TextureRect, default_icon_pos: Vector2, is_active: bool) -> void:
	button.disabled = is_active
	icon.modulate = ACTIVE_ICON_MODULATE if is_active else INACTIVE_ICON_MODULATE
	icon.position = default_icon_pos + Vector2(0, ACTIVE_ICON_OFFSET_Y if is_active else 0)
