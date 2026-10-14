extends Control
## Temporary on-device diagnostics: display, safe area and raw sensor values.
## Replaced as the main scene in Chunk 3; kept in tests/ for future device checks.

@onready var _info_label: Label = $Margin/InfoLabel


func _process(_delta: float) -> void:
	_info_label.text = _build_report()


func _build_report() -> String:
	var lines := PackedStringArray()
	lines.append("Arcane Roll %s" % ProjectSettings.get_setting("application/config/version"))
	lines.append("Device: %s" % OS.get_model_name())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("FPS: %d   Refresh: %.0f Hz" % [Engine.get_frames_per_second(), DisplayServer.screen_get_refresh_rate()])
	lines.append("")
	lines.append("Screen px: %s" % DisplayServer.screen_get_size())
	lines.append("Viewport:  %s" % get_viewport_rect().size)
	lines.append("Safe area: %s" % DisplayServer.get_display_safe_area())
	lines.append("Cutouts:   %d" % DisplayServer.get_display_cutouts().size())
	lines.append("")
	lines.append("Accel:   %s" % _format_vec(Input.get_accelerometer()))
	lines.append("Gravity: %s" % _format_vec(Input.get_gravity()))
	lines.append("Gyro:    %s" % _format_vec(Input.get_gyroscope()))
	lines.append("Magnet:  %s" % _format_vec(Input.get_magnetometer()))
	return "\n".join(lines)


func _format_vec(v: Vector3) -> String:
	return "(%6.2f, %6.2f, %6.2f)" % [v.x, v.y, v.z]
