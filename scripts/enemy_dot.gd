class_name EnemyDot
extends Control

## Tiny creep silhouette used by the wave readout chips.

var tint: Color = Color.WHITE
## Flyers get wings on their chip, so an air wave is obvious in the readout.
var winged: bool = false


func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.42
	if winged:
		r *= 0.78
		var wing := Color(tint.lightened(0.3), 0.85)
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([
				c,
				c + Vector2(r * 2.1 * side, -r * 1.1),
				c + Vector2(r * 1.7 * side, r * 0.5),
			]), wing)
	draw_circle(c, r, tint)
	draw_arc(c, r, 0.0, TAU, 14, tint.darkened(0.45), 1.0, true)
	draw_circle(c + Vector2(r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.85))
