class_name TDMap
extends Node2D

## Static playfield: terrain tiles, the dirt path, and the spawn / base
## markers. Water is drawn by WaterLayer on top of this so it can animate.

var game: Node = null


func _palette() -> Dictionary:
	return game.level_def["palette"]


func _tile(kind: String, center: Vector2, size: float) -> bool:
	# Try a level-specific sprite first, then the generic one.
	if Art.draw_centered(self, "tile_%s_%s" % [kind, game.level_def["id"]], center, size):
		return true
	return Art.draw_centered(self, "tile_" + kind, center, size)


## Ground pattern. Each map picks one, which changes the whole feel of the
## board before a single prop is drawn.
func _draw_ground(r: Rect2, c: Vector2i, pal: Dictionary) -> void:
	var a: Color = pal["ground_a"]
	var b: Color = pal["ground_b"]
	match str(game.level_def.get("ground_style", "checker")):
		"stripes":
			draw_rect(r, a if c.y % 2 == 0 else b)
			draw_line(Vector2(r.position.x, r.position.y + r.size.y * 0.5),
					Vector2(r.end.x, r.position.y + r.size.y * 0.5),
					Color(1, 1, 1, 0.025), 2.0)
		"dots":
			draw_rect(r, b)
			for i in 4:
				var at := r.position + Vector2(r.size.x * (0.25 + 0.5 * float(i % 2)),
						r.size.y * (0.25 + 0.5 * floorf(float(i) / 2.0)))
				draw_circle(at, 2.0, a.lightened(0.08))
		"tiles":
			draw_rect(r, a if (c.x + c.y) % 2 == 0 else b)
			draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.035), false, 1.0)
		"flat":
			draw_rect(r, a)
			var blot := _hash01(c, 5)
			if blot < 0.5:
				draw_circle(r.get_center() + Vector2(_hash01(c, 6) - 0.5,
						_hash01(c, 7) - 0.5) * r.size.x * 0.6,
						r.size.x * (0.18 + 0.16 * blot), b)
		"dunes":
			draw_rect(r, a)
			for i in 2:
				var pts := PackedVector2Array()
				for step in 7:
					var px := r.position.x + r.size.x * float(step) / 6.0
					pts.append(Vector2(px, r.position.y + r.size.y * (0.3 + 0.4 * float(i))
							+ sin(px * 0.06 + float(c.y)) * 4.0))
				draw_polyline(pts, b.lightened(0.06), 3.0, true)
		_:
			draw_rect(r, a if (c.x + c.y) % 2 == 0 else b)


## Deterministic pseudo-random value for a cell, so scattered props land in
## the same place every redraw without storing anything.
func _hash01(c: Vector2i, salt: int = 0) -> float:
	var v := sin(float(c.x) * 12.9898 + float(c.y) * 78.233 + float(salt) * 3.7) * 43758.5453
	return v - floorf(v)


## True when this path cell runs left-right, so surface detail can follow the
## direction of travel.
func _path_horizontal(c: Vector2i) -> bool:
	return game.is_path(c + Vector2i(1, 0)) or game.is_path(c + Vector2i(-1, 0))


## Surface treatment of the road: cobbles, planks, rails, cracked ice and so
## on. Drawn per path cell over the ribbon.
func _draw_path_surface(cell: float, pal: Dictionary) -> void:
	var style := str(game.level_def.get("path_style", "dirt"))
	var fill: Color = pal["path_fill"]
	var edge: Color = pal["path_edge"]
	for key: Vector2i in game.terrain:
		if game.terrain_at(key) != TDData.Terrain.PATH:
			continue
		var at: Vector2 = game.cell_center(key)
		var horizontal := _path_horizontal(key)
		match style:
			"gravel":
				for i in 7:
					draw_circle(at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 20) - 0.5)
							* cell * 0.7, 1.6, edge.lightened(0.25))
			"mud":
				for i in 3:
					var pos := at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 9) - 0.5) \
							* cell * 0.6
					draw_circle(pos, cell * 0.11, fill.darkened(0.18))
			"stone", "slabs":
				var step: float = cell * 0.5
				for ix in 2:
					for iy in 2:
						var block := Rect2(at + Vector2(float(ix) - 1.0, float(iy) - 1.0) * step
								+ Vector2(1.5, 1.5), Vector2(step - 3.0, step - 3.0))
						draw_rect(block, fill.lightened(0.05 + 0.05 * _hash01(key, ix * 3 + iy)))
						draw_rect(block, edge, false, 1.0)
			"brick":
				var rows := 3
				for iy in rows:
					var y := at.y - cell * 0.5 + cell * (float(iy) + 0.5) / float(rows)
					var offset: float = cell * 0.25 * float(iy % 2)
					draw_line(Vector2(at.x - cell * 0.45, y), Vector2(at.x + cell * 0.45, y),
							edge, 1.0)
					draw_line(Vector2(at.x - cell * 0.2 + offset, y - cell * 0.14),
							Vector2(at.x - cell * 0.2 + offset, y + cell * 0.14), edge, 1.0)
			"boardwalk", "planks":
				var count := 4
				for i in count:
					var t := (float(i) + 0.5) / float(count) - 0.5
					if horizontal:
						draw_line(at + Vector2(t * cell, -cell * 0.3),
								at + Vector2(t * cell, cell * 0.3), edge, 1.5)
					else:
						draw_line(at + Vector2(-cell * 0.3, t * cell),
								at + Vector2(cell * 0.3, t * cell), edge, 1.5)
				if style == "planks":
					draw_rect(Rect2(at - Vector2(cell, cell) * 0.32,
							Vector2(cell, cell) * 0.64), Color(1, 1, 1, 0.04))
			"rail":
				var along := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				var across := along.orthogonal()
				for side: float in [-0.16, 0.16]:
					draw_line(at + along * -cell * 0.5 + across * cell * side,
							at + along * cell * 0.5 + across * cell * side,
							Color(0.72, 0.74, 0.8, 0.55), 2.0)
				for i in 3:
					var t := (float(i) - 1.0) * cell * 0.3
					draw_line(at + along * t - across * cell * 0.24,
							at + along * t + across * cell * 0.24, edge, 3.0)
			"towpath":
				# A beaten rut down the middle with grass creeping in.
				var rut := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				draw_line(at - rut * cell * 0.45, at + rut * cell * 0.45,
						edge.lightened(0.12), cell * 0.16)
				for i in 4:
					draw_circle(at + Vector2(_hash01(key, i) - 0.5,
							_hash01(key, i + 11) - 0.5) * cell * 0.8, 1.4,
							Color(0.45, 0.55, 0.3, 0.35))
			"chalk":
				# Pale dust, wheel-worn at the edges.
				draw_rect(Rect2(at - Vector2(cell, cell) * 0.34,
						Vector2(cell, cell) * 0.68), Color(1, 1, 1, 0.05))
				for side: float in [-0.26, 0.26]:
					if horizontal:
						draw_line(at + Vector2(-cell * 0.5, cell * side),
								at + Vector2(cell * 0.5, cell * side),
								edge.lightened(0.2), 2.0)
					else:
						draw_line(at + Vector2(cell * side, -cell * 0.5),
								at + Vector2(cell * side, cell * 0.5),
								edge.lightened(0.2), 2.0)
			"causeway":
				# Big stones with the waterline stained across them.
				var block := Rect2(at - Vector2(cell, cell) * 0.42,
						Vector2(cell, cell) * 0.84)
				draw_rect(block, fill.lightened(0.04))
				draw_rect(block, edge, false, 1.5)
				draw_line(at + Vector2(-cell * 0.42, cell * 0.2),
						at + Vector2(cell * 0.42, cell * 0.2),
						Color(0.2, 0.4, 0.45, 0.35), 3.0)
			"reedmat":
				# Woven matting: two directions of weave.
				for i in 4:
					var t := (float(i) + 0.5) / 4.0 - 0.5
					draw_line(at + Vector2(t * cell, -cell * 0.42),
							at + Vector2(t * cell, cell * 0.42),
							edge.lightened(0.15), 1.5)
					draw_line(at + Vector2(-cell * 0.42, t * cell),
							at + Vector2(cell * 0.42, t * cell),
							fill.darkened(0.12), 1.5)
			"haulroad":
				# Two tyre tracks, and spoil kicked out to the sides.
				var along := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				var across := along.orthogonal()
				for side: float in [-0.2, 0.2]:
					draw_line(at + along * -cell * 0.5 + across * cell * side,
							at + along * cell * 0.5 + across * cell * side,
							edge.darkened(0.1), cell * 0.14)
				for i in 5:
					draw_circle(at + Vector2(_hash01(key, i) - 0.5,
							_hash01(key, i + 17) - 0.5) * cell * 0.9, 1.3,
							fill.lightened(0.2))
			"saltcrust":
				# Dried polygons, the way a salt pan cracks.
				for iy in 2:
					for ix in 2:
						var cellet := at + Vector2(float(ix) - 0.5, float(iy) - 0.5) \
								* cell * 0.42
						draw_arc(cellet, cell * 0.19, 0.0, TAU, 6,
								Color(1, 1, 1, 0.12), 1.0, true)
				draw_circle(at, cell * 0.05, Color(1, 1, 1, 0.10))
			"snowpack":
				# Packed snow with a sled groove down it.
				draw_rect(Rect2(at - Vector2(cell, cell) * 0.36,
						Vector2(cell, cell) * 0.72), Color(1, 1, 1, 0.07))
				var groove := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				draw_line(at - groove * cell * 0.45, at + groove * cell * 0.45,
						Color(0.75, 0.85, 0.95, 0.35), 2.0, true)
			"glaze":
				# Wind-polished blue ice, striated along the slope.
				draw_rect(Rect2(at - Vector2(cell, cell) * 0.4,
						Vector2(cell, cell) * 0.8), Color(0.6, 0.8, 1.0, 0.10))
				for i in 3:
					var y := at.y - cell * 0.3 + cell * 0.3 * float(i)
					draw_line(Vector2(at.x - cell * 0.42, y + _hash01(key, i) * 3.0),
							Vector2(at.x + cell * 0.42, y - _hash01(key, i + 5) * 3.0),
							Color(0.85, 0.95, 1.0, 0.25), 1.0, true)
			"cinder":
				# Crushed clinker, still warm in places.
				for i in 9:
					var grain := at + Vector2(_hash01(key, i) - 0.5,
							_hash01(key, i + 23) - 0.5) * cell * 0.82
					draw_circle(grain, 1.5, edge.darkened(0.2))
				for i in 2:
					draw_circle(at + Vector2(_hash01(key, i + 3) - 0.5,
							_hash01(key, i + 9) - 0.5) * cell * 0.6, 1.8,
							Color(1.0, 0.45, 0.2, 0.35))
			"pontoon":
				# Floating sections, bolted at the joins.
				var span := Vector2(cell * 0.86, cell * 0.5) if horizontal \
						else Vector2(cell * 0.5, cell * 0.86)
				var deck := Rect2(at - span * 0.5, span)
				draw_rect(deck, fill.lightened(0.05))
				draw_rect(deck, edge, false, 1.5)
				for corner: Vector2 in [deck.position, deck.end,
						deck.position + Vector2(span.x, 0.0),
						deck.position + Vector2(0.0, span.y)]:
					draw_circle(corner, 1.4, Color(0.75, 0.78, 0.82, 0.5))
			"ice":
				draw_rect(Rect2(at - Vector2(cell, cell) * 0.32, Vector2(cell, cell) * 0.64),
						Color(0.85, 0.93, 1.0, 0.10))
				var a := at + Vector2(-cell * 0.3, -cell * 0.1 + _hash01(key, 2) * 8.0)
				var b := at + Vector2(cell * 0.3, cell * 0.15 - _hash01(key, 3) * 8.0)
				draw_line(a, b, Color(0.9, 0.97, 1.0, 0.35), 1.5, true)
			"ember":
				for i in 2:
					var start := at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 4) - 0.5) \
							* cell * 0.7
					var end := start + Vector2(_hash01(key, i + 8) - 0.5,
							_hash01(key, i + 12) - 0.5) * cell * 0.5
					draw_line(start, end, Color(1.0, 0.45, 0.15, 0.5), 2.0, true)
					draw_circle(end, 1.6, Color(1.0, 0.7, 0.3, 0.6))
			"cobble":
				for i in 6:
					var spot := at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 30) - 0.5) \
							* cell * 0.66
					draw_circle(spot, cell * 0.09, fill.lightened(0.10 + 0.1 * _hash01(key, i)))
					draw_arc(spot, cell * 0.09, 0.0, TAU, 8, edge, 1.0, true)
			"grit":
				for i in 10:
					draw_circle(at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 40) - 0.5)
							* cell * 0.8, 1.1, edge.lightened(0.3))
				draw_line(at + Vector2(-cell * 0.4, cell * 0.18),
						at + Vector2(cell * 0.4, cell * 0.18), Color(1, 1, 1, 0.06), 2.0)
			"basalt":
				for iy in 2:
					for ix in 2:
						var hex := at + Vector2(float(ix) - 0.5, float(iy) - 0.5) * cell * 0.44
						var pts := PackedVector2Array()
						for k in 6:
							pts.append(hex + Vector2.RIGHT.rotated(TAU * float(k) / 6.0)
									* cell * 0.2)
						draw_colored_polygon(pts, fill.darkened(0.06 * float(ix + iy)))
						draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.0, true)
			"flagstone":
				for iy in 2:
					for ix in 2:
						var slab := Rect2(at + Vector2(float(ix) - 1.0, float(iy) - 1.0)
								* cell * 0.5 + Vector2(2.0, 2.0),
								Vector2(cell * 0.5 - 4.0, cell * 0.5 - 4.0))
						draw_rect(slab, fill.lightened(0.04 + 0.06 * _hash01(key, ix + iy * 2)))
						draw_rect(slab, edge, false, 1.0)
				draw_circle(at, 1.6, edge)
			"duckboard":
				var along := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				var across := along.orthogonal()
				for i in 5:
					var t := (float(i) + 0.5) / 5.0 - 0.5
					draw_line(at + along * t * cell + across * cell * -0.28,
							at + along * t * cell + across * cell * 0.28, edge, 1.5)
				for side: float in [-0.3, 0.3]:
					draw_line(at + along * -cell * 0.5 + across * cell * side,
							at + along * cell * 0.5 + across * cell * side,
							fill.darkened(0.2), 2.0)
			"clinker":
				for i in 8:
					var chip := at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 50) - 0.5) \
							* cell * 0.72
					draw_circle(chip, 1.4 + 1.4 * _hash01(key, i + 60),
							edge.lightened(0.18 + 0.2 * _hash01(key, i)))
			"crystal":
				draw_rect(Rect2(at - Vector2(cell, cell) * 0.3, Vector2(cell, cell) * 0.6),
						Color(0.8, 0.9, 1.0, 0.10))
				for i in 2:
					var a := at + Vector2(-cell * 0.32, -cell * 0.15 + float(i) * cell * 0.3)
					draw_line(a, a + Vector2(cell * 0.64, cell * 0.08),
							Color(0.9, 0.97, 1.0, 0.3), 1.5, true)
			"conduit":
				var run := Vector2(1.0, 0.0) if horizontal else Vector2(0.0, 1.0)
				var side_dir := run.orthogonal()
				for offset: float in [-0.18, 0.18]:
					draw_line(at + run * -cell * 0.5 + side_dir * cell * offset,
							at + run * cell * 0.5 + side_dir * cell * offset,
							fill.lightened(0.12), 4.0)
				draw_line(at - side_dir * cell * 0.26, at + side_dir * cell * 0.26,
						edge.lightened(0.25), 2.5)
			"sand":
				for i in 2:
					var pts := PackedVector2Array()
					for step in 6:
						var px := at.x - cell * 0.45 + cell * 0.9 * float(step) / 5.0
						pts.append(Vector2(px, at.y + (float(i) - 0.5) * cell * 0.3
								+ sin(px * 0.09 + float(key.y)) * 2.5))
					draw_polyline(pts, fill.lightened(0.12), 1.5, true)
			_:
				for i in 4:
					draw_circle(at + Vector2(_hash01(key, i) - 0.5, _hash01(key, i + 16) - 0.5)
							* cell * 0.75, 1.4, edge.lightened(0.15))


## A wash of colour over the whole board: dusk gold, volcanic red, arctic blue.
func _draw_tint() -> void:
	var tint: Color = game.level_def.get("tint", Color(0, 0, 0, 0))
	if tint.a <= 0.0:
		return
	draw_rect(Rect2(0.0, float(TDData.HUD_H), float(TDData.MAP_W), float(TDData.MAP_H)), tint)


## Theme props on dry ground: trees, grass tufts, cracks, snow and so on.
## Each level names its own motif, which is most of what makes the maps look
## like different places.
func _draw_decor(cell: float) -> void:
	var kind := str(game.level_def.get("decor", ""))
	if kind == "":
		return
	var pal := _palette()
	for key: Vector2i in game.terrain:
		if game.terrain_at(key) != TDData.Terrain.GROUND:
			continue
		var roll := _hash01(key)
		if roll > 0.45:
			continue
		var center: Vector2 = game.cell_center(key) + Vector2(
				_hash01(key, 1) - 0.5, _hash01(key, 2) - 0.5) * cell * 0.52
		_draw_prop(kind, center, cell, roll, pal)


func _draw_prop(kind: String, at: Vector2, cell: float, roll: float, pal: Dictionary) -> void:
	var scale: float = cell * (0.1 + 0.06 * roll)
	match kind:
		"trees":
			draw_circle(at + Vector2(1.0, 2.0), scale * 1.15, Color(0, 0, 0, 0.22))
			draw_circle(at, scale * 1.1, Color(0.09, 0.19, 0.10, 0.95))
			draw_circle(at + Vector2(-scale * 0.3, -scale * 0.3), scale * 0.55,
					Color(0.14, 0.27, 0.13, 0.9))
		"grass":
			for i in 3:
				var lean := (float(i) - 1.0) * 0.45
				draw_line(at + Vector2(float(i) * 2.5 - 2.5, scale),
						at + Vector2(float(i) * 2.5 - 2.5 + lean * scale, -scale),
						Color(0.72, 0.63, 0.32, 0.5), 1.5, true)
		"reeds":
			for i in 3:
				var x := at.x + float(i) * 3.0 - 3.0
				draw_line(Vector2(x, at.y + scale), Vector2(x + 1.5, at.y - scale * 1.4),
						Color(0.35, 0.62, 0.5, 0.55), 1.5, true)
				draw_circle(Vector2(x + 1.5, at.y - scale * 1.4), 1.3,
						Color(0.55, 0.72, 0.45, 0.6))
		"leaves":
			var autumn: Array = [Color(0.72, 0.35, 0.16, 0.6), Color(0.6, 0.24, 0.14, 0.55),
					Color(0.78, 0.52, 0.2, 0.5), Color(0.5, 0.3, 0.15, 0.5)]
			for i in 4:
				var tint: Color = autumn[i]
				draw_circle(at + Vector2(_hash01(Vector2i(int(at.x), int(at.y)), i + 3) - 0.5,
						_hash01(Vector2i(int(at.y), int(at.x)), i + 9) - 0.5) * cell * 0.4,
						1.8, tint)
		"cracks":
			var a := at + Vector2(-scale, -scale * 0.4)
			var b := at + Vector2(0.0, scale * 0.3)
			var c := at + Vector2(scale, -scale * 0.2)
			draw_polyline(PackedVector2Array([a, b, c]), Color(0.08, 0.06, 0.05, 0.8), 2.0, true)
			draw_polyline(PackedVector2Array([a, b, c]), Color(0.85, 0.32, 0.12, 0.35), 1.0, true)
		"snow":
			draw_circle(at, scale * 0.9, Color(0.92, 0.96, 1.0, 0.14))
			for i in 3:
				draw_circle(at + Vector2(float(i) * 3.5 - 3.5, float(i % 2) * 3.0 - 1.5),
						1.4, Color(0.95, 0.98, 1.0, 0.5))
		"vines":
			var pts := PackedVector2Array()
			for i in 5:
				var t := float(i) / 4.0
				pts.append(at + Vector2(lerpf(-scale, scale, t), sin(t * PI * 1.5) * scale * 0.6))
			draw_polyline(pts, Color(0.22, 0.42, 0.28, 0.6), 1.5, true)
			draw_circle(pts[1], 1.8, Color(0.3, 0.55, 0.3, 0.6))
			draw_circle(pts[3], 1.8, Color(0.26, 0.48, 0.28, 0.6))
		"heather":
			for i in 3:
				var base_pt := at + Vector2(float(i) * 3.0 - 3.0, scale * 0.6)
				draw_line(base_pt, base_pt + Vector2(0.0, -scale * 1.2),
						Color(0.35, 0.45, 0.3, 0.55), 1.5, true)
				draw_circle(base_pt + Vector2(0.0, -scale * 1.3), 2.0,
						Color(0.62, 0.42, 0.72, 0.6))
		"cactus":
			draw_line(at + Vector2(0.0, scale), at + Vector2(0.0, -scale),
					Color(0.32, 0.55, 0.3, 0.75), 3.0, true)
			draw_line(at + Vector2(0.0, -scale * 0.1), at + Vector2(-scale * 0.7, -scale * 0.5),
					Color(0.32, 0.55, 0.3, 0.7), 2.0, true)
			draw_line(at + Vector2(0.0, scale * 0.3), at + Vector2(scale * 0.6, -scale * 0.1),
					Color(0.32, 0.55, 0.3, 0.7), 2.0, true)
		"columns":
			var col_rect := Rect2(at - Vector2(scale * 0.35, scale), Vector2(scale * 0.7, scale * 2.0))
			draw_rect(col_rect, Color(0.62, 0.60, 0.66, 0.55))
			draw_rect(Rect2(col_rect.position - Vector2(2.0, 2.0),
					Vector2(col_rect.size.x + 4.0, 3.0)), Color(0.7, 0.68, 0.74, 0.6))
			draw_line(at + Vector2(0.0, -scale), at + Vector2(0.0, scale),
					Color(0.4, 0.38, 0.44, 0.5), 1.0)
		"driftwood":
			draw_line(at + Vector2(-scale, scale * 0.4), at + Vector2(scale, -scale * 0.3),
					Color(0.55, 0.5, 0.45, 0.6), 2.5, true)
			draw_line(at + Vector2(-scale * 0.5, -scale * 0.4), at + Vector2(scale * 0.6, scale * 0.5),
					Color(0.48, 0.44, 0.4, 0.5), 2.0, true)
		"banners":
			draw_line(at + Vector2(0.0, scale), at + Vector2(0.0, -scale * 1.4),
					Color(0.55, 0.57, 0.62, 0.6), 1.5, true)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -scale * 1.4),
					at + Vector2(scale * 0.9, -scale * 1.1), at + Vector2(0.0, -scale * 0.7)]),
					Color(0.45, 0.55, 0.75, 0.6))
		"sleepers":
			draw_rect(Rect2(at - Vector2(scale, scale * 0.35), Vector2(scale * 2.0, scale * 0.7)),
					Color(0.42, 0.38, 0.35, 0.55))
			draw_line(at + Vector2(-scale, 0.0), at + Vector2(scale, 0.0),
					Color(0.6, 0.62, 0.66, 0.35), 1.0)
		"spires":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -scale * 1.6),
					at + Vector2(scale * 0.6, scale * 0.6), at + Vector2(-scale * 0.6, scale * 0.6)]),
					Color(0.35, 0.28, 0.38, 0.7))
			draw_line(at + Vector2(0.0, -scale * 1.6), at + Vector2(0.0, scale * 0.6),
					Color(0.55, 0.42, 0.6, 0.4), 1.0)
		"ferns":
			for i in 3:
				var stem := at + Vector2(float(i) * 3.5 - 3.5, scale * 0.7)
				draw_line(stem, stem + Vector2(float(i) - 1.0, -scale * 1.5),
						Color(0.25, 0.5, 0.3, 0.6), 1.5, true)
				for k in 3:
					var leaf := stem + Vector2(float(i) - 1.0, -scale * 1.5) * (0.4 + 0.3 * float(k))
					draw_circle(leaf, 1.6, Color(0.3, 0.58, 0.34, 0.55))
		"buoys":
			draw_circle(at, scale * 0.5, Color(0.8, 0.4, 0.3, 0.55))
			draw_line(at, at + Vector2(0.0, -scale), Color(0.75, 0.78, 0.8, 0.5), 1.5)
			draw_circle(at + Vector2(0.0, -scale), 1.6, Color(0.9, 0.85, 0.5, 0.6))
		"obelisks":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-scale * 0.35, scale),
					at + Vector2(-scale * 0.22, -scale * 1.5),
					at + Vector2(scale * 0.22, -scale * 1.5),
					at + Vector2(scale * 0.35, scale)]), Color(0.42, 0.38, 0.5, 0.65))
			draw_line(at + Vector2(0.0, -scale * 1.4), at + Vector2(0.0, scale * 0.8),
					Color(0.6, 0.55, 0.7, 0.35), 1.0)
		"crystals":
			for i in 2:
				var base_pt := at + Vector2(float(i) * 5.0 - 2.5, scale * 0.6)
				draw_colored_polygon(PackedVector2Array([base_pt,
						base_pt + Vector2(-2.5, -scale * (0.9 + 0.4 * float(i))),
						base_pt + Vector2(2.5, -scale * (0.7 + 0.4 * float(i)))]),
						Color(0.7, 0.88, 1.0, 0.5))
		"pipes":
			draw_rect(Rect2(at - Vector2(scale, 2.0), Vector2(scale * 2.0, 4.0)),
					Color(0.45, 0.4, 0.35, 0.6))
			draw_circle(at + Vector2(-scale, 0.0), 2.6, Color(0.55, 0.5, 0.45, 0.6))
			draw_circle(at + Vector2(scale, 0.0), 2.6, Color(0.55, 0.5, 0.45, 0.6))
		"bolts":
			var r := Rect2(at - Vector2(scale, scale) * 0.8, Vector2(scale, scale) * 1.6)
			draw_rect(r, Color(0.16, 0.17, 0.2, 0.55))
			draw_rect(r, Color(0.55, 0.35, 0.2, 0.35), false, 1.0)
			for corner: Vector2 in [r.position, r.position + Vector2(r.size.x, 0.0),
					r.position + Vector2(0.0, r.size.y), r.end]:
				draw_circle(corner, 1.1, Color(0.7, 0.72, 0.78, 0.5))
		"blossom":
			for i in 5:
				var petal := at + Vector2.RIGHT.rotated(TAU * float(i) / 5.0 + roll) \
						* scale * 0.8
				draw_circle(petal, scale * 0.42, Color(0.95, 0.7, 0.8, 0.55))
			draw_circle(at, scale * 0.32, Color(1.0, 0.9, 0.6, 0.6))
		"hedges":
			var box := Rect2(at - Vector2(scale * 1.3, scale * 0.7),
					Vector2(scale * 2.6, scale * 1.4))
			draw_rect(box, Color(0.18, 0.32, 0.16, 0.6))
			draw_rect(box, Color(0.28, 0.45, 0.22, 0.5), false, 1.0)
		"lilies":
			draw_circle(at, scale * 0.9, Color(0.22, 0.42, 0.28, 0.55))
			draw_arc(at, scale * 0.9, 0.6 + roll, 5.4 + roll, 10,
					Color(0.35, 0.6, 0.4, 0.5), 1.0, true)
			draw_circle(at + Vector2(scale * 0.3, -scale * 0.3), scale * 0.22,
					Color(0.95, 0.85, 0.9, 0.6))
		"nets":
			var frame := Rect2(at - Vector2(scale, scale), Vector2(scale, scale) * 2.0)
			draw_rect(frame, Color(0.35, 0.3, 0.22, 0.35), false, 1.0)
			for i in 3:
				var t := (float(i) + 0.5) / 3.0
				draw_line(frame.position + Vector2(frame.size.x * t, 0.0),
						frame.position + Vector2(frame.size.x * t, frame.size.y),
						Color(0.6, 0.58, 0.5, 0.3), 1.0)
				draw_line(frame.position + Vector2(0.0, frame.size.y * t),
						frame.position + Vector2(frame.size.x, frame.size.y * t),
						Color(0.6, 0.58, 0.5, 0.3), 1.0)
		"rubble":
			for i in 3:
				var chunk := at + Vector2(_hash01(Vector2i(int(at.x), int(at.y)), i) - 0.5,
						roll - 0.5) * scale * 1.6
				var pts := PackedVector2Array([
					chunk + Vector2(-scale * 0.5, scale * 0.4),
					chunk + Vector2(0.0, -scale * 0.55),
					chunk + Vector2(scale * 0.55, scale * 0.4)])
				draw_colored_polygon(pts, Color(pal["rock"]).darkened(0.05 + 0.05 * float(i)))
		"glass":
			for i in 3:
				var shard := at + Vector2.RIGHT.rotated(TAU * float(i) / 3.0 + roll) * scale
				draw_line(at, shard, Color(0.8, 0.9, 0.95, 0.35), 1.5, true)
			draw_circle(at, scale * 0.22, Color(0.9, 0.97, 1.0, 0.4))
		"hummocks":
			draw_arc(at, scale * 1.1, PI, TAU, 12, Color(0.85, 0.92, 1.0, 0.35), 2.0, true)
			draw_arc(at + Vector2(scale * 0.6, scale * 0.2), scale * 0.7, PI, TAU, 10,
					Color(0.8, 0.88, 0.98, 0.28), 1.5, true)
		"drifts":
			var pts := PackedVector2Array([
				at + Vector2(-scale * 1.6, scale * 0.5),
				at + Vector2(-scale * 0.4, -scale * 0.5),
				at + Vector2(scale * 1.0, -scale * 0.1),
				at + Vector2(scale * 1.6, scale * 0.5)])
			draw_polyline(pts, Color(1, 1, 1, 0.22), 2.0, true)
		"slag":
			draw_circle(at, scale * 0.9, Color(0.2, 0.18, 0.17, 0.6))
			draw_circle(at + Vector2(scale * 0.2, -scale * 0.15), scale * 0.35,
					Color(1.0, 0.42, 0.15, 0.45))
		"bollards":
			draw_circle(at, scale * 0.55, Color(0.3, 0.32, 0.36, 0.65))
			draw_arc(at, scale * 0.85, 0.0, TAU, 12, Color(0.62, 0.55, 0.4, 0.4), 1.5, true)
		_:
			draw_circle(at, scale * 0.5, Color(pal["rock"]).darkened(0.1))


func _draw() -> void:
	var cell := float(TDData.CELL)
	var pal := _palette()

	for y in TDData.ROWS:
		for x in TDData.COLS:
			var c := Vector2i(x, y)
			var center: Vector2 = game.cell_center(c)
			var r := Rect2(center - Vector2(cell, cell) * 0.5, Vector2(cell, cell))
			match game.terrain_at(c):
				TDData.Terrain.WATER:
					# Base colour only; WaterLayer paints the animated surface.
					draw_rect(r, pal["water_a"])
				TDData.Terrain.ROCK:
					if not _tile("rock", center, cell):
						draw_rect(r, pal["ground_b"])
						draw_circle(center, cell * 0.34, pal["rock"])
						draw_circle(center + Vector2(cell * 0.16, -cell * 0.12), cell * 0.19,
								Color(pal["rock"]).lightened(0.12))
				TDData.Terrain.PATH:
					if not _tile("path", center, cell):
						draw_rect(r, pal["path_fill"])
				_:
					if not _tile("grass", center, cell):
						_draw_ground(r, c, pal)

	for x in TDData.COLS + 1:
		draw_line(Vector2(float(x) * cell, float(TDData.HUD_H)),
				Vector2(float(x) * cell, float(TDData.HUD_H) + float(TDData.ROWS) * cell),
				Color(1, 1, 1, 0.03), 1.0)
	for y in TDData.ROWS + 1:
		draw_line(Vector2(0.0, float(TDData.HUD_H) + float(y) * cell),
				Vector2(float(TDData.COLS) * cell, float(TDData.HUD_H) + float(y) * cell),
				Color(1, 1, 1, 0.03), 1.0)

	_draw_decor(cell)

	# Path ribbon on top of the tiles: dark shoulders, lighter core.
	var textured: bool = Art.tex("tile_path") != null \
			or Art.tex("tile_path_%s" % game.level_def["id"]) != null
	if not textured:
		for route: PackedVector2Array in game.routes:
			draw_polyline(route, pal["path_edge"], cell * 0.78, true)
			draw_polyline(route, pal["path_fill"], cell * 0.64, true)
			for i in range(1, route.size() - 1):
				draw_circle(route[i], cell * 0.32, pal["path_fill"])
		_draw_path_surface(cell, pal)

	_draw_tint()

	# One spawn portal and one base marker per route, numbered when a map has
	# several so the pairs can be told apart.
	var font := ThemeDB.fallback_font
	var many: bool = game.routes.size() > 1
	# Lanes that share a base only get one marker between them.
	var drawn_bases: Array = []
	var base_labels: Dictionary = {}
	for index in game.routes.size():
		var route: PackedVector2Array = game.routes[index]
		var goal: Vector2 = route[route.size() - 1]
		var key := "%d_%d" % [int(goal.x), int(goal.y)]
		if base_labels.has(key):
			base_labels[key].append(index + 1)
		else:
			base_labels[key] = [index + 1]
	for index in game.routes.size():
		var route: PackedVector2Array = game.routes[index]
		var tint: Color = TDData.route_color(index)
		var start: Vector2 = route[0]
		var goal: Vector2 = route[route.size() - 1]
		var s_in := start + (route[1] - start).normalized() * cell * 1.25
		var g_in := goal + (route[route.size() - 2] - goal).normalized() * cell * 1.25
		draw_circle(s_in, cell * 0.3, Color(tint.r, tint.g, tint.b, 0.32))
		draw_arc(s_in, cell * 0.3, 0.0, TAU, 24, tint, 3.0, true)
		var tag := " %d" % (index + 1) if many else ""
		draw_string(font, s_in + Vector2(-34.0, 34.0), "SPAWN" + tag,
				HORIZONTAL_ALIGNMENT_CENTER, 68, 12, Color(tint.r, tint.g, tint.b, 0.8))

		var base_key := "%d_%d" % [int(goal.x), int(goal.y)]
		if drawn_bases.has(base_key):
			continue
		drawn_bases.append(base_key)
		draw_circle(g_in, cell * 0.3, Color(0.95, 0.3, 0.3, 0.3))
		draw_arc(g_in, cell * 0.3, 0.0, TAU, 24, Color("ef5350"), 3.0, true)
		var lanes: Array = base_labels[base_key]
		var base_tag := ""
		if many and lanes.size() < game.routes.size():
			base_tag = " %d" % int(lanes[0])
		draw_string(font, g_in + Vector2(-34.0, 34.0), "BASE" + base_tag,
				HORIZONTAL_ALIGNMENT_CENTER, 68, 12, Color(1, 0.6, 0.6, 0.75))
