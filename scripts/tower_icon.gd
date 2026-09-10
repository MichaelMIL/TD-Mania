class_name TowerIcon
extends Control

## Small procedural portrait of a tower, used by the build palette. Drawn from
## the same colour and category flags as the real tower so the two cannot
## drift apart.

var type_id: String = "gun"


func _draw() -> void:
	var d: Dictionary = TDData.TOWERS[type_id]
	var col: Color = d["color"]
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.42

	if int(d["terrain"]) == TDData.Terrain.WATER:
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color("22333d"))
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col.darkened(0.3), false, 2.0)
	elif bool(d.get("air", false)):
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color("2b3446"))
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col.darkened(0.4), false, 2.0)
	else:
		draw_circle(c, r, Color("2b3446"))
		draw_arc(c, r, 0.0, TAU, 24, col.darkened(0.3), 2.0, true)

	match type_id:
		"airfield":
			draw_rect(Rect2(c - Vector2(r * 0.8, 3.0), Vector2(r * 1.6, 6.0)), Color("1c2431"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -r * 0.55),
					c + Vector2(-5.0, r * 0.3), c + Vector2(5.0, r * 0.3)]), col)
		"helipad":
			draw_arc(c, r * 0.6, 0.0, TAU, 20, Color(1, 1, 1, 0.4), 2.0, true)
			draw_line(c + Vector2(-4.0, -5.0), c + Vector2(-4.0, 5.0), Color(1, 1, 1, 0.55), 2.0)
			draw_line(c + Vector2(4.0, -5.0), c + Vector2(4.0, 5.0), Color(1, 1, 1, 0.55), 2.0)
			draw_line(c + Vector2(-4.0, 0.0), c + Vector2(4.0, 0.0), Color(1, 1, 1, 0.55), 2.0)
		"command":
			draw_arc(c, r * 0.75, 0.0, TAU, 22, Color(col.r, col.g, col.b, 0.4), 1.5, true)
			draw_circle(c, r * 0.32, Color("38414f"))
			draw_line(c, c + Vector2(r * 0.7, -r * 0.5), col, 2.0, true)
		"tesla":
			draw_line(c + Vector2(0.0, r * 0.5), c + Vector2(0.0, -r * 0.2), col, 3.0)
			draw_arc(c + Vector2(0.0, -r * 0.35), r * 0.35, PI, TAU, 12, col.lightened(0.3),
					3.0, true)
		"flame":
			draw_rect(Rect2(c - Vector2(3.0, r * 0.1), Vector2(6.0, r * 0.7)), col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6.0, -r * 0.1),
					c + Vector2(0.0, -r * 0.8), c + Vector2(6.0, -r * 0.1)]), col)
		"mortar":
			draw_rect(Rect2(c - Vector2(6.0, r * 0.1), Vector2(12.0, r * 0.8)), col.darkened(0.3))
			draw_circle(c + Vector2(0.0, -r * 0.35), r * 0.3, col)
		"marksman":
			draw_rect(Rect2(c - Vector2(2.5, r * 0.9), Vector2(5.0, r * 1.5)), col.darkened(0.2))
			draw_circle(c + Vector2(0.0, -r * 0.1), r * 0.22, col.darkened(0.35))
		"torpedo":
			draw_rect(Rect2(c - Vector2(r * 0.6, 6.0), Vector2(r * 1.2, 4.0)), col.darkened(0.2))
			draw_rect(Rect2(c - Vector2(r * 0.6, 1.0), Vector2(r * 1.2, 4.0)), col.darkened(0.2))
		"tarpit":
			draw_circle(c, r * 0.66, col.darkened(0.4))
			for i in 3:
				draw_circle(c + Vector2.RIGHT.rotated(float(i) * 2.1) * r * 0.3, 2.4, col)
		"mine":
			draw_line(c + Vector2(-r * 0.6, r * 0.55), c + Vector2(0.0, -r * 0.7),
					col.darkened(0.3), 2.5)
			draw_line(c + Vector2(r * 0.6, r * 0.55), c + Vector2(0.0, -r * 0.7),
					col.darkened(0.3), 2.5)
			draw_circle(c + Vector2(0.0, r * 0.4), r * 0.22, col)
		"shock":
			draw_arc(c, r * 0.75, 0.0, TAU, 22, Color(col.r, col.g, col.b, 0.45), 2.0, true)
			draw_arc(c, r * 0.5, 0.0, TAU, 18, col, 2.0, true)
			draw_circle(c, r * 0.22, col.lightened(0.25))
		"ballista":
			for i in 2:
				var y := c.y + (float(i) - 0.5) * r * 0.6
				draw_rect(Rect2(c.x - r * 0.7, y - 1.6, r * 1.4, 3.2), col.darkened(0.2))
			draw_arc(c - Vector2(r * 0.4, 0.0), r * 0.55, -1.3, 1.3, 10, col.darkened(0.4),
					2.5, true)
		"laser":
			draw_rect(Rect2(c - Vector2(3.0, r * 0.75), Vector2(6.0, r * 1.1)),
					col.darkened(0.25))
			draw_circle(c + Vector2(0.0, -r * 0.75), r * 0.28, col.lightened(0.35))
			draw_circle(c + Vector2(0.0, -r * 0.75), r * 0.13, Color(1, 1, 1, 0.85))
		"wavegun":
			draw_rect(Rect2(c - Vector2(4.0, r * 0.2), Vector2(8.0, r * 0.8)),
					col.darkened(0.25))
			for i in 3:
				draw_arc(c + Vector2(0.0, -r * 0.2), r * (0.35 + 0.22 * float(i)),
						PI * 1.15, PI * 1.85, 10,
						Color(col.r, col.g, col.b, 0.6 - 0.15 * float(i)), 2.0, true)
		_:
			# Generic turret: a barrel pointing up out of a hub.
			var w := 4.5 if type_id == "gun" else 6.5
			draw_rect(Rect2(c - Vector2(w, r * 0.85), Vector2(w * 2.0, r * 1.1)),
					col.darkened(0.2))
			draw_circle(c, r * 0.34, col)
			draw_circle(c, r * 0.2, col.lightened(0.3))
