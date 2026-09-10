class_name WaterLayer
extends Node2D

## Animated water surface, drawn only over water cells. Kept separate from
## TDMap so the static terrain does not have to redraw every frame.

var game: Node = null
var t: float = 0.0
var cells: Array = []


func _ready() -> void:
	for key: Vector2i in game.terrain:
		if game.terrain_at(key) == TDData.Terrain.WATER:
			cells.append(key)


func _process(delta: float) -> void:
	t += delta
	if not cells.is_empty():
		queue_redraw()


## Draws a pale rim on every dry edge that meets water, so islands and lake
## shores read as land rather than holes in the map. Drawn after the water so
## the surf sits on top of it.
## Per-map water treatment: drifting floes, murky bubbles, or breaking surf.
func _draw_water_style(c: Vector2i, r: Rect2, cell: float, swell: float) -> void:
	match str(game.level_def.get("water_style", "calm")):
		"floes":
			var drift := fmod(t * 6.0 + float(c.x) * 17.0 + float(c.y) * 31.0, cell)
			var at := r.position + Vector2(drift, cell * 0.35 + 6.0 * sin(t + float(c.x)))
			var pts := PackedVector2Array([at, at + Vector2(cell * 0.28, -4.0),
					at + Vector2(cell * 0.34, 7.0), at + Vector2(cell * 0.1, 10.0)])
			draw_colored_polygon(pts, Color(0.85, 0.93, 1.0, 0.5))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.35), 1.0, true)
		"murk":
			for i in 3:
				var phase := fmod(t * 0.6 + float(i) * 0.33 + float(c.x + c.y) * 0.11, 1.0)
				var at := r.position + Vector2(cell * (0.2 + 0.3 * float(i)),
						cell * (1.0 - phase))
				draw_circle(at, 1.5 + 1.5 * phase, Color(0.6, 0.8, 0.55, 0.22 * (1.0 - phase)))
			draw_rect(r, Color(0.05, 0.12, 0.08, 0.18))
		"surf":
			# Foam only where the water meets dry land, so shores look alive.
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if game.terrain_at(c + o) == TDData.Terrain.WATER:
					continue
				var mid: Vector2 = r.get_center() + Vector2(o) * cell * 0.42
				var edge := Vector2(o).orthogonal() * cell * 0.5
				var wobble := 0.4 + 0.6 * absf(sin(t * 2.0 + float(c.x + c.y)))
				draw_line(mid - edge, mid + edge, Color(1, 1, 1, 0.12 + 0.18 * wobble), 5.0)


func _draw_shorelines(cell: float) -> void:
	var neighbours: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in cells:
		var center: Vector2 = game.cell_center(c)
		for o: Vector2i in neighbours:
			var side := c + o
			if game.terrain_at(side) == TDData.Terrain.WATER:
				continue
			if not game.in_bounds(side):
				continue
			var mid := center + Vector2(o) * (cell * 0.5 - 2.0)
			var edge := Vector2(o).orthogonal() * cell * 0.5
			var surf := 0.5 + 0.5 * sin(t * 2.2 + center.x * 0.05 + center.y * 0.05)
			draw_line(mid - edge, mid + edge, Color(0.88, 0.95, 1.0, 0.16 + 0.14 * surf), 4.0)
			draw_line(mid - edge, mid + edge, Color(0.88, 0.95, 1.0, 0.35), 1.5)


func _draw() -> void:
	var cell := float(TDData.CELL)
	var pal: Dictionary = game.level_def["palette"]
	var deep: Color = pal["water_a"]
	var shallow: Color = pal["water_b"]

	for c: Vector2i in cells:
		var center: Vector2 = game.cell_center(c)
		var r := Rect2(center - Vector2(cell, cell) * 0.5, Vector2(cell, cell))
		if Art.draw_centered(self, "tile_water_%s" % game.level_def["id"], center, cell) \
				or Art.draw_centered(self, "tile_water", center, cell):
			continue
		# Phase comes from world position, not tile index, so the swell flows
		# continuously across neighbouring cells instead of banding per tile.
		draw_rect(r, deep)
		var swell := 0.5 + 0.5 * sin(t * 1.2 + center.x * 0.012 + center.y * 0.03)
		draw_rect(r, deep.lerp(shallow, 0.25 + 0.4 * swell))
		for i in 3:
			var base_y := r.position.y + cell * (0.2 + 0.3 * float(i))
			var pts := PackedVector2Array()
			for step in 9:
				var px := r.position.x + cell * float(step) / 8.0
				pts.append(Vector2(px, base_y
						+ sin(t * 1.6 + px * 0.05 + base_y * 0.09) * 2.6))
			draw_polyline(pts, Color(1, 1, 1, 0.07 + 0.05 * swell), 2.0, true)
		_draw_water_style(c, r, cell, swell)
	_draw_shorelines(cell)
