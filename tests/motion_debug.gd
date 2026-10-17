extends Node3D
## Chunk 8 on-device check of motion input: live filtered values, a scrolling graph
## and every detected shake. "Follow gyro" spins the die with the phone's rotation
## so the device-to-world mapping and its sign can be judged by eye.

var _follow_gyro := false
var _spin_sign := 1.0
var _shake_count := 0
var _last_shake := "none yet"
var _shake_this_frame := false
var _max_linear := 0.0

@onready var _motion: MotionInput = $MotionInput
@onready var _die: Die = $D6
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _info_label: Label = $HUD/InfoLabel
@onready var _graph: SensorGraph = $HUD/Graph
@onready var _follow_button: Button = $HUD/Buttons/FollowButton
@onready var _flip_button: Button = $HUD/Buttons/FlipButton
@onready var _reset_button: Button = $HUD/Buttons/ResetButton


func _ready() -> void:
	_motion.shake_detected.connect(_on_shake_detected)
	_follow_button.pressed.connect(_on_follow_pressed)
	_flip_button.pressed.connect(_on_flip_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_motion.set_active(true)
	_update_buttons()


func _process(delta: float) -> void:
	var linear := _motion.linear_acceleration.length()
	_max_linear = maxf(_max_linear, linear)
	_graph.threshold = _motion.shake_threshold
	_graph.push(linear, _motion.angular_velocity.length(), _shake_this_frame)
	_shake_this_frame = false

	if _follow_gyro:
		var world_spin := (
			MotionInput.device_to_world(_motion.angular_velocity, _camera) * _spin_sign
		)
		var speed := world_spin.length()
		if speed > 0.01:
			_die.global_basis = (
				(Basis(world_spin / speed, speed * delta) * _die.global_basis).orthonormalized()
			)

	_info_label.text = _build_report(linear)


func _build_report(linear: float) -> String:
	var accel_status := (
		"OK"
		if _motion.has_accelerometer()
		else ("ABSENT" if _motion.is_accelerometer_absent() else "checking...")
	)
	var gyro_status := "OK" if _motion.has_gyroscope() else "no data yet (rotate phone)"
	var lines := PackedStringArray(
		[
			(
				"Accelerometer: %s   Gravity: %s"
				% [accel_status, "estimated" if _motion.is_using_estimated_gravity() else "sensor"]
			),
			"Gyroscope: %s" % gyro_status,
			"",
			"Linear accel: %s  |%.1f| m/s2" % [_fmt(_motion.linear_acceleration), linear],
			"Max since reset: %.1f m/s2" % _max_linear,
			(
				"Gyro: %s  |%.2f| rad/s"
				% [_fmt(_motion.angular_velocity), _motion.angular_velocity.length()]
			),
			"",
			(
				"Threshold %.1f   Strokes %d/%d   Cooldown %.1f s"
				% [
					_motion.shake_threshold,
					_motion.get_stroke_count(),
					_motion.strokes_required,
					_motion.get_cooldown_left()
				]
			),
			"Shakes: %d   Last: %s" % [_shake_count, _last_shake],
		]
	)
	return "\n".join(lines)


func _fmt(v: Vector3) -> String:
	return "(%5.1f, %5.1f, %5.1f)" % [v.x, v.y, v.z]


func _on_shake_detected(intensity: float) -> void:
	_shake_count += 1
	_last_shake = "#%d  intensity %.2f" % [_shake_count, intensity]
	_shake_this_frame = true


func _on_follow_pressed() -> void:
	_follow_gyro = not _follow_gyro
	_update_buttons()


func _on_flip_pressed() -> void:
	_spin_sign = -_spin_sign
	_update_buttons()


func _on_reset_pressed() -> void:
	_die.global_basis = Basis.IDENTITY
	_max_linear = 0.0
	_shake_count = 0
	_last_shake = "none yet"


func _update_buttons() -> void:
	_follow_button.text = "Follow gyro: %s" % ("ON" if _follow_gyro else "OFF")
	_flip_button.text = "Sign: %+d" % int(_spin_sign)
	_reset_button.text = "Reset"
