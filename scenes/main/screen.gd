class_name Screen
extends Control
## Base for full-screen UI states hosted by Main.
## Screens never reference each other; they emit signals and Main navigates.


## Called on Android Back (or Esc on desktop).
## Return true if the screen handled it internally (e.g. closed a panel).
func handle_back() -> bool:
	return false


## Called when Android sends the app to the background.
func on_app_paused() -> void:
	pass
