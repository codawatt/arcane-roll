class_name RollController
extends Screen
## Roll screen. Flow: LOCKED -> READY -> ROLLING -> RESULT, plus RESULT -> READY (Roll Again).
## Confirm or Back leaves the screen. Each result comes from RollResolver before any
## animation starts; the die only animates toward the pose built from that result,
## so animation can never change the outcome.

enum State { LOCKED, READY, ROLLING, RESULT }

signal exit_requested
signal state_changed(new_state: State)

## Tumble strength for the Roll button. Chunk 9 passes shake strength and gyro axis instead.
const BUTTON_ROLL_INTENSITY := 0.6
## Phone rotation maps onto the tumble with this sign: +1 = the die turns with the phone
## (chosen on device in Chunk 8).
const SPIN_SIGN := 1.0
## Below this gyro speed (rad/s) the phone's rotation is ignored and the tumble axis is random.
const MIN_TWIST_SPEED := 1.0
## Gyro speed (rad/s) that counts as a full-strength twist.
const STRONG_TWIST_SPEED := 8.0
## Key twist unlocks and rolls again. Mirrors Settings.motion_gestures (user option).
var motion_gestures_enabled := true
var _state := State.LOCKED
var _die: Die
var _face_reader: Node3D
var _resolver := RollResolver.new()
var _result := 0  # Generated result of the current roll.
var _shown_face := 0  # Face detected on the settled die: what the player sees.
var _camera: Camera3D
@onready var _status_label: Label = %StatusLabel
@onready var _result_label: Label = %ResultLabel
@onready var _unlock_button: Button = %UnlockButton
@onready var _roll_button: Button = %RollButton
@onready var _roll_again_button: Button = %RollAgainButton
@onready var _confirm_button: Button = %ConfirmButton
@onready var _motion: MotionInput = $MotionInput


## Called by Main before the screen enters the tree.
func setup(die: Die, face_reader: Node3D, camera: Camera3D) -> void:
	_die = die
	_face_reader = face_reader
	_camera = camera


func _ready() -> void:
	assert(
		_die != null and _face_reader != null and _camera != null,
		"RollController.setup() must be called before the screen is added."
	)
	_motion.shake_detected.connect(_on_shake_detected)
	_motion.accelerometer_detected.connect(_refresh_ui)
	_motion.twist_detected.connect(_on_twist_detected)
	_motion.gyroscope_detected.connect(_refresh_ui)
	_unlock_button.pressed.connect(_on_unlock_pressed)
	_roll_button.pressed.connect(_on_roll_pressed)
	_roll_again_button.pressed.connect(_on_roll_again_pressed)
	_confirm_button.pressed.connect(exit_requested.emit)
	_die.roll_finished.connect(_on_die_roll_finished)
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _exit_tree() -> void:
	# The die outlives this screen: disconnect explicitly, then land any roll in
	# progress (Back mid-roll) instead of leaving the die frozen mid-air.
	if is_instance_valid(_die):
		if _die.roll_finished.is_connected(_on_die_roll_finished):
			_die.roll_finished.disconnect(_on_die_roll_finished)
		_die.finish_roll_now()


## Android sent the app to the background: land the roll now, so the
## player returns to a result instead of a half-finished tumble.
func on_app_paused() -> void:
	if _state == State.ROLLING:
		_die.finish_roll_now()  # Emits roll_finished, which shows the result.


# --- Input handlers: silently ignore requests that don't fit the current state ---


func _on_unlock_pressed() -> void:
	if _state == State.LOCKED:
		_change_state(State.READY)


func _on_roll_again_pressed() -> void:
	if _state == State.RESULT:
		_change_state(State.READY)


func _on_roll_pressed() -> void:
	_start_roll(BUTTON_ROLL_INTENSITY, Vector3.ZERO)


## A deliberate shake rolls the die. The shake's strength and the phone's twist shape
## the tumble (intensity and direction); the result is still decided by RollResolver.
func _on_shake_detected(shake_intensity: float) -> void:
	# Read the gyro before _start_roll(): leaving Ready deactivates and resets MotionInput.
	var twist := MotionInput.device_to_world(_motion.angular_velocity, _camera) * SPIN_SIGN
	var twist_speed := twist.length()
	var twist_intensity := clampf(twist_speed / STRONG_TWIST_SPEED, 0.0, 1.0)
	var spin_axis := twist if twist_speed >= MIN_TWIST_SPEED else Vector3.ZERO
	_start_roll(maxf(shake_intensity, twist_intensity), spin_axis)


## Key twist: unlock when Locked, roll again on the Result screen. Ignored in other states.
func _on_twist_detected() -> void:
	if not motion_gestures_enabled:
		return
	match _state:
		State.LOCKED:
			_on_unlock_pressed()
		State.RESULT:
			_on_roll_again_pressed()


## GDD: sensors run only while unlocked (Ready). With motion gestures on (user option),
## they also run while Locked and on the Result screen to catch the key twist.
## They never run while the die is rolling.
func _update_motion() -> void:
	var listening := (
		_state == State.READY
		or (motion_gestures_enabled and (_state == State.LOCKED or _state == State.RESULT))
	)
	_motion.set_active(listening)


func _apply_settings() -> void:
	motion_gestures_enabled = Settings.motion_gestures
	_update_motion()
	_refresh_ui()


func _twist_available() -> bool:
	return motion_gestures_enabled and _motion.has_gyroscope()


## Single entry point for roll requests: Roll button now, shake gesture in Chunk 9.
## intensity (0..1) and spin_axis only shape the animation, never the result.
func _start_roll(intensity: float, spin_axis: Vector3) -> void:
	if _state != State.READY:
		return  # E.g. a double-tap or a shake while already rolling.
	# Fairness order (GDD §4): the result is decided first, independent of animation.
	_result = _resolver.roll_result()
	var target := _resolver.rest_basis_for(_result, _read_direction())
	_change_state(State.ROLLING)
	_die.roll_to(target, intensity, spin_axis)


# --- State machine ---


static func _is_allowed(from: State, to: State) -> bool:
	match from:
		State.LOCKED:
			return to == State.READY
		State.READY:
			return to == State.ROLLING
		State.ROLLING:
			return to == State.RESULT
		State.RESULT:
			return to == State.READY
	return false


func _change_state(to: State) -> void:
	if not _is_allowed(_state, to):
		push_error(
			"RollController: illegal transition %s -> %s" % [State.keys()[_state], State.keys()[to]]
		)
		return
	_state = to
	_update_motion()
	_refresh_ui()
	state_changed.emit(_state)


func _refresh_ui() -> void:
	_unlock_button.visible = _state == State.LOCKED
	_roll_button.visible = _state == State.READY
	_roll_again_button.visible = _state == State.RESULT
	_confirm_button.visible = _state == State.RESULT
	_result_label.text = str(_shown_face) if _state == State.RESULT else ""
	match _state:
		State.LOCKED:
			_status_label.text = "Locked - twist to unlock" if _twist_available() else "Locked"
		State.READY:
			_status_label.text = (
				"Ready - shake or tap Roll" if _motion.has_accelerometer() else "Ready - tap Roll"
			)
		State.ROLLING:
			_status_label.text = "Rolling..."
		State.RESULT:
			_status_label.text = "Result - twist to roll again" if _twist_available() else "Result"


# --- Rolling ---


func _read_direction() -> Vector3:
	return _face_reader.global_position - _die.global_position


func _on_die_roll_finished() -> void:
	if _state != State.ROLLING:
		return
	# GDD §4 steps 5-7: detect the face from the die's orientation, verify, display.
	var direction := _read_direction()
	if not RollResolver.verify(_die, direction, _result):
		# Only possible if the face table or resolver is broken; fail loudly in debug.
		push_error(
			(
				"Roll verification failed: generated %d, detected %d"
				% [_result, _die.get_face_toward(direction)]
			)
		)
		assert(false, "Roll verification failed")
	_shown_face = _die.get_face_toward(direction)  # Always show what the die shows.
	_change_state(State.RESULT)
