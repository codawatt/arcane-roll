class_name RollController
extends Screen
## Roll screen. Shell version: Confirm returns to the menu.
## The Locked/Ready/Rolling/Result state machine arrives in Chunk 6.

signal exit_requested

@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	_confirm_button.pressed.connect(exit_requested.emit)
