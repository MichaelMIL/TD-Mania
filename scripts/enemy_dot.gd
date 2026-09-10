class_name EnemyDot
extends Control

## Tiny creep silhouette used by the wave readout chips.

var tint: Color = Color.WHITE


func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.42
	draw_circle(c, r, tint)
	draw_arc(c, r, 0.0, TAU, 14, tint.darkened(0.45), 1.0, true)
	draw_circle(c + Vector2(r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.85))
