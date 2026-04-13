extends Node

const DEFAULT_CURSOR := preload("res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Cursors/Cursor_01.png")
const BUTTON_CURSOR := preload("res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Cursors/Cursor_02.png")

func _ready() -> void:
	Input.set_custom_mouse_cursor(DEFAULT_CURSOR, Input.CURSOR_ARROW, Vector2.ZERO)
	Input.set_custom_mouse_cursor(BUTTON_CURSOR, Input.CURSOR_POINTING_HAND, Vector2.ZERO)
