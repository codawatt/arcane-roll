extends Node
## App root. Owns the persistent background, 3D world and UI layers,
## swaps screens, applies the display safe area, and routes Android Back
## and app-pause events to the active screen.

enum ScreenId { MAIN_MENU, ROLL }

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menu/main_menu.tscn")
const ROLL_SCREEN_SCENE: PackedScene = preload("res://scenes/roll/roll_screen.tscn")

var _current_screen: Screen = null
var _current_id: ScreenId = ScreenId.MAIN_MENU

@onready var _safe_area: MarginContainer = $UILayer/SafeArea
@onready var _screen_host: Control = $UILayer/SafeArea/ScreenHost
@onready var _die: Die = $World/DieAnchor/D6
@onready var _face_reader: Marker3D = $World/FaceReader
@onready var _camera: Camera3D = $World/CameraRig/Camera3D
@onready var _background: AppBackground = $BackgroundLayer/Background


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_background.set_bands_shown(false, false)  # Start hidden; the menu slides them in.
	_show_main_menu()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_back()
		NOTIFICATION_APPLICATION_PAUSED:
			if _current_screen != null:
				_current_screen.on_app_paused()


func _unhandled_input(event: InputEvent) -> void:
	# Desktop stand-in for Android Back. On Android, the notification above handles it.
	if not OS.has_feature("android") and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()


func _handle_back() -> void:
	if _current_screen != null and _current_screen.handle_back():
		return
	match _current_id:
		ScreenId.ROLL:
			_show_main_menu()
		ScreenId.MAIN_MENU:
			get_tree().quit()


func _show_main_menu() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	menu.setup(_die)
	# Deferred: the old screen is freed while its own button signal is still emitting.
	menu.start_requested.connect(_show_roll_screen, CONNECT_DEFERRED)
	_swap_screen(menu, ScreenId.MAIN_MENU)
	_background.set_bands_shown(true)


func _show_roll_screen() -> void:
	var roll := ROLL_SCREEN_SCENE.instantiate() as RollController
	roll.setup(_die, _face_reader, _camera)
	roll.exit_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	_swap_screen(roll, ScreenId.ROLL)
	_background.set_bands_shown(false)


func _swap_screen(new_screen: Screen, id: ScreenId) -> void:
	if _current_screen != null:
		_screen_host.remove_child(_current_screen)  # Hide immediately, no 1-frame overlap.
		_current_screen.queue_free()
	_current_screen = new_screen
	_current_id = id
	_screen_host.add_child(new_screen)


## Converts the OS safe area (window pixels) into viewport units and applies it
## as margins, so UI never sits under cutouts or system bars.
## Desktop reports monitor-level areas, so margins stay zero there.
func _apply_safe_area() -> void:
	var margins := Vector4.ZERO  # left, top, right, bottom
	if OS.has_feature("mobile"):
		var window_size := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if window_size.x > 0.0 and window_size.y > 0.0:
			var to_viewport := get_viewport().get_visible_rect().size / window_size
			margins = Vector4(
				safe.position.x * to_viewport.x,
				safe.position.y * to_viewport.y,
				(window_size.x - safe.end.x) * to_viewport.x,
				(window_size.y - safe.end.y) * to_viewport.y
			)
	_safe_area.add_theme_constant_override("margin_left", roundi(margins.x))
	_safe_area.add_theme_constant_override("margin_top", roundi(margins.y))
	_safe_area.add_theme_constant_override("margin_right", roundi(margins.z))
	_safe_area.add_theme_constant_override("margin_bottom", roundi(margins.w))
