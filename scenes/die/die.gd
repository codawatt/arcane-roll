class_name Die
extends Node3D
## A six-sided die. Knows its face layout, reports which face points along a
## direction, and plays tumble animations that end exactly on a requested pose.
## It never decides results: RollResolver does (Chunk 5).

signal roll_finished
## Emitted at every bounce during a roll; strength is 0..1. Chunk 14 plays the landing sound here.
signal impact(strength: float)
## Emitted once per roll when the free tumble ends and the settle begins.
signal tumble_finished
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

## The whole roll is simulated at this fixed step when it starts, then played
## back by elapsed time, so it looks identical at 30, 60 or 120 FPS.
const SIM_STEP := 1.0 / 240.0
const MIN_BOUNCE_SPEED := 0.6  # Below this the die stops hopping.
const REST_ANGLE := 0.01  # rad (~0.6 deg): close enough to count as resting.
const REST_SPIN := 0.05  # rad/s

@export_group("Tumble")
## Spin speed in rad/s at intensity 0 and at intensity 1.
@export var min_spin_speed := 18.0
@export var max_spin_speed := 40.0
## How fast the spin slows down (exponential, per second).
@export var spin_drag := 1.6
## Extra random spin added at each bounce, per unit of impact speed.
@export var impact_spin_kick := 1.2

@export_group("Hop")
## Launch speed at intensity 0 and at intensity 1 (die = 1 unit wide).
@export var min_hop_speed := 3.5
@export var max_hop_speed := 6.5
@export var gravity := 25.0
## Fraction of speed kept after each bounce.
@export_range(0.0, 0.9) var bounce_restitution := 0.35

@export_group("Settle")
## Once on the ground and slower than this (rad/s), the die tips onto its nearest face.
@export var settle_start_speed := 7.0
## Spring frequency in rad/s: higher = quicker settle.
@export var settle_frequency := 8.0
## Below 1.0 the die overshoots and rocks before resting; lower = more rocking.
@export_range(0.1, 1.0) var settle_damping_ratio := 0.45
## Hard limit for one roll; the die always lands by then.
@export var max_roll_time := 4.0

@export_group("Preview settle")
## Spring used when the menu's spinning preview eases into its square-on rest.
## Higher frequency = snappier; lower damping = more overshoot.
@export var preview_settle_frequency := 7.0
@export_range(0.1, 1.0) var preview_settle_damping := 0.45

var _rest_position := Vector3.ZERO
var _rng := RandomNumberGenerator.new()  # Cosmetic only (tumble axes); never affects results.
var _rolling := false
var _frames: Array[Quaternion] = []  # Simulated orientation per SIM_STEP.
var _heights := PackedFloat32Array()  # Simulated hop height per SIM_STEP.
var _impact_times := PackedFloat32Array()
var _impact_strengths := PackedFloat32Array()
var _next_impact := 0
var _settle_start_time := 0.0
var _target := Quaternion.IDENTITY
var _correction := Quaternion.IDENTITY
var _play_time := 0.0
var _settling := false
var _settle_from := Basis.IDENTITY
var _settle_angle := 0.0
var _settle_velocity := 0.0
var _settle_target := 0.0
var _tumble_signaled := false
var _pulse_tween: Tween


func _ready() -> void:
	_rest_position = position
	_rng.randomize()
	set_process(false)


# --- Face logic (unchanged from Chunk 4) ---


## Returns the face whose outward normal is most aligned with world_direction.
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


## Orientation in which `face` points along `direction`, twisted by `twist` around it.
static func basis_with_face_toward(face: int, direction: Vector3, twist: float = 0.0) -> Basis:
	var normal := FACE_NORMALS[face]
	var target := direction.normalized()
	var axis := normal.cross(target)
	var tilt := Basis.IDENTITY
	if axis.is_zero_approx():
		if normal.dot(target) < 0.0:
			var perpendicular := normal.cross(Vector3.UP)

			if perpendicular.is_zero_approx():
				perpendicular = normal.cross(Vector3.RIGHT)

			tilt = Basis(perpendicular.normalized(), PI)
	else:
		tilt = Basis(axis.normalized(), normal.angle_to(target))
	return Basis(target, twist) * tilt


# --- Rolling ---


func is_rolling() -> bool:
	return _rolling


## Length in seconds of the current (or last) roll, known as soon as it starts.
func get_roll_duration() -> float:
	return maxf(0.0, (_frames.size() - 1) * SIM_STEP)


## Starts a tumble that ends exactly at `target` (world space) and emits roll_finished.
## intensity (0..1) scales spin and hop. spin_axis (world space, optional) sets the
## initial tumble direction; Chunk 9 passes the gyroscope here.
func roll_to(target: Basis, intensity: float = 0.5, spin_axis: Vector3 = Vector3.ZERO) -> void:
	_settling = false
	var strength := clampf(intensity, 0.0, 1.0)
	var axis := _random_tumble_axis() if spin_axis.is_zero_approx() else spin_axis.normalized()
	var natural_rest := _simulate(
		global_basis.get_rotation_quaternion(),
		axis * lerpf(min_spin_speed, max_spin_speed, strength),
		lerpf(min_hop_speed, max_hop_speed, strength)
	)
	_target = target.get_rotation_quaternion()
	_correction = _target * natural_rest.inverse()
	if _correction.w < 0.0:
		_correction = -_correction  # Same rotation, shorter way round.
	_play_time = 0.0
	_next_impact = 0
	_tumble_signaled = false
	_rolling = true
	set_process(true)


## Ends the current roll immediately on its target (Back, app paused).
func finish_roll_now() -> void:
	if _rolling:
		_land()


func is_settling() -> bool:
	return _settling


## Ends a spinning preview (spin_speed = current yaw speed in rad/s) by continuing in the
## same direction to the next square-on angle, then overshooting slightly and settling.
## Leaves the die flat and lined up with the world axes (the corner-facing camera view).
func settle_spin(spin_speed: float) -> void:
	if _rolling:
		return
	var direction := 1.0 if spin_speed >= 0.0 else -1.0
	var min_travel := absf(spin_speed) * 0.25  # Never stop sooner than the motion suggests.
	var to_square: float = -_yaw_from_square() * direction
	var quarter_turns := maxi(0, ceili((min_travel - to_square) / (PI / 2.0)))
	_settle_target = direction * (to_square + quarter_turns * PI / 2.0)
	_settle_from = global_basis.orthonormalized()
	_settle_angle = 0.0
	_settle_velocity = spin_speed  # Start at the current speed: no visible jolt.
	_settling = true
	set_process(true)


## Brief scale pop for feedback (unlock, result). Scales the Model child, so it never
## interferes with roll orientation, which is set on this node.
func pulse(amount: float = 0.12) -> void:
	var model := $Model as Node3D
	if _pulse_tween != null:
		_pulse_tween.kill()
	model.scale = Vector3.ONE
	_pulse_tween = create_tween()
	(
		_pulse_tween
		. tween_property(model, "scale", Vector3.ONE * (1.0 + amount), 0.08)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_pulse_tween
		. tween_property(model, "scale", Vector3.ONE, 0.4)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _process(delta: float) -> void:
	if _settling:
		_step_settle(delta)
		return
	_play_time += delta
	while _next_impact < _impact_times.size() and _impact_times[_next_impact] <= _play_time:
		impact.emit(_impact_strengths[_next_impact])
		_next_impact += 1
	if not _tumble_signaled and _play_time >= _settle_start_time:
		_tumble_signaled = true
		tumble_finished.emit()
	var frame_position := _play_time / SIM_STEP
	var i := floori(frame_position)
	if i >= _frames.size() - 1:
		_land()
		return
	var weight := frame_position - i
	var simulated := _frames[i].slerp(_frames[i + 1], weight)
	# Steer the free simulation onto the requested pose. The correction blends in
	# while the die spins fast (where it is invisible) and is complete before it settles.
	var blend := smoothstep(0.0, maxf(_settle_start_time, SIM_STEP), _play_time)
	global_basis = Basis(Quaternion.IDENTITY.slerp(_correction, blend) * simulated)
	position = _rest_position + Vector3.UP * lerpf(_heights[i], _heights[i + 1], weight)


func _land() -> void:
	_rolling = false
	set_process(false)
	position = _rest_position
	global_basis = Basis(_target)  # Exact: removes any interpolation rounding.
	roll_finished.emit()


## Simulates a complete roll at a fixed step and records it for playback.
## Returns the flat pose the free simulation comes to rest in.
func _simulate(start: Quaternion, spin: Vector3, hop_speed: float) -> Quaternion:
	_frames.clear()
	_heights.clear()
	_impact_times.clear()
	_impact_strengths.clear()
	var orientation := start
	var angular_velocity := spin
	var height := 0.0
	var vertical_speed := hop_speed
	var settling := false
	var rest := start
	var stiffness := settle_frequency * settle_frequency
	var damping := 2.0 * settle_damping_ratio * settle_frequency
	var time := 0.0
	_settle_start_time = max_roll_time
	_frames.append(orientation)
	_heights.append(height)

	while time < max_roll_time:
		time += SIM_STEP

		# Hop: gravity with damped bounces. While tumbling, each bounce kicks the spin.
		if height > 0.0 or vertical_speed > 0.0:
			vertical_speed -= gravity * SIM_STEP
			height += vertical_speed * SIM_STEP
			if height <= 0.0:
				var impact_speed := -vertical_speed
				height = 0.0
				_impact_times.append(time)
				_impact_strengths.append(clampf(impact_speed / max_hop_speed, 0.0, 1.0))
				if not settling:
					angular_velocity += _random_tumble_axis() * impact_speed * impact_spin_kick
				vertical_speed = impact_speed * bounce_restitution
				if vertical_speed < MIN_BOUNCE_SPEED:
					vertical_speed = 0.0
		var grounded := height <= 0.0 and vertical_speed <= 0.0

		# Spin: free tumble with drag, then a spring tips the die onto its nearest face.
		if not settling:
			angular_velocity *= exp(-spin_drag * SIM_STEP)
			if grounded and angular_velocity.length() < settle_start_speed:
				settling = true
				_settle_start_time = time
				rest = _nearest_rest(orientation)
		else:
			var error := _rotation_between(orientation, rest)
			angular_velocity += (error * stiffness - angular_velocity * damping) * SIM_STEP
		orientation = _rotated(orientation, angular_velocity, SIM_STEP)

		_frames.append(orientation)
		_heights.append(height)
		if (
			settling
			and grounded
			and angular_velocity.length() < REST_SPIN
			and _rotation_between(orientation, rest).length() < REST_ANGLE
		):
			break

	if not settling:  # Safety net: time ran out before the die slowed down.
		rest = _nearest_rest(orientation)
		_settle_start_time = time
	_frames[-1] = rest  # The recording ends exactly at rest.
	return rest


## The flat pose closest to `orientation`: tip the most upward face straight up, keep the yaw.
func _nearest_rest(orientation: Quaternion) -> Quaternion:
	var world_basis := Basis(orientation)
	var up_normal := Vector3.UP
	var best := -INF
	for face: int in FACE_NORMALS:
		var normal := world_basis * FACE_NORMALS[face]
		if normal.y > best:
			best = normal.y
			up_normal = normal
	var axis := up_normal.cross(Vector3.UP)
	if axis.is_zero_approx():
		return orientation
	return Quaternion(axis.normalized(), up_normal.angle_to(Vector3.UP)) * orientation


## Yaw around world up that the die is away from being lined up with the axes,
## in [-PI/4, PI/4]. Measured from the side face that points closest to +Z.
func _yaw_from_square() -> float:
	var world_basis := global_basis.orthonormalized()
	var closest := Vector3.BACK
	var best := -INF
	for face: int in FACE_NORMALS:
		var normal := world_basis * FACE_NORMALS[face]
		if absf(normal.y) < 0.5 and normal.z > best:  # Side faces only.
			best = normal.z
			closest = normal
	return atan2(closest.x, closest.z)


func _step_settle(delta: float) -> void:
	var stiffness := preview_settle_frequency * preview_settle_frequency
	var damping := 2.0 * preview_settle_damping * preview_settle_frequency
	var steps := maxi(1, ceili(delta / SIM_STEP))  # Fixed sub-steps: stable at any frame rate.
	var dt := delta / steps
	for _i in steps:
		_settle_velocity += (
			((_settle_target - _settle_angle) * stiffness - _settle_velocity * damping) * dt
		)
		_settle_angle += _settle_velocity * dt
	if absf(_settle_target - _settle_angle) < 0.001 and absf(_settle_velocity) < 0.01:
		_settle_angle = _settle_target  # Land exactly square-on.
		_settling = false
		set_process(false)
	global_basis = Basis(Vector3.UP, _settle_angle) * _settle_from


## Mostly horizontal axis, so the die tumbles end over end rather than spinning like a top.
func _random_tumble_axis() -> Vector3:
	var angle := _rng.randf() * TAU
	return Vector3(cos(angle), _rng.randf_range(-0.5, 0.5), sin(angle)).normalized()


## World-space rotation (axis * angle) that turns `from` into `to` the short way.
static func _rotation_between(from: Quaternion, to: Quaternion) -> Vector3:
	var delta := to * from.inverse()
	if delta.w < 0.0:
		delta = -delta
	var angle := delta.get_angle()
	return Vector3.ZERO if angle < 0.0001 else delta.get_axis() * angle


static func _rotated(orientation: Quaternion, angular_velocity: Vector3, dt: float) -> Quaternion:
	var speed := angular_velocity.length()
	if speed < 0.000001:
		return orientation
	return (Quaternion(angular_velocity / speed, speed * dt) * orientation).normalized()
