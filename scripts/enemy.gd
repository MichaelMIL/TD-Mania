class_name Enemy
extends Node2D

## A creep walking the fixed path. Movement is pure maths along the
## waypoint polyline; no physics bodies are involved.

signal died(enemy: Enemy)
signal leaked(enemy: Enemy)
## Emitted when a creep that breaks apart dies, so the game can spawn its brood.
signal split(enemy: Enemy, kind: String, count: int)

var kind: String = "grunt"
var display_name: String = "Grunt"
var max_hp: float = 40.0
var hp: float = 40.0
var base_speed: float = 60.0
var armor: float = 0.0
var reward: int = 5
var leak_damage: int = 1
var radius: float = 13.0
var color: Color = Color.WHITE

var path: PackedVector2Array = PackedVector2Array()
var route_index: int = 0
var walk_pos: Vector2 = Vector2.ZERO
var lane: float = 0.0
var seg: int = 0
var progress: float = 0.0
var slow_timer: float = 0.0
var slow_factor: float = 1.0
var burn_dps: float = 0.0
var burn_timer: float = 0.0
## Tower that lit the fire, so burn ticks are credited to it.
var burn_source: Node = null
var hit_flash: float = 0.0
## How shove-resistant this creep currently is; see push_back().
var push_fatigue: float = 0.0
## Flyers cut across the map and can only be shot by towers that reach up.
var flying: bool = false
## Hits absorbed outright before damage starts landing. Wave affixes hand
## these out; a volley strips them cheaply, one big shot wastes itself.
var shield_hits: int = 0
## Bosses do something rather than only being large: "rally" hurries the
## escort along, "quake" stuns the towers near it. Driven by the game, which
## is the only thing that can see the rest of the board.
var ability: String = ""
var ability_period: float = 0.0
var ability_radius: float = 0.0
var ability_clock: float = 0.0
## A rallied creep runs faster for a while.
var haste_timer: float = 0.0
var haste_factor: float = 1.0
var slow_immune: bool = false
var burn_immune: bool = false
var heal: float = 0.0
var heal_range: float = 0.0
var steal_gold: int = 0
var split_into: String = ""
var split_count: int = 0
var charge_period: float = 0.0
var charge_time: float = 0.0
var charge_mult: float = 1.0
var charge_clock: float = 0.0
var charging: float = 0.0
var wobble: float = 0.0
var dead: bool = false


## Creeps move ahead of everything else in the frame (towers, projectiles,
## aircraft all sit at the default priority) so the targeting grid the game
## builds on the first query of a frame already holds their new positions.
const PROCESS_ORDER := -10
## How often an undisturbed creep rebuilds its art.
const IDLE_REDRAW_HZ := 12.0

var _idle_clock: float = 0.0


func _init() -> void:
	process_priority = PROCESS_ORDER


func setup(k: String, hp_mult: float, speed_mult: float, points: PackedVector2Array) -> void:
	kind = k
	var d: Dictionary = TDData.enemy_def(k)
	display_name = str(d["name"])
	max_hp = float(d["hp"]) * hp_mult
	hp = max_hp
	base_speed = float(d["speed"]) * speed_mult
	armor = float(d["armor"])
	reward = int(d["reward"])
	leak_damage = int(d["damage"])
	radius = float(d["radius"])
	color = d["color"]
	slow_immune = bool(d.get("slow_immune", false))
	burn_immune = bool(d.get("burn_immune", false))
	heal = float(d.get("heal", 0.0))
	heal_range = float(d.get("heal_range", 0.0))
	steal_gold = int(d.get("steal_gold", 0))
	split_into = str(d.get("split_into", ""))
	split_count = int(d.get("split_count", 0))
	charge_period = float(d.get("charge_period", 0.0))
	charge_time = float(d.get("charge_time", 0.0))
	charge_mult = float(d.get("charge_mult", 1.0))
	charge_clock = randf() * maxf(0.1, charge_period)
	ability = str(d.get("ability", ""))
	ability_period = float(d.get("ability_period", 0.0))
	ability_radius = float(d.get("ability_radius", 0.0))
	# Half a period in, so a boss does something before it is halfway home.
	ability_clock = ability_period * 0.5
	flying = bool(d.get("flying", false))
	if flying:
		# Flyers ignore the road entirely: spawn point straight to the base.
		# Reusing the same two-point polyline keeps progress, lanes, slows
		# and leak handling exactly as they are for everything else.
		path = PackedVector2Array([points[0], points[points.size() - 1]])
	else:
		path = points
	walk_pos = path[0]
	lane = randf_range(-1.0, 1.0) * (float(TDData.CELL) * 0.22 - radius * 0.35)
	_sync_position()
	wobble = randf() * TAU


func _process(delta: float) -> void:
	if dead:
		return
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			queue_redraw()
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta * 4.0)
		queue_redraw()
	if push_fatigue > 0.0:
		push_fatigue = maxf(0.0, push_fatigue - delta * PUSH_FATIGUE_DECAY)
	if haste_timer > 0.0:
		haste_timer -= delta
		if haste_timer <= 0.0:
			haste_factor = 1.0
			queue_redraw()
	if burn_timer > 0.0:
		burn_timer -= delta
		# The tower that lit the fire may have been sold since. A freed object
		# compares equal to null in GDScript, so test validity directly.
		if not is_instance_valid(burn_source):
			burn_source = null
		take_damage(burn_dps * delta, true, burn_source)
		if dead:
			return
		if burn_timer <= 0.0:
			burn_dps = 0.0
			queue_redraw()
	wobble += delta * 9.0
	# The bob and the wing beat are the only reason a walking creep redraws.
	# Twelve times a second is indistinguishable and costs a fifth as much.
	_idle_clock += delta
	if _idle_clock >= 1.0 / IDLE_REDRAW_HZ:
		_idle_clock = 0.0
		queue_redraw()
	if charge_period > 0.0:
		# Sprinters build up, burst forward, then settle again.
		charge_clock += delta
		if charging > 0.0:
			charging -= delta
			if charging <= 0.0:
				queue_redraw()
		elif charge_clock >= charge_period:
			charge_clock = 0.0
			charging = charge_time
			queue_redraw()

	var step := speed() * delta
	while step > 0.0 and seg < path.size() - 1:
		var to_next: Vector2 = path[seg + 1] - walk_pos
		var dist := to_next.length()
		if dist <= step:
			walk_pos = path[seg + 1]
			step -= dist
			progress += dist
			seg += 1
		else:
			walk_pos += to_next / dist * step
			progress += step
			step = 0.0
	_sync_position()
	if seg >= path.size() - 1:
		_leak()


## Shoves the creep back down its own road. Used by the Wave Cannon.
## Repeated shoves lose their grip: without this a pair of Wave Cannons can
## hold a lane at a standstill forever. Fatigue decays in `_process`.
const PUSH_FATIGUE_MAX := 4.0
const PUSH_FATIGUE_DECAY := 1.2


func push_back(distance: float) -> void:
	if dead or path.size() < 2:
		return
	var remaining := distance / (1.0 + push_fatigue)
	push_fatigue = minf(PUSH_FATIGUE_MAX, push_fatigue + 1.0)
	while remaining > 0.0:
		var anchor: Vector2 = path[seg]
		var gap := walk_pos.distance_to(anchor)
		if gap > remaining:
			walk_pos += (anchor - walk_pos).normalized() * remaining
			progress = maxf(0.0, progress - remaining)
			break
		walk_pos = anchor
		progress = maxf(0.0, progress - gap)
		remaining -= gap
		if seg <= 0:
			break
		seg -= 1
	_sync_position()
	queue_redraw()


## Places the node beside the path centre line by `lane` pixels, so a pack
## of creeps spreads out instead of stacking into one silhouette.
func _sync_position() -> void:
	if seg >= path.size() - 1:
		position = walk_pos
		return
	var dir: Vector2 = (path[seg + 1] - path[seg]).normalized()
	position = walk_pos + dir.orthogonal() * lane


func speed() -> float:
	return base_speed * slow_factor * haste_factor \
			* (charge_mult if charging > 0.0 else 1.0)


## Hurried along by a boss's rally.
func hasten(factor: float, duration: float) -> void:
	if dead:
		return
	haste_factor = maxf(haste_factor, factor)
	haste_timer = maxf(haste_timer, duration)
	queue_redraw()


## Returns true when this hit was the killing blow. `source` is the tower that
## fired, so kills and damage can be tallied per tower.
func take_damage(amount: float, pierce_armor: bool = false, source: Node = null) -> bool:
	if dead:
		return false
	if not is_instance_valid(source):
		source = null
	if shield_hits > 0:
		# The shot is spent breaking the shield, whatever it was carrying.
		shield_hits -= 1
		hit_flash = 1.0
		queue_redraw()
		return false
	var dealt := amount if pierce_armor else maxf(1.0, amount - armor)
	dealt = minf(dealt, hp)
	hp -= dealt
	if source != null and is_instance_valid(source):
		source.damage_dealt += dealt
	hit_flash = 1.0
	queue_redraw()
	if hp <= 0.0:
		dead = true
		if source != null and is_instance_valid(source):
			source.kills += 1
		if split_into != "" and split_count > 0:
			split.emit(self, split_into, split_count)
		died.emit(self)
		queue_free()
		return true
	return false


## Tops a wounded creep back up; Menders call this on their neighbours.
func mend(amount: float) -> void:
	if dead:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before:
		queue_redraw()


## Lingering fire damage. A stronger flame refreshes both the rate and the
## duration; a weaker one only tops the duration up.
func apply_burn(dps: float, duration: float, source: Node = null) -> void:
	if dead or burn_immune:
		return
	if source != null:
		burn_source = source
	burn_dps = maxf(burn_dps, dps)
	burn_timer = maxf(burn_timer, duration)
	queue_redraw()


func apply_slow(factor: float, duration: float) -> void:
	if dead or slow_immune:
		return
	slow_factor = minf(slow_factor, maxf(0.15, 1.0 - factor))
	slow_timer = maxf(slow_timer, duration)
	queue_redraw()


func _leak() -> void:
	if dead:
		return
	dead = true
	leaked.emit(self)
	queue_free()


func _draw() -> void:
	var bob := sin(wobble) * radius * 0.09
	# Flyers ride high above their shadow, which is how you tell at a glance
	# that half your towers cannot touch them.
	var lift := radius * 1.15 if flying else 0.0
	var body_pos := Vector2(0.0, bob - lift)
	var tint := color
	if slow_timer > 0.0:
		tint = tint.lerp(Color("6fd0ff"), 0.45)
	if burn_timer > 0.0:
		tint = tint.lerp(Color("ff8a3d"), 0.4 + 0.2 * sin(wobble * 2.0))
	if charging > 0.0:
		tint = tint.lerp(Color.WHITE, 0.35)
	if hit_flash > 0.0:
		tint = tint.lerp(Color.WHITE, hit_flash * 0.8)

	# Shadow. A flyer's is smaller and darker, cast from further up.
	if flying:
		draw_circle(Vector2(0.0, radius * 0.62), radius * 0.5, Color(0, 0, 0, 0.35))
	else:
		draw_circle(Vector2(0.0, radius * 0.62), radius * 0.82, Color(0, 0, 0, 0.25))

	if flying:
		var beat := sin(wobble * 2.2) * 0.5 + 0.5
		var span := radius * (1.5 + 0.35 * beat)
		var wing := Color(tint.lightened(0.25), 0.8)
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([
				body_pos,
				body_pos + Vector2(span * side, -radius * (0.5 + 0.35 * beat)),
				body_pos + Vector2(span * side * 0.8, radius * 0.35),
			]), wing)
	if not Art.draw_centered(self, "enemy_" + kind, body_pos, radius * 2.3, 0.0, tint):
		draw_circle(body_pos, radius, tint)
		draw_arc(body_pos, radius, 0.0, TAU, 20, tint.darkened(0.5), 2.0, true)
		# Eye highlight so creeps read as characters, not blobs.
		draw_circle(body_pos + Vector2(radius * 0.3, -radius * 0.28), radius * 0.26,
				Color(1, 1, 1, 0.85))
		draw_circle(body_pos + Vector2(radius * 0.38, -radius * 0.28), radius * 0.12,
				Color(0.05, 0.06, 0.09))
		if armor > 0.0:
			draw_arc(body_pos, radius * 0.62, 0.0, TAU, 16, Color(1, 1, 1, 0.35), 2.0, true)

	if shield_hits > 0:
		draw_arc(body_pos, radius + 6.0, 0.0, TAU, 26,
				Color(0.75, 0.85, 1.0, 0.75), 2.0, true)
	if slow_timer > 0.0:
		draw_arc(body_pos, radius + 4.0, 0.0, TAU, 22, Color(0.55, 0.85, 1.0, 0.7), 1.5, true)
	if burn_timer > 0.0:
		for i in 3:
			var ang := wobble * 1.6 + TAU * float(i) / 3.0
			var tip := Vector2.UP.rotated(ang * 0.4) * (radius + 5.0 + sin(wobble + float(i)) * 2.0)
			draw_line(body_pos + tip * 0.6, body_pos + tip,
					Color(1.0, 0.55, 0.2, 0.75), 2.0, true)

	if heal > 0.0:
		# Mender cross, and a faint ring showing who it can reach.
		draw_arc(body_pos, heal_range, 0.0, TAU, 40, Color(0.4, 0.9, 0.9, 0.12), 1.5, true)
		draw_line(body_pos + Vector2(-4.0, 0.0), body_pos + Vector2(4.0, 0.0),
				Color(1, 1, 1, 0.9), 2.0)
		draw_line(body_pos + Vector2(0.0, -4.0), body_pos + Vector2(0.0, 4.0),
				Color(1, 1, 1, 0.9), 2.0)
	if slow_immune:
		draw_arc(body_pos, radius + 3.0, 0.0, TAU, 20, Color(1.0, 0.6, 0.3, 0.5), 1.5, true)
	if steal_gold > 0:
		draw_circle(body_pos + Vector2(0.0, -radius - 5.0), 2.6, Color("ffd54f"))
	if charging > 0.0:
		for i in 3:
			var trail_at := body_pos - Vector2(6.0 + 5.0 * float(i), 0.0)
			draw_circle(trail_at, radius * (0.5 - 0.12 * float(i)),
					Color(tint.r, tint.g, tint.b, 0.35 - 0.1 * float(i)))
	if split_count > 0:
		draw_arc(body_pos, radius * 0.55, 0.0, TAU, 14, Color(1, 1, 1, 0.35), 1.5, true)

	# Health bar.
	if hp < max_hp:
		var w := radius * 2.2
		var top := -radius - 9.0
		draw_rect(Rect2(-w * 0.5 - 1.0, top - 1.0, w + 2.0, 6.0), Color(0, 0, 0, 0.55))
		var frac: float = clampf(hp / max_hp, 0.0, 1.0)
		var bar := Color("66bb6a").lerp(Color("ef5350"), 1.0 - frac)
		draw_rect(Rect2(-w * 0.5, top, w * frac, 4.0), bar)
