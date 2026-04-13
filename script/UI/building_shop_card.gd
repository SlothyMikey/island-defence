extends Button

signal building_selected(building_id: StringName)

@export var building_id: StringName = &""
@export var building_name: String = "Building Name":
	set(value):
		building_name = value
		_update_ui()
@export_multiline var description: String = "Describe what this building does.":
	set(value):
		description = value
		_update_ui()
@export var quantity: int = 0:
	set(value):
		quantity = max(value, 0)
		_update_ui()
@export var gold_cost: int = 0:
	set(value):
		gold_cost = max(value, 0)
		_update_ui()
@export var building_texture: Texture2D:
	set(value):
		building_texture = value
		_update_ui()

@onready var card_body: CanvasItem = $CardBody
@onready var hover_tint: CanvasItem = $CardBody/HoverTint
@onready var building_image_rect: TextureRect = $CardBody/CardPadding/Content/ImageFrame/ImagePadding/BuildingImage
@onready var building_name_label: Label = $CardBody/CardPadding/Content/TextColumn/BuildingNameLabel
@onready var description_label: Label = $CardBody/CardPadding/Content/TextColumn/DescriptionLabel
@onready var quantity_label: Label = $CardBody/CardPadding/Content/TextColumn/MetaRow/QuantityLabel
@onready var gold_cost_label: Label = $CardBody/CardPadding/Content/TextColumn/MetaRow/GoldRow/GoldCostLabel

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	_update_ui()

func _on_pressed() -> void:
	building_selected.emit(building_id)

func _on_mouse_entered() -> void:
	hover_tint.visible = true
	card_body.position = Vector2(0, -1)

func _on_mouse_exited() -> void:
	hover_tint.visible = false
	card_body.position = Vector2.ZERO

func _on_button_down() -> void:
	card_body.position = Vector2(0, 1)

func _on_button_up() -> void:
	card_body.position = Vector2(0, -1) if is_hovered() else Vector2.ZERO

func _update_ui() -> void:
	if not is_node_ready():
		return

	building_image_rect.texture = building_texture
	building_name_label.text = building_name
	description_label.text = description
	description_label.visible = not description.is_empty()
	quantity_label.text = "Owned: %d" % quantity
	if gold_cost_label:
		gold_cost_label.text = str(gold_cost)
