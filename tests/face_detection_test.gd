extends Node3D
## Chunk 4 test: verifies Die face detection against the FaceReader.
## On start: an automatic logic check (every face, many twists and tilts).
## Then: tap / click / Space shows faces 1..6 in turn so you can count pips by eye.
## T shows a random tilted orientation (desktop only).

const TWISTS_PER_FACE := 200
const MAX_TEST_TILT_DEG := 30.0  # Below 45 degrees, the intended face must still win.

var _manual_face := 0

@onready var _die: Die = $D6
@onready var _reader: Marker3D = $FaceReader
@onready var _info_label: Label = $HUD/InfoLabel


func _ready() -> void:
	_run_logic_check()
	_show_next_face()


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if (touch != null and touch.pressed) or event.is_action_pressed("ui_accept"):
		_show_next_face()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_show_random_tilt()


func _read_direction() -> Vector3:
	return _reader.global_position - _die.global_position


func _run_logic_check() -> void:
	var failures := 0
	var direction := _read_direction()
	for face: int in Die.FACE_NORMALS:
		for i in TWISTS_PER_FACE:
			var exact := Die.basis_with_face_toward(face, direction, randf() * TAU)
			_die.basis = exact
			if _die.get_face_toward(direction) != face:
				failures += 1
			_die.basis = _random_tilt() * exact
			if _die.get_face_toward(direction) != face:
				failures += 1
	var total := Die.FACE_NORMALS.size() * TWISTS_PER_FACE * 2
	if failures == 0:
		print("[FaceDetectionTest] PASS: %d/%d orientations detected correctly" % [total, total])
	else:
		push_error("[FaceDetectionTest] FAIL: %d/%d orientations misdetected" % [failures, total])


func _show_next_face() -> void:
	_manual_face = _manual_face % 6 + 1
	_die.basis = Die.basis_with_face_toward(_manual_face, _read_direction(), _random_quarter_turn())
	_update_label("Expected %d" % _manual_face)


func _show_random_tilt() -> void:
	var face := randi_range(1, 6)
	_die.basis = (
		_random_tilt() * Die.basis_with_face_toward(face, _read_direction(), _random_quarter_turn())
	)
	_update_label("Tilted, built with %d up" % face)


func _random_tilt() -> Basis:
	var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if axis.is_zero_approx():
		axis = Vector3.RIGHT
	return Basis(axis.normalized(), deg_to_rad(randf_range(-MAX_TEST_TILT_DEG, MAX_TEST_TILT_DEG)))


## Quarter turns only: any other twist around a horizontal read direction
## would leave the die resting on an edge.
func _random_quarter_turn() -> float:
	return randi_range(0, 3) * (PI / 2.0)


func _update_label(header: String) -> void:
	var detected := _die.get_face_toward(_read_direction())
	_info_label.text = (
		"%s\nDetected: %d\nAlignment: %.3f\n\nTap / Space: next face\nT: random tilt"
		% [header, detected, _die.get_face_alignment(detected, _read_direction())]
	)
