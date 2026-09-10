class_name Tower
extends Node2D

## A placed tower.
##
## Land and water towers scan the game's enemy list for the creep furthest
## along the path within range, track it with the turret, then shoot or beam
## it. Air towers (Airfield, Helipad) instead launch aircraft that fly out,
## attack, and come home to rearm.
##
## Every level past 1 also applies a named perk from TDData.TOWERS[..].levels,
## merged into a modifier dictionary that the accessors below read.

var game: Node = null
var type_id: String = "gun"
var cell: Vector2i = Vector2i.ZERO
## One purchased rank count per upgrade track in TDData.TOWERS[..].tracks.
var ranks: Array = []
var invested: int = 0

var cooldown: float = 0.0
var target: Enemy = null
var beam_targets: Array = []
var turret_angle: float = -PI * 0.5
var recoil: float = 0.0
var beam_on: bool = false
var beam_flicker: float = 0.0
var show_range: bool = false
## Which creep this tower prefers; cycled from the bottom bar or with T.
var target_mode: int = TDData.Target.FIRST
var units: Array = []
var pad_spin: float = 0.0
## Focus Laser: how long the beam has held the same creep.
var focus_time: float = 0.0
var field_pulse: float = 0.0
# Air-tower telemetry: sorties launched and aircraft recovered.
var kills: int = 0
var damage_dealt: float = 0.0
var sorties_flown: int = 0
var sorties_landed: int = 0

# Aura buffs from nearby Command Posts, refreshed periodically rather than
# every frame since support towers rarely change.
var buff_damage: float = 0.0
var buff_rate: float = 0.0
var buff_timer: float = 0.0
var support_pulse: float = 0.0


func setup(t: String, c: Vector2i) -> void:
	type_id = t
	cell = c
	invested = int(def()["cost"])
	# Towers start plain: the tech tree unlocks which ranks may be installed,
	# and gold installs them during the match. The developer cheat skips all
	# of that and hands over a finished tower.
	ranks.resize(TDData.tracks(t).size())
	ranks.fill(0)
	if Cheats.max_towers:
		max_out()


func def() -> Dictionary:
	return TDData.tower_def(type_id)


## Rebuilding the merged track mods meant a fresh dictionary several times
## per tower per frame. Ranks change only when something is installed, so
## the result is cached against a hash of them.
var _mods_cache: Dictionary = {}
var _mods_stamp: int = -1


func mods() -> Dictionary:
	# Tuning can rewrite what a rank does, so its version is part of the key.
	var stamp := ranks.hash() ^ (Tuning.version << 8)
	if stamp != _mods_stamp:
		_mods_stamp = stamp
		_mods_cache = TDData.mods_for(type_id, ranks)
	return _mods_cache


## Total ranks bought across all tracks; drives the level pips and the label.
func level() -> int:
	var total := 0
	for r in ranks:
		total += int(r)
	return total


## Base stat, this tower's own upgrade tracks, any Command Post aura, and
## finally the account-wide tech bought in the tech tree.
func stat(key: String) -> float:
	var value := float(def().get(key, 0.0)) * float(mods().get(key + "_mult", 1.0))
	if key == "damage":
		value *= 1.0 + buff_damage
		value *= Progress.bonus_mult("damage_mult")
		if is_air():
			value *= Progress.bonus_mult("air_damage_mult")
	elif key == "rate":
		value *= 1.0 + buff_rate
		value *= Progress.bonus_mult("rate_mult")
	elif key == "range":
		value *= Progress.bonus_mult("range_mult")
	return value


func min_range() -> float:
	return float(def().get("min_range", 0.0)) * float(mods().get("min_range_mult", 1.0))


func splash() -> float:
	return float(def()["splash"]) * float(mods().get("splash_mult", 1.0)) \
			* Progress.bonus_mult("splash_mult")


func slow_factor() -> float:
	var m := mods()
	var base := maxf(float(def()["slow"]) + float(m.get("slow_add", 0.0)),
			float(m.get("slow_set", 0.0)))
	return 0.0 if base <= 0.0 else minf(0.85, base + Progress.bonus_add("slow_add"))


func slow_duration() -> float:
	return float(def()["slow_dur"]) + float(mods().get("slow_dur_add", 0.0))


func burn() -> float:
	return float(def().get("burn", 0.0)) + float(mods().get("burn_add", 0.0))


func shots() -> int:
	return 1 + int(mods().get("shots_add", 0))


func chain() -> int:
	return int(def().get("chain", 1)) + int(mods().get("chain_add", 0))


func pierce_count() -> int:
	return int(def().get("pierce_count", 0)) + int(mods().get("pierce_add", 0))


func shatter() -> float:
	return maxf(1.0, float(mods().get("shatter", 1.0)))


func pierces() -> bool:
	return bool(def()["pierce_armor"]) or bool(mods().get("pierce", false))


func is_air() -> bool:
	return bool(def().get("air", false))


func is_support() -> bool:
	return bool(def().get("support", false))


## Slow field: hurts nothing, but everything inside it wades.
func is_field() -> bool:
	return bool(def().get("field", false))


## Pulses damage around itself instead of aiming.
func is_pulse() -> bool:
	return bool(def().get("pulse", false))


## Pays gold at the end of each wave instead of shooting.
func income() -> float:
	return float(def().get("income", 0.0)) * float(mods().get("income_mult", 1.0))


## Bolts fired per volley, each at its own target.
func volley() -> int:
	return int(def().get("volley", 1)) + int(mods().get("volley_add", 0))


## Peak damage multiplier once the beam has stayed on one creep.
func focus_peak() -> float:
	var base := float(def().get("focus", 1.0))
	return base + float(mods().get("focus_add", 0.0)) if base > 1.0 else 1.0


## Whether this tower can shoot at flyers at all. Roughly half the roster
## can, so an air wave forces a mixed defence instead of more of the same.
func hits_air() -> bool:
	return bool(def().get("hits_air", false)) or is_air()


func knockback() -> float:
	return float(def().get("knockback", 0.0)) + float(mods().get("knockback_add", 0.0))


func aura_damage() -> float:
	return float(def().get("aura_damage", 0.0)) + float(mods().get("aura_damage_add", 0.0))


func aura_rate() -> float:
	return float(def().get("aura_rate", 0.0)) + float(mods().get("aura_rate_add", 0.0))


func unit_count() -> int:
	return int(def().get("unit_count", 1)) + int(mods().get("unit_count_add", 0))


func unit_shots() -> int:
	return int(def().get("unit_shots", 1)) + int(mods().get("unit_shots_add", 0))


func unit_speed() -> float:
	return float(def().get("unit_speed", 240.0)) * float(mods().get("unit_speed_mult", 1.0))


# ------------------------------------------------------------------ upgrades

## Steps to the next targeting priority.
func cycle_target_mode() -> void:
	target_mode = (target_mode + 1) % TDData.TARGET_NAMES.size()


func target_mode_name() -> String:
	return str(TDData.TARGET_NAMES[target_mode])


func track_rank(track: int) -> int:
	return int(ranks[track])


## Rank of the track with this data key ("dmg", "rate", "range", ...), or 0.
func rank_of(key: String) -> int:
	var list: Array = TDData.tracks(type_id)
	for i in list.size():
		if str(list[i]["key"]) == key:
			return int(ranks[i])
	return 0


# --------------------------------------------------- upgrade appearance
# Every visible dimension of the tower comes from these, so buying a rank
# always changes the silhouette. dev_verify asserts exactly that.

## 0-3: how much armour plating the base has grown.
func plate_tier() -> int:
	var total := level()
	if total >= 9:
		return 3
	if total >= 6:
		return 2
	if total >= 3:
		return 1
	return 0


func barrel_length() -> float:
	return 26.0 + 3.4 * float(rank_of("range")) + 1.6 * float(rank_of("dmg")) \
			+ 1.2 * float(rank_of("pierce"))


func barrel_width() -> float:
	return 9.0 + 1.5 * float(rank_of("dmg")) + 1.3 * float(rank_of("blast"))


func muzzle_size() -> float:
	return 4.0 + 0.9 * float(rank_of("blast")) + 0.5 * float(rank_of("dmg")) \
			+ 0.8 * float(rank_of("burn"))


## Visible barrels: extra tubes from the twin-shot capstone and from the
## torpedo battery's spread tubes.
func barrel_count() -> int:
	return maxi(1, shots() + maxi(0, rank_of("pierce") if type_id == "torpedo" else 0))


## Size of the little module stud that marks each track's ranks on the rim.
func stud_size(track: int) -> float:
	var rank := track_rank(track)
	return 0.0 if rank <= 0 else 2.0 + 0.75 * float(rank)


## Compact description of everything the upgrades change visually.
func visual_signature() -> String:
	var parts: Array = ["p%d" % plate_tier(), "l%.1f" % barrel_length(),
			"w%.1f" % barrel_width(), "m%.1f" % muzzle_size(), "b%d" % barrel_count(),
			"u%d" % unit_count(), "s%d" % unit_shots(), "c%d" % chain()]
	for i in ranks.size():
		parts.append("t%d:%.1f" % [i, stud_size(i)])
	return " ".join(parts)


func track_max(track: int) -> int:
	return int(TDData.tracks(type_id)[track]["max"])


## A track opens once its own prerequisite rank is bought and the account is
## high enough; each tower therefore has a small tree of its own.
func track_open(track: int) -> bool:
	var need: Dictionary = TDData.track_requirement(type_id, track)
	if need.is_empty():
		return true
	var parent := TDData.track_index(type_id, str(need["track"]))
	return parent >= 0 and track_rank(parent) >= int(need["rank"])


## What still blocks this track: {"name": ..., "rank": ..., "have": ...} or {}.
func track_block(track: int) -> Dictionary:
	if track_open(track):
		return {}
	var need: Dictionary = TDData.track_requirement(type_id, track)
	var parent := TDData.track_index(type_id, str(need["track"]))
	return {"name": TDData.tracks(type_id)[parent]["name"], "rank": int(need["rank"]),
		"have": track_rank(parent)}


## Highest rank the account has unlocked for this track in the tech tree.
func track_cap(track: int) -> int:
	return mini(track_max(track), Progress.track_rank_for(type_id, track))


## Gold price of the next rank on this tower.
func track_cost(track: int) -> int:
	return TDData.track_gold_cost(type_id, track, track_rank(track))


## Installable right now: unlocked in the tech tree, prerequisite met, and not
## already at the ceiling.
func can_upgrade_track(track: int) -> bool:
	return track_rank(track) < track_cap(track) and track_open(track)


func can_upgrade() -> bool:
	for i in ranks.size():
		if can_upgrade_track(i):
			return true
	return false


## Cheapest installable track, used by the quick-upgrade key.
func cheapest_track() -> int:
	var best := -1
	var best_cost := 1 << 30
	for i in ranks.size():
		if can_upgrade_track(i) and track_cost(i) < best_cost:
			best_cost = track_cost(i)
			best = i
	return best


## Installs every rank on this tower, ignoring unlocks and gold. Returns the
## number of ranks added; used by the developer cheat.
func max_out() -> int:
	var added := 0
	for i in ranks.size():
		var top := track_max(i)
		added += top - track_rank(i)
		ranks[i] = top
	queue_redraw()
	return added


func upgrade_track(track: int) -> void:
	invested += track_cost(track)
	ranks[track] = track_rank(track) + 1
	queue_redraw()


func sell_value() -> int:
	return int(float(invested) * (0.7 + Progress.bonus_add("sell_refund_add")))


## Rebuilding a tower's ~35 draw commands every frame is what the machine was
## actually spending its time on: 150 towers came to 5,900 commands a frame
## and 50 ms of script. Nothing about a tower changes most frames, so a
## redraw is asked for only when something visible moved.
const REDRAW_ANGLE := 0.012
## Idle animations (support rings, mine glow, tar bubbles) run at this many
## frames a second instead of the full rate. Nobody can see the difference.
const IDLE_REDRAW_HZ := 12.0

var _drawn_angle: float = -99.0
var _drawn_recoil: float = -1.0
var _drawn_beam: bool = false
var _drawn_targets: int = -1
var _idle_clock: float = 0.0


## True when enough has changed on screen to be worth rebuilding the art.
func _needs_redraw() -> bool:
	if beam_on != _drawn_beam or beam_targets.size() != _drawn_targets:
		return true
	if absf(angle_difference(turret_angle, _drawn_angle)) > REDRAW_ANGLE:
		return true
	# Recoil has to settle back to zero exactly, or the barrel sticks out.
	return absf(recoil - _drawn_recoil) > 0.01


func _redraw_if_changed() -> void:
	if not _needs_redraw():
		return
	_drawn_angle = turret_angle
	_drawn_recoil = recoil
	_drawn_beam = beam_on
	_drawn_targets = beam_targets.size()
	queue_redraw()


## Animations that never stop still redraw, just not sixty times a second.
func _redraw_idle(delta: float) -> void:
	_idle_clock += delta
	if _idle_clock >= 1.0 / IDLE_REDRAW_HZ:
		_idle_clock = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	buff_timer -= delta
	if buff_timer <= 0.0:
		buff_timer = 0.4
		if is_support():
			buff_damage = 0.0
			buff_rate = 0.0
		else:
			var aura: Dictionary = game.aura_at(position)
			buff_damage = float(aura["damage"])
			buff_rate = float(aura["rate"])

	if is_support():
		support_pulse += delta
		_redraw_idle(delta)
		return

	if income() > 0.0:
		# Mines just sit there and pay out when the wave ends.
		support_pulse += delta
		_redraw_idle(delta)
		return

	if is_field():
		_process_field(delta)
		_redraw_idle(delta)
		return

	if is_pulse():
		_process_pulse(delta)
		_redraw_idle(delta)
		return

	if is_air():
		_process_air(delta)
		_redraw_idle(delta)
		return

	var rng := stat("range")
	var min_rng := min_range()
	if target != null and (not is_instance_valid(target) or target.dead
			or position.distance_to(target.position) > rng + 8.0
			or position.distance_to(target.position) < min_rng):
		target = null
	if target == null:
		# Losing the target resets a focusing beam's ramp.
		focus_time = 0.0
		target = game.find_target(position, rng, min_rng, target_mode, hits_air())

	beam_on = false
	beam_targets.clear()
	if target != null:
		var desired := (target.position - position).angle()
		turret_angle = lerp_angle(turret_angle, desired, minf(1.0, delta * 14.0))
		if bool(def()["beam"]):
			_process_beam(delta, rng)
		else:
			cooldown -= delta
			if cooldown <= 0.0 and absf(angle_difference(turret_angle, desired)) < 0.45:
				if volley() > 1:
					_fire_volley()
				else:
					for i in shots():
						_shoot(float(i) * 0.06)
				cooldown = 1.0 / maxf(0.05, stat("rate"))
	else:
		cooldown = maxf(0.0, cooldown - delta)
	recoil = maxf(0.0, recoil - delta * 7.0)
	_redraw_if_changed()


## Slow field: everything in range is kept slowed while it stands here.
func _process_field(delta: float) -> void:
	field_pulse += delta
	var rng := stat("range")
	for e: Enemy in game.find_targets(position, rng, 64, 0.0, target_mode, hits_air()):
		if is_instance_valid(e) and not e.dead:
			e.apply_slow(slow_factor(), maxf(0.25, slow_duration()))


## Shockwave: slams the ground on a timer, no target needed.
func _process_pulse(delta: float) -> void:
	cooldown -= delta
	if cooldown > 0.0:
		return
	cooldown = 1.0 / maxf(0.05, stat("rate"))
	recoil = 1.0
	var hit: Array = game.find_targets(position, stat("range"), 64, 0.0, target_mode,
			hits_air())
	if hit.is_empty():
		cooldown = 0.25
		return
	Audio.play("shot_cannon", -10.0)
	game.explode(position, splash(), stat("damage"), def()["color"], slow_factor(),
			slow_duration(), pierces(), shatter(), self, 0.0, hits_air())


func _process_beam(delta: float, rng: float) -> void:
	beam_on = true
	beam_flicker += delta * 30.0
	Audio.beam_active(1)
	beam_targets = game.find_targets(position, rng, chain(), min_range(), target_mode,
			hits_air())
	# A focusing beam ramps up while it stays on the same creep.
	var ramp := 1.0
	if focus_peak() > 1.0:
		focus_time = minf(focus_time + delta, float(def().get("focus_time", 3.0)))
		ramp = lerpf(1.0, focus_peak(),
				focus_time / maxf(0.1, float(def().get("focus_time", 3.0))))
	var dps := stat("damage") * ramp * delta
	var burn_dps := burn()
	for e: Enemy in beam_targets:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(dps, pierces(), self)
			if burn_dps > 0.0 and is_instance_valid(e) and not e.dead:
				e.apply_burn(burn_dps, 2.5, self)
	if randf() < delta * 5.0 and is_instance_valid(target):
		game.fx_spark(target.position, def()["color"])


## Air towers keep a small squadron: whenever a slot is free, the cooldown is
## up and something is worth attacking, another aircraft takes off.
func _process_air(delta: float) -> void:
	pad_spin += delta * 2.0
	for i in range(units.size() - 1, -1, -1):
		if not is_instance_valid(units[i]):
			units.remove_at(i)
	cooldown = maxf(0.0, cooldown - delta)
	if units.size() >= unit_count() or cooldown > 0.0:
		return
	var prey: Enemy = game.find_target(position, stat("range"), min_range(), target_mode,
			hits_air())
	if prey == null:
		return
	var craft := Aircraft.new()
	craft.game = game
	craft.tower = self
	craft.kind = str(def()["unit"])
	craft.color = def()["color"]
	craft.speed = unit_speed()
	craft.damage = stat("damage")
	craft.splash = splash()
	craft.shots = unit_shots()
	craft.pierce_armor = pierces()
	craft.op_range = stat("range")
	craft.pad = position
	craft.target_mode = target_mode
	craft.position = position
	craft.target = prey
	game.layer_air.add_child(craft)
	units.append(craft)
	sorties_flown += 1
	Audio.play("shot_light", -12.0)
	cooldown = 1.0 / maxf(0.02, stat("rate"))


## Fires one bolt at each of several creeps at once.
func _fire_volley() -> void:
	var picks: Array = game.find_targets(position, stat("range"), volley(), min_range(),
			target_mode, hits_air())
	var keep := target
	for e: Enemy in picks:
		target = e
		_shoot(0.0)
	target = keep


## Which firing sample suits this tower, and how loud it should sit.
func _shot_sound() -> String:
	if splash() >= 40.0:
		return "shot_cannon"
	if float(def()["damage"]) >= 40.0:
		return "shot_cannon"
	if float(def()["proj_speed"]) >= 600.0:
		return "shot_light"
	return "shot_gun"


func _shot_volume() -> float:
	return -8.0 if shots() > 1 or volley() > 1 else -6.0


func _shoot(delay: float) -> void:
	if not is_instance_valid(target):
		return
	var p := Projectile.new()
	p.game = game
	p.target = target
	p.dest = target.position
	p.damage = stat("damage")
	p.speed = float(def()["proj_speed"])
	p.splash = splash()
	p.slow = slow_factor()
	p.slow_dur = slow_duration()
	p.pierce_armor = pierces()
	p.knockback = knockback()
	p.shatter = shatter()
	p.cluster = int(mods().get("cluster", 0))
	p.pierce_count = pierce_count()
	p.burn = burn()
	p.max_travel = stat("range") * 1.35
	p.color = def()["color"]
	p.source = self
	p.hits_air = hits_air()
	p.radius = 3.0 + splash() * 0.06
	var spread := (randf() - 0.5) * 0.12 if shots() > 1 else 0.0
	p.position = position + Vector2(20.0 - delay * 60.0, 0.0).rotated(turret_angle + spread)
	p.rotation = turret_angle + spread
	game.layer_proj.add_child(p)
	recoil = 1.0
	game.fx_spark(p.position, def()["color"])
	Audio.play(_shot_sound(), _shot_volume())


func _draw() -> void:
	var col: Color = def()["color"]
	var rng := stat("range")

	if show_range:
		draw_circle(Vector2.ZERO, rng, Color(col.r, col.g, col.b, 0.08))
		draw_arc(Vector2.ZERO, rng, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.55), 1.5, true)
		var dead := min_range()
		if dead > 0.0:
			draw_circle(Vector2.ZERO, dead, Color(0.9, 0.3, 0.3, 0.10))
			draw_arc(Vector2.ZERO, dead, 0.0, TAU, 40, Color(0.95, 0.4, 0.4, 0.5), 1.5, true)

	if beam_on:
		var muzzle := Vector2(20.0, 0.0).rotated(turret_angle)
		for e: Enemy in beam_targets:
			if not is_instance_valid(e):
				continue
			var tip := to_local(e.position)
			var jitter := sin(beam_flicker + tip.x) * 3.0
			var mid := (muzzle + tip) * 0.5 + (tip - muzzle).orthogonal().normalized() * jitter
			draw_polyline([muzzle, mid, tip], Color(col.r, col.g, col.b, 0.25), 9.0, true)
			draw_polyline([muzzle, mid, tip], Color(1, 1, 1, 0.9), 2.0, true)

	if not Art.draw_centered(self, "tower_" + type_id + "_base", Vector2.ZERO, 56.0):
		_draw_base(col)

	if is_air():
		_draw_pad(col)
	elif is_support():
		_draw_support(col)
	elif is_field():
		_draw_field(col)
	elif income() > 0.0:
		_draw_mine(col)
	elif is_pulse():
		_draw_pulse(col)
	else:
		_draw_turret(col)
	_draw_studs(col)




func _draw_base(col: Color) -> void:
	draw_circle(Vector2(0.0, 3.0), 22.0, Color(0, 0, 0, 0.3))
	_draw_plating(col)
	if int(def()["terrain"]) == TDData.Terrain.WATER:
		# Water towers read as a platform on stilts.
		draw_rect(Rect2(-21.0, -21.0, 42.0, 42.0), Color("22333d"))
		draw_rect(Rect2(-21.0, -21.0, 42.0, 42.0), col.darkened(0.35), false, 2.5)
		for i in 4:
			var p := Vector2(-13.0 + 8.66 * float(i), -13.0 + 8.66 * float(i))
			draw_line(Vector2(-19.0, p.y), Vector2(19.0, p.y), Color(1, 1, 1, 0.05), 1.0)
	elif is_air():
		draw_rect(Rect2(-22.0, -22.0, 44.0, 44.0), Color("2b3446"))
		draw_rect(Rect2(-22.0, -22.0, 44.0, 44.0), col.darkened(0.4), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, 22.0, Color("2b3446"))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 26, col.darkened(0.35), 2.5, true)
		draw_circle(Vector2.ZERO, 15.0, Color("3c4a63"))


## Upgraded towers grow a reinforced footing: a plate, then bolts, then an
## outer ring, so investment reads at a glance.
func _draw_plating(col: Color) -> void:
	var tier := plate_tier()
	if tier <= 0:
		return
	var plate := PackedVector2Array()
	for i in 8:
		plate.append(Vector2.RIGHT.rotated(TAU * float(i) / 8.0 + PI / 8.0) * 25.0)
	draw_colored_polygon(plate, Color(0.16, 0.19, 0.25, 0.9))
	draw_polyline(plate + PackedVector2Array([plate[0]]),
			Color(col.r, col.g, col.b, 0.5), 1.5, true)
	if tier >= 2:
		for i in 4:
			draw_circle(Vector2.RIGHT.rotated(TAU * float(i) / 4.0 + PI / 4.0) * 21.0,
					2.0, Color(0.75, 0.78, 0.85, 0.8))
	if tier >= 3:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.55), 2.0, true)


## One stud per upgrade track, growing with that track's rank.
func _draw_studs(col: Color) -> void:
	var n := ranks.size()
	for i in n:
		var r := stud_size(i)
		if r <= 0.0:
			continue
		var at := Vector2.RIGHT.rotated(PI * 0.35 + TAU * float(i) / float(maxi(n, 1))) * 24.0
		draw_circle(at, r + 1.0, Color(0.05, 0.07, 0.1, 0.8))
		draw_circle(at, r, col.lightened(0.15 * float(track_rank(i))))


func _draw_turret(col: Color) -> void:
	var back := -recoil * 4.0
	if Art.draw_centered(self, "tower_" + type_id + "_gun",
			Vector2(back, 0.0).rotated(turret_angle), 46.0, turret_angle):
		return
	draw_set_transform(Vector2.ZERO, turret_angle, Vector2.ONE)
	var length := barrel_length()
	var width := barrel_width()
	var muzzle := muzzle_size()
	var tubes := barrel_count()
	var fins := rank_of("rate")
	match type_id:
		"cannon":
			draw_rect(Rect2(2.0 + back, -width * 0.75, length * 0.85, width * 1.5),
					col.darkened(0.2))
			draw_rect(Rect2(length * 0.85 + back, -width * 0.9, 5.0, width * 1.8), col)
			for i in rank_of("blast"):
				draw_arc(Vector2(length * 0.85 + back, 0.0), muzzle + 2.0 * float(i),
						-1.1, 1.1, 10, Color(col.r, col.g, col.b, 0.35), 1.5, true)
		"frost":
			draw_rect(Rect2(2.0 + back, -width * 0.45, length * 0.7, width * 0.9),
					col.darkened(0.15))
			draw_circle(Vector2(length * 0.8 + back, 0.0), muzzle + 1.5, col.lightened(0.3))
			for i in rank_of("slow"):
				var ang := -0.9 + 0.6 * float(i)
				draw_line(Vector2(10.0, 0.0), Vector2(10.0, 0.0)
						+ Vector2.RIGHT.rotated(ang) * (6.0 + 1.5 * float(i)),
						Color(0.75, 0.93, 1.0, 0.8), 2.0, true)
		"tesla":
			draw_rect(Rect2(0.0 + back, -width * 0.33, length * 0.6, width * 0.66),
					col.darkened(0.2))
			for i in chain():
				draw_arc(Vector2(length * 0.72 + back, 0.0), muzzle + 3.0 + 2.5 * float(i),
						-1.2, 1.2, 12, col.lightened(0.4), 2.5, true)
		"ballista":
			for i in maxi(2, tubes):
				var y := (float(i) - float(maxi(2, tubes) - 1) * 0.5) * (width * 0.7)
				draw_rect(Rect2(2.0 + back, y - 1.8, length * 0.95, 3.6), col.darkened(0.2))
				draw_circle(Vector2(length * 0.95 + back, y), 2.4, col.lightened(0.3))
			draw_arc(Vector2(6.0 + back, 0.0), width * 0.9, -1.3, 1.3, 12, col.darkened(0.35),
					3.0, true)
		"laser":
			draw_rect(Rect2(2.0 + back, -width * 0.35, length * 0.75, width * 0.7),
					col.darkened(0.25))
			var lens := muzzle + 1.5
			draw_circle(Vector2(length * 0.8 + back, 0.0), lens, col.lightened(0.35))
			draw_circle(Vector2(length * 0.8 + back, 0.0), lens * 0.5, Color(1, 1, 1, 0.8))
			for i in rank_of("focus"):
				draw_arc(Vector2(length * 0.8 + back, 0.0), lens + 3.0 + 2.5 * float(i),
						-0.8, 0.8, 8, Color(col.r, col.g, col.b, 0.5), 1.5, true)
		"wavegun":
			draw_rect(Rect2(2.0 + back, -width * 0.6, length * 0.7, width * 1.2),
					col.darkened(0.25))
			for i in 3:
				draw_arc(Vector2(length * 0.75 + back, 0.0), muzzle + 3.0 + 4.0 * float(i),
						-1.0, 1.0, 10, Color(col.r, col.g, col.b, 0.55 - 0.12 * float(i)),
						2.5, true)
		"tide":
			draw_rect(Rect2(2.0 + back, -width * 0.55, length * 0.8, width * 1.1),
					col.darkened(0.25))
			draw_circle(Vector2(length * 0.9 + back, 0.0), muzzle + 1.0, col.lightened(0.2))
			draw_arc(Vector2(length * 0.9 + back, 0.0), muzzle + 4.0, -0.9, 0.9, 10,
					Color(1, 1, 1, 0.35), 2.0, true)
		"marksman":
			draw_rect(Rect2(2.0 + back, -width * 0.3, length * 1.15, width * 0.6),
					col.darkened(0.2))
			draw_circle(Vector2(9.0 + back, 0.0), width * 0.62, col.darkened(0.35))
			draw_line(Vector2(14.0 + back, -width * 0.75),
					Vector2(14.0 + length * 0.35 + back, -width * 0.75),
					Color(1, 1, 1, 0.4), 1.5)
			for i in maxi(0, tubes - 1):
				draw_rect(Rect2(2.0 + back, width * 0.45 + 3.0 * float(i), length * 0.9,
						width * 0.3), col.darkened(0.3))
		"flame":
			draw_rect(Rect2(2.0 + back, -width * 0.5, length * 0.55, width),
					col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([
					Vector2(length * 0.55 + back, -muzzle - 2.0),
					Vector2(length * 0.55 + muzzle + 8.0 + back, 0.0),
					Vector2(length * 0.55 + back, muzzle + 2.0)]), col)
			for i in rank_of("burn"):
				draw_circle(Vector2(8.0 + back, -width * 0.8 - 3.0 * float(i)), 3.0,
						col.darkened(0.1))
		"mortar":
			draw_rect(Rect2(-2.0 + back, -width * 0.9, length * 0.62, width * 1.8),
					col.darkened(0.3))
			draw_circle(Vector2(length * 0.7 + back, 0.0), muzzle + 4.0, col.darkened(0.1))
			draw_circle(Vector2(length * 0.7 + back, 0.0), muzzle, Color("1a1512"))
			for i in rank_of("range"):
				draw_circle(Vector2(-8.0 - 3.0 * float(i) + back, 0.0), 2.2,
						Color(1, 1, 1, 0.35))
		"torpedo":
			for i in tubes:
				var offset := -width * 0.55 + width * 1.1 * float(i) / float(maxi(1, tubes - 1)) \
						if tubes > 1 else 0.0
				draw_rect(Rect2(2.0 + back, offset - 2.5, length * 0.85, 5.0),
						col.darkened(0.2))
				draw_circle(Vector2(length * 0.85 + back, offset), 3.0, col.lightened(0.3))
		_:
			for i in tubes:
				var y := (float(i) - float(tubes - 1) * 0.5) * (width * 0.55)
				draw_rect(Rect2(2.0 + back, y - width * 0.22, length, width * 0.44),
						col.darkened(0.15))
				draw_rect(Rect2(length + back, y - muzzle * 0.35, 4.0, muzzle * 0.7), col)
			for i in fins:
				var fx := 8.0 + 4.0 * float(i) + back
				draw_line(Vector2(fx, -width * 0.6), Vector2(fx, width * 0.6),
						Color(1, 1, 1, 0.25), 1.5)
	var hub := 8.0 + 0.4 * float(level())
	draw_circle(Vector2.ZERO, hub, col)
	draw_circle(Vector2.ZERO, hub * 0.62, col.lightened(0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Airfields show a runway, helipads a marked circle; parked aircraft appear
## whenever a slot is idle so the pad reads as "loaded" or "flying".
func _draw_pad(col: Color) -> void:
	var idle: int = unit_count() - units.size()
	if type_id == "airfield":
		# Runway with dashed centre line and threshold bars.
		draw_rect(Rect2(-20.0, -9.0, 40.0, 18.0), Color("1c2431"))
		for i in 5:
			draw_line(Vector2(-15.0 + 7.5 * float(i), 0.0),
					Vector2(-11.0 + 7.5 * float(i), 0.0), Color(1, 1, 1, 0.4), 1.5)
		for sx: float in [-18.0, 18.0]:
			draw_line(Vector2(sx, -7.0), Vector2(sx, 7.0), Color(1, 1, 1, 0.25), 2.0)
		# One bomb dot per Bomb Racks rank, and a wider apron once a second
		# bomber is stationed here.
		for i in unit_shots():
			draw_circle(Vector2(-14.0 + 6.0 * float(i), 13.0), 2.2, col.darkened(0.1))
		if unit_count() > 1:
			draw_rect(Rect2(-22.0, -19.0, 44.0, 38.0), Color(col.r, col.g, col.b, 0.35),
					false, 1.5)
		if idle > 0:
			for i in mini(idle, 2):
				_draw_plane_icon(Vector2(0.0, -6.0 + 12.0 * float(i)), col, 0.55)
	else:
		# Helipad circle with a drawn H, plus a corner beacon.
		draw_circle(Vector2.ZERO, 16.0, Color("1c2431"))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 26, Color(1, 1, 1, 0.35), 2.0, true)
		draw_line(Vector2(-6.0, -7.0), Vector2(-6.0, 7.0), Color(1, 1, 1, 0.45), 2.5)
		draw_line(Vector2(6.0, -7.0), Vector2(6.0, 7.0), Color(1, 1, 1, 0.45), 2.5)
		draw_line(Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Color(1, 1, 1, 0.45), 2.5)
		draw_circle(Vector2(17.0, -17.0), 2.6,
				Color(1.0, 0.4, 0.3, 0.5 + 0.5 * sin(pad_spin * 3.0)))
		# Ammo boxes stack up with Ammo Belts; a second ring marks the escort.
		for i in int(ceilf(float(unit_shots() - 14) / 5.0)):
			draw_rect(Rect2(-20.0 + 5.0 * float(i), 12.0, 4.0, 6.0), col.darkened(0.15))
		if unit_count() > 1:
			draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.4),
					1.5, true)
		if idle > 0:
			for i in mini(idle, 2):
				_draw_heli_icon(Vector2(0.0, -5.0 + 10.0 * float(i)), col, 0.55,
						pad_spin * 3.0)


## Tar pits bubble; the ring shows how far the sludge reaches.
func _draw_field(col: Color) -> void:
	var rng := stat("range")
	draw_circle(Vector2.ZERO, rng, Color(col.r, col.g, col.b, 0.10))
	draw_arc(Vector2.ZERO, rng, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.4), 2.0, true)
	draw_circle(Vector2.ZERO, 18.0, col.darkened(0.45))
	for i in 4:
		var phase := fposmod(field_pulse * 0.7 + float(i) * 0.25, 1.0)
		draw_circle(Vector2.RIGHT.rotated(float(i) * 1.9 + field_pulse * 0.4) * 9.0 * phase,
				2.0 + 2.5 * (1.0 - phase), Color(col.r, col.g, col.b, 0.7 * (1.0 - phase)))


## Gold mines show a headframe and a slowly filling ore pile.
func _draw_mine(col: Color) -> void:
	draw_circle(Vector2.ZERO, 17.0, Color("2a2418"))
	draw_line(Vector2(-11.0, 10.0), Vector2(0.0, -14.0), col.darkened(0.3), 3.0)
	draw_line(Vector2(11.0, 10.0), Vector2(0.0, -14.0), col.darkened(0.3), 3.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), col.darkened(0.2), 2.0)
	var heap: int = 3 + rank_of("income")
	for i in heap:
		var ang := TAU * float(i) / float(heap) + support_pulse * 0.3
		draw_circle(Vector2.RIGHT.rotated(ang) * 10.0, 2.6, col)


## Shockwave towers show the ring they will slam next.
func _draw_pulse(col: Color) -> void:
	var ready: float = 1.0 - clampf(cooldown * maxf(0.05, stat("rate")), 0.0, 1.0)
	draw_arc(Vector2.ZERO, splash(), 0.0, TAU, 44, Color(col.r, col.g, col.b, 0.16), 2.0, true)
	draw_arc(Vector2.ZERO, splash() * ready, 0.0, TAU, 40,
			Color(col.r, col.g, col.b, 0.45), 3.0, true)
	draw_circle(Vector2.ZERO, 16.0 - 3.0 * recoil, Color("263a38"))
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 22, col, 2.5, true)
	draw_circle(Vector2.ZERO, 7.0 + 3.0 * ready, col.lightened(0.2))


## Command Posts show a rotating radar sweep and a soft aura ring.
func _draw_support(col: Color) -> void:
	var r := stat("range")
	var sweep := support_pulse * 1.6
	draw_arc(Vector2.ZERO, r, sweep, sweep + 0.9, 20, Color(col.r, col.g, col.b, 0.16), 6.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.12), 1.5, true)
	var dish := 12.0 + 1.2 * float(rank_of("range"))
	draw_circle(Vector2.ZERO, dish, Color("38414f"))
	draw_arc(Vector2.ZERO, dish, 0.0, TAU, 20, col.darkened(0.2), 2.0, true)
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(sweep) * (dish + 3.0), col, 2.5, true)
	# An antenna mast per aura rank.
	var masts := rank_of("aura_dmg") + rank_of("aura_rate")
	for i in masts:
		var ang := -PI * 0.5 + (float(i) - float(masts - 1) * 0.5) * 0.5
		var base_pt := Vector2.RIGHT.rotated(ang) * 15.0
		draw_line(base_pt, base_pt + Vector2.RIGHT.rotated(ang) * 8.0,
				Color(0.85, 0.88, 0.95, 0.7), 1.5, true)
		draw_circle(base_pt + Vector2.RIGHT.rotated(ang) * 9.0, 1.8, col)
	draw_circle(Vector2(0.0, -18.0), 3.0, Color(1.0, 0.85, 0.4,
			0.4 + 0.6 * absf(sin(support_pulse * 2.0))))


func _draw_plane_icon(pos: Vector2, col: Color, scale: float) -> void:
	draw_set_transform(pos, -PI * 0.5, Vector2(scale, scale))
	draw_colored_polygon(PackedVector2Array([Vector2(16.0, 0.0), Vector2(-10.0, 7.0),
			Vector2(-10.0, -7.0)]), col)
	draw_rect(Rect2(-4.0, -14.0, 7.0, 28.0), col.darkened(0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_heli_icon(pos: Vector2, col: Color, scale: float, spin: float) -> void:
	draw_set_transform(pos, -PI * 0.5, Vector2(scale, scale))
	draw_rect(Rect2(-14.0, -3.0, 26.0, 6.0), col.darkened(0.3))
	draw_circle(Vector2(6.0, 0.0), 7.0, col)
	draw_set_transform(pos, spin, Vector2(scale, scale))
	draw_line(Vector2(-16.0, 0.0), Vector2(16.0, 0.0), Color(1, 1, 1, 0.5), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
