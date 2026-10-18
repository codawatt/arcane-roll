class_name RollResolver
extends RefCounted
## Decides each roll, independently of input and animation (GDD §4 "Rolling Fairness"):
##   1. roll_result()    - a uniformly random face value.
##   2. rest_basis_for() - a resting orientation that shows that face to the reader.
##   3. verify()         - confirms the die actually shows the result.
## Motion input never reaches this class, so it cannot influence results.

## Cosmetic turn around the vertical axis so rests don't look identical.
## Kept small so the corner-facing camera view is preserved.
const MAX_REST_YAW_DEG := 8.0
## The read face must point within ~25 degrees of the reader to count as settled.
const MIN_VERIFIED_ALIGNMENT := 0.9

var _result_rng := RandomNumberGenerator.new()  # Results only.
var _pose_rng := RandomNumberGenerator.new()  # Cosmetic choices only; never affects results.


## Pass a seed >= 0 for reproducible tests. Real play uses the default (fresh random seeds).
func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_result_rng.seed = seed_value
		_pose_rng.seed = seed_value + 1
	else:
		_result_rng.randomize()
		_pose_rng.randomize()


## Uniform over 1..N, where N is the die's face count.
## randi_range uses unbiased bounded generation, so every face has exactly 1/N probability.
func roll_result() -> int:
	return _result_rng.randi_range(1, Die.FACE_NORMALS.size())


## Resting orientation showing `face` toward `read_direction`, flat on a face.
## A random quarter turn picks which neighboring face ends up on top; a small
## yaw adds variety. read_direction must be horizontal (FaceReader at the die's
## height), otherwise quarter turns would not leave the die resting flat.
func rest_basis_for(face: int, read_direction: Vector3) -> Basis:
	var quarter_turn := _pose_rng.randi_range(0, 3) * (PI / 2.0)
	var facing := Die.basis_with_face_toward(face, read_direction, quarter_turn)
	var yaw := deg_to_rad(_pose_rng.randf_range(-MAX_REST_YAW_DEG, MAX_REST_YAW_DEG))
	return Basis(Vector3.UP, yaw) * facing


## True if the die shows `expected` toward the reader and sits squarely enough to read.
static func verify(die: Die, read_direction: Vector3, expected: int) -> bool:
	var detected := die.get_face_toward(read_direction)
	return (
		detected == expected
		and die.get_face_alignment(detected, read_direction) >= MIN_VERIFIED_ALIGNMENT
	)
