extends Node3D
## Chunk 5 test: proves displayed results are uniform and always match the generated result.
## On start: ROLLS full-pipeline rolls (result -> rest pose -> detection -> verification)
## plus a chi-square uniformity check on the displayed faces.
## Then: tap / click / Space performs a single roll (instant snap; animation comes in Chunk 7).

const ROLLS := 600_000
## Chi-square critical value for 5 degrees of freedom at significance 0.001:
## a perfectly fair die exceeds this by chance only once in 1000 runs.
const CHI_SQUARE_CRITICAL := 20.515
## Set >= 0 to reproduce a specific run (the seed is printed every run); -1 = new seed.
const FIXED_SEED := 12345

var _resolver: RollResolver
var _batch_summary := ""

@onready var _die: Die = $D6
@onready var _reader: Marker3D = $FaceReader
@onready var _info_label: Label = $HUD/InfoLabel


func _ready() -> void:
	var seed_value := FIXED_SEED if FIXED_SEED >= 0 else randi()
	_resolver = RollResolver.new(seed_value)
	_run_batch(seed_value)
	_info_label.text = _batch_summary + "\n\nTap / Space: roll"


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if (touch != null and touch.pressed) or event.is_action_pressed("ui_accept"):
		_roll_once()


func _read_direction() -> Vector3:
	return _reader.global_position - _die.global_position


func _run_batch(seed_value: int) -> void:
	var direction := _read_direction()
	var counts: Dictionary[int, int] = {}
	for face: int in Die.FACE_NORMALS:
		counts[face] = 0
	var mismatches := 0
	var not_flat := 0
	var start_ms := Time.get_ticks_msec()

	for _i in ROLLS:
		var result := _resolver.roll_result()
		_die.basis = _resolver.rest_basis_for(result, direction)
		if not RollResolver.verify(_die, direction, result):
			mismatches += 1
		if not _is_resting_flat():
			not_flat += 1
		counts[_die.get_face_toward(direction)] += 1  # Tally what the player would see.

	var expected := float(ROLLS) / counts.size()
	var chi_square := 0.0
	var lines := PackedStringArray()
	for face: int in range(1, counts.size() + 1):
		var observed := counts[face]
		chi_square += pow(observed - expected, 2.0) / expected
		lines.append("  %d: %6d  (%.2f%%)" % [face, observed, 100.0 * observed / ROLLS])

	var passed := mismatches == 0 and not_flat == 0 and chi_square < CHI_SQUARE_CRITICAL
	_batch_summary = (
		"%s  %d rolls, seed %d, %d ms\n%s\nchi-square %.2f (limit %.3f)\nmismatches %d, not flat %d"
		% [
			"PASS" if passed else "FAIL",
			ROLLS,
			seed_value,
			Time.get_ticks_msec() - start_ms,
			"\n".join(lines),
			chi_square,
			CHI_SQUARE_CRITICAL,
			mismatches,
			not_flat
		]
	)
	if passed:
		print("[FairnessTest] " + _batch_summary)
	else:
		push_error("[FairnessTest] " + _batch_summary)


## Resting flat means some face points straight up.
func _is_resting_flat() -> bool:
	var top := _die.get_face_toward(Vector3.UP)
	return _die.get_face_alignment(top, Vector3.UP) > 0.999


func _roll_once() -> void:
	var direction := _read_direction()
	var result := _resolver.roll_result()
	_die.basis = _resolver.rest_basis_for(result, direction)
	_info_label.text = (
		"%s\n\nRolled: %d\nDetected: %d\nVerified: %s\n\nTap / Space: roll"
		% [
			_batch_summary,
			result,
			_die.get_face_toward(direction),
			RollResolver.verify(_die, direction, result)
		]
	)
