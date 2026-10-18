class_name AppBackground
extends Control
## App background (GDD §3): solid color, diagonally drifting dot grid, and a band of
## inward-pointing triangles on each edge gliding in opposite directions, with a soft
## drop shadow. Everything is drawn by one opaque shader, colored live from Settings;
## being opaque, it also clears the screen every frame (3D environment in Canvas mode).
## The bands slide in on the menu and out during play (driven by Main).

const BAND_SLIDE_TIME := 0.45  # Seconds for a full slide.

var _band_reveal := 1.0
var _band_tween: Tween

@onready var _pattern: ColorRect = $Pattern
@onready var _material: ShaderMaterial = $Pattern.material as ShaderMaterial


func _ready() -> void:
	Settings.changed.connect(_apply_colors)
	_pattern.resized.connect(_update_size)
	_apply_colors()
	_update_size()
	_set_band_reveal(_band_reveal)


## Slides both edge bands in (shown) or out. Reverses smoothly if interrupted mid-slide.
func set_bands_shown(shown: bool, animate: bool = true) -> void:
	var target := 1.0 if shown else 0.0
	if _band_tween != null:
		_band_tween.kill()
		_band_tween = null
	if not animate or is_equal_approx(_band_reveal, target):
		_set_band_reveal(target)
		return
	# Scale duration by the distance left, so a reversal mid-slide keeps the same speed.
	var duration := BAND_SLIDE_TIME * absf(target - _band_reveal)
	_band_tween = create_tween()
	var tweener := _band_tween.tween_method(_set_band_reveal, _band_reveal, target, duration)
	if shown:
		tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)  # Slight overshoot, then settle.
	else:
		tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)  # Accelerate away.


func _set_band_reveal(value: float) -> void:
	_band_reveal = value
	_material.set_shader_parameter("band_reveal", value)


func _apply_colors() -> void:
	_material.set_shader_parameter("background_color", Settings.background_color)
	_material.set_shader_parameter("dot_color", Settings.dot_color)
	_material.set_shader_parameter("triangle_color", Settings.triangle_color)


## The shader works in canvas units, so it needs the real size to keep shapes undistorted.
func _update_size() -> void:
	_material.set_shader_parameter("rect_size", _pattern.size)
