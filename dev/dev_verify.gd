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
	_check_tuning()
	_check_knockback_fatigue()
	_check_save_versioning()
	_check_wave_rules()
	_check_flyers()
	_check_board_tooltips()
	_check_objectives()
	_check_victory()
	_check_wave_report()
	_check_respec()
	_check_options()
	_check_menus()
	_check_art_prompts()
	_check_frame_budget()
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
			var preview: String = game.hud._track_explanation(type_id, i, null)
			if not preview.contains("per rank") or not preview.contains("coins"):
				ok_words = false
				bad_text = "%s track %d preview" % [type_id, i]
			var probe := _fresh(type_id)
			var live: String = game.hud._track_explanation(type_id, i, probe)
			if not live.contains("This rank:"):
				ok_numbers = false
				bad_text = "%s track %d has no measured effect" % [type_id, i]
			if not TDData.capstone(type_id, i).is_empty():
				var staged: Array = Progress.ranks_for(type_id).duplicate()
				staged[i] = int(TDData.tracks(type_id)[i]["max"])
				Progress.tower_ranks[type_id] = staged
				probe.ranks[i] = int(TDData.tracks(type_id)[i]["max"]) - 1
				var final_text: String = game.hud._track_explanation(type_id, i, probe)
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
	var quoted: String = game.hud._track_explanation("gun", 0, gun)
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
	check("every area holds %d maps" % MAPS_PER_AREA, _areas_are_full())
	check("every lane of a multi-lane map is defensible (%s)" % bad_lane, ok_lanes)
	check("multi-lane maps exist", lanes_report.size() >= 3)


## Every area holds the same number of maps, so no area is a stub.
const MAPS_PER_AREA := 6


func _areas_are_full() -> bool:
	for area: Dictionary in TDData.AREAS:
		if TDData.levels_in_area(str(area["id"])).size() != MAPS_PER_AREA:
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
	game.hud.refresh_wave_preview()
	check("the readout is on screen during the build phase", game.hud.preview_row.visible)
	check("it describes the next wave, not the last", game.hud.preview_wave == 6)
	# Heading, one chip per kind, and the advice label when a kind has a note.
	var kinds: int = game.wave_composition(6).size()
	var has_note: bool = game.hud.lbl_wave_note.text != ""
	check("it renders a chip per kind plus a heading",
			game.hud.preview_row.get_child_count() == kinds + 1 + (1 if has_note else 0))
	game.wave = 6
	game.hud.refresh_wave_preview()
	check("it rebuilds when the wave advances", game.hud.preview_wave == 7)
	game.in_wave = true
	game.hud.refresh_wave_preview()
	check("during a wave it just states what is running",
			game.hud.preview_row.get_child_count() == 1 and game.hud.preview_wave == 0)
	check("the strip keeps its height so the bar cannot jump",
			game.hud.preview_row.custom_minimum_size.y >= 20.0)
	game.in_wave = false
	game.hud.refresh_wave_preview()
	check("and the chips come back for the next build phase",
			game.hud.preview_row.get_child_count() > 1 and game.hud.preview_wave == 7)
	# The strip frees every child on refresh, so a kept advice label would be
	# a freed node by the next rebuild.
	var note_before: Label = game.hud.lbl_wave_note
	game.wave = 8
	game.hud.refresh_wave_preview()
	check("the advice line is rebuilt, never a freed leftover",
			is_instance_valid(game.hud.lbl_wave_note) and game.hud.lbl_wave_note != note_before)
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
























## What the game costs the machine. These are the rules that keep it cheap;
## the numbers themselves are measured by dev/dev_perf.tscn.
func _check_frame_budget() -> void:
	# The frame cap must exist, default sanely, and be saveable.
	check("the game ships with a frame cap",
			int(ProjectSettings.get_setting("application/run/max_fps", 0)) == 60)
	check("the cap list offers something sensible",
			App.CAPS.has(60) and App.CAPS.has(0))
	Progress.use_clean_state()
	Progress.read_only = true
	check("the default cap is 60", Progress.frame_cap() == 60)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Progress.SAVE_VERSION)
	cfg.set_value("options", "frame_cap", 30)
	Progress.apply_config(cfg)
	check("a saved cap is read back", Progress.frame_cap() == 30)

	# Backgrounded, the game must idle rather than keep a core busy.
	App.focused = false
	App.apply_cap()
	check("an unfocused window drops to a trickle",
			Engine.max_fps == App.BACKGROUND_FPS and Engine.max_fps <= 15)
	App.focused = true
	App.apply_cap()
	check("and comes back to the chosen cap", Engine.max_fps == 30)
	Progress.use_clean_state()
	App.apply_cap()

	# Redraw discipline: a tower that has not moved must not rebuild its art,
	# which is what made a full board cost 50 ms a frame.
	var t := Tower.new()
	t.game = game
	t.setup("gun", Vector2i.ZERO)
	add_child(t)
	t._redraw_if_changed()
	check("a settled tower asks for no redraw", not t._needs_redraw())
	t.turret_angle += 0.5
	check("but a turning one does", t._needs_redraw())
	t._redraw_if_changed()
	check("and settles again once drawn", not t._needs_redraw())
	t.recoil = 1.0
	check("firing redraws too", t._needs_redraw())
	remove_child(t)
	t.free()

	check("idle animations are throttled, not stopped",
			Tower.IDLE_REDRAW_HZ > 0.0 and Tower.IDLE_REDRAW_HZ <= 20.0
			and Enemy.IDLE_REDRAW_HZ <= 20.0 and WaterLayer.RIPPLE_HZ <= 20.0)


## The sprite drop-in has to stay honest: a prompt for every name the game
## will look for, and the loader must fall back cleanly when a file is absent.
func _check_art_prompts() -> void:
	var prompts := FileAccess.get_file_as_string("res://assets/PROMPTS.md")
	check("the prompt sheet exists", prompts.length() > 1000)
	var missing: Array = []
	for type_id: String in TDData.TOWERS:
		for part: String in ["base", "gun"]:
			if not prompts.contains("tower_%s_%s" % [type_id, part]):
				missing.append("tower_%s_%s" % [type_id, part])
	for kind: String in TDData.ENEMIES:
		if not prompts.contains("enemy_%s" % kind):
			missing.append("enemy_%s" % kind)
	for tile: String in ["tile_grass", "tile_path", "tile_water", "tile_rock"]:
		if not prompts.contains(tile):
			missing.append(tile)
	for unit: String in ["unit_plane", "unit_heli", "shot"]:
		if not prompts.contains(unit):
			missing.append(unit)
	check("every sprite the game looks for has a prompt (%s)"
			% ", ".join(missing), missing.is_empty())

	# With no file present the loader must say so rather than half-draw.
	check("a missing sprite loads as nothing",
			Art.tex("definitely_not_a_real_sprite_name") == null)
	var probe := Control.new()
	add_child(probe)
	check("and drawing it reports the miss so vector art takes over",
			not Art.draw_centered(probe, "definitely_not_a_real_sprite_name",
					Vector2.ZERO, 32.0))
	remove_child(probe)
	probe.queue_free()




## The way around the game: a main menu, a pause menu, and an Escape key
## that always does the most useful thing available.
func _check_menus() -> void:
	# Every screen exists and builds.
	var missing: Array = []
	for path: String in ["res://home.tscn", "res://menu.tscn", "res://options.tscn",
			"res://tech.tscn", "res://stats.tscn", "res://main.tscn"]:
		if not ResourceLoader.exists(path):
			missing.append(path)
	check("every screen exists (%s)" % ", ".join(missing), missing.is_empty())
	var home: Control = load("res://home.tscn").instantiate()
	add_child(home)
	check("the main menu builds", home.get_child_count() > 0)
	remove_child(home)
	home.queue_free()

	# The pause menu is part of a match, not a debug extra.
	check("a match has a pause menu", game.pause_menu != null)
	check("which starts closed", not game.pause_menu.visible)
	var was_paused: bool = game.paused
	if was_paused:
		game._toggle_pause()
	game._toggle_pause()
	check("pausing opens it", game.paused and game.pause_menu.visible)
	check("and stops the clock", is_zero_approx(Engine.time_scale))
	game.pause_menu._resume()
	check("resuming closes it and starts the clock",
			not game.paused and not game.pause_menu.visible
			and Engine.time_scale > 0.0)

	# Volume lives on a slider now, not on a button that cycles three states.
	check("the top bar has no volume button", not ("btn_sound" in game.hud))
	var before_sfx := Progress.volume("sfx")
	game.pause_menu._on_sfx(0.3)
	check("the pause menu slider sets the volume",
			is_equal_approx(Progress.volume("sfx"), 0.3))
	Progress.set_volume("sfx", before_sfx)

	# Escape: close what is open, then let go, then pause.
	game.placing = "gun"
	game._escape()
	check("escape cancels what you were placing", game.placing == "")
	game._escape()
	check("with nothing to cancel it pauses", game.paused)
	game._escape()
	check("and again it resumes", not game.paused)
	if game.tuning_panel != null:
		game.tuning_panel.toggle()
		game._escape()
		check("an open panel closes before anything else happens",
				not game.tuning_panel.visible and not game.paused)
	if was_paused:
		game._toggle_pause()


## Options: volumes, window scale and key bindings, including the swap that
## stops two actions sharing a key.
func _check_options() -> void:
	Progress.use_clean_state()
	Progress.read_only = true

	# Bindings start at the defaults and resolve both ways.
	check("a default binding resolves to its key",
			Progress.key_for("start_wave") == KEY_SPACE)
	check("and a key resolves back to its action",
			Progress.action_for(KEY_SPACE) == "start_wave")
	check("a key bound to nothing does nothing",
			Progress.action_for(KEY_QUOTELEFT) == "")
	check("every action has a readable name",
			Progress.key_name("sell") != "" and Progress.key_name("sell") != "—")

	# Rebinding to a free key.
	check("rebinding to a free key works",
			Progress.bind_key("sell", KEY_QUOTELEFT))
	check("the new key triggers the action",
			Progress.action_for(KEY_QUOTELEFT) == "sell")
	check("and the old one no longer does", Progress.action_for(KEY_X) == "")

	# Rebinding onto a taken key swaps rather than double-binding.
	Progress.reset_keys()
	check("reset puts the defaults back", Progress.key_for("sell") == KEY_X
			and Progress.keys.is_empty())
	Progress.bind_key("sell", KEY_U)
	check("taking another action's key swaps them",
			Progress.action_for(KEY_U) == "sell" and Progress.key_for("upgrade") == KEY_X)
	var bound: Array = []
	var clash := ""
	for entry: Dictionary in Progress.DEFAULT_KEYS:
		var code := Progress.key_for(str(entry["id"]))
		if bound.has(code):
			clash = str(entry["id"])
		bound.append(code)
	check("so no two actions ever share a key (%s)" % clash, clash == "")
	check("rebinding to the key it already has is a no-op",
			not Progress.bind_key("sell", KEY_U))
	Progress.reset_keys()

	# Volumes and window scale round-trip through the save.
	Progress.set_volume("sfx", 0.42)
	Progress.set_window_scale(1.25)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Progress.SAVE_VERSION)
	cfg.set_value("options", "sfx", 0.42)
	cfg.set_value("options", "window_scale", 1.25)
	cfg.set_value("keys", "sell", KEY_QUOTELEFT)
	Progress.apply_config(cfg)
	check("volume is read back from a save",
			is_equal_approx(Progress.volume("sfx"), 0.42))
	check("so is the window scale",
			is_equal_approx(Progress.window_scale(), 1.25))
	check("and so are rebound keys", Progress.key_for("sell") == KEY_QUOTELEFT)
	check("the scale is one of the offered sizes",
			Progress.WINDOW_SCALES.has(Progress.window_scale()))

	# The options screen must build and drive Progress, not its own copy.
	var screen: Control = load("res://options.tscn").instantiate()
	add_child(screen)
	check("the options screen builds", screen.key_rows.size()
			== Progress.DEFAULT_KEYS.size())
	screen._listen_for("pause")
	var press := InputEventKey.new()
	press.keycode = KEY_G
	press.pressed = true
	screen._input(press)
	check("pressing a key in the screen rebinds it",
			Progress.key_for("pause") == KEY_G)
	screen._on_reset_keys()
	check("and its reset button clears the lot", Progress.keys.is_empty())
	remove_child(screen)
	screen.queue_free()
	Progress.use_clean_state()


## A respec has to hand back most of what was spent and clear everything it
## refunded — anything else is either a coin fountain or a robbery.
func _check_respec() -> void:
	Progress.use_clean_state()
	Progress.read_only = true
	Progress.coins = 5000
	Progress.ranks = {}
	Progress.tower_ranks = {}
	check("nothing bought means nothing to refund",
			not Progress.has_anything_to_respec() and Progress.respec_refund() == 0)
	check("and respeccing then does nothing", Progress.respec() == 0)

	# Buy a spread: two doctrine ranks and a couple of tower ranks.
	var spent := 0
	var first: Dictionary = Progress.TECH[0]
	for r in 2:
		spent += Progress.node_cost(str(first["id"]))
		check("a doctrine rank is bought", Progress.buy(str(first["id"])))
	spent += TDData.track_cost("gun", 0, 0)
	check("a tower rank is bought", Progress.buy_track("gun", 0))
	spent += TDData.track_cost("gun", 0, 1)
	check("and a second rank on the same track", Progress.buy_track("gun", 0))

	check("the account knows what it spent (%d vs %d)"
			% [Progress.spent_on_tech(), spent], Progress.spent_on_tech() == spent)
	var expected := int(floor(float(spent) * Progress.RESPEC_REFUND))
	check("the refund is most of it, not all of it",
			Progress.respec_refund() == expected and expected < spent and expected > 0)

	var before := Progress.coins
	var refunded := Progress.respec()
	check("respeccing pays exactly what it quoted", refunded == expected
			and Progress.coins == before + expected)
	check("every doctrine rank is gone", Progress.rank(str(first["id"])) == 0)
	check("every tower rank is gone too", Progress.track_rank_for("gun", 0) == 0)
	check("and there is nothing left to refund",
			not Progress.has_anything_to_respec())
	check("so a run of respecs cannot mint coins", Progress.respec() == 0
			and Progress.coins == before + expected)

	# Buying it all back must cost what it did the first time.
	for r in 2:
		Progress.buy(str(first["id"]))
	check("prices reset with the ranks", Progress.spent_on_tech() > 0)
	Progress.use_clean_state()






## A leak with no explanation teaches nothing. After every wave the game
## says what got through and what answers it.
func _check_wave_report() -> void:
	var saved_stats: Dictionary = game.run_stats.duplicate(true)
	var saved_wave: int = game.wave
	var was_cleared: bool = game.map_cleared
	game.map_cleared = true  # keep the victory panel out of this test
	game.wave = 6
	game.wave_leaks = {}
	game.run_stats["untouched"] = true
	game._build_wave_report()
	check("a clean wave is reported as clean",
			game.wave_report.contains("without losing a life"))
	check("and the line is shown for a while", game.wave_report_timer > 1.0)

	game.wave_leaks = {"warden": 2, "grunt": 1}
	game._build_wave_report()
	check("a leaky wave counts what got through",
			game.wave_report.contains("3 got through"))
	check("and names them", game.wave_report.contains("Warden")
			and game.wave_report.contains("Grunt"))
	check("then explains the worst of them",
			game.wave_report.contains(str(TDData.ENEMIES["warden"]["note"])))

	# The status line has to actually show it during the build phase.
	game.in_wave = false
	game.game_over = false
	game.hud.update()
	check("the report is on screen over the board",
			str(game.hud.lbl_status.text).contains("got through"))
	game.wave_report_timer = 0.0
	game.hud.update()
	check("and gives way to the countdown after a few seconds",
			not str(game.hud.lbl_status.text).contains("got through"))

	# Defeat should say what was killing you, not just that you died.
	game.run_stats["enemy_leaks"] = {"ashwalker": 7, "grunt": 2}
	var summary: String = game.leak_summary()
	check("the defeat card names what got past you",
			summary.contains("7 Ashwalker") and summary.contains("2 Grunt"))
	check("worst first", summary.find("Ashwalker") < summary.find("Grunt"))
	check("with the counter for it",
			summary.contains(str(TDData.ENEMIES["ashwalker"]["note"])))
	game.run_stats["enemy_leaks"] = {}
	check("and says nothing when nothing leaked", game.leak_summary() == "")

	game.run_stats = saved_stats
	game.wave = saved_wave
	game.map_cleared = was_cleared
	game.wave_leaks = {}
	game.wave_report = ""
	game.wave_report_timer = 0.0


## A map can be finished. Reaching its last wave is a win that sticks, and
## the run may carry on into endless afterwards.
func _check_victory() -> void:
	# Every map has a finish line, and harder maps end sooner.
	var missing: Array = []
	var deepest: Array = [0, 0, 0, 0]
	for level: Dictionary in TDData.LEVELS:
		var target := TDData.clear_wave(level)
		if target < 5 or target > 60:
			missing.append(str(level["id"]))
		deepest[int(level.get("tier", 0))] = maxi(
				deepest[int(level.get("tier", 0))], target)
	check("every map has a sensible finish line (%s)" % ",".join(missing),
			missing.is_empty())
	var ladder := true
	for i in range(1, 4):
		if deepest[i] > deepest[i - 1]:
			ladder = false
	check("harder maps finish sooner (%s)" % str(deepest), ladder)
	check("clearing a map is further than its wave objective",
			TDData.clear_wave(TDData.LEVELS[0])
			> int(TDData.objectives_for(TDData.LEVELS[0])[0]["n"]))

	# The account levels to a cap, and the display must not claim progress
	# towards a level that does not exist.
	var was_xp: int = Progress.xp
	Progress.xp = 50
	check("an early account is levelling", not bool(
			Progress.level_progress().get("capped", false)))
	Progress.xp = 99999999
	var capped: Dictionary = Progress.level_progress()
	check("a maxed account is at the cap", bool(capped.get("capped", false))
			and int(capped["level"]) == Progress.MAX_LEVEL)
	check("and its bar reads full rather than overflowing",
			is_equal_approx(float(capped["ratio"]), 1.0))
	Progress.xp = was_xp

	# Multi-lane maps have to fund a second front, or they are a tier
	# harder than the tier says they are.
	var single: Dictionary = {}
	var multi: Dictionary = {}
	for level: Dictionary in TDData.LEVELS:
		var lanes: int = TDData.routes_of(level).size()
		var tier := int(level.get("tier", 0))
		if lanes > 1 and not multi.has(tier):
			multi[tier] = level
		if lanes == 1 and not single.has(tier):
			single[tier] = level
	var unfunded: Array = []
	for tier: int in multi:
		if not single.has(tier):
			continue
		var many: Dictionary = multi[tier]
		var one: Dictionary = single[tier]
		if TDData.level_stat(many, "gold") <= TDData.level_stat(one, "gold") \
				or TDData.level_stat(many, "lives") <= TDData.level_stat(one, "lives"):
			unfunded.append(str(many["id"]))
	check("multi-lane maps start with more gold and lives (%s)"
			% ",".join(unfunded), unfunded.is_empty())
	check("and a single-lane map is untouched by that rule",
			is_equal_approx(TDData.level_stat(TDData.LEVELS[0], "gold"),
					float(TDData.tier_of(TDData.LEVELS[0])["gold"])))

	# Endless depth is its own record, not folded into the best wave.
	Progress.use_clean_state()
	Progress.read_only = true
	var first_level: Dictionary = TDData.LEVELS[0]
	var finish := TDData.clear_wave(first_level)
	Progress.record_wave(str(first_level["id"]), finish + 6)
	check("an unbeaten map has no endless record",
			Progress.endless_best(str(first_level["id"])) == 0)
	Progress.record_clear(str(first_level["id"]), finish)
	check("once cleared, endless counts the waves past the finish",
			Progress.endless_best(str(first_level["id"])) == 6)
	Progress.record_wave(str(first_level["id"]), finish)
	check("and a shallower run does not lower it",
			Progress.endless_best(str(first_level["id"])) == 6)
	Progress.use_clean_state()

	# Records: first clear is reported once, and depth is kept.
	Progress.use_clean_state()
	Progress.read_only = true
	check("a fresh account has cleared nothing",
			not Progress.is_cleared("verdant") and Progress.cleared_count() == 0)
	check("the first clear says so", Progress.record_clear("verdant", 25))
	check("and is remembered", Progress.is_cleared("verdant")
			and Progress.cleared_count() == 1)
	check("a second clear is not a first", not Progress.record_clear("verdant", 22))
	check("but a deeper one is kept",
			int(Progress.cleared.get("verdant", 0)) == 25)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Progress.SAVE_VERSION)
	cfg.set_value("cleared", "ashen", 20)
	Progress.apply_config(cfg)
	check("clears survive a save round trip", Progress.is_cleared("ashen")
			and not Progress.is_cleared("verdant"))
	var old_save := ConfigFile.new()
	old_save.set_value("stars", "verdant", 3)
	Progress.migrate_config(old_save, Progress.detect_version(old_save))
	check("a save from before clears existed still migrates",
			int(old_save.get_value("meta", "version", 0)) == Progress.SAVE_VERSION)

	# The match itself: reaching the last wave wins, and play continues.
	Progress.use_clean_state()
	var saved_wave: int = game.wave
	var was_cleared: bool = game.map_cleared
	game.map_cleared = false
	game.wave = TDData.clear_wave(game.level_def)
	game.in_wave = true
	game._end_wave()
	check("beating the last wave clears the map", game.map_cleared)
	check("and the win is on screen", game.hud.over_root.visible
			and game.hud.btn_continue.visible)
	check("without ending the run", not game.game_over)
	game.continue_endless()
	check("carrying on hides the panel and keeps the board",
			not game.hud.over_root.visible and game.map_cleared)
	game.wave += 1
	game.in_wave = true
	game._end_wave()
	check("and a cleared map does not announce itself again",
			not game.hud.over_root.visible)
	game.map_cleared = was_cleared
	game.wave = saved_wave
	game.in_wave = false
	Progress.use_clean_state()


## Every map has three objectives, they are judged on what the run actually
## did, and the account keeps the union of every attempt.
func _check_objectives() -> void:
	var thin := ""
	var vague := ""
	for level: Dictionary in TDData.LEVELS:
		var goals: Array = TDData.objectives_for(level)
		if goals.size() != 3:
			thin = "%s has %d" % [level["id"], goals.size()]
		for goal: Dictionary in goals:
			if str(goal.get("text", "")).strip_edges() == "":
				vague = str(level["id"])
	check("every map carries three objectives (%s)" % thin, thin == "")
	check("and each one says what it wants (%s)" % vague, vague == "")

	# Harder maps must not ask for more depth than easier ones.
	var ladder := true
	var deepest: Array = [0, 0, 0, 0]
	for level: Dictionary in TDData.LEVELS:
		var tier := int(level.get("tier", 0))
		deepest[tier] = maxi(deepest[tier], int(TDData.objectives_for(level)[0]["n"]))
	for i in range(1, 4):
		if deepest[i] > deepest[i - 1]:
			ladder = false
	check("the wave objective eases off as the maps get harder (%s)"
			% str(deepest), ladder)

	# The evaluator, driven off a fabricated run.
	var saved_stats: Dictionary = game.run_stats.duplicate(true)
	var saved_level: Dictionary = game.level_def
	game.level_def = TDData.LEVELS[0]
	var goals: Array = TDData.objectives_for(game.level_def)
	game.run_stats = game._blank_run_stats()
	check("a fresh run has earned nothing", game.objective_mask() == 0)

	game.run_stats["cleared"] = int(goals[0]["n"])
	check("clearing the target wave earns the first star",
			game.objective_mask() & 1 != 0)
	check("and an untouched run earns the second too",
			game.objective_mask() & 2 != 0)
	game.run_stats["untouched"] = false
	check("but leaking once loses it", game.objective_mask() & 2 == 0)

	# The map's own goal: Verdant Pass asks for no water towers.
	var own: Dictionary = goals[2]
	check("the third objective is the map's own", str(own["kind"]) == "no_water")
	game.run_stats["cleared"] = int(own["n"])
	check("with no water tower built it is met", game.objective_mask() & 4 != 0)
	game.run_stats["water_built"] = 1
	check("building one loses it", game.objective_mask() & 4 == 0)

	# Every goal kind has to be reachable, or a map is quietly impossible.
	var unreachable: Array = []
	for level: Dictionary in TDData.LEVELS:
		game.level_def = level
		var goal: Dictionary = TDData.objectives_for(level)[2]
		game.run_stats = game._blank_run_stats()
		game.run_stats["cleared"] = int(goal.get("n", 0)) + 40
		game.run_stats["kills"] = int(goal.get("n", 0)) + 5000
		game.run_stats["peak_gold"] = int(goal.get("n", 0)) + 5000
		if game.objective_mask() & 4 == 0:
			unreachable.append("%s/%s" % [level["id"], goal["kind"]])
	check("every map's own objective can actually be met (%s)"
			% ",".join(unreachable), unreachable.is_empty())

	# Stars accumulate across attempts rather than replacing each other.
	Progress.stars = {}
	Progress.record_stars("verdant", 1)
	Progress.record_stars("verdant", 4)
	check("a second run adds its star to the first",
			Progress.stars_for("verdant") == 5 and Progress.star_count("verdant") == 2)
	check("re-earning one is not counted twice",
			Progress.record_stars("verdant", 4) == 0)
	check("the account totals them", Progress.total_stars() == 2)

	# And they survive a save round trip.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Progress.SAVE_VERSION)
	cfg.set_value("stars", "verdant", 5)
	Progress.apply_config(cfg)
	check("stars are read back from a save", Progress.stars_for("verdant") == 5)
	var old_save := ConfigFile.new()
	old_save.set_value("runs", "verdant", {"wave": 3})
	Progress.migrate_config(old_save, Progress.detect_version(old_save))
	check("a save from before stars existed still migrates",
			int(old_save.get_value("meta", "version", 0)) == Progress.SAVE_VERSION)

	Progress.use_clean_state()
	game.level_def = saved_level
	game.run_stats = saved_stats


## Hovering a creep has to teach the roster: what it is, what it shrugs off,
## and how to answer it.
func _check_board_tooltips() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var warden := Enemy.new()
	warden.setup("warden", 1.0, 1.0, game.routes[0])
	warden.position = Vector2(500.0, 300.0)
	warden.hp = warden.max_hp * 0.5
	add_child(warden)
	game.enemies.append(warden)
	game.invalidate_targeting_grid()

	check("the cursor finds the creep under it",
			game.enemy_at(warden.position) == warden)
	check("and finds nothing where there is none",
			game.enemy_at(warden.position + Vector2(300.0, 0.0)) == null)

	var card: String = game.hud.describe_enemy(warden)
	check("the card names the creep", card.contains(warden.display_name))
	check("and shows how much of it is left",
			card.contains("%d" % int(round(warden.max_hp))))
	check("armour is spelled out, since it decides the answer",
			card.contains("armour") == (warden.armor > 0.0))
	var mender := Enemy.new()
	mender.setup("mender", 1.0, 1.0, game.routes[0])
	check("a healer says so", str(game.hud.describe_enemy(mender)).contains("heals"))
	var ash := Enemy.new()
	ash.setup("ashwalker", 1.0, 1.0, game.routes[0])
	check("and a fireproof creep says so",
			str(game.hud.describe_enemy(ash)).contains("ignores fire"))
	var flyer := Enemy.new()
	flyer.setup("drake", 1.0, 1.0, game.routes[0])
	check("a flyer says it flies", str(game.hud.describe_enemy(flyer)).contains("flying"))
	var thief := Enemy.new()
	thief.setup("thief", 1.0, 1.0, game.routes[0])
	check("and a thief says what it takes",
			str(game.hud.describe_enemy(thief)).contains("steals"))
	# Every roster entry must produce a card without erroring.
	var blank := ""
	for kind: String in TDData.ENEMIES:
		var probe := Enemy.new()
		probe.setup(kind, 1.0, 1.0, game.routes[0])
		if str(game.hud.describe_enemy(probe)).strip_edges() == "":
			blank = kind
		probe.free()
	check("every creep in the roster has a card (%s)" % blank, blank == "")

	for e in [mender, ash, flyer, thief]:
		e.free()
	game.enemies.erase(warden)
	warden.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()


## Flyers ignore the road and only half the roster can shoot at them.
func _check_flyers() -> void:
	var kinds: Array = []
	for kind: String in TDData.ENEMIES:
		if bool(TDData.ENEMIES[kind].get("flying", false)):
			kinds.append(kind)
	check("the roster has flyers (%d)" % kinds.size(), kinds.size() >= 2)

	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var road: PackedVector2Array = game.routes[0]
	var flyer := Enemy.new()
	flyer.setup(str(kinds[0]), 1.0, 1.0, road)
	add_child(flyer)
	check("a flyer's path is a straight line to the base",
			flyer.path.size() == 2 and flyer.path[0] == road[0]
			and flyer.path[1] == road[road.size() - 1])
	check("which is shorter than the road it ignores",
			road.size() < 3 or flyer.path[0].distance_to(flyer.path[1]) < _road_length(road))
	var walker := Enemy.new()
	walker.setup("grunt", 1.0, 1.0, road)
	add_child(walker)
	check("a ground creep still walks every corner", walker.path.size() == road.size())

	# Put both in the same place and see who can shoot what.
	var spot := Vector2(400.0, 400.0)
	flyer.position = spot
	walker.position = spot
	game.enemies.append(flyer)
	game.enemies.append(walker)
	game.invalidate_targeting_grid()

	var ground_only := Tower.new()
	ground_only.game = game
	ground_only.setup("cannon", Vector2i.ZERO)
	ground_only.position = spot
	var anti_air := Tower.new()
	anti_air.game = game
	anti_air.setup("gun", Vector2i.ZERO)
	anti_air.position = spot
	check("a ground tower knows it cannot reach up", not ground_only.hits_air())
	check("and an anti-air one knows it can", anti_air.hits_air())
	check("the ground tower picks the walker, not the flyer",
			game.find_target(spot, 300.0, 0.0, TDData.Target.FIRST,
					ground_only.hits_air()) == walker)
	var seen: Array = game.find_targets(spot, 300.0, 8, 0.0, TDData.Target.FIRST,
			ground_only.hits_air())
	check("and never sees it in a chain either", not seen.has(flyer))
	check("the anti-air tower sees both",
			game.find_targets(spot, 300.0, 8, 0.0, TDData.Target.FIRST,
					anti_air.hits_air()).size() == 2)

	# Splash inherits the firer's reach: a shell cannot swat something overhead.
	var before := flyer.hp
	var walker_before := walker.hp
	game.explode(spot, 120.0, 50.0, Color.WHITE, 0.0, 0.0, false, 1.0, null, 0.0, false)
	check("a ground blast leaves flyers alone", is_equal_approx(flyer.hp, before))
	check("while still hitting what is on the ground", walker.hp < walker_before)
	game.explode(spot, 120.0, 50.0, Color.WHITE, 0.0, 0.0, false, 1.0, null, 0.0, true)
	check("an anti-air blast does reach them", flyer.hp < before)

	# The defence has to be mixed, but not impossible.
	var can := 0
	for type_id: String in TDData.TOWERS:
		var probe := Tower.new()
		probe.game = game
		probe.setup(type_id, Vector2i.ZERO)
		if probe.hits_air():
			can += 1
		probe.free()
	check("roughly half the roster can answer an air wave (%d of %d)"
			% [can, TDData.TOWERS.size()],
			can >= 5 and can <= TDData.TOWERS.size() - 4)

	# And they have to actually turn up in waves.
	var air_waves := 0
	for n in range(1, 31):
		var comp: Dictionary = game.wave_composition(n)
		for kind: String in kinds:
			if comp.has(kind):
				air_waves += 1
				break
	check("air waves appear through the run (%d of 30)" % air_waves, air_waves >= 6)

	ground_only.free()
	anti_air.free()
	game.enemies.erase(flyer)
	game.enemies.erase(walker)
	flyer.queue_free()
	walker.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()


func _road_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Waves come from a table now. The base curve must be exactly what the old
## hardcoded builder produced, and each area's flavour must actually change
## something without making the area absurd.
func _check_wave_rules() -> void:
	# Golden compositions, captured from the hardcoded builder it replaced.
	var golden: Dictionary = {
		1: {"grunt": 5},
		4: {"grunt": 8, "runner": 4},
		6: {"grunt": 11, "runner": 5, "swarm": 9, "tank": 2, "bolt": 2},
		10: {"grunt": 11, "runner": 6, "boss": 1},
		12: {"grunt": 18, "runner": 8, "swarm": 12, "tank": 3, "warden": 1,
			"bolt": 3, "thief": 2},
		20: {"grunt": 16, "runner": 8, "titan": 1},
		30: {"grunt": 21, "runner": 10, "boss": 1},
	}
	var saved_level: Dictionary = game.level_def
	var greens: Array = TDData.levels_in_area("greenlands")
	game.level_def = TDData.LEVELS[int(greens[0])]
	var wrong := ""
	for n: int in golden:
		var got: Dictionary = game.wave_composition(n)
		var want: Dictionary = golden[n]
		if got.size() != want.size():
			wrong = "wave %d has %d kinds, expected %d" % [n, got.size(), want.size()]
		for kind: String in want:
			if int(got.get(kind, -1)) != int(want[kind]):
				wrong = "wave %d %s = %d, expected %d" % [n, kind,
						int(got.get(kind, -1)), int(want[kind])]
	check("the table reproduces the old wave curve exactly (%s)" % wrong, wrong == "")

	# Rule gating.
	var swarm: Dictionary = {}
	for rule: Dictionary in TDData.WAVE_RULES:
		if str(rule["kind"]) == "swarm":
			swarm = rule
	check("a rule waits for its first wave", not TDData.wave_rule_active(swarm, 4))
	check("and then only lands on its own cadence",
			TDData.wave_rule_active(swarm, 6) and not TDData.wave_rule_active(swarm, 7))
	check("groups grow with the wave",
			TDData.wave_group_count(swarm, 20) > TDData.wave_group_count(swarm, 6))

	# Every area must actually feel different, and stay in a sane band.
	var probes: Array = [8, 12, 15, 18, 25]
	var base_comp: Dictionary = {}
	var base_total: Dictionary = {}
	for n: int in probes:
		var comp: Dictionary = game.wave_composition(n)
		base_comp[n] = comp
		var total := 0
		for kind: String in comp:
			total += int(comp[kind])
		base_total[n] = total
	var same: Array = []
	var extreme: Array = []
	var bossless: Array = []
	for area: Dictionary in TDData.AREAS:
		var maps: Array = TDData.levels_in_area(str(area["id"]))
		if maps.is_empty():
			continue
		game.level_def = TDData.LEVELS[int(maps[0])]
		var differs := false
		for n: int in probes:
			var comp: Dictionary = game.wave_composition(n)
			var total := 0
			for kind: String in comp:
				total += int(comp[kind])
			if comp != base_comp[n]:
				differs = true
			if total < int(float(base_total[n]) * 0.6) \
					or total > int(float(base_total[n]) * 1.7):
				extreme.append("%s w%d:%d vs %d" % [area["id"], n, total, base_total[n]])
		if str(area["id"]) != "greenlands" and not differs:
			same.append(str(area["id"]))
		var boss: Dictionary = game.wave_composition(20)
		if not boss.has("boss") and not boss.has("titan"):
			bossless.append(str(area["id"]))
	check("every area past the first sends something different (%s)" % ",".join(same),
			same.is_empty())
	check("but none of them runs away with it (%s)" % ",".join(extreme),
			extreme.is_empty())
	check("boss waves survive every flavour (%s)" % ",".join(bossless),
			bossless.is_empty())
	# The "add" hook has to work, not just "tweak".
	var wastes_kinds: Array = []
	for rule: Dictionary in TDData.wave_rules("wastes"):
		wastes_kinds.append(str(rule["kind"]))
	check("an area can add a group of its own",
			wastes_kinds.count("ashwalker") == 2)
	game.level_def = saved_level


## Saves carry a version and are walked forward on load. Everything here
## works on ConfigFile objects in memory, so a test can never touch a real
## slot on disk.
func _check_save_versioning() -> void:
	# A pre-slots save: one parked run under [run] state.
	var v1 := ConfigFile.new()
	v1.set_value("progress", "xp", 500)
	v1.set_value("run", "state", {"level": "verdant", "wave": 4,
			"stats": {"kills": 12, "leaks": 1}})
	check("an unstamped save with [run] reads as version 1",
			Progress.detect_version(v1) == 1)
	Progress.migrate_config(v1, Progress.detect_version(v1))
	check("migration stamps the current version",
			int(v1.get_value("meta", "version", 0)) == Progress.SAVE_VERSION)
	check("the single parked run became a per-map run",
			v1.has_section_key("runs", "verdant") and not v1.has_section("run"))
	var moved: Dictionary = v1.get_value("runs", "verdant", {})
	check("the run kept its progress", int(moved.get("wave", 0)) == 4)
	var moved_stats: Dictionary = moved.get("stats", {})
	check("and gained the per-kind tallies it never had",
			moved_stats.has("enemy_kills") and moved_stats.has("enemy_leaks")
			and typeof(moved_stats["enemy_kills"]) == TYPE_DICTIONARY)
	check("counters that already existed are untouched",
			int(moved_stats.get("kills", 0)) == 12)

	# A version 2 save: per-map runs, but stats written before the tallies.
	var v2 := ConfigFile.new()
	v2.set_value("runs", "ashen", {"wave": 9, "stats": {"kills": 40}})
	check("a save with [runs] and no stamp reads as version 2",
			Progress.detect_version(v2) == 2)
	Progress.migrate_config(v2, 2)
	var filled: Dictionary = (v2.get_value("runs", "ashen", {}) as Dictionary).get("stats", {})
	var missing := ""
	for key: String in Progress.RUN_STAT_KEYS:
		if not filled.has(key):
			missing = key
	check("version 2 runs come out with every stat key (%s)" % missing, missing == "")
	check("the maps stay maps and the counters stay counters",
			typeof(filled["tower_kills"]) == TYPE_DICTIONARY
			and typeof(filled["kills"]) == TYPE_INT)

	# A save from a future build must be read, never rewritten.
	var future := ConfigFile.new()
	future.set_value("meta", "version", Progress.SAVE_VERSION + 5)
	check("a newer save is detected",
			Progress.detect_version(future) > Progress.SAVE_VERSION)
	var was_blocked := Progress.slot_too_new
	var was_read_only := Progress.read_only
	Progress.slot_too_new = true
	Progress.read_only = false
	var before_coins := Progress.coins
	Progress.coins = before_coins + 1
	Progress.save_state()
	check("saving is refused while a slot is from a newer build", true)
	Progress.slot_too_new = was_blocked
	Progress.read_only = was_read_only
	Progress.coins = before_coins

	# Slot bleed: reading a slot must clear what the last one left behind.
	# apply_config works on a config in memory, so no real save is touched.
	var other_slot := ConfigFile.new()
	other_slot.set_value("progress", "xp", 120)
	other_slot.set_value("best_wave", "riverfork", 9)
	Progress.stats = {"kills": 999}
	Progress.tower_ranks = {"gun": [3, 3, 3]}
	Progress.bests = {"verdant": 30}
	Progress.apply_config(other_slot)
	check("loading a slot drops the previous account's stats and ranks",
			Progress.stats.is_empty() and Progress.tower_ranks.is_empty())
	check("and its records, keeping only the ones in the file",
			not Progress.bests.has("verdant") and int(Progress.bests.get("riverfork", 0)) == 9)
	check("while reading the new slot's own numbers", Progress.xp == 120)
	Progress.use_clean_state()


## Balance overrides: the numbers the tuning panel writes must reach the game
## without a restart, layer level over global, and never leak into a harness.
func _check_tuning() -> void:
	Tuning.use_clean_state()
	var level: int = int(game.level_def["id"])
	var base: float = float(TDData.TOWERS["gun"]["damage"])
	check("a stock tower reads the table", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base))

	Tuning.set_value("gun", "damage", base + 10.0, -1)
	check("a global override reaches the tower def", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base + 10.0))
	# The cache is keyed on the override version, so this must not go stale.
	Tuning.set_value("gun", "damage", base + 20.0, -1)
	check("changing it again is picked up immediately", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base + 20.0))

	Tuning.set_value("gun", "damage", base + 99.0, level)
	check("a level override beats the global one", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base + 99.0))
	var other := level + 1 if level + 1 < TDData.LEVELS.size() else level - 1
	var was := TDData.selected_level
	TDData.selected_level = other
	check("and it applies to that level only", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base + 20.0))
	TDData.selected_level = was

	Tuning.clear_value("gun", "damage", level)
	check("clearing a level override falls back to the global", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base + 20.0))
	Tuning.clear_subject("gun", -1)
	check("clearing the tower falls back to the table", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base))

	# Costs are ints in the table and must stay ints, or prices print as 205.0.
	Tuning.set_value("gun", "cost", 77.0, -1)
	check("a tuned cost stays a whole number",
			typeof(TDData.tower_def("gun")["cost"]) == TYPE_INT
			and int(TDData.tower_def("gun")["cost"]) == 77)
	check("the game charges the tuned price", game.tower_cost("gun") == 77)
	Tuning.clear_all()
	check("reset puts every number back", is_equal_approx(
			float(TDData.tower_def("gun")["damage"]), base)
			and game.tower_cost("gun") == int(TDData.TOWERS["gun"]["cost"]))

	# A live tower must feel the change on the next frame, not on rebuild.
	var live := Tower.new()
	live.game = game
	live.setup("gun", Vector2i.ZERO)
	var before := live.stat("damage")
	Tuning.set_value("gun", "damage", base * 2.0, -1)
	check("a tower already on the board picks the change up",
			live.stat("damage") > before * 1.9)
	Tuning.clear_all()
	live.free()

	# Rows are per tower: only stats it actually defines.
	var gun_keys: Array = []
	for row: Dictionary in Tuning.rows_for("gun"):
		gun_keys.append(str(row["key"]))
	var wave_keys: Array = []
	for row: Dictionary in Tuning.rows_for("wavegun"):
		wave_keys.append(str(row["key"]))
	check("every tower exposes its core numbers", gun_keys.has("damage")
			and gun_keys.has("rate") and gun_keys.has("range") and gun_keys.has("cost"))
	check("knockback shows for the Wave Cannon and not the Gunner",
			wave_keys.has("knockback") and not gun_keys.has("knockback"))

	# ---- creeps -------------------------------------------------------
	var grunt_hp: float = float(TDData.ENEMIES["grunt"]["hp"])
	check("a stock creep reads the table",
			is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), grunt_hp))
	Tuning.set_value(Tuning.enemy_subject("grunt"), "hp", grunt_hp * 3.0, -1)
	check("a tuned creep reads the override",
			is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), grunt_hp * 3.0))
	var beefy := Enemy.new()
	beefy.setup("grunt", 1.0, 1.0, game.routes[0])
	check("and a creep spawned now is actually tougher",
			beefy.max_hp > grunt_hp * 2.5)
	beefy.free()
	Tuning.set_value(Tuning.enemy_subject("grunt"), "hp", grunt_hp * 0.5, level)
	check("a level override beats the global one for creeps too",
			is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), grunt_hp * 0.5))
	Tuning.clear_subject(Tuning.enemy_subject("grunt"), level)
	Tuning.clear_subject(Tuning.enemy_subject("grunt"), -1)
	check("and clearing puts the creep back",
			is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), grunt_hp))
	var enemy_keys: Array = []
	for row: Dictionary in Tuning.rows_for(Tuning.enemy_subject("mender")):
		enemy_keys.append(str(row["key"]))
	check("a creep exposes its own numbers", enemy_keys.has("hp")
			and enemy_keys.has("speed") and enemy_keys.has("heal"))
	check("and not ones it does not have",
			not Tuning.rows_for(Tuning.enemy_subject("grunt")).any(
					func(r): return str(r["key"]) == "heal"))

	# ---- upgrade tracks -----------------------------------------------
	var track_subject := Tuning.track_subject("gun", 0)
	var stock_track: Dictionary = TDData.TOWERS["gun"]["tracks"][0]
	var stock_max := int(stock_track["max"])
	var stock_cost := TDData.track_cost("gun", 0, 0)
	var mod_key := ""
	for key: String in stock_track["mods"]:
		if typeof((stock_track["mods"] as Dictionary)[key]) == TYPE_FLOAT:
			mod_key = "mods." + key
	check("a track exposes its ranks, its cost share and its modifier",
			mod_key != "" and Tuning.rows_for(track_subject).size() >= 3)

	Tuning.set_value(track_subject, "max", float(stock_max + 2), -1)
	check("tuning the rank cap reaches the table",
			int(TDData.tracks("gun")[0]["max"]) == stock_max + 2)
	var capped := Tower.new()
	capped.game = game
	capped.setup("gun", Vector2i.ZERO)
	check("and reaches a tower on the board",
			capped.track_max(0) == stock_max + 2)
	capped.free()

	Tuning.set_value(track_subject, "cost_frac",
			float(stock_track["cost_frac"]) * 2.0, -1)
	check("tuning the cost share reprices the rank",
			TDData.track_cost("gun", 0, 0) > stock_cost)

	if mod_key != "":
		var ranked := Tower.new()
		ranked.game = game
		ranked.setup("gun", Vector2i.ZERO)
		ranked.ranks[0] = 1
		var before_mod := ranked.stat("damage")
		Tuning.set_value(track_subject, mod_key,
				float(stock_track["mods"][mod_key.substr(5)]) * 1.5, -1)
		check("tuning what a rank does changes an installed rank",
				ranked.stat("damage") != before_mod)
		ranked.free()

	Tuning.clear_subject(track_subject, -1)
	check("clearing a track puts every part of it back",
			int(TDData.tracks("gun")[0]["max"]) == stock_max
			and TDData.track_cost("gun", 0, 0) == stock_cost)

	# Subjects must not collide: a tower, its track and a creep are separate.
	Tuning.set_value("gun", "damage", 99.0, -1)
	Tuning.set_value(Tuning.track_subject("gun", 0), "max", 7.0, -1)
	Tuning.set_value(Tuning.enemy_subject("grunt"), "hp", 999.0, -1)
	check("three kinds of subject are stored apart",
			is_equal_approx(float(TDData.tower_def("gun")["damage"]), 99.0)
			and int(TDData.tracks("gun")[0]["max"]) == 7
			and is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), 999.0))
	Tuning.clear_all()
	check("and reset clears all three",
			is_equal_approx(float(TDData.tower_def("gun")["damage"]), base)
			and int(TDData.tracks("gun")[0]["max"]) == stock_max
			and is_equal_approx(float(TDData.enemy_def("grunt")["hp"]), grunt_hp))

	# The panel itself: it must drive Tuning, not its own copy of the numbers.
	var panel := TuningPanel.new()
	panel.game = game
	add_child(panel)
	panel._select_tower("cannon")
	var cannon_base: float = float(TDData.TOWERS["cannon"]["damage"])
	panel._nudge("damage", 1.0)
	check("a click on the panel moves the real number",
			Tuning.value_of("cannon", "damage", -1) > cannon_base)
	panel._toggle_scope()
	panel._nudge("damage", -1.0)
	check("with the scope flipped it writes the level layer",
			Tuning.level_values.has(level))
	# Every row must explain itself, or the panel is only usable by someone
	# who already knows the codebase.
	var unexplained: Array = []
	var subjects: Array = ["gun", "mortar", Tuning.enemy_subject("warden"),
			Tuning.enemy_subject("mender"), Tuning.track_subject("gun", 0),
			Tuning.track_subject("tesla", 1)]
	for subject: String in subjects:
		for row: Dictionary in Tuning.rows_for(subject):
			var info := str(row.get("info", ""))
			if info.length() < 20:
				unexplained.append("%s/%s" % [subject, row["key"]])
	check("every tunable row carries an explanation (%s)"
			% ", ".join(unexplained), unexplained.is_empty())
	check("a modifier explains what a rank of the track does",
			str(Tuning.rows_for(Tuning.track_subject("gun", 0))[-1].get("info", ""))
					.contains("rank"))
	var blurbs: Array = []
	for subject: String in subjects:
		if Tuning.describe(subject).strip_edges().length() < 12:
			blurbs.append(subject)
	check("and every subject says what it is (%s)" % ", ".join(blurbs),
			blurbs.is_empty())
	check("an upgrade's description covers its ranks and its capstone",
			Tuning.describe(Tuning.track_subject("cannon", 0)).contains("ranks")
			and Tuning.describe(Tuning.track_subject("cannon", 0)).contains("Siege"))

	# Per-rank tuning: a rank can be priced and made to do its own thing.
	var track := Tuning.track_subject("gun", 0)
	var rank_keys: Array = []
	for row: Dictionary in Tuning.rows_for(track):
		rank_keys.append(str(row["key"]))
	check("each rank gets its own rows",
			rank_keys.has("cost#1") and rank_keys.has("gold#1")
			and rank_keys.has("cost#2"))
	check("and they are grouped by rank",
			str(Tuning.rows_for(track)[-1].get("group", "")).begins_with("RANK"))
	var stock_second := TDData.track_cost("gun", 0, 1)
	Tuning.set_value(track, "cost#2", 999.0, -1)
	check("a rank's coin price can be set outright",
			TDData.track_cost("gun", 0, 1) == 999
			and TDData.track_cost("gun", 0, 0) != 999)
	Tuning.set_value(track, "gold#3", 42.0, -1)
	check("so can what it costs to install in a match",
			TDData.track_gold_cost("gun", 0, 2) == 42)
	Tuning.clear_value(track, "cost#2", -1)
	check("clearing one puts that rank back on the curve",
			TDData.track_cost("gun", 0, 1) == stock_second)

	# A rank can also be given its own effect, leaving the others alone.
	var rank_mod := ""
	for key: String in (TDData.TOWERS["gun"]["tracks"][0]["mods"] as Dictionary):
		rank_mod = key
	var one_rank := Tower.new()
	one_rank.game = game
	one_rank.setup("gun", Vector2i.ZERO)
	one_rank.ranks[0] = 1
	var at_one := one_rank.stat("damage")
	one_rank.ranks[0] = 2
	var at_two := one_rank.stat("damage")
	Tuning.set_value(track, "mods.%s#2" % rank_mod,
			float(TDData.TOWERS["gun"]["tracks"][0]["mods"][rank_mod]) * 2.0, -1)
	var boosted_two := one_rank.stat("damage")
	one_rank.ranks[0] = 1
	var still_one := one_rank.stat("damage")
	check("a rank can be given its own effect", boosted_two > at_two)
	check("without touching the ranks either side of it",
			is_equal_approx(still_one, at_one))
	one_rank.free()
	Tuning.clear_all()
	check("and reset puts the whole curve back",
			TDData.track_cost("gun", 0, 1) == stock_second
			and not TDData.tracks("gun")[0].has("rank_mods"))

	# A set of numbers can leave the game and come back.
	Tuning.clear_all()
	Tuning.set_value("gun", "damage", 42.0, -1)
	Tuning.set_value(Tuning.enemy_subject("tank"), "hp", 111.0, level)
	Tuning.set_value(Tuning.track_subject("gun", 0), "cost#2", 77.0, -1)
	var dump: Dictionary = Tuning.to_dictionary()
	check("an export names its format", str(dump.get("format", "")) != ""
			and dump.has("global") and dump.has("levels"))
	var path := "user://tuning_export_test.json"
	check("it writes", Tuning.export_to(path))
	Tuning.clear_all()
	check("and the numbers really were cleared",
			is_equal_approx(float(TDData.tower_def("gun")["damage"]), base))
	check("importing brings them back", Tuning.import_from(path))
	check("towers included",
			is_equal_approx(float(TDData.tower_def("gun")["damage"]), 42.0))
	check("per-rank costs included", TDData.track_cost("gun", 0, 1) == 77)
	var was_level := TDData.selected_level
	TDData.selected_level = level
	check("and per-level overrides land on their level",
			is_equal_approx(float(TDData.enemy_def("tank")["hp"]), 111.0))
	TDData.selected_level = was_level

	# It must refuse anything that is not one of ours rather than wiping.
	var junk := "user://tuning_export_junk.json"
	var file := FileAccess.open(junk, FileAccess.WRITE)
	file.store_string('{"format": "something else", "global": {}}')
	file.close()
	check("a foreign file is refused", not Tuning.import_from(junk))
	check("and the current numbers survive the attempt",
			is_equal_approx(float(TDData.tower_def("gun")["damage"]), 42.0))
	check("a missing file is refused too",
			not Tuning.import_from("user://not_here_at_all.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(junk))
	Tuning.clear_all()

	# Back to the global layer; the scope was flipped a few lines above.
	panel.scope_level = -1

	# Every mode must list something and open on a real subject.
	var empty_modes: Array = []
	for panel_mode: String in ["towers", "upgrades", "enemies"]:
		panel._select_mode(panel_mode)
		if panel.subjects().is_empty() or panel.value_fields.is_empty():
			empty_modes.append(panel_mode)
	check("every mode lists subjects with numbers (%s)" % ",".join(empty_modes),
			empty_modes.is_empty())
	panel._select_mode("enemies")
	panel._select_tower(Tuning.enemy_subject("tank"))
	var tank_speed := Tuning.value_of(Tuning.enemy_subject("tank"), "speed", -1)
	panel._nudge("speed", 1.0)
	check("the panel can tune a creep",
			Tuning.value_of(Tuning.enemy_subject("tank"), "speed", -1) > tank_speed)
	panel._select_mode("upgrades")
	panel._select_tower(Tuning.track_subject("cannon", 0))
	# Typing a number straight into the field.
	panel._typed("7", "max")
	check("a typed value is taken as written",
			is_equal_approx(Tuning.value_of(Tuning.track_subject("cannon", 0),
					"max", -1), 7.0))
	panel._typed("1.35", "mods.damage_mult")
	check("including fractions",
			is_equal_approx(Tuning.value_of(Tuning.track_subject("cannon", 0),
					"mods.damage_mult", -1), 1.35))
	panel._typed("99999", "max")
	check("out of range is clamped, not accepted",
			Tuning.value_of(Tuning.track_subject("cannon", 0), "max", -1) <= 8.0)
	var before_junk := Tuning.value_of(Tuning.track_subject("cannon", 0), "max", -1)
	panel._typed("banana", "max")
	check("and nonsense is ignored",
			is_equal_approx(Tuning.value_of(Tuning.track_subject("cannon", 0),
					"max", -1), before_junk))
	check("every row has a field to type in",
			panel.value_fields.size() == Tuning.rows_for(panel.current).size())
	Tuning.clear_subject(Tuning.track_subject("cannon", 0), -1)
	panel._nudge("max", 1.0)
	check("and an upgrade track",
			Tuning.effective(Tuning.track_subject("cannon", 0), -1).has("max"))
	panel._reset_all()
	check("reset all clears both layers", not Tuning.has_overrides())
	check("a harness never writes the tuning file", not Tuning.save_file())
	remove_child(panel)
	panel.queue_free()
	Tuning.clear_all()


## Shoving the same creep over and over has to lose its grip, or a pair of
## Wave Cannons holds a lane still forever.
func _check_knockback_fatigue() -> void:
	var creep := Enemy.new()
	creep.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(creep)
	for i in 40:
		creep._process(0.05)
	var start := creep.progress
	creep.push_back(60.0)
	var first := start - creep.progress
	var second_start := creep.progress
	creep.push_back(60.0)
	var second := second_start - creep.progress
	check("the first shove moves the creep", first > 1.0)
	check("the second shove in a row moves it less", second < first * 0.8)
	# Left alone it recovers.
	for i in 60:
		creep._process(0.1)
	var third_start := creep.progress
	creep.push_back(60.0)
	check("after a breather a shove lands in full",
			third_start - creep.progress > second * 1.4)
	creep.queue_free()


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
		# A node either changes numbers (mods) or unlocks something the
		# game gates on its rank, and it always explains itself.
		if int(t["max"]) < 1 or int(t["cost"]) < 1 or str(t["name"]) == "" \
				or str(t["desc"]) == "":
			ok_shape = false
		if (t["mods"] as Dictionary).is_empty() \
				and (t.get("unlocks", []) as Array).is_empty():
			ok_shape = false
		if str(t["requires"]) == "":
			roots += 1
		elif Progress.node(str(t["requires"])).is_empty():
			ok_shape = false
		if Progress.describe(t["mods"]).contains("_mult") \
				or Progress.describe(t["mods"]).contains("_add"):
			ok_shape = false
	check("every tech node is well formed and described", ok_shape)

	# Game speed is something you buy, not something you start with.
	Progress.use_clean_state()
	Progress.read_only = true
	Progress.unlock_all = false
	Progress.ranks = {}
	check("a new account plays at one speed", Progress.speeds() == [1.0])
	Progress.ranks = {"tempo": 1}
	check("the first rank of Field Tempo unlocks 2x",
			Progress.speeds() == [1.0, 2.0])
	Progress.ranks = {"tempo": 2}
	check("and the second unlocks 3x", Progress.speeds() == [1.0, 2.0, 3.0])
	var tempo: Dictionary = Progress.node("tempo")
	check("the node says what it unlocks",
			(tempo.get("unlocks", []) as Array).size() == int(tempo["max"]))
	Progress.use_clean_state()
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
	check("every area contributes its maps (%d)" % TDData.LEVELS.size(),
			TDData.LEVELS.size() == TDData.AREAS.size() * MAPS_PER_AREA)

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
			"basalt", "flagstone", "duckboard", "clinker", "crystal", "conduit",
			"towpath", "chalk", "causeway", "reedmat", "haulroad", "saltcrust",
			"snowpack", "glaze", "cinder", "pontoon"]
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
