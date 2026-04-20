extends Panel

@export var slot_scene: PackedScene = preload("res://scenes/UI/resource_slot.tscn")

@onready var slots_row: HBoxContainer = $Padding/SlotsRow

func add_resource_slot(resource_id: StringName = &"", icon: Texture2D = null, amount: int = 0) -> Control:
	if slot_scene == null:
		push_warning("ResourceHolderPanel is missing a slot_scene.")
		return null

	var slot := slot_scene.instantiate() as Control
	if slot == null:
		push_warning("slot_scene must instantiate a Control-based resource slot.")
		return null

	slots_row.add_child(slot)

	if resource_id != StringName():
		slot.set("resource_id", resource_id)
	if icon != null:
		slot.call("set_icon", icon)
	slot.call("set_amount", amount)

	return slot

func get_resource_slot(resource_id: StringName) -> Control:
	for child in slots_row.get_children():
		if child.get("resource_id") == resource_id:
			return child as Control
	return null

func set_resource_icon(resource_id: StringName, icon: Texture2D) -> void:
	var slot := get_resource_slot(resource_id)
	if slot != null:
		slot.call("set_icon", icon)

func set_resource_amount(resource_id: StringName, amount: int) -> void:
	var slot := get_resource_slot(resource_id)
	if slot != null:
		slot.call("set_amount", amount)
