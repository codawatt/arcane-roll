class_name CustomizePanel
extends BottomSheet
## Customize panel (GDD §3): independent background / dot / triangle colors from curated
## swatches, applied instantly and saved via Settings, plus the Sound effects and
## Twist gestures switches. No dimming, so color changes stay visible while choosing.

# First entry of each row is the Settings default.
const BACKGROUND_SWATCHES: Array[Color] = [
	Color("1e1b2e"),
	Color("0f1a2b"),
	Color("102420"),
	Color("2a1616"),
	Color("1c1c1c"),
	Color("2b2118"),
	Color("231a33"),
]
const DOT_SWATCHES: Array[Color] = [
	Color("3a3358"),
	Color("2d4466"),
	Color("2e5248"),
	Color("5a2f2f"),
	Color("3c3c3c"),
	Color("5a4632"),
	Color("4b3a66"),
]
const TRIANGLE_SWATCHES: Array[Color] = [
	Color("8e7cc3"),
	Color("c9a227"),
	Color("4fa3a5"),
	Color("c0504d"),
	Color("d8d8d8"),
	Color("6faf5f"),
	Color("e07b39"),
]
const SWATCH_HEIGHT := 96.0

@onready var _background_row: HBoxContainer = %BackgroundRow
@onready var _dots_row: HBoxContainer = %DotsRow
@onready var _triangles_row: HBoxContainer = %TrianglesRow
@onready var _sound_toggle: CheckButton = %SoundToggle
@onready var _gestures_toggle: CheckButton = %GesturesToggle


func _ready() -> void:
	super()  # BottomSheet setup: anchoring, tap-outside, hidden start.
	_build_swatches(
		_background_row,
		BACKGROUND_SWATCHES,
		func(color: Color) -> void: Settings.background_color = color
	)
	_build_swatches(_dots_row, DOT_SWATCHES, func(color: Color) -> void: Settings.dot_color = color)
	_build_swatches(
		_triangles_row,
		TRIANGLE_SWATCHES,
		func(color: Color) -> void: Settings.triangle_color = color
	)
	_sound_toggle.toggled.connect(func(on: bool) -> void: Settings.sfx_muted = not on)
	_gestures_toggle.toggled.connect(func(on: bool) -> void: Settings.motion_gestures = on)
	%ResetButton.pressed.connect(Settings.reset_colors)
	%DoneButton.pressed.connect(close)
	Settings.changed.connect(_sync_from_settings)


func _on_opening() -> void:
	_sync_from_settings()


func _build_swatches(row: HBoxContainer, palette: Array[Color], apply: Callable) -> void:
	var group := ButtonGroup.new()
	for color: Color in palette:
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(0.0, SWATCH_HEIGHT)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.set_meta("color", color)
		var plain := _swatch_style(color, false)
		var selected := _swatch_style(color, true)
		swatch.add_theme_stylebox_override("normal", plain)
		swatch.add_theme_stylebox_override("hover", plain)
		swatch.add_theme_stylebox_override("pressed", selected)
		swatch.add_theme_stylebox_override("hover_pressed", selected)
		swatch.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		swatch.pressed.connect(apply.bind(color))
		row.add_child(swatch)


func _swatch_style(color: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(20)
	style.set_border_width_all(6 if selected else 2)
	style.border_color = Color.WHITE if selected else Color(1.0, 1.0, 1.0, 0.25)
	return style


## Highlights the swatches and sets the switches to match the saved Settings.
func _sync_from_settings() -> void:
	_sync_row(_background_row, Settings.background_color)
	_sync_row(_dots_row, Settings.dot_color)
	_sync_row(_triangles_row, Settings.triangle_color)
	_sound_toggle.set_pressed_no_signal(not Settings.sfx_muted)
	_gestures_toggle.set_pressed_no_signal(Settings.motion_gestures)


func _sync_row(row: HBoxContainer, current: Color) -> void:
	for child in row.get_children():
		var swatch := child as Button
		var color: Color = swatch.get_meta("color")
		swatch.set_pressed_no_signal(color.is_equal_approx(current))
