extends Node
## User preferences: colors (GDD §3), SFX mute (GDD §6) and motion gestures (Chunk 9b).
## Changes apply immediately through `changed` and are saved locally: debounced while
## values are changing, and flushed when the app is paused or closed.

signal changed

const SAVE_PATH := "user://settings.cfg"
const FORMAT_VERSION := 1
const SAVE_DELAY := 0.5  # Seconds; groups rapid changes (e.g. dragging a color) into one write.

const DEFAULT_BACKGROUND := Color("1e1b2e")
const DEFAULT_DOTS := Color("3a3358")
const DEFAULT_TRIANGLES := Color("8e7cc3")

var background_color := DEFAULT_BACKGROUND:
	set(value):
		if background_color == value:
			return
		background_color = value
		_value_changed()

var dot_color := DEFAULT_DOTS:
	set(value):
		if dot_color == value:
			return
		dot_color = value
		_value_changed()

var triangle_color := DEFAULT_TRIANGLES:
	set(value):
		if triangle_color == value:
			return
		triangle_color = value
		_value_changed()

var sfx_muted := false:
	set(value):
		if sfx_muted == value:
			return
		sfx_muted = value
		_value_changed()

var motion_gestures := true:
	set(value):
		if motion_gestures == value:
			return
		motion_gestures = value
		_value_changed()

var _loading := false
var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	load_settings()


func _notification(what: int) -> void:
	# Android may kill a paused app without warning, so write pending changes now.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _exit_tree() -> void:
	flush()  # get_tree().quit() (Back on the menu) ends up here.


func reset_colors() -> void:
	background_color = DEFAULT_BACKGROUND
	dot_color = DEFAULT_DOTS
	triangle_color = DEFAULT_TRIANGLES


## Writes pending changes immediately, if there are any.
func flush() -> void:
	if _save_timer != null and not _save_timer.is_stopped():
		_save_timer.stop()
		save()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	config.set_value("colors", "background", background_color)
	config.set_value("colors", "dots", dot_color)
	config.set_value("colors", "triangles", triangle_color)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.set_value("input", "motion_gestures", motion_gestures)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Settings: could not save %s (%s)" % [SAVE_PATH, error_string(error)])


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return  # First launch: keep the defaults.
	if error != OK:
		push_warning(
			"Settings: %s is unreadable (%s); using defaults." % [SAVE_PATH, error_string(error)]
		)
		return
	_loading = true
	background_color = _read(config, "colors", "background", DEFAULT_BACKGROUND)
	dot_color = _read(config, "colors", "dots", DEFAULT_DOTS)
	triangle_color = _read(config, "colors", "triangles", DEFAULT_TRIANGLES)
	sfx_muted = _read(config, "audio", "sfx_muted", false)
	motion_gestures = _read(config, "input", "motion_gestures", true)
	_loading = false
	changed.emit()


## Returns the stored value, or `fallback` if it is missing or of the wrong type.
func _read(config: ConfigFile, section: String, key: String, fallback: Variant) -> Variant:
	var value: Variant = config.get_value(section, key, fallback)
	return value if typeof(value) == typeof(fallback) else fallback


func _value_changed() -> void:
	if _loading or _save_timer == null:
		return  # Loading (one signal at the end) or still initializing.
	changed.emit()
	_save_timer.start()  # Restarting the timer delays the write until changes stop.
