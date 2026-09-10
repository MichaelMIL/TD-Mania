class_name RoutePreview
extends Node2D

## Shows the road the next wave will walk: a dashed line flowing from each
## spawn towards its base, with arrows pointing the way. It is on during the
## build phase and switches off the moment the wave starts.

const FLASH_TIME := 4.0
const DASH := 16.0
const GAP := 14.0

var game: Node = null
var flash: float = 0.0
var t: float = 0.0


func _process(delta: float) -> void:
	t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
	queue_redraw()


## Called when a build phase opens so the roads flash up before the next wave.
func announce() -> void:
	flash = FLASH_TIME


func _alpha() -> float:
	# Nothing to preview once the creeps are actually walking.
	if game.game_over or game.in_wave:
		return 0.0
	if flash > 0.0:
		return lerpf(0.4, 1.0, clampf(flash / FLASH_TIME, 0.0, 1.0))
	return 0.35 + 0.08 * sin(t * 2.2)


func _draw() -> void:
	if game == null or game.routes.is_empty():
		return
	var alpha := _alpha()
	if alpha <= 0.01:
		return
	# Only the lanes the next wave will use, so a single-lane round reads at a
	# glance on a multi-lane map.
	var lanes: Array = game.next_wave_lanes()
	for index in game.routes.size():
		if not lanes.has(index):
			continue
		_draw_route(game.routes[index], TDData.route_color(index), alpha)


## Dash spans for one segment as [start, end] distances along it. The phase
## comes from distance-from-spawn minus elapsed flow, so the pattern slides
## towards the base and stays continuous across corners. Extracted from the
## drawing so the dev suite can check which way it moves.
func dash_spans(travelled: float, span: float) -> Array:
	var period := DASH + GAP
	var out: Array = []
	var at := -fposmod(travelled - fmod(t * 46.0, period), period)
	while at < span:
		var head: float = maxf(at, 0.0)
		var tail: float = minf(at + DASH, span)
		if tail > head:
			out.append([head, tail])
		at += period
	return out


func _draw_route(route: PackedVector2Array, tint: Color, alpha: float) -> void:
	var period := DASH + GAP
	var flow := fmod(t * 46.0, period)
	var travelled := 0.0
	var next_arrow := 40.0
	for i in range(route.size() - 1):
		var from: Vector2 = route[i]
		var to: Vector2 = route[i + 1]
		var span := from.distance_to(to)
		if span <= 0.0:
			continue
		var dir := (to - from) / span
		for dash: Array in dash_spans(travelled, span):
			draw_line(from + dir * float(dash[0]), from + dir * float(dash[1]),
					Color(tint.r, tint.g, tint.b, alpha * 0.85), 4.0, true)
		while next_arrow < travelled + span:
			var local := next_arrow - travelled
			if local >= 0.0:
				_draw_arrow(from + dir * local, dir, tint, alpha)
			next_arrow += 150.0
		travelled += span


func _draw_arrow(at: Vector2, dir: Vector2, tint: Color, alpha: float) -> void:
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([
			at + dir * 9.0, at - dir * 5.0 + side * 6.0, at - dir * 5.0 - side * 6.0]),
			Color(tint.r, tint.g, tint.b, alpha))
