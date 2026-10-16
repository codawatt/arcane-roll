class_name Die
extends Node3D
## A six-sided die. Knows its face layout and reports which face points
## along a given world direction. Does not decide results or animate (Chunks 5 and 7).

## Outward face normals in the die's local space, keyed by face value.
## Measured from dice_prop.blend's pip geometry after Godot's Y-up conversion.
## Opposite faces sum to 7.
const FACE_NORMALS: Dictionary[int, Vector3] = {
	1: Vector3.UP,
	6: Vector3.DOWN,
	3: Vector3.RIGHT,
	4: Vector3.LEFT,
	2: Vector3.BACK,  # +Z
	5: Vector3.FORWARD,  # -Z
}


## Returns the face whose outward normal is most aligned with world_direction.
## The most-aligned face wins, so small tilts never cause a wrong read.
func get_face_toward(world_direction: Vector3) -> int:
	var direction := world_direction.normalized()
	var world_basis := global_basis.orthonormalized()
	var best_face := 0
	var best_alignment := -INF
	for face: int in FACE_NORMALS:
		var alignment := (world_basis * FACE_NORMALS[face]).dot(direction)
		if alignment > best_alignment:
			best_alignment = alignment
			best_face = face
	return best_face


## How squarely a face points along world_direction: 1.0 = exactly, 0.0 = sideways.
func get_face_alignment(face: int, world_direction: Vector3) -> float:
	var world_normal := global_basis.orthonormalized() * FACE_NORMALS[face]
	return world_normal.dot(world_direction.normalized())


## Builds an orientation in which the given face points along `direction`,
## then twists it by `twist` radians around that direction.
## Chunk 5 uses this to build the target orientation for each roll result.
## ALERT code was changed from reference
static func basis_with_face_toward(face: int, direction: Vector3, twist: float = 0.0) -> Basis:
	var normal: Vector3 = FACE_NORMALS[face]
	var target := direction.normalized()
	var axis := normal.cross(target)
	var tilt := Basis.IDENTITY

	if axis.is_zero_approx():
		if normal.dot(target) < 0.0:
			# Choose a reference axis not parallel to normal.
			var reference := Vector3.UP
			if absf(normal.dot(reference)) > 0.99:
				reference = Vector3.RIGHT

			var perpendicular := normal.cross(reference).normalized()
			tilt = Basis(perpendicular, PI)
	else:
		tilt = Basis(axis.normalized(), normal.angle_to(target))

	return Basis(target, twist) * tilt
