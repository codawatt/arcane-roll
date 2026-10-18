class_name CreditsPanel
extends BottomSheet
## Credits and attribution: developer, third-party assets with their terms, and the
## Godot Engine notices its MIT license requires (engine license text, plus the
## engine's third-party components and their full license texts, shown on request).

## [heading, body] pairs. Keep in sync with THIRD_PARTY_NOTICES.md in the repository.
const CREDITS := [
	["Design & development", "Roșca Dragoș-Florin\ngithub.com/codawatt/arcane-roll"],
	[
		"3D die model",
		'"Dice 3D Model Low Poly" by Etienne Pouvreau\nsmolware.itch.io - free to use for any kind of project'
	],
	[
		"Sound effects",
		"Casino Audio and Interface Sounds by Kenney\nkenney.nl - CC0 1.0 Universal (public domain)"
	],
	["Font", "Dungeon Crawler CB by sadboy\ndafont.com - 100% free"],
	["Engine", "Made with Godot Engine\ngodotengine.org"],
]

var _license_text: RichTextLabel
var _licenses_button: Button

@onready var _scroll: ScrollContainer = %Scroll
@onready var _body: VBoxContainer = %Body


func _ready() -> void:
	super()  # BottomSheet setup: anchoring, tap-outside, hidden start.
	%DoneButton.pressed.connect(close)
	for entry: Array in CREDITS:
		_add_section(entry[0], entry[1])
	# Required by Godot's MIT license: the engine's own license text.
	_add_section("Godot Engine license", Engine.get_license_text())

	_licenses_button = Button.new()
	_licenses_button.pressed.connect(_toggle_licenses)
	_body.add_child(_licenses_button)
	_license_text = _make_text(22)
	_license_text.visible = false
	_body.add_child(_license_text)
	_update_licenses_button()


## Always open at the top, with the long license list collapsed.
func _on_opening() -> void:
	_license_text.visible = false
	_update_licenses_button()
	_scroll.scroll_vertical = 0


func _add_section(heading: String, body: String) -> void:
	var title := _make_text(36)
	title.text = heading
	_body.add_child(title)
	var text := _make_text(28)
	text.text = body
	text.modulate.a = 0.8
	_body.add_child(text)


func _make_text(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let drags reach the ScrollContainer.
	label.add_theme_font_size_override("normal_font_size", font_size)
	return label


func _toggle_licenses() -> void:
	if _license_text.text.is_empty():
		_license_text.text = _third_party_text()  # Built on first use: it is long.
	_license_text.visible = not _license_text.visible
	_update_licenses_button()


func _update_licenses_button() -> void:
	_licenses_button.text = ("Hide" if _license_text.visible else "Show") + " third-party licenses"


## The engine's bundled third-party components, their copyright holders and licenses,
## followed by each license's full text, straight from the running engine.
func _third_party_text() -> String:
	var lines := PackedStringArray(
		["Godot Engine includes the following third-party components:", ""]
	)
	for component: Dictionary in Engine.get_copyright_info():
		lines.append(component["name"])
		for part: Dictionary in component["parts"]:
			for holder: String in part["copyright"]:
				lines.append("  Copyright " + holder)
			lines.append("  License: " + part["license"])
		lines.append("")
	var licenses := Engine.get_license_info()
	for license_name: String in licenses:
		lines.append("--- %s ---" % license_name)
		lines.append(licenses[license_name])
		lines.append("")
	return "\n".join(lines)
