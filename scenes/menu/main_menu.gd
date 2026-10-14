class_name MainMenu
extends Screen
## Main menu. Shell version: Start only. Full layout arrives in Chunk 12.

signal start_requested

@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(start_requested.emit)
