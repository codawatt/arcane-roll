class_name MotionInput
extends Node
## Reads and filters the accelerometer, gravity and gyroscope sensors and detects
## deliberate shakes. Knows nothing about dice or rolling.
## The OS sensors are enabled in project settings; this node only processes them
## while active, which is how "sensors activate only when the die is unlocked" works.

## Emitted once per deliberate shake. intensity (0..1) reflects how hard it was.
signal shake_detected(intensity: float)

## A real accelerometer always reads ~9.8 m/s² (gravity); below this it is treated as absent.
const ABSENT_ACCEL_LEVEL := 0.5
## Seconds the accelerometer may stay silent after activation before being reported absent.
const AVAILABILITY_GRACE := 0.5
## Strokes closer together than this (s) are vibration after an impact, not a new stroke.
const MIN_STROKE_GAP := 0.06

@export_group("Shake detection")
## Raw linear acceleration (gravity removed) must exceed this to count, in m/s².
## A new stroke must also swing at least this far to the opposite side of the previous one.
@export var shake_threshold := 10.0
## Alternating strokes needed for a shake (3 = back, forth, back).
@export var strokes_required := 3
## A pause in strong motion longer than this (s) restarts the stroke count.
@export var stroke_timeout := 0.35
## Peak acceleration (m/s²) that counts as intensity 1.0.
@export var strong_shake := 50.0
## Minimum seconds between two detected shakes.
@export var cooldown := 1.0

@export_group("Smoothing")
## Filter time constants in seconds: higher = smoother but slower to react.
@export var accel_smoothing := 0.02
@export var gyro_smoothing := 0.06
## Only used without a gravity sensor: gravity is estimated by heavily smoothing the accelerometer.
@export var gravity_estimate_smoothing := 0.4

## Device frame (X right, Y up, Z out of the screen), m/s², gravity removed, smoothed. For display.
var linear_acceleration := Vector3.ZERO
## Same, unsmoothed: shake detection uses this so short peaks keep their full height.
var raw_linear_acceleration := Vector3.ZERO
## Device frame, rad/s, smoothed.
var angular_velocity := Vector3.ZERO
## Strongest acceleration of the current or most recent stroke sequence, m/s² (for tuning).
var last_peak_magnitude := 0.0

var _active := false
var _active_time := 0.0
var _clock := 0.0
var _accel_seen := false
var _gyro_seen := false
var _using_estimated_gravity := false
var _gravity_estimate := Vector3.ZERO
var _cooldown_left := 0.0
var _stroke_count := 0
var _stroke_direction := Vector3.ZERO  # Unit direction of the current stroke.
var _stroke_start_time := 0.0
var _last_strong_time := 0.0
var _sequence_peak := 0.0


func _ready() -> void:
	set_process(false)


## Starts or stops sensor processing. Detection state is reset either way.
func set_active(active: bool) -> void:
	_active = active
	_active_time = 0.0
	set_process(active)
	_stroke_count = 0
	_stroke_direction = Vector3.ZERO
	_sequence_peak = 0.0
	linear_acceleration = Vector3.ZERO
	raw_linear_acceleration = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func is_active() -> bool:
	return _active


## True once the accelerometer has delivered real data.
func has_accelerometer() -> bool:
	return _accel_seen


## True once the accelerometer has stayed silent past the grace period: shaking is unavailable.
func is_accelerometer_absent() -> bool:
	return _active and not _accel_seen and _active_time > AVAILABILITY_GRACE


## True once the gyroscope has reported any rotation. Unknown (false) until the phone moves.
func has_gyroscope() -> bool:
	return _gyro_seen


func is_using_estimated_gravity() -> bool:
	return _using_estimated_gravity


func get_stroke_count() -> int:
	return _stroke_count


func get_cooldown_left() -> float:
	return _cooldown_left


## Converts a device-frame vector to world space. In portrait, the phone's axes match
## the screen's, and the screen shows the camera's view, so the camera's basis maps one
## onto the other.
static func device_to_world(device_vector: Vector3, camera: Camera3D) -> Vector3:
	return camera.global_basis * device_vector


func _process(delta: float) -> void:
	_clock += delta
	_active_time += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var accel := Input.get_accelerometer()
	var gyro := Input.get_gyroscope()
	if accel.length() > ABSENT_ACCEL_LEVEL:
		_accel_seen = true
	if gyro != Vector3.ZERO:
		_gyro_seen = true
	if not _accel_seen:
		return

	var gravity := Input.get_gravity()
	_using_estimated_gravity = gravity.is_zero_approx()
	if _using_estimated_gravity:
		# No gravity sensor: gravity is the slow-moving part of the accelerometer signal.
		if _gravity_estimate.is_zero_approx():
			_gravity_estimate = accel
		_gravity_estimate = _gravity_estimate.lerp(accel, _blend(delta, gravity_estimate_smoothing))
		gravity = _gravity_estimate

	raw_linear_acceleration = accel - gravity
	linear_acceleration = linear_acceleration.lerp(
		raw_linear_acceleration, _blend(delta, accel_smoothing)
	)
	angular_velocity = angular_velocity.lerp(gyro, _blend(delta, gyro_smoothing))
	_detect_shake(raw_linear_acceleration)


## A shake is a quick series of strokes in alternating directions. Each new stroke
## must swing strongly to the opposite side of the previous one; the acceleration does
## not need to drop to zero in between (in real hand shakes it rarely does).
## Putting the phone down (one stroke) or picking it up (two) is not enough.
func _detect_shake(linear: Vector3) -> void:
	if _stroke_count > 0 and _clock - _last_strong_time > stroke_timeout:
		_stroke_count = 0  # The motion paused: start counting again.
	var magnitude := linear.length()
	if magnitude < shake_threshold or _cooldown_left > 0.0:
		return
	_last_strong_time = _clock

	if _stroke_count == 0:
		_stroke_count = 1
		_stroke_direction = linear / magnitude
		_stroke_start_time = _clock
		_sequence_peak = magnitude
	else:
		_sequence_peak = maxf(_sequence_peak, magnitude)
		var swung_opposite := linear.dot(_stroke_direction) < -shake_threshold
		if swung_opposite and _clock - _stroke_start_time >= MIN_STROKE_GAP:
			_stroke_count += 1
			_stroke_direction = linear / magnitude
			_stroke_start_time = _clock
	last_peak_magnitude = _sequence_peak

	if _stroke_count >= strokes_required:
		var intensity := clampf(
			inverse_lerp(shake_threshold, strong_shake, _sequence_peak), 0.0, 1.0
		)
		_stroke_count = 0
		_cooldown_left = cooldown
		shake_detected.emit(intensity)


## Frame-rate-independent smoothing factor for a given time constant.
static func _blend(delta: float, time_constant: float) -> float:
	return 1.0 - exp(-delta / maxf(time_constant, 0.0001))
