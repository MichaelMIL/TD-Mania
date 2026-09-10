extends VerifySuite

## Towers: buying them, upgrading them, tuning them, placing them.

func suite_name() -> String:
	return "towers"


func run() -> void:
	_check_tracks()
	_check_new_towers()
	_check_aura()
	_check_drag()
	_check_tuning()
	_check_cheats()

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

## Drag and drop bookkeeping: the palette starts a drag, the map rect decides
## where a release counts, and placement still respects terrain.
func _check_drag() -> void:
	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			spot = key
			break
	# A misplaced tower can be picked up and put down again, free, once a
	# wave, between waves.
	var move_cell := Vector2i(-99, -99)
	var spare := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			if move_cell.x < 0:
				move_cell = key
			elif spare.x < 0:
				spare = key
	game.placing = "gun"
	game.gold = 999
	game._try_place(move_cell)
	game.placing = ""
	var moved: Tower = game.occupied[move_cell]
	game._select(moved)
	game.in_wave = false
	game.move_used_wave = -1
	check("a placed tower can be moved between waves", game.can_move_selected())
	var gold_before: int = game.gold
	game.begin_move()
	check("picking it up takes it off the board",
			game.moving == moved and not game.occupied.has(move_cell))
	game._click(spare)
	check("putting it down moves it", game.occupied.get(spare) == moved
			and moved.cell == spare)
	check("and costs nothing", game.gold == gold_before)
	check("but only once a wave", not game.can_move_selected())
	game.move_used_wave = -1
	game.begin_move()
	game._click(Vector2i(-5, -5))
	check("dropping it somewhere impossible puts it back",
			game.occupied.get(spare) == moved and game.moving == null)
	game.in_wave = true
	check("and a tower cannot be moved mid-wave", not game.can_move_selected())
	game.in_wave = false
	game.begin_move()
	game._start_wave()
	check("starting a wave never leaves one in hand",
			game.moving == null and game.occupied.has(spare))
	game.wave -= 1
	game.in_wave = false
	game.occupied.erase(spare)
	moved.queue_free()
	game._select(null)

	# Hovering a palette card previews the tower without buying it.
	game.hud._hover_card("mortar")
	check("hovering a card arms the preview", game.preview_tower == "mortar")
	check("but does not arm placement", game.placing == "")
	game.hud._hover_card("")
	check("and leaving the card drops it", game.preview_tower == "")

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
