extends Control

@export var resource_id: StringName
@export var icon: Texture2D:
	set(value):
		icon = value
		_update_ui()
@export var amount: int = 0:
	set(value):
		amount = max(value, 0)
		_update_ui()

@onready var icon_rect: TextureRect = $Frame/IconAnchor/Icon
@onready var amount_label: Label = $AmountLabel

func _ready() -> void:
	_update_ui()

func configure(resource_key: StringName, icon_texture: Texture2D, value: int = 0) -> void:
	resource_id = resource_key
	icon = icon_texture
	amount = max(value, 0)
	_update_ui()

func set_amount(value: int) -> void:
	amount = max(value, 0)
	_update_ui()

func set_icon(value: Texture2D) -> void:
	icon = value
	_update_ui()

func _update_ui() -> void:
	if not is_node_ready():
		return

	icon_rect.texture = icon
	amount_label.text = str(amount)
	
	if resource_id == &"gold":
		icon_rect.custom_minimum_size = Vector2(40, 40)
	else:
		icon_rect.custom_minimum_size = Vector2(52, 52)
