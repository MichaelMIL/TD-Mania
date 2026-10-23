class_name UpgradeIcon
extends Control

## A picture for one upgrade track, drawn on the track's button.
##
## If `assets/upgrade_<tower>_<track key>.png` exists it is used (prompts for
## all of them are in `assets/PROMPTS.md`). Otherwise a badge in the tower's
## colour is drawn with a symbol for what the track does: a burst for
## damage, chevrons for fire rate, a crosshair for range, a snowflake for a
## slow, and so on. The symbol comes from the track's own stat changes, so a
## retuned or new track still gets a sensible picture.

var type_id: String = ""
var track: int = -1

## Tracks whose picture says more than their first stat would. A gold mine
## has three tracks that all raise income; a tar pit's slow is not ice.
const OVERRIDES: Dictionary = {
	"mine/income": "coin",
	"mine/rate": "moon",
	"mine/range": "flag",
	"tarpit/slow": "drops",
	"flame/chain": "cone",
	"tide/slow": "swirl",
	"tide/dmg": "wave",
	"wavegun/push": "push",
	"airfield/rate": "wrench",
	"airfield/bombs": "bomb",
	"helipad/ammo": "ammo",
	"helipad/speed": "rotor",
}

## The symbol for each kind of stat change, by the track's first mod.
const BY_MOD: Dictionary = {
	"damage_mult": "damage",
	"rate_mult": "rate",
	"range_mult": "range",
	"splash_mult": "splash",
	"slow_add": "snow",
	"slow_dur_add": "hourglass",
	"chain_add": "chain",
	"burn_add": "flame",
	"min_range_mult": "range",
	"volley_add": "volley",
	"focus_add": "lens",
	"income_mult": "coin",
	"pierce_add": "pierce",
	"knockback_add": "push",
	"unit_shots_add": "ammo",
	"unit_count_add": "squad",
	"unit_speed_mult": "rotor",
	"aura_damage_add": "aura_up",
	"aura_rate_add": "aura_fast",
}


static func art_name(tower: String, key: String) -> String:
	return "upgrade_%s_%s" % [tower, key]


## The symbol a track is drawn with when it has no picture of its own.
static func glyph_for(tower: String, t: Dictionary) -> String:
	var key := "%s/%s" % [tower, str(t.get("key", ""))]
	if OVERRIDES.has(key):
		return OVERRIDES[key]
	var mods: Dictionary = t.get("mods", {})
	for mod: String in mods:
		if BY_MOD.has(mod):
			return BY_MOD[mod]
	return "damage"


func show_track(tower: String, index: int) -> void:
	if tower == type_id and index == track:
		return
	type_id = tower
	track = index
	queue_redraw()


func _draw() -> void:
	if type_id == "" or track < 0 or not TDData.TOWERS.has(type_id):
		return
	var list: Array = TDData.tracks(type_id)
	if track >= list.size():
		return
	var t: Dictionary = list[track]
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var picture := Art.tex(art_name(type_id, str(t.get("key", ""))))
	if picture != null:
		var side := r * 2.0
		draw_texture_rect(picture, Rect2(c - Vector2(r, r), Vector2(side, side)), false)
		return
	var tint: Color = TDData.TOWERS[type_id]["color"]
	draw_circle(c, r, Color("0d141e"))
	draw_circle(c, r * 0.9, Color(tint.r, tint.g, tint.b, 0.14))
	draw_arc(c, r - 1.0, 0.0, TAU, 40, tint.darkened(0.1), maxf(1.5, r * 0.07), true)
	draw_glyph(self, glyph_for(type_id, t), c, r * 0.58, tint.lightened(0.3))


## A crescent: the part of a circle (centre `c`, radius `r`) outside a second
## circle offset by `off` with radius `r2`, as one polygon so it needs no
## background colour to cut it out.
static func _crescent(c: Vector2, r: float, off: Vector2, r2: float) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var start := (-off).angle()
	for i in 64:
		var p := c + Vector2.from_angle(start + TAU * float(i) / 64.0) * r
		if p.distance_to(c + off) > r2:
			outer.append(p)
	var inner := PackedVector2Array()
	var back := (-off).angle()
	for i in 64:
		var p := c + off + Vector2.from_angle(back + TAU * float(i) / 64.0) * r2
		if p.distance_to(c) <= r:
			inner.append(p)
	# The inner arc runs from where the outer one stops back to where it began.
	if inner.size() > 0 and outer.size() > 0 \
			and inner[0].distance_to(outer[outer.size() - 1]) > inner[inner.size() - 1].distance_to(outer[outer.size() - 1]):
		inner.reverse()
	outer.append_array(inner)
	return outer


## Draws one symbol centred on `c`, about `s` from centre to edge. Static so
## anything else that wants the same picture can draw it.
static func draw_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	var dim := Color(col.r, col.g, col.b, col.a * 0.55)
	match glyph:
		"damage":
			# An impact: an eight-point burst.
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0 - PI * 0.5
				pts.append(c + Vector2.from_angle(a) * (s if i % 2 == 0 else s * 0.45))
			ci.draw_colored_polygon(pts, col)
		"rate":
			# Fast-forward: two chevrons.
			for dx: float in [-0.45, 0.25]:
				var o := c + Vector2(dx * s, 0.0)
				ci.draw_polyline(PackedVector2Array([o + Vector2(-s * 0.3, -s * 0.7),
						o + Vector2(s * 0.35, 0.0), o + Vector2(-s * 0.3, s * 0.7)]), col,
						w * 1.3, true)
		"range":
			ci.draw_arc(c, s, 0.0, TAU, 32, col, w, true)
			ci.draw_arc(c, s * 0.5, 0.0, TAU, 24, dim, w, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * s * 0.7, c + d * s * 1.15, col, w, true)
			ci.draw_circle(c, s * 0.14, col)
		"splash":
			ci.draw_circle(c, s * 0.42, col)
			for i in 8:
				var d := Vector2.from_angle(TAU * float(i) / 8.0)
				ci.draw_line(c + d * s * 0.6, c + d * s * 1.05, col, w, true)
		"snow":
			for i in 3:
				var d := Vector2.from_angle(PI * float(i) / 3.0 + PI * 0.5)
				ci.draw_line(c - d * s, c + d * s, col, w, true)
				for sgn: float in [-1.0, 1.0]:
					var tip := c + d * s * sgn * 0.62
					var side := d.orthogonal() * s * 0.22
					ci.draw_line(tip, tip + d * s * sgn * 0.25 + side, col, w * 0.8, true)
					ci.draw_line(tip, tip + d * s * sgn * 0.25 - side, col, w * 0.8, true)
		"hourglass":
			var top := PackedVector2Array([c + Vector2(-s * 0.6, -s), c + Vector2(s * 0.6, -s),
					c + Vector2(0.0, 0.0)])
			var bottom := PackedVector2Array([c + Vector2(0.0, 0.0), c + Vector2(s * 0.6, s),
					c + Vector2(-s * 0.6, s)])
			ci.draw_colored_polygon(top, dim)
			ci.draw_colored_polygon(bottom, col)
			ci.draw_line(c + Vector2(-s * 0.75, -s), c + Vector2(s * 0.75, -s), col, w, true)
			ci.draw_line(c + Vector2(-s * 0.75, s), c + Vector2(s * 0.75, s), col, w, true)
		"chain":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.15, -s),
					c + Vector2(-s * 0.55, s * 0.1), c + Vector2(-s * 0.05, s * 0.1),
					c + Vector2(-s * 0.2, s), c + Vector2(s * 0.55, -s * 0.15),
					c + Vector2(s * 0.05, -s * 0.15)]), col)
		"flame":
			var outer := PackedVector2Array()
			for i in 20:
				var a := TAU * float(i) / 20.0
				var p := Vector2(sin(a) * 0.62, -cos(a) * 0.6)
				if p.y < 0.0:
					p.x *= 1.0 + p.y * 0.85
					p.y *= 1.65
				outer.append(c + Vector2(0.0, s * 0.3) + p * s)
			ci.draw_colored_polygon(outer, col)
			ci.draw_circle(c + Vector2(0.0, s * 0.4), s * 0.25, Color(1, 1, 1, 0.55))
		"cone":
			# A spray: three jets fanning out from a nozzle.
			var base := c + Vector2(-s * 0.85, s * 0.6)
			ci.draw_circle(base, s * 0.2, col)
			for a: float in [-1.05, -0.55, -0.05]:
				ci.draw_line(base, base + Vector2.from_angle(a) * s * 1.55,
						col if a == -0.55 else dim, w * 1.3, true)
		"volley":
			for dx: float in [-0.55, 0.0, 0.55]:
				var x := c.x + dx * s
				ci.draw_line(Vector2(x, c.y + s * 0.9), Vector2(x, c.y - s * 0.5), col, w, true)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x, c.y - s),
						Vector2(x - s * 0.2, c.y - s * 0.45), Vector2(x + s * 0.2, c.y - s * 0.45)]),
						col)
		"lens":
			ci.draw_arc(c + Vector2(0.0, s * 0.9), s * 1.25, -PI * 0.78, -PI * 0.22, 16, col,
					w, true)
			ci.draw_arc(c - Vector2(0.0, s * 0.9), s * 1.25, PI * 0.22, PI * 0.78, 16, col,
					w, true)
			for dy: float in [-0.35, 0.0, 0.35]:
				ci.draw_line(c + Vector2(-s, dy * s), c + Vector2(s * 0.95, 0.0), dim, w * 0.7, true)
		"coin":
			ci.draw_circle(c, s, col)
			ci.draw_arc(c, s * 0.72, 0.0, TAU, 24, Color(0, 0, 0, 0.35), w, true)
			ci.draw_line(c + Vector2(0.0, -s * 0.45), c + Vector2(0.0, s * 0.45),
					Color(0, 0, 0, 0.45), w * 1.2, true)
		"moon":
			ci.draw_colored_polygon(_crescent(c, s * 0.85, Vector2(s * 0.42, -s * 0.28),
					s * 0.7), col)
			ci.draw_circle(c + Vector2(s * 0.55, s * 0.55), s * 0.12, col)
		"flag":
			ci.draw_line(c + Vector2(-s * 0.55, s), c + Vector2(-s * 0.55, -s), col, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s),
					c + Vector2(s * 0.85, -s * 0.6), c + Vector2(-s * 0.5, -s * 0.15)]), col)
		"drops":
			for o: Vector2 in [Vector2(-0.45, 0.25), Vector2(0.4, 0.35), Vector2(0.0, -0.4)]:
				var p := c + o * s
				ci.draw_circle(p + Vector2(0.0, s * 0.12), s * 0.3, col)
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.26, s * 0.05),
						p + Vector2(0.0, -s * 0.4), p + Vector2(s * 0.26, s * 0.05)]), col)
		"swirl":
			var pts := PackedVector2Array()
			for i in 40:
				var a := float(i) * 0.33
				pts.append(c + Vector2.from_angle(a) * s * (0.12 + float(i) / 40.0 * 0.95))
			ci.draw_polyline(pts, col, w, true)
		"wave":
			for row: float in [-0.35, 0.35]:
				var pts := PackedVector2Array()
				for i in 17:
					var x := -1.0 + float(i) / 8.0
					pts.append(c + Vector2(x * s, row * s + sin(x * PI * 1.5) * s * 0.25))
				ci.draw_polyline(pts, col if row > 0.0 else dim, w * 1.2, true)
		"push":
			ci.draw_line(c + Vector2(s * 0.85, -s), c + Vector2(s * 0.85, s), col, w * 1.3, true)
			for dx: float in [-0.8, -0.2]:
				var o := c + Vector2(dx * s, 0.0)
				ci.draw_polyline(PackedVector2Array([o + Vector2(-s * 0.15, -s * 0.6),
						o + Vector2(s * 0.35, 0.0), o + Vector2(-s * 0.15, s * 0.6)]), col,
						w * 1.2, true)
		"pierce":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.85), Vector2(s * 0.24, s * 1.7)), dim)
			ci.draw_line(c + Vector2(-s, 0.0), c + Vector2(s * 0.55, 0.0), col, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s, 0.0),
					c + Vector2(s * 0.45, -s * 0.32), c + Vector2(s * 0.45, s * 0.32)]), col)
		"ammo":
			for dx: float in [-0.55, 0.0, 0.55]:
				var x := c.x + dx * s
				ci.draw_rect(Rect2(x - s * 0.17, c.y - s * 0.2, s * 0.34, s * 0.95), col)
				ci.draw_circle(Vector2(x, c.y - s * 0.2), s * 0.17, col.lightened(0.2))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x - s * 0.17, c.y - s * 0.2),
						Vector2(x, c.y - s * 0.75), Vector2(x + s * 0.17, c.y - s * 0.2)]),
						col.lightened(0.2))
		"bomb":
			ci.draw_circle(c + Vector2(-s * 0.1, s * 0.15), s * 0.7, col)
			ci.draw_line(c + Vector2(s * 0.3, -s * 0.35), c + Vector2(s * 0.7, -s * 0.8), dim,
					w, true)
			ci.draw_circle(c + Vector2(s * 0.75, -s * 0.85), s * 0.16, Color("ffca28"))
		"squad":
			for o: Vector2 in [Vector2(-0.45, 0.3), Vector2(0.45, -0.3)]:
				var p := c + o * s
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -s * 0.6),
						p + Vector2(s * 0.5, s * 0.35), p + Vector2(0.0, s * 0.15),
						p + Vector2(-s * 0.5, s * 0.35)]), col)
		"rotor":
			ci.draw_circle(c, s * 0.2, col)
			for i in 4:
				var d := Vector2.from_angle(TAU * float(i) / 4.0 + 0.4)
				ci.draw_line(c, c + d * s, col, w * 1.3, true)
			ci.draw_arc(c, s * 1.0, -0.2, 0.9, 10, dim, w * 0.8, true)
			ci.draw_arc(c, s * 1.0, PI - 0.2, PI + 0.9, 10, dim, w * 0.8, true)
		"wrench":
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.25, -s * 0.25), col,
					w * 2.0, true)
			ci.draw_arc(c + Vector2(s * 0.45, -s * 0.45), s * 0.42, PI * 0.95, PI * 2.55, 14, col,
					w * 1.6, true)
		"aura_up", "aura_fast":
			ci.draw_arc(c, s, 0.0, TAU, 32, dim, w, true)
			var heads := [0.0] if glyph == "aura_up" else [-0.3, 0.3]
			for dy: float in heads:
				var o := c + Vector2(0.0, dy * s)
				ci.draw_polyline(PackedVector2Array([o + Vector2(-s * 0.5, s * 0.25),
						o + Vector2(0.0, -s * 0.3), o + Vector2(s * 0.5, s * 0.25)]), col,
						w * 1.4, true)
			if glyph == "aura_up":
				ci.draw_line(c + Vector2(0.0, -s * 0.2), c + Vector2(0.0, s * 0.6), col, w * 1.4, true)
		_:
			ci.draw_circle(c, s * 0.5, col)
