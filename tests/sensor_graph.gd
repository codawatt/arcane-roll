class_name SensorGraph
extends Control
## Scrolling debug graph: linear acceleration (orange), gyro speed (cyan),
## shake threshold (white line) and detected shakes (green bars). About 3 s at 120 FPS.

const SAMPLES := 360
const ACCEL_RANGE := 80.0  # m/s² at the top edge.
const GYRO_RANGE := 20.0  # rad/s at the top edge.

var threshold := 14.0

var _accel := PackedFloat32Array()
var _gyro := PackedFloat32Array()
var _shakes := PackedFloat32Array()


func _ready() -> void:
	_accel.resize(SAMPLES)
	_accel.fill(0.0)
	_gyro.resize(SAMPLES)
	_gyro.fill(0.0)
	_shakes.resize(SAMPLES)
	_shakes.fill(0.0)


func push(accel_magnitude: float, gyro_magnitude: float, shake: bool) -> void:
	_accel.remove_at(0)
	_accel.append(accel_magnitude)
	_gyro.remove_at(0)
	_gyro.append(gyro_magnitude)
	_shakes.remove_at(0)
	_shakes.append(1.0 if shake else 0.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
	var step := size.x / (SAMPLES - 1)
	for i in SAMPLES:
		if _shakes[i] > 0.0:
			draw_rect(Rect2(i * step - 4.0, 0.0, 8.0, size.y), Color(0.3, 1.0, 0.3, 0.7))
	var threshold_y := size.y * (1.0 - clampf(threshold / ACCEL_RANGE, 0.0, 1.0))
	draw_line(Vector2(0.0, threshold_y), Vector2(size.x, threshold_y), Color.WHITE, 2.0)
	draw_polyline(_to_points(_gyro, GYRO_RANGE), Color(0.3, 0.9, 1.0), 3.0)
	draw_polyline(_to_points(_accel, ACCEL_RANGE), Color(1.0, 0.6, 0.2), 3.0)


func _to_points(values: PackedFloat32Array, value_range: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(SAMPLES)
	var step := size.x / (SAMPLES - 1)
	for i in SAMPLES:
		points[i] = Vector2(i * step, size.y * (1.0 - clampf(values[i] / value_range, 0.0, 1.0)))
	return points
