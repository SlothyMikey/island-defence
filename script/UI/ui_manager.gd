extends CanvasLayer

@onready var shop_panel: Panel = $ShopPanel
# Updated the type from Button to TextureButton
@onready var shop_toggle_button: TextureButton = $ShopToggle_Button

func _ready() -> void:
	# Ensure the shop is closed when the game starts
	shop_panel.hide()
	
	# Connect the button's pressed signal via code
	shop_toggle_button.pressed.connect(_on_shop_toggle_button_pressed)

func _on_shop_toggle_button_pressed() -> void:
	# Toggle the visible state (if true it becomes false, and vice versa)
	shop_panel.visible = !shop_panel.visible
	
	# Note: The old text-changing logic has been removed here. 
	# Your TextureButton will handle its visual states (Normal, Pressed, Hover)
	# automatically based on the textures you assigned in the Inspector!
