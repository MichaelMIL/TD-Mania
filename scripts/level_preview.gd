class_name LevelPreview
extends Control

## Miniature of one level: terrain patches plus the creep path, scaled to fit
## the control. Rendered from TDData so it always matches the real map.

var level_index: int = 0


func _draw() -> void:
	var d: Dictionary = TDData.LEVELS[level_index]
	var pal: Dictionary = d["palette"]
	var s: float = minf(size.x / float(TDData.COLS), size.y / float(TDData.ROWS))
	var origin := Vector2((size.x - s * float(TDData.COLS)) * 0.5,
			(size.y - s * float(TDData.ROWS)) * 0.5)

	draw_rect(Rect2(origin, Vector2(s * float(TDData.COLS), s * float(TDData.ROWS))),
			pal["ground_a"])
	for r: Array in d["water"]:
		draw_rect(Rect2(origin + Vector2(float(r[0]), float(r[1])) * s,
				Vector2(float(r[2]), float(r[3])) * s), pal["water_b"])
	for r: Array in d["ground"]:
		draw_rect(Rect2(origin + Vector2(float(r[0]), float(r[1])) * s,
				Vector2(float(r[2]), float(r[3])) * s), pal["ground_b"])
	for r: Array in d["rock"]:
		draw_rect(Rect2(origin + Vector2(float(r[0]), float(r[1])) * s,
				Vector2(float(r[2]), float(r[3])) * s), pal["rock"])

	for route: Array in TDData.routes_of(d):
		var pts := PackedVector2Array()
		for wp: Vector2i in route:
			pts.append(origin + (Vector2(wp) + Vector2(0.5, 0.5)) * s)
		draw_polyline(pts, pal["path_edge"], s * 0.85, true)
		draw_polyline(pts, pal["path_fill"], s * 0.62, true)
		draw_circle(pts[0], s * 0.42, Color("9575cd"))
		draw_circle(pts[pts.size() - 1], s * 0.42, Color("ef5350"))
	draw_rect(Rect2(origin, Vector2(s * float(TDData.COLS), s * float(TDData.ROWS))),
			Color(1, 1, 1, 0.12), false, 1.0)
