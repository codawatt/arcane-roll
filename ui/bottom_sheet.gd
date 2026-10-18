class_name BottomSheet
extends Control
## Base for panels that slide up from the bottom over the current screen (Customize,
## Credits). Expects two children: Blocker (ColorRect, Mouse Filter Stop) and Sheet.
## Closes on a tap above the sheet; Android Back is routed here by the hosting screen.

const SLIDE_TIME := 0.35  # Seconds for a full open or close.

## 0 = the sheet's height follows its content; otherwise a fraction of the screen height.
@export_range(0.0, 1.0) var height_ratio := 0.0

var _open := false
var _reveal := 0.0
var _tween: Tween

@onready var _blocker: Control = $Blocker
@onready var _sheet: Control = $Sheet


func _ready() -> void:
	# Anchor the sheet to the bottom edge, full width; _set_reveal slides it.
	_sheet.anchor_left = 0.0
	_sheet.anchor_right = 1.0
	_sheet.anchor_top = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.offset_left = 0.0
	_sheet.offset_right = 0.0
	_blocker.gui_input.connect(_on_blocker_input)
	visible = false
	_set_reveal(0.0)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_on_opening()
	visible = true
	_animate_to(1.0)


func close() -> void:
	if not _open:
		return
	_open = false
	_animate_to(0.0)


## Override to refresh content just before the sheet slides in.
func _on_opening() -> void:
	pass


func _animate_to(target: float) -> void:
	if _tween != null:
		_tween.kill()  # Reopening mid-close (or vice versa) reverses smoothly.
	if is_equal_approx(_reveal, target):
		_set_reveal(target)
		visible = _open
		return
	_tween = create_tween()
	(
		_tween
		. tween_method(_set_reveal, _reveal, target, SLIDE_TIME * absf(target - _reveal))
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT if target > 0.0 else Tween.EASE_IN)
	)
	if target == 0.0:
		_tween.finished.connect(hide)


## 0 = sheet fully below the screen, 1 = fully open.
func _set_reveal(value: float) -> void:
	_reveal = value
	var height := (
		size.y * height_ratio if height_ratio > 0.0 else _sheet.get_combined_minimum_size().y
	)
	_sheet.offset_top = lerpf(0.0, -height, value)
	_sheet.offset_bottom = lerpf(height, 0.0, value)


## A tap above the sheet closes the panel.
func _on_blocker_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton  # Touch arrives as mouse via emulation.
	if click != null and click.pressed:
		close()
