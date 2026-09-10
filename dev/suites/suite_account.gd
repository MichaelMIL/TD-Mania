extends VerifySuite

## The account: progress, saves, slots, options, menus and the first run.

func suite_name() -> String:
	return "account"


func run() -> void:
	_check_progression()
	_check_tech()
	_check_slots()
	_check_save_versioning()
	_check_run_seed()
	_check_save_safety()
	_check_tutorial()
	_check_respec()
	_check_options()
	_check_menus()
	_check_frame_budget()
	_check_stats()
	await _check_saved_runs()

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

## Saves survive being interrupted: a write lands whole or not at all, and
## the copy it replaced is kept.
func _check_save_safety() -> void:
	var path := "user://td_mania_safety_test.cfg"
	var dir := DirAccess.open("user://")
	for leftover: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))

	var first := ConfigFile.new()
	first.set_value("meta", "version", Progress.SAVE_VERSION)
	first.set_value("progress", "xp", 111)
	check("a save writes", Progress.write_config(first, path))
	check("and lands where it was asked to", FileAccess.file_exists(path))
	check("leaving no temporary file behind", not FileAccess.file_exists(path + ".tmp"))

	var second := ConfigFile.new()
	second.set_value("meta", "version", Progress.SAVE_VERSION)
	second.set_value("progress", "xp", 222)
	Progress.write_config(second, path)
	check("the second write keeps the first as a backup",
			FileAccess.file_exists(path + ".bak"))
	var read_back: ConfigFile = Progress.read_config(path)
	check("and reading gets the newer one",
			int(read_back.get_value("progress", "xp", 0)) == 222)

	# A file that cannot be parsed must not be preferred over the backup.
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("[progress\nxp = ")
	broken.close()
	var rescued: ConfigFile = Progress.read_config(path)
	check("a corrupt save falls back to the backup", rescued != null
			and int(rescued.get_value("progress", "xp", 0)) == 111)

	# A file that parses but is not one of ours is not a save either.
	var stranger := ConfigFile.new()
	stranger.set_value("something", "else", 1)
	check("a foreign file is not mistaken for a save",
			not Progress.looks_like_save(stranger))
	stranger.save(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	check("and with no backup to fall back on, nothing is loaded",
			Progress.read_config(path) == null)

	for leftover: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))

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

## The first run teaches itself: a line at a time, each waiting for the
## player to do the thing rather than for a clock.
func _check_tutorial() -> void:
	Progress.use_clean_state()
	Progress.read_only = true
	Progress.stats = {}
	Progress.options.erase("tutorial_done")
	check("a brand new account is shown the ropes", Tutorial.wanted())
	Progress.stats = {"runs": 3}
	check("someone who has played is not", not Tutorial.wanted())
	Progress.stats = {}
	Tutorial.mark_seen()
	check("and neither is someone who has already seen it", not Tutorial.wanted())
	Progress.options.erase("tutorial_done")

	var walk := Tutorial.new()
	walk.game = game
	add_child(walk)
	check("it has something to say", walk.steps.size() >= 6)
	var vague := ""
	for step: Dictionary in walk.steps:
		if str(step["text"]).length() < 40:
			vague = str(step["text"])
		if not step.has("until") and not step.has("wait"):
			vague = "a step that never ends"
	check("every step says something and can be got past (%s)" % vague,
			vague == "")

	# A step that waits for the player does not move on by itself.
	var saved_towers: Dictionary = game.occupied.duplicate()
	game.occupied = {}
	walk.index = 1
	walk._show_step()
	for i in 20:
		walk._process(0.5)
	check("a step waiting on the player stays put", walk.index == 1)
	game.occupied = {Vector2i(0, 0): null}
	walk._process(0.1)
	check("and moves on the moment they do it", walk.index == 2)
	game.occupied = saved_towers

	# A step that only asks to be read moves on by itself.
	walk.index = 0
	walk._show_step()
	walk._process(0.1)
	check("a step that only wants reading waits a beat", walk.index == 0)
	for i in 12:
		walk._process(0.5)
	check("then moves on", walk.index >= 1)

	# Skipping is final.
	walk._skip()
	check("skipping ends it", not walk.visible)
	check("and it does not come back", not Tutorial.wanted())
	remove_child(walk)
	walk.queue_free()
	Progress.use_clean_state()

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

## A run's randomness comes from one number, and that number travels with
## the run.
func _check_run_seed() -> void:
	check("a run has a seed", game.run_seed != 0)
	var state: Dictionary = game._capture_run()
	check("parking a run keeps its seed",
			int(state.get("seed", 0)) == game.run_seed)
	check("and the handicaps it was played under",
			state.has("modifiers"))
	var original: int = game.run_seed
	game.run_seed = 12345
	game._restore_run(state)
	check("resuming picks the run's own seed back up",
			game.run_seed == original)

	# The seed decides what the run does: same number, same rolls.
	seed(original)
	var first: Array = []
	for i in 5:
		first.append(randi())
	seed(original)
	var again: Array = []
	for i in 5:
		again.append(randi())
	check("the same seed plays out the same way", first == again)
	seed(original + 1)
	var different: Array = []
	for i in 5:
		different.append(randi())
	check("and a different one does not", first != different)

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
