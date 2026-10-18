class_name MainMenu
extends Screen
## Main menu (GDD §3): title, rotating die preview between selection arrows (disabled
## until more dice exist), Start / Customize / Credits, and the version label.

signal start_requested
signal customize_requested
signal credits_requested

const PREVIEW_SPIN_SPEED := 0.6  # rad/s around the vertical axis.
const PREVIEW_SPIN_RAMP := 1.5  # rad/s²: the spin eases in instead of starting abruptly.

var _die: Die
var _spin_speed := 0.0


## Called by Main before the screen enters the tree.
func setup(die: Die) -> void:
	_die = die


## The preview eases into a square-on rest with a small overshoot instead of freezing.
## The die finishes that motion on its own after this screen is gone.
func _on_start_pressed() -> void:
	_die.settle_spin(_spin_speed)
	start_requested.emit()


func _ready() -> void:
	assert(_die != null, "MainMenu.setup() must be called before the screen is added.")
	%StartButton.pressed.connect(_on_start_pressed)
	%CustomizeButton.pressed.connect(customize_requested.emit)
	%CreditsButton.pressed.connect(credits_requested.emit)
	%VersionLabel.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	# Dice selection comes with additional dice (GDD §8, future updates): disabled for now.
	for arrow: Button in [%PrevButton, %NextButton]:
		arrow.disabled = true
		arrow.focus_mode = Control.FOCUS_NONE


func _process(delta: float) -> void:
	if _die.is_rolling() or _die.is_settling():
		return
	_spin_speed = move_toward(_spin_speed, PREVIEW_SPIN_SPEED, PREVIEW_SPIN_RAMP * delta)
	# Vertical axis only, so the die stays flat on a face for the next roll.
	_die.global_basis = (
		(Basis(Vector3.UP, _spin_speed * delta) * _die.global_basis).orthonormalized()
	)
