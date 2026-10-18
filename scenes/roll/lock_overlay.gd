class_name LockOverlay
extends PanelContainer
## Locked-state overlay: a translucent panel over the die with a padlock and, when twist
## gestures are available, a blinking phone icon miming the key twist. Tapping it unlocks.

signal tapped

const FADE_TIME := 0.25
const TWIST_PERIOD := 1.4  # Seconds per back-and-forth twist of the phone icon.
const ICON_COLOR := Color(0.95, 0.93, 1.0)

var _shown := true
var _twist_hint := false
var _time := 0.0
var _tween: Tween
var _padlock_body := StyleBoxFlat.new()

@onready var _icons: Control = $Content/Icons
@onready var _hint_label: Label = $Content/HintLabel


func _ready() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	panel.set_corner_radius_all(48)
	panel.set_border_width_all(2)
	panel.border_color = Color(1.0, 1.0, 1.0, 0.15)
	panel.set_content_margin_all(32)
	add_theme_stylebox_override("panel", panel)
	_padlock_body.bg_color = ICON_COLOR
	_padlock_body.set_corner_radius_all(16)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_icons.draw.connect(_draw_icons)
	_update_hint()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		_icons.queue_redraw()


## Fades the overlay in or out. Calling it with the current state does nothing.
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	mouse_filter = Control.MOUSE_FILTER_STOP if shown else Control.MOUSE_FILTER_IGNORE
	if _tween != null:
		_tween.kill()
	pivot_offset = size / 2.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0 if shown else 0.0, FADE_TIME)
	if shown:
		visible = true
		scale = Vector2.ONE * 0.9
		(
			_tween
			. tween_property(self, "scale", Vector2.ONE, FADE_TIME)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	else:
		_tween.tween_property(self, "scale", Vector2.ONE * 1.08, FADE_TIME)
		_tween.chain().tween_callback(hide)


func set_twist_hint(enabled: bool) -> void:
	if enabled == _twist_hint:
		return
	_twist_hint = enabled
	_update_hint()
	_icons.queue_redraw()


func _update_hint() -> void:
	_hint_label.text = "Tap or twist to unlock" if _twist_hint else "Tap to unlock"


func _on_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton  # Touch arrives as mouse via emulation.
	if click != null and click.pressed and _shown:
		tapped.emit()


func _draw_icons() -> void:
	var center := _icons.size / 2.0
	if _twist_hint:
		_draw_padlock(center + Vector2(-110.0, 0.0))
		# Blinks twice per twist cycle.
		var blink := 0.55 + 0.45 * (0.5 + 0.5 * cos(_time * TAU * 2.0 / TWIST_PERIOD))
		_draw_twisting_phone(center + Vector2(110.0, 0.0), Color(ICON_COLOR, blink))
	else:
		_draw_padlock(center)


func _draw_padlock(at: Vector2) -> void:
	_icons.draw_arc(at + Vector2(0.0, -30.0), 42.0, PI, TAU, 24, ICON_COLOR, 12.0, true)  # Shackle.
	_icons.draw_style_box(_padlock_body, Rect2(at + Vector2(-62.0, -30.0), Vector2(124.0, 100.0)))
	_icons.draw_circle(at + Vector2(0.0, 14.0), 11.0, Color(0.0, 0.0, 0.0, 0.6))  # Keyhole.


## The phone's width follows cos() of a back-and-forth angle, so it reads as the phone
## turning around its long axis, like a key.
func _draw_twisting_phone(at: Vector2, color: Color) -> void:
	var angle := sin(_time * TAU / TWIST_PERIOD) * deg_to_rad(70.0)
	var width := 80.0 * maxf(absf(cos(angle)), 0.15)
	_icons.draw_rect(
		Rect2(at - Vector2(width / 2.0, 70.0), Vector2(width, 140.0)), color, false, 6.0
	)
	_icons.draw_arc(
		at + Vector2(0.0, 40.0), 70.0, deg_to_rad(50.0), deg_to_rad(130.0), 16, color, 5.0, true
	)
