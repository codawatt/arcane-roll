extends Control
## Chunk 10 test: change preferences, restart the app, and confirm they persist.

@onready var _info_label: Label = %InfoLabel


func _ready() -> void:
	Settings.changed.connect(_refresh)
	%RandomizeButton.pressed.connect(_on_randomize_pressed)
	%MuteButton.pressed.connect(func() -> void: Settings.sfx_muted = not Settings.sfx_muted)
	%GesturesButton.pressed.connect(
		func() -> void: Settings.motion_gestures = not Settings.motion_gestures
	)
	%ResetButton.pressed.connect(Settings.reset_colors)
	_refresh()


func _on_randomize_pressed() -> void:
	Settings.background_color = Color.from_hsv(randf(), 0.5, 0.25)
	Settings.dot_color = Color.from_hsv(randf(), 0.4, 0.45)
	Settings.triangle_color = Color.from_hsv(randf(), 0.6, 0.8)


func _refresh() -> void:
	_info_label.text = (
		"Background  #%s\nDots  #%s\nTriangles  #%s\nSFX muted: %s\nMotion gestures: %s\n\n%s"
		% [
			Settings.background_color.to_html(false),
			Settings.dot_color.to_html(false),
			Settings.triangle_color.to_html(false),
			Settings.sfx_muted,
			Settings.motion_gestures,
			ProjectSettings.globalize_path(Settings.SAVE_PATH)
		]
	)
