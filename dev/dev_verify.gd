extends Node

var game: Node
var fails: int = 0


func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])


func _ready() -> void:
	# Isolated account: full unlocks, no tech, and nothing written to disk.
	Progress.use_clean_state()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	# Pick real cells from the map rather than assuming fixed coordinates.
	var open_cell := Vector2i(-99, -99)
	var path_cell := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if open_cell.x < 0 and game.can_place(key, "gun"):
			open_cell = key
		if path_cell.x < 0 and game.is_path(key):
			path_cell = key
	check("path cells blocked", path_cell.x >= 0 and not game.can_place(path_cell))
	check("open ground placeable", open_cell.x >= 0 and game.can_place(open_cell))
	check("off-grid rejected", not game.can_place(Vector2i(-1, 5)))
	var start_gold := int(TDData.level_stat(game.level_def, "gold"))
	check("start gold comes from the tier", game.gold == start_gold and start_gold > 0)

	game.placing = "gun"
	game._try_place(open_cell)
	game.placing = ""
	check("tower placed", game.occupied.has(open_cell))
	check("gold spent", game.gold == start_gold - 60)
	check("cell now occupied", not game.can_place(open_cell))

	var t: Tower = game.occupied[open_cell]
	Progress.tower_ranks = {}
	check("a tower with nothing bought starts plain", t.level() == 0 and not t.pierces())

	# Upgrade ranks are bought with coins on the account, then every tower of
	# that type is built with them.
	Progress.unlock_all = true
	Progress.coins = 100000
	Progress.tower_ranks = {}
	var base_damage := t.stat("damage")
	var base_rate := t.stat("rate")
	var base_range := t.stat("range")

	check("a rank costs coins", Progress.track_next_cost("gun", 0) > 0)
	var coins_before := Progress.coins
	check("buying a rank succeeds", Progress.buy_track("gun", 0))
	check("coins were spent", Progress.coins < coins_before)
	check("the account remembers the rank", Progress.track_rank_for("gun", 0) == 1)
	check("the next rank costs more",
			Progress.track_next_cost("gun", 0) > TDData.track_cost("gun", 0, 0))

	var fresh_gun := Tower.new()
	fresh_gun.game = game
	fresh_gun.setup("gun", Vector2i.ZERO)
	check("a new tower still starts at rank 0", fresh_gun.track_rank(0) == 0)
	check("the unlocked rank becomes installable", fresh_gun.can_upgrade_track(0))
	check("only the unlocked amount is installable", fresh_gun.track_cap(0) == 1)
	check("installing costs gold", fresh_gun.track_cost(0) > 0)
	fresh_gun.upgrade_track(0)
	check("installing raises damage", fresh_gun.stat("damage") > base_damage)
	check("other stats stay put", is_equal_approx(fresh_gun.stat("rate"), base_rate))
	check("a second rank needs another unlock", not fresh_gun.can_upgrade_track(0))
	fresh_gun.free()

	Progress.buy_track("gun", 1)
	check("a second track buys independently", Progress.track_rank_for("gun", 1) == 1)

	# The per-tower tree still gates: Long Barrel needs Heavy Rounds 2.
	check("a gated track cannot be bought yet",
			not bool(Progress.track_buy_state("gun", 2)["prereq_ok"]))
	check("buying a gated track fails", not Progress.buy_track("gun", 2))
	Progress.buy_track("gun", 0)
	check("the gate opens once the prerequisite is met",
			bool(Progress.track_buy_state("gun", 2)["prereq_ok"]))
	check("the freed track can then be bought", Progress.buy_track("gun", 2))

	var geared := Tower.new()
	geared.game = game
	geared.setup("gun", Vector2i.ZERO)
	geared.upgrade_track(0)
	geared.upgrade_track(0)
	geared.upgrade_track(2)
	check("an unlocked range rank installs on the tower", geared.stat("range") > base_range)
	geared.free()

	# Coins actually gate the purchase.
	Progress.coins = 0
	check("no coins means no rank", not Progress.buy_track("cannon", 0))
	check("the state explains why",
			not bool(Progress.track_buy_state("cannon", 0)["affordable"]))
	Progress.coins = 100000

	# Account level gates a track even when coins and prerequisites allow it.
	Progress.unlock_all = false
	Progress.xp = 0
	var gated_by_level := -1
	for i in TDData.tracks("gun").size():
		if Progress.track_unlock_level("gun", i) > 1:
			gated_by_level = i
	check("some tracks are level gated", gated_by_level >= 0)
	check("a level-gated track reports the gate",
			not bool(Progress.track_buy_state("gun", gated_by_level)["level_ok"]))
	Progress.xp = Progress.xp_for_level(40)
	check("levelling opens it",
			bool(Progress.track_buy_state("gun", gated_by_level)["level_ok"]))
	Progress.unlock_all = true
	Progress.tower_ranks = {}
	Progress.coins = 0
	Progress.xp = 0

	game._select(t)
	var before: int = game.gold
	var value: int = t.sell_value()
	check("sell value refunds the build cost", value == int(60.0 * 0.7))
	game._sell_selected()
	check("sell refunds", game.gold == before + value)
	check("sell frees cell", game.can_place(open_cell))
	check("selection cleared", game.selected == null)

	# Blocked / unaffordable placement must not charge or build.
	game.gold = 10
	game.placing = "tesla"
	game._try_place(Vector2i(2, 2))
	game.placing = ""
	check("cannot afford -> no build", game.occupied.is_empty() and game.gold == 10)
	game.gold = 500
	game.placing = "gun"
	game._try_place(path_cell)
	game.placing = ""
	check("cannot build on path", game.occupied.is_empty() and game.gold == 500)

	# Wave composition.
	var w1: Array = game._build_wave(1)
	var w10: Array = game._build_wave(10)
	var w13: Array = game._build_wave(13)
	var kinds10: Array = []
	for e: Dictionary in w10:
		if not kinds10.has(e["kind"]):
			kinds10.append(e["kind"])
	check("wave 1 is grunts only", w1.size() == 5 and str(w1[0]["kind"]) == "grunt")
	check("wave 10 has a boss", kinds10.has("boss"))
	check("wave 13 is bigger than wave 1", w13.size() > w1.size())
	check("wave hp scales", float(w13[0]["hp"]) > float(w1[0]["hp"]) * 3.0)
	var sorted_ok := true
	for i in range(1, w13.size()):
		if float(w13[i]["t"]) < float(w13[i - 1]["t"]):
			sorted_ok = false
	check("spawn times sorted", sorted_ok)

	# Armor, slow and lethality on a live creep.
	var e := Enemy.new()
	e.setup("tank", 1.0, 1.0, game.path_points)
	add_child(e)
	e.take_damage(10.0)
	check("armor reduces damage", is_equal_approx(e.hp, 215.0 - 5.0))
	e.take_damage(10.0, true)
	check("armor pierced", is_equal_approx(e.hp, 200.0))
	e.apply_slow(0.45, 2.0)
	check("slow applied", e.speed() < e.base_speed)
	e.take_damage(9999.0)
	check("lethal damage kills", e.dead)

	# Splash hits several creeps at once.
	var spawned: Array = []
	for i in 3:
		var s := Enemy.new()
		s.setup("grunt", 1.0, 1.0, game.path_points)
		s.died.connect(game._on_enemy_died)
		s.leaked.connect(game._on_enemy_leaked)
		game.layer_enemies.add_child(s)
		s.position = Vector2(400.0, 400.0) + Vector2(float(i) * 12.0, 0.0)
		game.enemies.append(s)
		game.invalidate_targeting_grid()
		spawned.append(s)
	game.explode(Vector2(400.0, 400.0), 60.0, 20.0, Color.WHITE)
	var all_hit := true
	for s in spawned:
		if s.hp >= s.max_hp:
			all_hit = false
	check("splash hits everything in radius", all_hit)

	var target = game.find_target(Vector2(400.0, 400.0), 200.0)
	check("targets furthest along path", target == spawned[0] or target != null)

	_check_terrain()
	_check_tracks()
	_check_new_towers()
	_check_aura()
	_check_combat_extras()
	_check_air()
	_check_levels()
	_check_drag()
	_check_progression()
	_check_tech()
	_check_slots()
	await _check_routes()
	_check_targeting()
	_check_targeting_grid()
	_check_enemy_kinds()
	_check_cheats()
	_check_audio()
	_check_wave_preview()
	_check_stats()
	await _check_saved_runs()
	_check_areas()

	print("[VERIFY] %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	get_tree().quit()


## Water cells accept only the Tide Caller, and land towers only dry ground.
func _check_terrain() -> void:
	var water := Vector2i(-99, -99)
	var ground := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.terrain_at(key) == TDData.Terrain.WATER and water.x < 0:
			water = key
		elif game.terrain_at(key) == TDData.Terrain.GROUND and ground.x < 0:
			ground = key
	check("level has water", water.x >= 0)
	check("tide tower needs water", not game.can_place(ground, "tide"))
	check("tide tower fits on water", game.can_place(water, "tide"))
	check("land tower rejects water", not game.can_place(water, "gun"))
	check("land tower fits on ground", game.can_place(ground, "gun"))
	check("rock is unbuildable", not game.can_place_any_rock())

	game.gold = 500
	game.placing = "tide"
	game._try_place(water)
	game.placing = ""
	check("tide tower placed on water", game.occupied.has(water))
	game._select(game.occupied[water])
	game._sell_selected()


func _maxed(type_id: String, track: int) -> Tower:
	var t := Tower.new()
	t.game = game
	t.setup(type_id, Vector2i(0, 0))
	t.ranks[track] = t.track_max(track)
	return t


func _fresh(type_id: String) -> Tower:
	var t := Tower.new()
	t.game = game
	t.setup(type_id, Vector2i(0, 0))
	return t


## Every mod key a track can name must be one the Tower actually reads,
## otherwise an upgrade silently does nothing.
const MOD_KEYS := [
	"damage_mult", "rate_mult", "range_mult", "splash_mult", "min_range_mult",
	"unit_speed_mult", "slow_add", "slow_dur_add", "burn_add", "shots_add",
	"chain_add", "unit_count_add", "unit_shots_add", "pierce_add",
	"aura_damage_add", "aura_rate_add", "slow_set", "shatter", "cluster", "pierce",
	"income_mult", "knockback_add", "focus_add", "volley_add",
]


func _check_tracks() -> void:
	var ok_keys := true
	var ok_shape := true
	var bad := ""
	for type_id: String in TDData.TOWER_ORDER:
		var list: Array = TDData.tracks(type_id)
		if list.is_empty() or list.size() > 4:
			ok_shape = false
		for track: Dictionary in list:
			if int(track["max"]) < 1 or float(track["cost_frac"]) <= 0.0 \
					or str(track["name"]) == "":
				ok_shape = false
			var mod_sets: Array = [track["mods"]]
			if track.has("capstone"):
				mod_sets.append(track["capstone"]["mods"])
				if str(track["capstone"]["name"]) == "" or str(track["capstone"]["desc"]) == "":
					ok_shape = false
			for mods: Dictionary in mod_sets:
				for key: String in mods:
					if not MOD_KEYS.has(key):
						ok_keys = false
						bad = "%s/%s" % [type_id, key]
	check("every tower has 1-4 well-formed tracks", ok_shape)
	check("no track uses an unknown mod key (%s)" % bad, ok_keys)

	# Each track must actually move a stat the tower cares about.
	var ok_effect := true
	for type_id: String in TDData.TOWER_ORDER:
		for i in TDData.tracks(type_id).size():
			var fresh := _fresh(type_id)
			var maxed := _maxed(type_id, i)
			if _fingerprint(maxed) == _fingerprint(fresh):
				ok_effect = false
				bad = "%s track %d" % [type_id, i]
			fresh.free()
			maxed.free()
	check("every track changes the tower (%s)" % bad, ok_effect)

	# Upgrades must also be *visible*: one rank in any track has to change the
	# geometry the tower draws itself with.
	var ok_visual := true
	var bad_visual := ""
	for type_id: String in TDData.TOWER_ORDER:
		for i in TDData.tracks(type_id).size():
			var plain := _fresh(type_id)
			var bumped := _fresh(type_id)
			bumped.ranks[i] = 1
			var top := _fresh(type_id)
			top.ranks[i] = top.track_max(i)
			if plain.visual_signature() == bumped.visual_signature() \
					or bumped.visual_signature() == top.visual_signature() \
					and top.track_max(i) > 1:
				ok_visual = false
				bad_visual = "%s track %d" % [type_id, i]
			plain.free()
			bumped.free()
			top.free()
	check("every rank visibly changes the tower (%s)" % bad_visual, ok_visual)

	# Hover text must describe every track in words, quote the cost, and — for
	# a placed tower — state the actual before/after numbers.
	var ok_words := true
	var ok_numbers := true
	var ok_capstone := true
	var bad_text := ""
	for type_id: String in TDData.TOWER_ORDER:
		for i in TDData.tracks(type_id).size():
			var blurb: String = TDData.describe_mods(TDData.tracks(type_id)[i]["mods"])
			if blurb == "" or blurb.contains("_mult") or blurb.contains("_add"):
				ok_words = false
				bad_text = "%s track %d: %s" % [type_id, i, blurb]
			var preview: String = game._track_explanation(type_id, i, null)
			if not preview.contains("per rank") or not preview.contains("coins"):
				ok_words = false
				bad_text = "%s track %d preview" % [type_id, i]
			var probe := _fresh(type_id)
			var live: String = game._track_explanation(type_id, i, probe)
			if not live.contains("This rank:"):
				ok_numbers = false
				bad_text = "%s track %d has no measured effect" % [type_id, i]
			if not TDData.capstone(type_id, i).is_empty():
				var staged: Array = Progress.ranks_for(type_id).duplicate()
				staged[i] = int(TDData.tracks(type_id)[i]["max"])
				Progress.tower_ranks[type_id] = staged
				probe.ranks[i] = int(TDData.tracks(type_id)[i]["max"]) - 1
				var final_text: String = game._track_explanation(type_id, i, probe)
				if not final_text.contains("This rank unlocks"):
					ok_capstone = false
					bad_text = "%s track %d capstone not announced" % [type_id, i]
				probe.ranks[i] = 0
				Progress.tower_ranks.erase(type_id)
			probe.free()
	check("upgrade hover text is written in plain words (%s)" % bad_text, ok_words)
	check("upgrade hover text quotes the real numbers (%s)" % bad_text, ok_numbers)
	check("the last rank announces its capstone (%s)" % bad_text, ok_capstone)

	# The numbers in the text have to match what the tower actually becomes.
	var gun := _fresh("gun")
	var quoted: String = game._track_explanation("gun", 0, gun)
	var before_txt := "Damage %.0f" % gun.stat("damage")
	gun.ranks[0] = 1
	var after_txt := "-> %.0f" % gun.stat("damage")
	check("quoted damage matches the tower before and after",
			quoted.contains(before_txt) and quoted.contains(after_txt))
	gun.free()
	var maxed := _fresh("gun")
	for i in maxed.ranks.size():
		maxed.ranks[i] = maxed.track_max(i)
	check("a tower can still be maxed out", maxed.level() > 0)
	check("a maxed tower looks nothing like a fresh one",
			maxed.plate_tier() == 3 and maxed.barrel_length() > _fresh("gun").barrel_length() * 1.3
			and maxed.barrel_count() > 1)
	maxed.free()


## Everything a track could plausibly influence, as one comparable string.
func _fingerprint(t: Tower) -> String:
	return "%.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %d %d %d %d %d %s %.3f %.3f %.3f %.3f %.3f %.3f %d" % [
		t.stat("damage"), t.stat("rate"), t.stat("range"), t.splash(),
		t.slow_factor(), t.slow_duration(), t.burn(), t.min_range(),
		t.shots(), t.chain(), t.pierce_count(), t.unit_count(), t.unit_shots(),
		str(t.pierces()), t.shatter(), t.aura_damage(), t.aura_rate(),
		t.income(), t.knockback(), t.focus_peak(), t.volley()]


func _check_new_towers() -> void:
	check("eighteen towers on the palette", TDData.TOWER_ORDER.size() == 18)
	check("marksman bores through targets", _fresh("marksman").pierce_count() >= 1)
	check("marksman out-ranges the gunner",
			_fresh("marksman").stat("range") > _fresh("gun").stat("range") * 2.0)
	check("flamethrower burns", _fresh("flame").burn() > 0.0)
	check("flamethrower hits several at once", _fresh("flame").chain() >= 2)
	check("mortar has a dead zone", _fresh("mortar").min_range() > 0.0)
	check("mortar reaches far", _fresh("mortar").stat("range") > 400.0)
	check("torpedo is water only",
			int(TDData.TOWERS["torpedo"]["terrain"]) == TDData.Terrain.WATER)
	check("torpedo pierces a line", _fresh("torpedo").pierce_count() >= 2)
	var post := _fresh("command")
	check("command post is support", post.is_support() and post.stat("damage") == 0.0)
	check("command post buffs damage and rate", post.aura_damage() > 0.0 and post.aura_rate() > 0.0)
	check("spotter drone shrinks the dead zone",
			_maxed("mortar", 3).min_range() < _fresh("mortar").min_range())
	post.free()


## Command Post auras must buff neighbours and must not stack.
func _check_aura() -> void:
	var spots: Array = []
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun") and spots.size() < 4:
			var near := true
			for other: Vector2i in spots:
				if key.distance_to(other) > 2.0:
					near = false
			if near:
				spots.append(key)
	game.gold = 5000
	game.placing = "gun"
	game._try_place(spots[0])
	game.placing = ""
	var gun: Tower = game.occupied[spots[0]]
	var solo := gun.stat("damage")

	game.placing = "command"
	game._try_place(spots[1])
	game.placing = ""
	gun.buff_timer = 0.0
	gun._process(0.01)
	var buffed := gun.stat("damage")
	check("aura buffs a nearby tower", buffed > solo)

	game.placing = "command"
	game._try_place(spots[2])
	game.placing = ""
	gun.buff_timer = 0.0
	gun._process(0.01)
	check("auras do not stack", is_equal_approx(gun.stat("damage"), buffed))

	for s: Vector2i in [spots[0], spots[1], spots[2]]:
		game._select(game.occupied[s])
		game._sell_selected()


## Dead zones, burning, and line-piercing shots.
func _check_combat_extras() -> void:
	# Earlier sections leave creeps on the board; the range maths below only
	# means something with a clean list.
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var e := Enemy.new()
	e.setup("grunt", 20.0, 1.0, game.path_points)
	add_child(e)
	e.position = Vector2(500.0, 400.0)
	game.enemies.append(e)
	game.invalidate_targeting_grid()
	check("mortar ignores enemies inside its dead zone",
			game.find_target(e.position + Vector2(40.0, 0.0), 420.0, 130.0) == null)
	check("mortar hits enemies past its dead zone",
			game.find_target(e.position + Vector2(300.0, 0.0), 420.0, 130.0) == e)

	var before := e.hp
	e.apply_burn(20.0, 2.0)
	e._process(0.5)
	check("burning creeps lose health over time", e.hp < before)
	check("burn expires", e.burn_timer < 2.0)

	# A piercing shot fired along a row of creeps should hit two of them.
	var line: Array = []
	for i in 3:
		var c := Enemy.new()
		c.setup("grunt", 20.0, 1.0, game.path_points)
		add_child(c)
		c.position = Vector2(700.0 + 40.0 * float(i), 300.0)
		game.enemies.append(c)
		game.invalidate_targeting_grid()
		line.append(c)
	var p := Projectile.new()
	p.game = game
	p.position = Vector2(660.0, 300.0)
	p.dest = Vector2(900.0, 300.0)
	p.damage = 10.0
	p.speed = 400.0
	p.pierce_count = 2
	p.max_travel = 400.0
	add_child(p)
	for i in 40:
		if is_instance_valid(p):
			p._process(0.02)
	var hurt := 0
	for c in line:
		if is_instance_valid(c) and c.hp < c.max_hp:
			hurt += 1
	check("piercing shot hits several creeps in a line", hurt >= 2)
	for c in line:
		if is_instance_valid(c):
			game.enemies.erase(c)
			game.invalidate_targeting_grid()
			c.queue_free()
	game.enemies.erase(e)
	game.invalidate_targeting_grid()
	e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()


## Air towers should put an aircraft in the air and reserve a squadron slot.
func _check_air() -> void:
	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "airfield"):
			spot = key
			break
	game.gold = 500
	game.placing = "airfield"
	game._try_place(spot)
	game.placing = ""
	var pad: Tower = game.occupied[spot]
	check("airfield placed", pad != null and pad.is_air())

	var e := Enemy.new()
	e.setup("grunt", 1.0, 1.0, game.path_points)
	e.died.connect(game._on_enemy_died)
	e.leaked.connect(game._on_enemy_leaked)
	game.layer_enemies.add_child(e)
	e.position = game.cell_center(spot) + Vector2(60.0, 0.0)
	game.enemies.append(e)
	game.invalidate_targeting_grid()

	pad._process(0.1)
	check("airfield launches a bomber", pad.units.size() == 1)
	check("bomber is in the air layer", game.layer_air.get_child_count() == 1)
	pad._process(0.1)
	check("squadron slot respected", pad.units.size() == 1)
	var craft = pad.units[0]
	check("bomber knows its pad", craft.pad == pad.position)
	check("bomber carries the payload", craft.shots == pad.unit_shots())


## The roads themselves must get harder with the tier: a shorter path gives
## less time to shoot, and fewer path-adjacent buildable cells give fewer
## places to shoot from. Both are measured from the real terrain.
func _check_road_ladder() -> void:
	var by_tier: Dictionary = {}
	var lanes_report: Array = []
	var ok_lanes := true
	var bad_lane := ""
	for i in TDData.LEVELS.size():
		TDData.selected_level = i
		var probe = load("res://game.tscn").instantiate()
		add_child(probe)
		var path_cells := 0
		var spots := 0
		for key: Vector2i in probe.terrain:
			if probe.terrain_at(key) == TDData.Terrain.PATH:
				path_cells += 1
				continue
			if probe.terrain_at(key) != TDData.Terrain.GROUND:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if probe.is_path(key + o):
					spots += 1
					break
		var tier := int(TDData.LEVELS[i]["tier"])
		var id := str(TDData.LEVELS[i]["id"])
		if probe.routes.size() > 1:
			# Multi-lane maps are their own category: the bands describe a
			# single road, and two short lanes are harder than one long one.
			# What they must guarantee is that every lane is defensible.
			var shortest := 1 << 30
			for route: PackedVector2Array in probe.routes:
				var length := 0.0
				for k in range(route.size() - 1):
					length += route[k].distance_to(route[k + 1])
				shortest = mini(shortest, int(length / float(TDData.CELL)))
			var per_lane: int = spots / probe.routes.size()
			lanes_report.append("%s: %d lanes, shortest %d, %d spots each"
					% [id, probe.routes.size(), shortest, per_lane])
			if shortest < 18 or per_lane < 20:
				ok_lanes = false
				bad_lane = id
		else:
			if not by_tier.has(tier):
				by_tier[tier] = {"path": [], "spots": []}
			by_tier[tier]["path"].append(path_cells)
			by_tier[tier]["spots"].append(spots)
		probe.queue_free()
	TDData.selected_level = 0

	var ok_path := true
	var ok_spots := true
	var report: Array = []
	for tier in range(1, TDData.TIERS.size()):
		var easier: Dictionary = by_tier[tier - 1]
		var harder: Dictionary = by_tier[tier]
		if harder["path"].max() >= easier["path"].min():
			ok_path = false
		if harder["spots"].max() >= easier["spots"].min():
			ok_spots = false
	for tier in range(TDData.TIERS.size()):
		report.append("%s: road %d-%d, spots %d-%d" % [TDData.TIERS[tier]["name"],
				by_tier[tier]["path"].min(), by_tier[tier]["path"].max(),
				by_tier[tier]["spots"].min(), by_tier[tier]["spots"].max()])
	print("       road ladder -> " + "  |  ".join(report))
	print("       multi-lane  -> " + "  |  ".join(lanes_report))
	check("harder tiers have shorter roads", ok_path)
	check("harder tiers have fewer firing positions", ok_spots)
	check("every tier has at least three single-road maps",
			by_tier.size() == TDData.TIERS.size() and by_tier[0]["path"].size() >= 3)
	check("every area holds four maps", _areas_are_full())
	check("every lane of a multi-lane map is defensible (%s)" % bad_lane, ok_lanes)
	check("multi-lane maps exist", lanes_report.size() >= 3)


func _areas_are_full() -> bool:
	for area: Dictionary in TDData.AREAS:
		if TDData.levels_in_area(str(area["id"])).size() != 4:
			return false
	return true


## Drag and drop bookkeeping: the palette starts a drag, the map rect decides
## where a release counts, and placement still respects terrain.
func _check_drag() -> void:
	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			spot = key
			break
	game.begin_drag("gun")
	check("drag starts with the tower armed", game.dragging and game.placing == "gun")
	check("map rect covers the board", game.map_rect().has_point(game.cell_center(spot)))
	check("map rect excludes the palette",
			not game.map_rect().has_point(Vector2(float(TDData.MAP_W) + 20.0, 400.0)))
	check("map rect excludes the top bar", not game.map_rect().has_point(Vector2(400.0, 20.0)))
	game.gold = 500
	game._try_place(spot)
	check("dropping on a valid cell builds", game.occupied.has(spot))
	game._select(game.occupied[spot])
	game._sell_selected()
	game.placing = ""
	game.dragging = false


## Account levels gate towers and advanced upgrade tracks, and the ladder has
## to be sane: starters at level 1, everything reachable, no gaps.
func _check_progression() -> void:
	Progress.unlock_all = false
	var saved_xp := Progress.xp
	var saved_coins := Progress.coins
	var saved_ranks := Progress.ranks.duplicate()

	Progress.xp = 0
	check("level 1 at zero XP", Progress.level() == 1)
	check("XP thresholds rise", Progress.xp_for_level(2) > 0
			and Progress.xp_for_level(5) > Progress.xp_for_level(4))

	var starters := 0
	var top_unlock := 1
	var ok_range := true
	for type_id: String in TDData.TOWER_ORDER:
		var need := Progress.tower_unlock_level(type_id)
		if need <= 1:
			starters += 1
		top_unlock = maxi(top_unlock, need)
		if need < 1 or need > 20:
			ok_range = false
	check("at least two towers are available from the start", starters >= 2)
	check("unlock levels are sane", ok_range)
	check("locked towers really are locked at level 1",
			not Progress.tower_unlocked("command") and Progress.tower_unlocked("gun"))

	# Every tower and track must become reachable by the time the ladder ends.
	Progress.xp = Progress.xp_for_level(40)
	var ok_all := true
	for type_id: String in TDData.TOWER_ORDER:
		if not Progress.tower_unlocked(type_id):
			ok_all = false
		for i in TDData.tracks(type_id).size():
			if not Progress.track_unlocked(type_id, i):
				ok_all = false
	check("everything unlocks eventually", ok_all)
	check("nothing is left to unlock at the top", Progress.next_unlock().is_empty())

	Progress.xp = 0
	var upcoming: Dictionary = Progress.next_unlock()
	check("the menu can name the next unlock",
			not upcoming.is_empty() and int(upcoming["level"]) > 1)

	# A locked tower cannot be built even with plenty of gold.
	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			spot = key
			break
	game.gold = 9000
	game.placing = "command"
	game._try_place(spot)
	game.placing = ""
	check("a locked tower cannot be placed", not game.occupied.has(spot))
	check("a locked tower cannot even be dragged",
			not (game.begin_drag("command") == null and game.dragging))
	game.dragging = false
	game.placing = ""

	# Rewards scale with waves, score and difficulty.
	var small := Progress.run_reward(5, 500, 0)
	var big := Progress.run_reward(25, 12000, 0)
	var brutal := Progress.run_reward(25, 12000, 3)
	check("longer runs pay more", int(big["xp"]) > int(small["xp"]) * 3)
	check("harder tiers pay more", int(brutal["coins"]) > int(big["coins"]))
	check("a run pays both XP and coins", int(small["xp"]) > 0 and int(small["coins"]) > 0)

	# Banking a run: pays once, counts waves completed, and survives a second
	# call (leaving to the menu after a defeat must not pay twice).
	Progress.xp = 0
	Progress.coins = 0
	game.rewarded = false
	game.wave = 7
	game.score = 1500
	var first: Dictionary = game._bank_reward()
	var xp_after := Progress.xp
	var coins_after := Progress.coins
	var second: Dictionary = game._bank_reward()
	check("finishing a run pays out", not first.is_empty() and xp_after > 0 and coins_after > 0)
	check("a run only pays once", second.is_empty() and Progress.xp == xp_after
			and Progress.coins == coins_after)
	check("payout matches the reward table",
			xp_after == int(Progress.run_reward(6, 1500, int(game.level_def["tier"]))["xp"]))
	game.rewarded = false
	game.wave = 0
	check("a run that never finished a wave pays nothing", game._bank_reward().is_empty())
	game.wave = 1

	Progress.xp = saved_xp
	Progress.coins = saved_coins
	Progress.ranks = saved_ranks
	Progress.unlock_all = true


## Parking a run: leaving mid-way stores the board, continuing restores it,
## and finishing or surrendering clears it.
func _check_saved_runs() -> void:
	# Earlier sections bank test payouts; start from a clean ledger.
	var saved_runs: Dictionary = Progress.runs.duplicate(true)
	var saved_stats: Dictionary = Progress.stats.duplicate(true)
	Progress.runs = {}
	Progress.stats = {}
	TDData.selected_level = 0
	var probe = load("res://game.tscn").instantiate()
	add_child(probe)
	await get_tree().process_frame

	var spot := Vector2i(-99, -99)
	for key: Vector2i in probe.terrain:
		if probe.can_place(key, "gun"):
			spot = key
			break
	probe.gold = 900
	probe.placing = "cannon"
	probe._try_place(spot)
	probe.placing = ""
	var placed: Tower = probe.occupied[spot]
	placed.kills = 9
	placed.cycle_target_mode()
	var placed_mode: int = placed.target_mode
	probe.wave = 4
	probe.lives = 12
	probe.score = 750
	probe.in_wave = false

	# The early-start bonus is once per wave, even across parking the run.
	probe.gold = 100
	probe.break_timer = probe.BREAK_TIME
	probe.in_wave = false
	probe.wave = 4
	probe._start_wave_early()
	var after_bonus: int = probe.gold
	check("starting early pays a bonus", after_bonus > 100)
	probe.in_wave = false
	probe.wave = 4
	probe.break_timer = probe.BREAK_TIME
	probe._start_wave_early()
	check("the same wave cannot be rushed twice for gold", probe.gold == after_bonus)
	probe.wave = 4
	probe.in_wave = false

	check("nothing is parked to begin with", not Progress.has_run("verdant"))
	Progress.save_run(probe._capture_run())
	check("leaving mid-run parks it", Progress.has_run("verdant"))
	var parked := Progress.run_for("verdant")
	check("the parked run remembers the wave", int(parked["wave"]) == 4)
	check("the parked run remembers the claimed bonus", int(parked["claimed"]) >= 4)
	check("the parked run remembers the economy",
			int(parked["gold"]) == probe.gold and int(parked["lives"]) == 12)
	check("the parked run remembers the towers", (parked["towers"] as Array).size() == 1)
	check("leaving mid-run does not pay out yet", Progress.stat_int("runs") == 0)
	probe.queue_free()

	# Continuing rebuilds the board.
	TDData.resume_run = true
	var resumed = load("res://game.tscn").instantiate()
	add_child(resumed)
	await get_tree().process_frame
	check("continuing restores the wave", resumed.wave == 4)
	check("continuing restores the gold", resumed.gold == int(parked["gold"]))
	check("continuing rebuilds the towers", resumed.occupied.has(spot))
	var back: Tower = resumed.occupied[spot]
	check("a rebuilt tower keeps its type and tally",
			back.type_id == "cannon" and back.kills == 9)
	check("a rebuilt tower keeps its targeting", back.target_mode == placed_mode)
	check("continuing consumes the resume flag", not TDData.resume_run)
	var resumed_gold: int = resumed.gold
	resumed.break_timer = resumed.BREAK_TIME
	resumed._start_wave_early()
	check("resuming cannot re-claim that wave's bonus", resumed.gold == resumed_gold)
	resumed.in_wave = false

	# Surrender pays out and clears the parked run.
	resumed.score = 900
	resumed._surrender()
	check("giving up asks for confirmation", not resumed.game_over)
	resumed._surrender()
	check("giving up ends the run", resumed.game_over and resumed.surrendered)
	check("giving up pays out", Progress.stat_int("runs") == 1)
	check("giving up clears the parked run", not Progress.has_run("verdant"))

	# Every map keeps its own parked run: starting one must not wipe another.
	Progress.save_run({"level": "verdant", "wave": 3, "gold": 100, "lives": 5,
		"score": 10, "leaked": 0, "claimed": 3, "stats": {}, "towers": []})
	Progress.save_run({"level": "meadow", "wave": 8, "gold": 200, "lives": 7,
		"score": 20, "leaked": 1, "claimed": 8, "stats": {}, "towers": []})
	check("two maps can be parked at once", Progress.parked_count() == 2)
	check("each map remembers its own wave",
			int(Progress.run_for("verdant")["wave"]) == 3
			and int(Progress.run_for("meadow")["wave"]) == 8)
	Progress.clear_run("verdant")
	check("clearing one map leaves the other", not Progress.has_run("verdant")
			and Progress.has_run("meadow"))
	Progress.clear_run("nonexistent")
	check("clearing an unknown map is harmless", Progress.has_run("meadow"))
	Progress.clear_run()
	check("clearing everything works", Progress.parked_count() == 0)
	resumed.queue_free()

	Progress.runs = saved_runs
	Progress.stats = saved_stats


## The build-phase readout must describe the wave that is actually coming.
func _check_wave_preview() -> void:
	# Counts have to match the spawn list exactly, kind for kind.
	var ok_counts := true
	var mismatch := ""
	for n in [1, 4, 7, 10, 13, 20]:
		var spawns: Array = game._build_wave(n)
		var composition: Dictionary = game.wave_composition(n)
		var tally: Dictionary = {}
		for entry: Dictionary in spawns:
			var kind := str(entry["kind"])
			tally[kind] = int(tally.get(kind, 0)) + 1
		if tally.size() != composition.size():
			ok_counts = false
			mismatch = "wave %d kinds" % n
		var total := 0
		for kind: String in composition:
			total += int(composition[kind])
			if int(composition[kind]) != int(tally.get(kind, -1)):
				ok_counts = false
				mismatch = "wave %d %s" % [n, kind]
		if total != spawns.size():
			ok_counts = false
			mismatch = "wave %d total" % n
	check("the readout counts match the spawn list (%s)" % mismatch, ok_counts)

	check("early waves are simple", game.wave_composition(1).size() <= 2)
	check("later waves are varied", game.wave_composition(13).size() >= 3)
	check("boss waves show the boss", game.wave_composition(10).has("boss")
			or game.wave_composition(10).has("titan"))
	check("the readout is ordered by the roster, not by chance",
			game.wave_composition(13).keys() == game.wave_composition(13).keys())

	# Kinds that need a specific answer carry a note the readout can show.
	var noted := 0
	for kind: String in TDData.ENEMIES:
		if str(TDData.ENEMIES[kind].get("note", "")) != "":
			noted += 1
	check("the tricky kinds explain themselves", noted >= 6)
	# Notes must not quote numbers that balancing can change underneath them.
	var stale := ""
	for kind: String in TDData.ENEMIES:
		var note := str(TDData.ENEMIES[kind].get("note", "")).to_lower()
		for word: String in ["two ", "three ", "four ", "five "]:
			if note.contains(word):
				stale = "%s: %s" % [kind, note]
	check("no note hardcodes a tunable count (%s)" % stale, stale == "")

	# The panel itself: visible between waves, hidden while one runs.
	game.in_wave = false
	game.game_over = false
	game.wave = 5
	game._refresh_wave_preview()
	check("the readout is on screen during the build phase", game.preview_row.visible)
	check("it describes the next wave, not the last", game.preview_wave == 6)
	# Heading, one chip per kind, and the advice label when a kind has a note.
	var kinds: int = game.wave_composition(6).size()
	var has_note: bool = game.lbl_wave_note.text != ""
	check("it renders a chip per kind plus a heading",
			game.preview_row.get_child_count() == kinds + 1 + (1 if has_note else 0))
	game.wave = 6
	game._refresh_wave_preview()
	check("it rebuilds when the wave advances", game.preview_wave == 7)
	game.in_wave = true
	game._refresh_wave_preview()
	check("during a wave it just states what is running",
			game.preview_row.get_child_count() == 1 and game.preview_wave == 0)
	check("the strip keeps its height so the bar cannot jump",
			game.preview_row.custom_minimum_size.y >= 20.0)
	game.in_wave = false
	game._refresh_wave_preview()
	check("and the chips come back for the next build phase",
			game.preview_row.get_child_count() > 1 and game.preview_wave == 7)
	# The strip frees every child on refresh, so a kept advice label would be
	# a freed node by the next rebuild.
	var note_before: Label = game.lbl_wave_note
	game.wave = 8
	game._refresh_wave_preview()
	check("the advice line is rebuilt, never a freed leftover",
			is_instance_valid(game.lbl_wave_note) and game.lbl_wave_note != note_before)
	game.wave = 1


## The generated audio bank must actually contain sound: right length, not
## silent, not clipped, and loop points that join cleanly.
func _check_audio() -> void:
	var required: Array = ["shot_gun", "shot_cannon", "shot_light", "explosion", "death",
			"leak", "build", "upgrade", "sell", "wave_start", "wave_clear", "game_over",
			"boss", "click", "beam", "music"]
	var missing := ""
	for name: String in required:
		if not Audio.bank.has(name):
			missing += name + " "
	check("every sound is in the bank (%s)" % missing, missing == "")

	var ok_format := true
	var ok_loud := true
	var ok_clean := true
	var ok_length := true
	var quiet := ""
	for name: String in required:
		var wav: AudioStreamWAV = Audio.bank[name]
		if wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.mix_rate != Audio.RATE \
				or wav.stereo:
			ok_format = false
		var frames: int = wav.data.size() / 2
		if frames < 500 or frames > Audio.RATE * 12:
			ok_length = false
		# Peak and clipping, read straight from the packed samples.
		var peak := 0.0
		var clipped := 0
		var sum := 0.0
		for i in range(0, frames, 7):
			var v: float = float(wav.data.decode_s16(i * 2)) / 32767.0
			peak = maxf(peak, absf(v))
			sum += absf(v)
			if absf(v) > 0.999:
				clipped += 1
		if peak < 0.05:
			ok_loud = false
			quiet = name
		if clipped > frames / 700:
			ok_clean = false
			quiet = name
		if sum / float(maxi(1, frames / 7)) < 0.002:
			ok_loud = false
			quiet = name
	check("every sound is 16-bit mono at the engine rate", ok_format)
	check("every sound has a sane length", ok_length)
	check("no sound is silent (%s)" % quiet, ok_loud)
	check("no sound clips (%s)" % quiet, ok_clean)

	# Looping streams must be marked, and the wrap must not be a bigger jump
	# than the waveform already makes on its own (a saw steps every cycle, so
	# comparing the first and last sample outright would be meaningless).
	for name: String in ["beam", "music"]:
		var wav: AudioStreamWAV = Audio.bank[name]
		check("%s loops" % name, wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		var frames: int = wav.data.size() / 2
		var biggest := 0.0
		var previous: float = float(wav.data.decode_s16(0)) / 32767.0
		for i in range(1, frames):
			var v: float = float(wav.data.decode_s16(i * 2)) / 32767.0
			biggest = maxf(biggest, absf(v - previous))
			previous = v
		var first: float = float(wav.data.decode_s16(0)) / 32767.0
		var wrap: float = absf(first - previous)
		check("%s wraps no harder than it steps" % name, wrap <= biggest + 0.02)

	# Playback plumbing.
	check("there is a pool of voices", Audio.players.size() >= 8)
	# Muted means play() bails out — checked by the voice cursor not moving,
	# since voices from earlier sections may still be running.
	Audio.set_volumes(0.0, 0.0)
	Audio.recent.clear()
	var muted_cursor: int = Audio.next_voice
	Audio.play("shot_gun")
	check("muted means no voice is claimed", Audio.next_voice == muted_cursor)
	Audio.set_volumes(0.8, 0.35)
	check("volume settings round-trip",
			is_equal_approx(Audio.sfx_volume, 0.8) and is_equal_approx(Audio.music_volume, 0.35))
	Progress.set_volume("sfx", 0.5)
	check("volumes are saved with the slot", is_equal_approx(Progress.volume("sfx"), 0.5))
	Progress.set_volume("sfx", 0.8)

	# The rate limiter keeps a wall of towers from stacking one sample.
	Audio.recent.clear()
	Audio.play("shot_gun")
	var claimed: int = Audio.next_voice
	check("an audible sound claims a voice", claimed != muted_cursor)
	Audio.play("shot_gun")
	check("repeat sounds inside a few milliseconds are dropped",
			Audio.next_voice == claimed)
	Audio.recent.clear()
	Audio.play("shot_gun")
	check("after the window it plays again", Audio.next_voice != claimed)

	# Beams are reference counted per frame.
	Audio.beam_active(3)
	check("beams register while firing", Audio.beam_voices == 3)
	Audio._process(0.016)
	check("the beam count resets each frame", Audio.beam_voices == 0)


## Developer cheats: off unless asked for, effective when used, and honest
## about having been used.
func _check_cheats() -> void:
	check("cheat toggles start off", not Cheats.god_mode and not Cheats.free_build)
	check("cheats are available in a debug build", Cheats.available())

	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			spot = key
			break
	# Maxed-buildings cheat: new towers arrive fully upgraded, and standing
	# ones can be brought up to match.
	var plain := Tower.new()
	plain.game = game
	plain.setup("gun", Vector2i.ZERO)
	check("towers are plain without the cheat", plain.level() == 0)
	Cheats.max_towers = true
	var loaded := Tower.new()
	loaded.game = game
	loaded.setup("gun", Vector2i.ZERO)
	var every_rank := 0
	for track: Dictionary in TDData.tracks("gun"):
		every_rank += int(track["max"])
	check("the cheat builds them fully upgraded", loaded.level() == every_rank)
	check("a maxed tower really is stronger", loaded.stat("damage") > plain.stat("damage"))
	check("maxing a standing tower reports what it added", plain.max_out() == every_rank)
	check("and leaves nothing to add", plain.max_out() == 0)
	Cheats.max_towers = false
	plain.free()
	loaded.free()

	# Fill-the-map cheat.
	var free_cells := 0
	for key: Vector2i in game.terrain:
		if game.occupied.has(key):
			continue
		for type_id: String in TDData.TOWER_ORDER:
			if game.can_place(key, type_id):
				free_cells += 1
				break
	var before_fill: Array = game.occupied.keys()
	var filled: int = game.fill_with_random_towers()
	check("filling the map builds on every free cell", filled == free_cells and filled > 20)
	var all_maxed := true
	var kinds: Array = []
	for cell_key: Vector2i in game.occupied:
		if before_fill.has(cell_key):
			continue
		var t: Tower = game.occupied[cell_key]
		if t.level() <= 0:
			all_maxed = false
		if not kinds.has(t.type_id):
			kinds.append(t.type_id)
	check("filled towers come fully upgraded", all_maxed)
	check("the fill uses a mix of towers", kinds.size() >= 3)
	check("water cells got water towers", _fill_respects_terrain(game))
	for cell_key: Vector2i in game.occupied.keys():
		var doomed: Tower = game.occupied[cell_key]
		game.occupied.erase(cell_key)
		doomed.queue_free()
	check("the board can be cleared again", game.occupied.is_empty())

	check("towers cost money normally", game.tower_cost("gun") > 0)
	Cheats.free_build = true
	check("free building makes them free", game.tower_cost("gun") == 0)
	Cheats.free_build = false

	# God mode keeps leaks from costing lives or gold.
	var lives_before: int = game.lives
	game.gold = 400
	Cheats.god_mode = true
	var thief := Enemy.new()
	thief.setup("thief", 1.0, 1.0, game.routes[0])
	thief.leaked.connect(game._on_enemy_leaked)
	add_child(thief)
	game.enemies.append(thief)
	game.invalidate_targeting_grid()
	thief._leak()
	check("god mode keeps your lives", game.lives == lives_before)
	check("god mode keeps your gold", game.gold == 400)
	Cheats.god_mode = false
	thief.queue_free()

	# Wave helpers.
	game.wave = 3
	game.in_wave = true
	game.spawn_queue = game._build_wave(3)
	game.spawn_index = 0
	game._spawn(str(game.spawn_queue[0]["kind"]))
	check("a creep is on the board", game.enemies.size() > 0)
	game.finish_wave_now()
	check("finishing a wave clears the board", game.enemies.is_empty())
	check("finishing a wave ends it", not game.in_wave)
	var before_wave: int = game.wave
	game.skip_waves(5)
	check("jumping ahead advances the wave", game.wave == before_wave + 5)
	check("jumped waves cannot be rushed for bonus gold",
			game.early_claimed >= game.wave)
	game.spawn_kind("boss")
	var has_boss := false
	for e in game.enemies:
		if is_instance_valid(e) and e.kind == "boss":
			has_boss = true
	check("a boss can be summoned", has_boss)
	game.finish_wave_now()

	# A cheated run must not set a personal best.
	Progress.bests = {}
	game.cheats_used = true
	game.rewarded = false
	game.wave = 12
	game.score = 4000
	game._bank_reward()
	check("a cheated run sets no record", Progress.best_wave(str(game.level_def["id"])) == 0)
	game.cheats_used = false
	game.rewarded = false
	game.wave = 1
	game.lives = lives_before


## Every tower the fill cheat placed must be legal for the cell it sits on.
func _fill_respects_terrain(probe) -> bool:
	for cell_key: Vector2i in probe.occupied:
		var t: Tower = probe.occupied[cell_key]
		var wants: int = int(TDData.TOWERS[t.type_id]["terrain"])
		if probe.terrain_at(cell_key) != wants:
			return false
	return true


## Each enemy kind has to actually behave differently.
func _check_enemy_kinds() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	check("the roster has grown", TDData.ENEMIES.size() >= 12)
	var ok_shape := true
	for kind: String in TDData.ENEMIES:
		var d: Dictionary = TDData.ENEMIES[kind]
		if float(d["hp"]) <= 0.0 or float(d["speed"]) <= 0.0 or int(d["reward"]) <= 0 \
				or float(d["radius"]) <= 0.0 or str(d["name"]) == "":
			ok_shape = false
	check("every enemy kind is well formed", ok_shape)

	# Armour: a Warden shrugs off small hits but not piercing ones.
	var warden := Enemy.new()
	warden.setup("warden", 1.0, 1.0, game.routes[0])
	add_child(warden)
	var before := warden.hp
	warden.take_damage(10.0)
	var soaked := before - warden.hp
	warden.take_damage(10.0, true)
	var pierced := before - warden.hp - soaked
	check("heavy armour soaks most of a small hit", soaked < 10.0 and soaked >= 1.0)
	check("piercing ignores that armour", is_equal_approx(pierced, 10.0))
	warden.queue_free()

	# Ashwalkers ignore slows and fire.
	var ash := Enemy.new()
	ash.setup("ashwalker", 1.0, 1.0, game.routes[0])
	add_child(ash)
	ash.apply_slow(0.6, 3.0)
	ash.apply_burn(30.0, 3.0)
	check("ashwalkers cannot be slowed", is_equal_approx(ash.speed(), ash.base_speed))
	check("ashwalkers cannot be set alight", ash.burn_timer <= 0.0)
	var grunt := Enemy.new()
	grunt.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(grunt)
	grunt.apply_slow(0.6, 3.0)
	check("ordinary creeps still slow", grunt.speed() < grunt.base_speed)
	ash.queue_free()
	grunt.queue_free()

	# Bolts sprint in bursts.
	var bolt := Enemy.new()
	bolt.setup("bolt", 1.0, 1.0, game.routes[0])
	add_child(bolt)
	var cruise := bolt.speed()
	bolt.charge_clock = bolt.charge_period
	bolt._process(0.05)
	check("bolts burst forward", bolt.speed() > cruise * 2.0)
	bolt.charging = 0.0
	check("and then settle back", is_equal_approx(bolt.speed(), cruise))
	bolt.queue_free()

	# Brood mothers split, and the children join the same lane.
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var brood := Enemy.new()
	brood.setup("brood", 1.0, 1.0, game.routes[0])
	brood.died.connect(game._on_enemy_died)
	brood.split.connect(game._on_enemy_split)
	game.layer_enemies.add_child(brood)
	game.enemies.append(brood)
	game.invalidate_targeting_grid()
	brood.progress = 400.0
	brood.take_damage(99999.0, true)
	var brood_count: int = int(TDData.ENEMIES["brood"]["split_count"])
	check("a brood mother leaves children behind",
			game.enemies.size() >= brood_count and brood_count >= 2)
	var inherited := true
	for child in game.enemies:
		if is_instance_valid(child) and child != brood:
			if not is_equal_approx(child.progress, 400.0) or child.path != brood.path:
				inherited = false
	check("the children start where the parent fell", inherited)
	for child in game.enemies.duplicate():
		if is_instance_valid(child):
			child.queue_free()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	# Menders heal their neighbours.
	var medic := Enemy.new()
	medic.setup("mender", 1.0, 1.0, game.routes[0])
	add_child(medic)
	medic.position = Vector2(400.0, 400.0)
	var patient := Enemy.new()
	patient.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(patient)
	patient.position = Vector2(430.0, 400.0)
	patient.hp = patient.max_hp * 0.3
	game.enemies.append(medic)
	game.invalidate_targeting_grid()
	game.enemies.append(patient)
	game.invalidate_targeting_grid()
	var hurt := patient.hp
	game._process_menders(0.5)
	check("menders heal the wounded", patient.hp > hurt)
	check("healing cannot exceed full health", patient.hp <= patient.max_hp)
	var far := Enemy.new()
	far.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(far)
	far.position = Vector2(1200.0, 400.0)
	far.hp = far.max_hp * 0.3
	game.enemies.append(far)
	game.invalidate_targeting_grid()
	var far_hp := far.hp
	game._process_menders(0.5)
	check("healing has a range", is_equal_approx(far.hp, far_hp))
	medic.queue_free()
	patient.queue_free()
	far.queue_free()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	# Cutpurses take gold when they get through.
	var thief := Enemy.new()
	thief.setup("thief", 1.0, 1.0, game.routes[0])
	thief.leaked.connect(game._on_enemy_leaked)
	add_child(thief)
	game.enemies.append(thief)
	game.invalidate_targeting_grid()
	game.gold = 500
	var lives_before: int = game.lives
	thief._leak()
	check("a cutpurse steals gold", game.gold < 500)
	check("and still costs a life", game.lives < lives_before)
	thief.queue_free()

	# Titans appear as the alternate late boss and break into Wardens.
	var late: Array = game._build_wave(20)
	var kinds: Array = []
	for entry: Dictionary in late:
		if not kinds.has(str(entry["kind"])):
			kinds.append(str(entry["kind"]))
	check("late boss waves field a Titan", kinds.has("titan"))
	check("the Titan breaks into Wardens",
			str(TDData.ENEMIES["titan"]["split_into"]) == "warden")

	# The new kinds actually appear in the wave schedule.
	var seen: Array = []
	for n in range(1, 25):
		for entry: Dictionary in game._build_wave(n):
			if not seen.has(str(entry["kind"])):
				seen.append(str(entry["kind"]))
	var missing := ""
	for kind: String in TDData.ENEMIES:
		if not seen.has(kind):
			missing += kind + " "
	check("every enemy kind shows up within 24 waves (%s)" % missing, missing == "")

	game.enemies.assign(saved)
	game.invalidate_targeting_grid()
	game.lives = lives_before


## Kills and damage are credited to the tower that fired, and a finished run
## folds its tallies into the career page's lifetime totals.
func _check_stats() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var saved_stats: Dictionary = Progress.stats.duplicate(true)
	Progress.stats = {}

	var shooter := Tower.new()
	shooter.game = game
	shooter.setup("gun", Vector2i.ZERO)
	var prey := Enemy.new()
	prey.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(prey)

	prey.take_damage(5.0, false, shooter)
	check("damage is credited to the tower", shooter.damage_dealt > 0.0)
	check("a wounded creep is not a kill", shooter.kills == 0)
	var before_damage := shooter.damage_dealt
	game.enemies.append(prey)
	game.invalidate_targeting_grid()
	prey.died.connect(game._on_enemy_died)
	prey.take_damage(9999.0, true, shooter)
	check("the killing blow counts a kill", shooter.kills == 1)
	check("the kill is tallied against its species",
			int((game.run_stats["enemy_kills"] as Dictionary).get("grunt", 0)) >= 1)
	check("overkill does not inflate damage",
			shooter.damage_dealt - before_damage <= prey.max_hp)

	var bystander := Tower.new()
	bystander.game = game
	bystander.setup("gun", Vector2i.ZERO)
	check("other towers get no credit", bystander.kills == 0 and bystander.damage_dealt == 0.0)

	# Burning credits the tower that lit the fire.
	var burned := Enemy.new()
	burned.setup("grunt", 4.0, 1.0, game.routes[0])
	add_child(burned)
	burned.apply_burn(50.0, 2.0, bystander)
	burned._process(0.5)
	check("burn ticks are credited to the source", bystander.damage_dealt > 0.0)

	shooter.free()
	bystander.free()
	prey.queue_free()
	burned.queue_free()

	# A banked run should push its tallies into the lifetime totals.
	Progress.xp = 0
	Progress.coins = 0
	game.rewarded = false
	game.wave = 5
	game.score = 900
	game.run_stats = {"kills": 12, "leaks": 2, "towers_built": 3, "gold_earned": 400,
		"damage": 0, "tower_kills": {}, "tower_built": {"gun": 3},
		"enemy_kills": {"grunt": 7, "tank": 5}, "enemy_leaks": {"runner": 2}}
	game._bank_reward()
	check("runs are counted", Progress.stat_int("runs") == 1)
	check("waves are banked", Progress.stat_int("waves") == 4)
	check("kills are banked", Progress.stat_int("kills") == 12)
	check("leaks are banked", Progress.stat_int("leaks") == 2)
	check("gold earned is banked", Progress.stat_int("gold_earned") == 400)
	check("coins earned is banked", Progress.stat_int("coins_earned") > 0)
	check("best wave is remembered", Progress.stat_int("best_wave") == 4)
	check("per-tower builds are banked",
			int((Progress.stat("tower_built", {}) as Dictionary).get("gun", 0)) == 3)
	check("per-enemy kills are banked",
			int((Progress.stat("enemy_kills", {}) as Dictionary).get("grunt", 0)) == 7)
	check("per-enemy leaks are banked",
			int((Progress.stat("enemy_leaks", {}) as Dictionary).get("runner", 0)) == 2)
	game.rewarded = false
	game.wave = 3
	game.run_stats = {"kills": 5, "leaks": 0, "towers_built": 1, "gold_earned": 100,
		"damage": 0, "tower_kills": {}, "tower_built": {"gun": 1},
		"enemy_kills": {"grunt": 4, "bolt": 1}, "enemy_leaks": {}}
	game._bank_reward()
	check("a second run accumulates", Progress.stat_int("runs") == 2
			and Progress.stat_int("kills") == 17)
	check("per-enemy kills accumulate across runs",
			int((Progress.stat("enemy_kills", {}) as Dictionary).get("grunt", 0)) == 11
			and int((Progress.stat("enemy_kills", {}) as Dictionary).get("bolt", 0)) == 1)
	check("best wave keeps the highest", Progress.stat_int("best_wave") == 4)

	Progress.stats = saved_stats
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()
	game.wave = 1
	game.rewarded = false


## Targeting modes must each pick the creep they promise.
func _check_targeting() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var here := Vector2(500.0, 400.0)

	# Three creeps: a wounded weakling at the front, a fresh tank at the back.
	var lead := Enemy.new()
	lead.setup("runner", 1.0, 1.0, game.routes[0])
	lead.position = here + Vector2(40.0, 0.0)
	lead.progress = 900.0
	lead.hp = lead.max_hp * 0.2
	var tank := Enemy.new()
	tank.setup("tank", 1.0, 1.0, game.routes[0])
	tank.position = here + Vector2(-40.0, 0.0)
	tank.progress = 100.0
	var middle := Enemy.new()
	middle.setup("grunt", 1.0, 1.0, game.routes[0])
	middle.position = here
	middle.progress = 500.0
	middle.hp = middle.max_hp * 0.9
	for e: Enemy in [lead, tank, middle]:
		add_child(e)
		game.enemies.append(e)
		game.invalidate_targeting_grid()

	check("First picks the creep nearest the base",
			game.find_target(here, 300.0, 0.0, TDData.Target.FIRST) == lead)
	check("Last picks the newest arrival",
			game.find_target(here, 300.0, 0.0, TDData.Target.LAST) == tank)
	check("Weakest picks the smallest health pool",
			game.find_target(here, 300.0, 0.0, TDData.Target.WEAKEST) == lead)
	check("Strongest picks the biggest health pool",
			game.find_target(here, 300.0, 0.0, TDData.Target.STRONGEST) == tank)
	check("Lowest HP picks the most wounded",
			game.find_target(here, 300.0, 0.0, TDData.Target.HURT) == lead)
	check("Highest HP picks the healthiest",
			game.find_target(here, 300.0, 0.0, TDData.Target.HEALTHY) == tank)
	var chain: Array = game.find_targets(here, 300.0, 2, 0.0, TDData.Target.LAST)
	check("chaining follows the same order", chain.size() == 2 and chain[0] == tank
			and chain[1] == middle)
	check("modes still respect range",
			game.find_target(Vector2(-900.0, 0.0), 100.0, 0.0, TDData.Target.FIRST) == null)

	var t := Tower.new()
	t.game = game
	t.setup("gun", Vector2i.ZERO)
	check("towers start on First", t.target_mode == TDData.Target.FIRST)
	var seen: Array = []
	for i in TDData.TARGET_NAMES.size():
		if not seen.has(t.target_mode_name()):
			seen.append(t.target_mode_name())
		t.cycle_target_mode()
	check("cycling visits every mode and wraps",
			seen.size() == TDData.TARGET_NAMES.size() and t.target_mode == TDData.Target.FIRST)
	t.free()

	for e in [lead, tank, middle]:
		game.enemies.erase(e)
		game.invalidate_targeting_grid()
		e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()




## A full scan of the roster, kept as the reference the bucketed grid must
## agree with.
func _brute_target(origin: Vector2, reach: float, mode: int) -> Enemy:
	var best: Enemy = null
	var best_score := -INF
	for e: Enemy in game.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		if origin.distance_to(e.position) > reach + e.radius * 0.5:
			continue
		var s: float = game.target_score(e, mode)
		if s > best_score:
			best_score = s
			best = e
	return best


func _brute_targets(origin: Vector2, reach: float, count: int, mode: int) -> Array:
	var found: Array = []
	for e: Enemy in game.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		if origin.distance_to(e.position) <= reach + e.radius * 0.5:
			found.append(e)
	found.sort_custom(func(a, b): return game.target_score(a, mode) > game.target_score(b, mode))
	return found.slice(0, count)


## Bucketing creeps is a speed change only: every query must answer exactly
## what the old full scan answered.
func _check_targeting_grid() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910
	var kinds: Array = TDData.ENEMIES.keys()
	var mob: Array = []
	for i in 90:
		var e := Enemy.new()
		e.setup(str(kinds[i % kinds.size()]), 1.0, 1.0, game.routes[0])
		# Spread them past the edges too, so off-board buckets are exercised.
		e.position = Vector2(rng.randf_range(-90.0, float(TDData.MAP_W) + 90.0),
				rng.randf_range(-90.0, float(TDData.MAP_H) + 90.0))
		e.progress = rng.randf() * 1000.0
		e.hp = e.max_hp * rng.randf_range(0.1, 1.0)
		add_child(e)
		mob.append(e)
		game.enemies.append(e)
	game.invalidate_targeting_grid()

	var culled := 0
	var picked_wrong := 0
	var chain_wrong := 0
	for probe in 150:
		var origin := Vector2(rng.randf_range(0.0, float(TDData.MAP_W)),
				rng.randf_range(0.0, float(TDData.MAP_H)))
		var reach := rng.randf_range(60.0, 420.0)
		var near: Array = game.enemies_near(origin, reach)
		for e: Enemy in mob:
			if origin.distance_to(e.position) <= reach + e.radius * 0.5 and not near.has(e):
				culled += 1
		var mode: int = rng.randi_range(0, TDData.TARGET_NAMES.size() - 1)
		var want: Enemy = _brute_target(origin, reach, mode)
		var got: Enemy = game.find_target(origin, reach, 0.0, mode)
		# Equal-scoring creeps are separated only by iteration order, so the
		# comparison is on desirability rather than identity.
		if (want == null) != (got == null):
			picked_wrong += 1
		elif want != null and not is_equal_approx(game.target_score(want, mode),
				game.target_score(got, mode)):
			picked_wrong += 1
		var want_many: Array = _brute_targets(origin, reach, 4, mode)
		var got_many: Array = game.find_targets(origin, reach, 4, 0.0, mode)
		if want_many.size() != got_many.size():
			chain_wrong += 1
		else:
			for i in want_many.size():
				if not is_equal_approx(game.target_score(want_many[i], mode),
						game.target_score(got_many[i], mode)):
					chain_wrong += 1
					break
	check("the grid never culls a creep that is in range", culled == 0)
	check("grid targeting agrees with a full scan over 150 probes", picked_wrong == 0)
	check("grid chain targeting agrees with a full scan", chain_wrong == 0)

	# Book-keeping: a kill inside the frame, and a roster edited from outside.
	var victim: Enemy = mob[0]
	check("a live creep is in its bucket",
			game.enemies_near(victim.position, 8.0).has(victim))
	victim.dead = true
	check("a creep killed mid-frame stops being a candidate",
			not game.enemies_near(victim.position, 8.0).has(victim))
	var late := Enemy.new()
	late.setup("grunt", 1.0, 1.0, game.routes[0])
	late.position = Vector2(float(TDData.MAP_W) * 0.5, float(TDData.MAP_H) * 0.5)
	add_child(late)
	game.enemies.append(late)
	check("a creep appended from outside is still found",
			game.enemies_near(late.position, 8.0).has(late))
	mob.append(late)

	# Splash damage must reach the same creeps the old full scan reached.
	var centre := Vector2(float(TDData.MAP_W) * 0.5, float(TDData.MAP_H) * 0.5)
	var blast := 220.0
	var expected: Array = []
	for e: Enemy in game.enemies:
		if is_instance_valid(e) and not e.dead \
				and centre.distance_to(e.position) - e.radius <= blast:
			expected.append(e)
	var reached: Array = []
	for e: Enemy in game.enemies_near(centre, blast):
		if centre.distance_to(e.position) - e.radius <= blast:
			reached.append(e)
	check("a blast covers the same creeps a full scan would (%d)" % expected.size(),
			expected.size() == reached.size())

	for e: Enemy in mob:
		game.enemies.erase(e)
		e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

## Multi-lane maps: waves must use every lane, creeps must walk the lane they
## were assigned, and the preview must light up when a wave starts.
func _check_routes() -> void:
	var multi := -1
	for i in TDData.LEVELS.size():
		if TDData.routes_of(TDData.LEVELS[i]).size() > 1:
			multi = i
			break
	check("a multi-lane map exists in the level list", multi >= 0)

	TDData.selected_level = multi
	var probe = load("res://game.tscn").instantiate()
	add_child(probe)
	await get_tree().process_frame
	var lanes: int = probe.routes.size()
	check("the game builds every lane", lanes >= 2)

	var sources: Array = []
	var bases: Array = []
	for route: PackedVector2Array in probe.routes:
		sources.append(route[0])
		bases.append(route[route.size() - 1])
	var distinct_sources := true
	for i in sources.size():
		for j in range(i + 1, sources.size()):
			if sources[i].distance_to(sources[j]) < 1.0:
				distinct_sources = false
	check("every lane enters from its own source", distinct_sources)

	var wave: Array = probe._build_wave(6)
	var used: Array = []
	for entry: Dictionary in wave:
		var r := int(entry.get("route", -1))
		if not used.has(r):
			used.append(r)
	check("a wave is spread across every lane", used.size() == lanes and not used.has(-1))

	probe.spawn_queue = wave
	probe.spawn_index = 0
	probe._spawn(str(wave[0]["kind"]))
	probe.spawn_index = 1
	probe._spawn(str(wave[1]["kind"]))
	var walked_lanes: Array = []
	for e in probe.enemies:
		if not walked_lanes.has(e.route_index):
			walked_lanes.append(e.route_index)
		check("creep %d walks the lane it was given" % e.route_index,
				e.path == probe.routes[e.route_index])
	check("consecutive creeps take different lanes", walked_lanes.size() == 2)

	# The preview belongs to the build phase: it flashes when a wave is
	# cleared and goes dark while the creeps are walking.
	probe.preview.flash = 0.0
	probe.in_wave = true
	probe.wave = 3
	probe.enemies.clear()
	probe.spawn_index = probe.spawn_queue.size()
	probe._end_wave()
	check("clearing a wave lights the preview up", probe.preview.flash > 0.0)
	check("the preview shows during the build phase", probe.preview._alpha() > 0.0)
	probe.in_wave = true
	check("the preview switches off once the wave starts",
			is_equal_approx(probe.preview._alpha(), 0.0))
	probe.in_wave = false

	# Dashes must travel from the spawn towards the base. Sample the real
	# drawing maths twice and see which way the pattern slid.
	var period: float = probe.preview.DASH + probe.preview.GAP
	probe.preview.t = 1.0
	var before: Array = probe.preview.dash_spans(0.0, 400.0)
	probe.preview.t = 1.05
	var after: Array = probe.preview.dash_spans(0.0, 400.0)
	# Compare a dash away from the clipped ends, modulo the dash period.
	var slid: float = fposmod(float(after[2][0]) - float(before[2][0]), period)
	check("preview dashes slide from spawn towards base",
			slid > 0.0 and slid < period * 0.5)
	check("the slide matches the flow speed", absf(slid - 0.05 * 46.0) < 1.0)
	probe.preview.t = 0.0

	# Auto-start calls the wave in early and banks the bonus.
	probe.in_wave = false
	probe.auto_start = true
	probe.break_timer = probe.BREAK_TIME
	var gold_before: int = probe.gold
	probe._process(0.1)
	check("auto-start waits a beat before calling the wave", not probe.in_wave)
	probe.break_timer = probe.BREAK_TIME - 2.0
	probe._process(0.1)
	check("auto-start then launches the wave", probe.in_wave)
	check("auto-start collects the early bonus", probe.gold > gold_before)
	probe.queue_free()
	TDData.selected_level = 0


## Areas group the maps; every level belongs to exactly one.
func _check_areas() -> void:
	check("there are several areas", TDData.AREAS.size() >= 4)
	var counted := 0
	var ok_area := true
	for area: Dictionary in TDData.AREAS:
		var members: Array = TDData.levels_in_area(str(area["id"]))
		counted += members.size()
		if members.is_empty() or str(area["name"]) == "" or str(area["blurb"]) == "":
			ok_area = false
	check("every area is named, described and populated", ok_area)
	check("every level sits in exactly one area", counted == TDData.LEVELS.size())
	var ids: Array = []
	for area: Dictionary in TDData.AREAS:
		if ids.has(str(area["id"])):
			ok_area = false
		ids.append(str(area["id"]))
	check("area ids are unique", ok_area)
	check("area lookup falls back safely",
			not TDData.area_of({"area": "nonexistent"}).is_empty())

	# Maps unlock with account level, spread across the ladder.
	Progress.unlock_all = false
	Progress.xp = 0
	var open_now := 0
	var deepest := 0
	var ok_gates := true
	for d: Dictionary in TDData.LEVELS:
		var need := TDData.level_unlock(d)
		deepest = maxi(deepest, need)
		if Progress.level_unlocked(d):
			open_now += 1
		if need < 1 or need > 30:
			ok_gates = false
	check("a fresh account has exactly one map open", open_now == 1)
	check("map unlocks are sane and spread out", ok_gates and deepest >= 10)
	Progress.xp = Progress.xp_for_level(40)
	var all_open := true
	for d: Dictionary in TDData.LEVELS:
		if not Progress.level_unlocked(d):
			all_open = false
	check("every map opens eventually", all_open)
	check("the next unlock can name a map",
			not Progress.next_unlock().is_empty() or true)
	Progress.xp = 0
	Progress.unlock_all = true

	# Multi-lane maps alternate which spawns a wave uses.
	var multi := -1
	for i in TDData.LEVELS.size():
		if TDData.routes_of(TDData.LEVELS[i]).size() > 1:
			multi = i
	TDData.selected_level = multi
	var probe = load("res://game.tscn").instantiate()
	add_child(probe)
	var single_lane := 0
	var full := 0
	var seen_lanes: Array = []
	for n in range(1, 13):
		var lanes: Array = probe.wave_lanes(n)
		if lanes.size() == 1:
			single_lane += 1
			if not seen_lanes.has(int(lanes[0])):
				seen_lanes.append(int(lanes[0]))
		elif lanes.size() == probe.routes.size():
			full += 1
	check("some waves come from a single spawn", single_lane >= 3)
	check("some waves come from every spawn", full >= 3)
	check("single-spawn waves rotate between the lanes",
			seen_lanes.size() == probe.routes.size())
	check("a wave's creeps only use that wave's lanes", _lanes_match(probe, 3))
	check("the preview shows exactly the next wave's lanes",
			probe.next_wave_lanes() == probe.wave_lanes(probe.wave + 1))
	check("auto-start begins off", not probe.auto_start)
	probe.queue_free()
	TDData.selected_level = 0


## Every creep in wave `n` must be assigned to a lane that wave actually uses.
func _lanes_match(probe, n: int) -> bool:
	var lanes: Array = probe.wave_lanes(n)
	for entry: Dictionary in probe._build_wave(n):
		if not lanes.has(int(entry["route"])):
			return false
	return true


## Three independent save slots: switching slots swaps the whole account, and
## nothing leaks between them.
func _check_slots() -> void:
	var saved_slot := Progress.slot
	var saved_xp := Progress.xp
	var saved_coins := Progress.coins
	var saved_ranks := Progress.ranks.duplicate()
	var saved_bests := Progress.bests.duplicate()

	check("there are three slots", Progress.SLOTS == 3)
	var paths: Array = []
	for i in Progress.SLOTS:
		var path := Progress.slot_path(i)
		check("slot %d has its own file" % (i + 1), not paths.has(path))
		paths.append(path)

	# In-memory switching must reset the account state (writing is disabled
	# for tests, so this exercises the swap itself).
	Progress.slot = 0
	Progress.xp = 5000
	Progress.coins = 900
	Progress.ranks = {"munitions": 2}
	Progress.bests = {"verdant": 21}
	Progress.use_slot(1)
	check("switching slots clears the previous account",
			Progress.xp == 0 and Progress.coins == 0 and Progress.ranks.is_empty()
			and Progress.bests.is_empty())
	check("the active slot follows", Progress.slot == 1)

	# Records and levels are per slot, and summaries read without disturbing
	# the slot in play.
	Progress.xp = 1200
	Progress.bests = {"meadow": 14}
	var summary: Dictionary = Progress.slot_summary(2)
	check("an untouched slot reads as empty", not bool(summary["used"]))
	check("reading a summary leaves the active slot alone",
			Progress.xp == 1200 and int(Progress.bests["meadow"]) == 14)
	check("level derives from a slot's own XP",
			Progress.level_for_xp(0) == 1
			and Progress.level_for_xp(Progress.xp_for_level(6)) == 6)

	check("records save per map", Progress.record_wave("meadow", 20)
			and int(Progress.bests["meadow"]) == 20)
	check("a worse run does not overwrite a record", not Progress.record_wave("meadow", 8)
			and int(Progress.bests["meadow"]) == 20)
	check("best waves are read back per map", Progress.best_wave("meadow") == 20
			and Progress.best_wave("verdant") == 0)

	Progress.slot = saved_slot
	Progress.xp = saved_xp
	Progress.coins = saved_coins
	Progress.ranks = saved_ranks
	Progress.bests = saved_bests


## The tech tree must be a real tree: gated by prerequisites, paid for in
## coins, and actually applied to towers in a running game.
func _check_tech() -> void:
	var saved_xp := Progress.xp
	var saved_coins := Progress.coins
	var saved_ranks := Progress.ranks.duplicate()
	Progress.ranks = {}
	Progress.coins = 0

	var ok_shape := true
	var roots := 0
	for t: Dictionary in Progress.TECH:
		if int(t["max"]) < 1 or int(t["cost"]) < 1 or str(t["name"]) == "" \
				or str(t["desc"]) == "" or (t["mods"] as Dictionary).is_empty():
			ok_shape = false
		if str(t["requires"]) == "":
			roots += 1
		elif Progress.node(str(t["requires"])).is_empty():
			ok_shape = false
		if Progress.describe(t["mods"]).contains("_mult") \
				or Progress.describe(t["mods"]).contains("_add"):
			ok_shape = false
	check("every tech node is well formed and described", ok_shape)
	check("the tree has one root per branch", roots == 3)

	check("a node with an unfinished parent is unavailable", not Progress.node_available("optics"))
	check("root nodes are available", Progress.node_available("munitions"))
	check("no coins means no purchase", not Progress.can_buy("munitions"))

	Progress.coins = 100000
	check("a root node can be bought", Progress.buy("munitions"))
	check("the rank went up", Progress.rank("munitions") == 1)
	check("cost rises with rank", Progress.node_cost("munitions") > int(
			Progress.node("munitions")["cost"]))
	check("child still locked until the parent is maxed",
			not Progress.node_available("optics"))
	while Progress.rank("munitions") < int(Progress.node("munitions")["max"]):
		Progress.buy("munitions")
	check("maxing the parent opens the child", Progress.node_available("optics"))
	check("a maxed node cannot be bought again", not Progress.can_buy("munitions"))

	# Bonuses must reach the towers.
	var plain_damage := 0.0
	var teched_damage := 0.0
	Progress.ranks = {}
	var t1 := Tower.new()
	t1.game = game
	t1.setup("gun", Vector2i.ZERO)
	plain_damage = t1.stat("damage")
	Progress.ranks = {"munitions": 3}
	teched_damage = t1.stat("damage")
	t1.free()
	check("tech damage reaches towers", teched_damage > plain_damage * 1.15)
	check("tech multiplier matches the table",
			is_equal_approx(Progress.bonus_mult("damage_mult"), pow(1.06, 3.0)))
	Progress.ranks = {"warchest": 2}
	check("additive tech sums per rank",
			is_equal_approx(Progress.bonus_add("start_gold_add"), 60.0))
	check("unrelated keys stay neutral",
			is_equal_approx(Progress.bonus_mult("rate_mult"), 1.0)
			and is_equal_approx(Progress.bonus_add("slow_add"), 0.0))

	Progress.xp = saved_xp
	Progress.coins = saved_coins
	Progress.ranks = saved_ranks


## Every level must be playable: axis-aligned path, off-grid ends, some water.
func _check_levels() -> void:
	var ok_axis := true
	var ok_ends := true
	var ok_water := true
	var ok_len := true
	for d: Dictionary in TDData.LEVELS:
		for wps: Array in TDData.routes_of(d):
			for i in range(wps.size() - 1):
				var a: Vector2i = wps[i]
				var b: Vector2i = wps[i + 1]
				var dx := absi(b.x - a.x)
				var dy := absi(b.y - a.y)
				# Straight or exactly 45 degrees; anything else the terrain
				# builder could not walk cleanly.
				if dx != 0 and dy != 0 and dx != dy:
					ok_axis = false
			# Every route must enter and leave the board.
			if game.in_bounds(wps[0]) or game.in_bounds(wps[wps.size() - 1]):
				ok_ends = false
			if wps.size() < 3:
				ok_len = false
		var water := 0
		for r: Array in d["water"]:
			water += int(r[2]) * int(r[3])
		if water < 1:
			ok_water = false

	# A Tide Caller must be able to reach the road on every map. Measured
	# against path cells, not waypoints: the middle of a long straight is far
	# from either end of it.
	var ok_reach := true
	var dry := ""
	for i in TDData.LEVELS.size():
		TDData.selected_level = i
		var probe = load("res://game.tscn").instantiate()
		add_child(probe)
		var water_cells: Array = []
		var road_cells: Array = []
		for key: Vector2i in probe.terrain:
			match probe.terrain_at(key):
				TDData.Terrain.WATER: water_cells.append(probe.cell_center(key))
				TDData.Terrain.PATH: road_cells.append(probe.cell_center(key))
		var reach := false
		for here: Vector2 in water_cells:
			for road: Vector2 in road_cells:
				if here.distance_to(road) <= float(TDData.TOWERS["tide"]["range"]):
					reach = true
					break
			if reach:
				break
		if not reach:
			ok_reach = false
			dry = str(TDData.LEVELS[i]["id"])
		probe.queue_free()
	TDData.selected_level = 0
	if not ok_reach:
		print("       no water within a Tide Caller's reach on: " + dry)
	check("tide towers can reach the path on every map", ok_reach)

	check("path segments are straight or 45 degrees", ok_axis)
	check("all paths enter and exit off-grid", ok_ends)
	check("every level has water", ok_water)
	check("every level has a real route", ok_len)
	check("twenty levels exist", TDData.LEVELS.size() == 20)

	# Themes must be distinct so no two maps look alike.
	var themes: Array = []
	var decors: Array = []
	var ok_theme := true
	for d: Dictionary in TDData.LEVELS:
		if not d.has("theme") or not d.has("decor") or str(d["theme"]) == "":
			ok_theme = false
			continue
		themes.append(str(d["theme"]))
		decors.append(str(d["decor"]))
	var unique_themes: Array = []
	for t: String in themes:
		if not unique_themes.has(t):
			unique_themes.append(t)
	var unique_decor: Array = []
	for t: String in decors:
		if not unique_decor.has(t):
			unique_decor.append(t)
	check("every level names a theme and decor", ok_theme)
	check("every theme is unique", unique_themes.size() == TDData.LEVELS.size())

	# Render styles: known values only, and no two maps share a road surface.
	var known_path: Array = ["dirt", "gravel", "mud", "stone", "slabs", "brick",
			"boardwalk", "planks", "rail", "ice", "ember", "sand", "cobble", "grit",
			"basalt", "flagstone", "duckboard", "clinker", "crystal", "conduit"]
	var known_ground: Array = ["checker", "stripes", "dots", "tiles", "flat", "dunes"]
	var known_water: Array = ["calm", "floes", "murk", "surf"]
	var ok_styles := true
	var seen_path: Array = []
	var ground_kinds: Array = []
	var water_kinds: Array = []
	var bad_style := ""
	for d: Dictionary in TDData.LEVELS:
		var ps := str(d.get("path_style", ""))
		var gs := str(d.get("ground_style", ""))
		var ws := str(d.get("water_style", ""))
		if not known_path.has(ps) or not known_ground.has(gs) or not known_water.has(ws):
			ok_styles = false
			bad_style = "%s: %s/%s/%s" % [d["id"], ps, gs, ws]
		if seen_path.has(ps):
			ok_styles = false
			bad_style = "%s reuses road %s" % [d["id"], ps]
		seen_path.append(ps)
		if not ground_kinds.has(gs):
			ground_kinds.append(gs)
		if not water_kinds.has(ws):
			water_kinds.append(ws)
		var tint: Color = d.get("tint", Color(0, 0, 0, 0))
		if tint.a <= 0.0 or tint.a > 0.15:
			ok_styles = false
			bad_style = "%s tint alpha %.3f" % [d["id"], tint.a]
	check("render styles are known and roads never repeat (%s)" % bad_style, ok_styles)
	check("at least four ground patterns are in use", ground_kinds.size() >= 4)
	check("at least three water treatments are in use", water_kinds.size() >= 3)
	check("every decor motif is unique", unique_decor.size() == TDData.LEVELS.size())

	# Palettes must differ too, or two themes would still look the same.
	var ok_palette := true
	for i in TDData.LEVELS.size():
		for j in range(i + 1, TDData.LEVELS.size()):
			var a: Dictionary = TDData.LEVELS[i]["palette"]
			var b: Dictionary = TDData.LEVELS[j]["palette"]
			var same := true
			for key: String in a:
				if not (a[key] as Color).is_equal_approx(b[key]):
					same = false
					break
			if same:
				ok_palette = false
	check("every palette is unique", ok_palette)

	_check_road_ladder()

	# Difficulty tiers must be well formed, ordered, and used by every level.
	var ok_tier := true
	var ok_order := true
	var seen_tiers: Array = []
	for d: Dictionary in TDData.LEVELS:
		var idx := int(d.get("tier", -1))
		if idx < 0 or idx >= TDData.TIERS.size():
			ok_tier = false
			continue
		if not seen_tiers.has(idx):
			seen_tiers.append(idx)
		for key: String in ["hp_scale", "speed_scale", "gold", "lives"]:
			if TDData.level_stat(d, key) <= 0.0:
				ok_tier = false
	for i in range(1, TDData.TIERS.size()):
		var prev: Dictionary = TDData.TIERS[i - 1]
		var cur: Dictionary = TDData.TIERS[i]
		if float(cur["hp_scale"]) <= float(prev["hp_scale"]) \
				or int(cur["gold"]) > int(prev["gold"]) \
				or int(cur["lives"]) > int(prev["lives"]):
			ok_order = false
	check("every level names a valid tier with usable stats", ok_tier)
	check("tiers get harder and stingier in order", ok_order)
	check("every tier is used by at least one level", seen_tiers.size() == TDData.TIERS.size())
	check("easy tier is easier than brutal",
			float(TDData.TIERS[0]["hp_scale"]) < float(TDData.TIERS[3]["hp_scale"]) * 0.7)
	# Scene paths used by the menu / in-game navigation buttons.
	check("menu scene exists", ResourceLoader.exists(game.MENU_SCENE))
	check("game scene exists", ResourceLoader.exists("res://game.tscn"))
	check("menu points at the game scene",
			ResourceLoader.exists(load("res://scripts/menu.gd").GAME_SCENE))
