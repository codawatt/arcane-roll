extends Node3D
## Chunk 7 test: tumble feel, verification and frame-rate independence.
## Tap / Space: roll at intensity 0.6.   1 / 2 / 3: roll at intensity 0 / 0.5 / 1.
## F: cycle the frame cap (uncapped / 30 / 60 / 120).

const FPS_CAPS: Array[int] = [0, 30, 60, 120]

var _resolver := RollResolver.new()
var _result := 0
var _fps_cap_index := 0
var _roll_start_ms := 0
var _bounces := 0
var _last_report := "No roll yet"

@onready var _die: Die = $D6
@onready var _reader: Marker3D = $FaceReader
@onready var _info_label: Label = $HUD/InfoLabel


func _ready() -> void:
	_die.roll_finished.connect(_on_roll_finished)
	_die.impact.connect(_on_impact)
	_refresh_label()


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if (touch != null and touch.pressed) or event.is_action_pressed("ui_accept"):
		_roll(0.6)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_roll(0.0)
		KEY_2:
			_roll(0.5)
		KEY_3:
			_roll(1.0)
		KEY_F:
			_fps_cap_index = (_fps_cap_index + 1) % FPS_CAPS.size()
			Engine.max_fps = FPS_CAPS[_fps_cap_index]
			_refresh_label()


func _read_direction() -> Vector3:
	return _reader.global_position - _die.global_position


func _roll(intensity: float) -> void:
	if _die.is_rolling():
		return
	_result = _resolver.roll_result()
	_die.roll_to(_resolver.rest_basis_for(_result, _read_direction()), intensity)
	_roll_start_ms = Time.get_ticks_msec()
	_bounces = 0
	_last_report = "Rolling at intensity %.1f..." % intensity
	_refresh_label()


func _on_impact(_strength: float) -> void:
	_bounces += 1


func _on_roll_finished() -> void:
	var direction := _read_direction()
	_last_report = (
		"Rolled %d   Detected %d   Verified %s\nPlanned %.2f s   Measured %.2f s   Bounces %d"
		% [
			_result,
			_die.get_face_toward(direction),
			RollResolver.verify(_die, direction, _result),
			_die.get_roll_duration(),
			(Time.get_ticks_msec() - _roll_start_ms) / 1000.0,
			_bounces
		]
	)
	_refresh_label()


func _refresh_label() -> void:
	var cap := FPS_CAPS[_fps_cap_index]
	_info_label.text = (
		"%s\n\nFPS cap: %s  (F)\nTap / Space: roll   1 / 2 / 3: intensity 0 / 0.5 / 1"
		% [_last_report, "none" if cap == 0 else str(cap)]
	)
