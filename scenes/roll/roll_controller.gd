class_name RollController
extends Screen
## Roll screen. Flow: LOCKED -> READY -> ROLLING -> RESULT, plus RESULT -> READY (Roll Again).
## Confirm or Back leaves the screen. Each result comes from RollResolver before any
## animation starts; the die only animates toward the pose built from that result,
## so animation can never change the outcome.

enum State { LOCKED, READY, ROLLING, RESULT }

signal exit_requested
signal state_changed(new_state: State)

## PLACEHOLDER animation values; Chunk 7 replaces the animation with the real tumble.
const PLACEHOLDER_ROLL_TIME := 0.8
const PLACEHOLDER_SPIN_TURNS := 2.0

var _state := State.LOCKED
var _die: Die
var _face_reader: Node3D
var _resolver := RollResolver.new()
var _result := 0  # Generated result of the current roll.
var _shown_face := 0  # Face detected on the settled die: what the player sees.
var _roll_start := Quaternion.IDENTITY
var _roll_target := Basis.IDENTITY
var _roll_tween: Tween

@onready var _status_label: Label = %StatusLabel
@onready var _result_label: Label = %ResultLabel
@onready var _unlock_button: Button = %UnlockButton
@onready var _roll_button: Button = %RollButton
@onready var _roll_again_button: Button = %RollAgainButton
@onready var _confirm_button: Button = %ConfirmButton


## Called by Main before the screen enters the tree.
func setup(die: Die, face_reader: Node3D) -> void:
	_die = die
	_face_reader = face_reader


func _ready() -> void:
	assert(
		_die != null and _face_reader != null,
		"RollController.setup() must be called before the screen is added."
	)
	_unlock_button.pressed.connect(_on_unlock_pressed)
	_roll_button.pressed.connect(_try_roll)
	_roll_again_button.pressed.connect(_on_roll_again_pressed)
	_confirm_button.pressed.connect(exit_requested.emit)
	_refresh_ui()


func _exit_tree() -> void:
	# Leaving mid-roll (Back): don't leave the die frozen mid-spin.
	if _state == State.ROLLING and is_instance_valid(_die):
		_die.global_basis = _roll_target


## Android sent the app to the background: land the roll now, so the
## player returns to a result instead of a half-finished tumble.
func on_app_paused() -> void:
	if _state == State.ROLLING:
		_finish_roll()


# --- Input handlers: silently ignore requests that don't fit the current state ---


func _on_unlock_pressed() -> void:
	if _state == State.LOCKED:
		_change_state(State.READY)


func _on_roll_again_pressed() -> void:
	if _state == State.RESULT:
		_change_state(State.READY)


## Single entry point for roll requests: Roll button now, shake gesture in Chunk 9.
func _try_roll() -> void:
	if _state != State.READY:
		return  # E.g. a double-tap or a shake while already rolling.
	# Fairness order (GDD §4): the result is decided first, independent of animation.
	_result = _resolver.roll_result()
	_roll_target = _resolver.rest_basis_for(_result, _read_direction())
	_change_state(State.ROLLING)
	_start_roll_animation()


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
			_status_label.text = "Locked"
		State.READY:
			_status_label.text = "Ready - tap Roll"
		State.ROLLING:
			_status_label.text = "Rolling..."
		State.RESULT:
			_status_label.text = "Result"


# --- Rolling ---


func _read_direction() -> Vector3:
	return _face_reader.global_position - _die.global_position


## PLACEHOLDER until Chunk 7: a fast spin that slows down and settles on the target.
## The spin reaches zero at t = 1, so the die ends exactly on the target pose.
func _start_roll_animation() -> void:
	_roll_start = _die.global_basis.get_rotation_quaternion()
	_roll_tween = create_tween()
	(
		_roll_tween
		. tween_method(_apply_roll_progress, 0.0, 1.0, PLACEHOLDER_ROLL_TIME)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	_roll_tween.finished.connect(_finish_roll)


func _apply_roll_progress(t: float) -> void:
	var settle := Basis(_roll_start.slerp(_roll_target.get_rotation_quaternion(), t))
	var spin := Basis(Vector3.UP, PLACEHOLDER_SPIN_TURNS * TAU * (1.0 - t))
	_die.global_basis = spin * settle


func _finish_roll() -> void:
	if _state != State.ROLLING:
		return
	if _roll_tween != null:
		_roll_tween.kill()  # Needed when fast-forwarding from on_app_paused().
		_roll_tween = null
	_die.global_basis = _roll_target  # Exact rest pose, free of interpolation rounding.

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
