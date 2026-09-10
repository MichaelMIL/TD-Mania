class_name Fx
extends Node2D

## Short-lived visual: an expanding ring, a spark puff, or floating text.

enum Mode { RING, SPARK, TEXT }

var mode: int = Mode.RING
var color: Color = Color.WHITE
var text: String = ""
var radius: float = 30.0
var font_size: int = 16
var life: float = 0.5
var age: float = 0.0
var drift: Vector2 = Vector2(0.0, -26.0)


func _process(delta: float) -> void:
	age += delta
	if mode == Mode.TEXT:
		position += drift * delta
	if age >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(age / life, 0.0, 1.0)
	var fade := 1.0 - t
	match mode:
		Mode.RING:
			var r: float = radius * (0.35 + 0.65 * ease(t, 0.4))
			draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.18 * fade))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 28,
					Color(color.r, color.g, color.b, fade), 3.0 * fade + 0.6, true)
		Mode.SPARK:
			for i in 5:
				var ang := TAU * float(i) / 5.0 + radius
				var d: float = 4.0 + 12.0 * t
				draw_line(Vector2.RIGHT.rotated(ang) * d * 0.4,
						Vector2.RIGHT.rotated(ang) * d,
						Color(color.r, color.g, color.b, fade), 2.0, true)
		Mode.TEXT:
			var font := ThemeDB.fallback_font
			var col := Color(color.r, color.g, color.b, fade)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size).x
			var origin := Vector2(-width * 0.5, 0.0)
			draw_string(font, origin + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, font_size, Color(0, 0, 0, fade * 0.7))
			draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
