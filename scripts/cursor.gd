class_name Cursor
extends Node2D

## Placement preview drawn on top of everything: the ghost tower, its range
## circle, and a green / red validity tint that respects terrain rules.

var game: Node = null


func _process(_delta: float) -> void:
	# The valid-cell hint pulses, so keep redrawing while a tower is armed.
	if game != null and game.placing != "":
		queue_redraw()


func _draw() -> void:
	if game == null:
		return
	if game.placing == "":
		_draw_preview()
		return
	var cell: Vector2i = game.hover_cell
	if not game.in_bounds(cell):
		return
	var d: Dictionary = TDData.tower_def(game.placing)
	var pos: Vector2 = game.cell_center(cell)
	var ok: bool = game.can_place(cell, game.placing) and game.gold >= int(d["cost"])
	var col: Color = Color("66bb6a") if ok else Color("ef5350")
	var size := float(TDData.CELL)

	draw_rect(Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)),
			Color(col.r, col.g, col.b, 0.18))
	draw_rect(Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)),
			Color(col.r, col.g, col.b, 0.8), false, 2.0)

	var rng := float(d["range"])
	var tint: Color = d["color"]
	draw_circle(pos, rng, Color(tint.r, tint.g, tint.b, 0.07))
	draw_arc(pos, rng, 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, 0.5), 1.5, true)
	var dead := float(d.get("min_range", 0.0))
	if dead > 0.0:
		draw_circle(pos, dead, Color(0.9, 0.3, 0.3, 0.1))
		draw_arc(pos, dead, 0.0, TAU, 40, Color(0.95, 0.4, 0.4, 0.5), 1.5, true)
	draw_circle(pos, 20.0, Color(tint.r, tint.g, tint.b, 0.35))
	# Green and red are the same colour to a good few people, so the cell
	# says yes or no in a shape as well.
	if ok:
		draw_line(pos + Vector2(-9.0, 0.0), pos + Vector2(-3.0, 7.0), col, 3.0, true)
		draw_line(pos + Vector2(-3.0, 7.0), pos + Vector2(9.0, -8.0), col, 3.0, true)
	else:
		draw_line(pos + Vector2(-8.0, -8.0), pos + Vector2(8.0, 8.0), col, 3.0, true)
		draw_line(pos + Vector2(8.0, -8.0), pos + Vector2(-8.0, 8.0), col, 3.0, true)

	# Highlight every cell of the same terrain type when nothing fits here, so
	# it is obvious where a water-only tower can go.
	if not game.can_place(cell, game.placing):
		var want: int = int(d["terrain"])
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005)
		for key: Vector2i in game.terrain:
			if game.terrain_at(key) == want and not game.occupied.has(key):
				var c: Vector2 = game.cell_center(key)
				var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
				draw_rect(r.grow(-3.0), Color(tint.r, tint.g, tint.b, 0.14))
				draw_rect(r.grow(-3.0), Color(tint.r, tint.g, tint.b, 0.45 + 0.35 * pulse),
						false, 2.0)


## What a tower would do from here, drawn while its palette card is hovered:
## every cell it could stand on, and the reach from the last cell the mouse
## was over. Nothing is committed, so it is drawn fainter than the real
## placement cursor.
func _draw_preview() -> void:
	var type_id: String = game.preview_tower
	if type_id == "" or not TDData.TOWERS.has(type_id):
		return
	var d: Dictionary = TDData.tower_def(type_id)
	var tint: Color = d["color"]
	var size := float(TDData.CELL)
	for key: Vector2i in game.terrain:
		if not game.can_place(key, type_id):
			continue
		var at: Vector2 = game.cell_center(key)
		draw_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)),
				Color(tint.r, tint.g, tint.b, 0.07))
	if not game.in_bounds(game.hover_cell):
		return
	var pos: Vector2 = game.cell_center(game.hover_cell)
	var rng := float(d["range"])
	draw_circle(pos, rng, Color(tint.r, tint.g, tint.b, 0.05))
	draw_arc(pos, rng, 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, 0.35), 1.5, true)
	var dead := float(d.get("min_range", 0.0))
	if dead > 0.0:
		draw_arc(pos, dead, 0.0, TAU, 40, Color(0.95, 0.4, 0.4, 0.35), 1.5, true)
