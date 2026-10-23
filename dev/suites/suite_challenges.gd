extends VerifySuite

## Challenges and the daily challenge: the set is well-formed, the daily is
## dealt the same for a date and differently across dates, every rule is
## enforced by a real match, and the payouts and streaks add up — while the
## map's own records are left alone.

func suite_name() -> String:
	return "challenges"


func run() -> void:
	_check_the_set()
	_check_the_daily()
	await _check_no_flyers_without_anti_air()
	await _check_rules_in_a_match()
	_check_rewards_and_streaks()
	TDData.active_challenge = {}


func _check_the_set() -> void:
	var ids: Dictionary = {}
	var bad: Array = []
	for c: Dictionary in Challenges.LIST:
		var id := str(c["id"])
		if ids.has(id):
			bad.append("%s twice" % id)
		ids[id] = true
		var found := false
		for level: Dictionary in TDData.LEVELS:
			if str(level["id"]) == str(c["level"]):
				found = true
		if not found:
			bad.append("%s: no map %s" % [id, c["level"]])
		if int(c["waves"]) <= 0 or int(c["reward"]) <= 0:
			bad.append("%s: no goal or no reward" % id)
		var rules: Dictionary = c.get("rules", {})
		for key: String in ["towers", "banned"]:
			for t: String in rules.get(key, []):
				if not TDData.TOWERS.has(t):
					bad.append("%s: no tower %s" % [id, t])
	check("every challenge names a real map and real towers (%s)"
			% ", ".join(bad), bad.is_empty())
	check("there are challenges to play", Challenges.LIST.size() >= 10)
	var sorted := true
	var last := 0
	var graded: Dictionary = {}
	for c: Dictionary in Challenges.LIST:
		if not c.has("grade") or int(c["grade"]) < last:
			sorted = false
		last = int(c.get("grade", 0))
		graded[last] = true
	check("every challenge is graded, easiest first", sorted)
	check("and every grade has a challenge in it", graded.size() == Challenges.GRADES.size())
	var lines := Challenges.rule_lines(Challenges.by_id("gun_line"))
	check("a challenge's rules read goal first", str(lines[0]) == "Reach wave 15")
	check("and say which towers are allowed", lines.has("Only Gunner"))
	check("a challenge parks under its own key",
			Challenges.run_key(Challenges.by_id("gun_line")) == "challenge:gun_line")


func _check_the_daily() -> void:
	# FNV-1a, so the same date deals the same daily on every machine.
	check("the daily's hash is FNV-1a", Challenges.stable_hash("abc") == 0x1a47e90b)
	var a := Challenges.daily_for("2026-10-22")
	var b := Challenges.daily_for("2026-10-22")
	check("a date always deals the same daily", JSON.stringify(a) == JSON.stringify(b))
	check("the daily parks under its date", Challenges.run_key(a) == "daily:2026-10-22")
	check("and carries a seed for the run", int(a.get("seed", 0)) > 0)

	var maps: Dictionary = {}
	var kits_ok := true
	var why := ""
	for day in 28:
		var key := "2026-11-%02d" % (day + 1)
		var c := Challenges.daily_for(key)
		maps[c["level"]] = true
		var kit: Array = c["rules"]["towers"]
		var air := false
		var level := Challenges.level_of(c)
		var water := 0
		for patch: Array in level.get("water", []):
			water += int(patch[2]) * int(patch[3])
		for t: String in kit:
			if bool(TDData.TOWERS[t].get("hits_air", false)):
				air = true
			if Challenges.DAILY_EXCLUDED.has(t):
				kits_ok = false
				why = "%s hands out %s" % [key, t]
			if int(TDData.TOWERS[t]["terrain"]) == TDData.Terrain.WATER \
					and water < Challenges.DAILY_WATER_CELLS:
				kits_ok = false
				why = "%s puts a water tower on a dry map" % key
		var distinct: Dictionary = {}
		for t: String in kit:
			distinct[t] = true
		if kit.size() != 4 or distinct.size() != 4:
			kits_ok = false
			why = "%s kit is not four towers" % key
		if not air:
			kits_ok = false
			why = "%s cannot hit flyers" % key
		if not kit.has("gun"):
			kits_ok = false
			why = "%s has no cheap opener" % key
	check("a month of dailies deals fair kits (%s)" % why, kits_ok)
	check("and moves around the maps", maps.size() >= 10)

	check("the day before the first of March", Challenges.previous_day("2026-03-01") == "2026-02-28")
	check("the day before new year", Challenges.previous_day("2027-01-01") == "2026-12-31")
	check("a date reads as a day", Challenges.pretty_date("2026-10-22") == "Thursday 22 October")
	check("a streak pays more, up to a cap", Challenges.streak_bonus(1) == 0
			and Challenges.streak_bonus(3) == 2 * Challenges.STREAK_STEP
			and Challenges.streak_bonus(100) == Challenges.STREAK_CAP)


## Starts a match under a challenge, the way the screen does.
func _start(c: Dictionary) -> Node:
	TDData.active_challenge = c.duplicate(true)
	TDData.selected_level = Challenges.level_index(c)
	TDData.resume_run = false
	var probe: Node = load("res://game.tscn").instantiate()
	add_child(probe)
	await get_tree().process_frame
	return probe


func _first_cell(probe: Node, type_id: String) -> Vector2i:
	for key: Vector2i in probe.terrain:
		if probe.can_place(key, type_id):
			return key
	return Vector2i(-99, -99)


## Flyers arrive from wave 5 and a kit with nothing that shoots upwards
## could only watch them go past. Rather than forbidding such a challenge,
## the waves arrive without flyers: each one is swapped for its counterpart
## on the ground, so the wave is the same size and still has to be answered.
func _check_no_flyers_without_anti_air() -> void:
	var probe: Node = await _start(Challenges.by_id("gun_line"))
	var flyers: Array = []
	for kind: String in TDData.ENEMIES:
		if bool(TDData.ENEMIES[kind].get("flying", false)):
			flyers.append(kind)
	check("there are flyers to worry about", flyers.size() >= 2)

	var grounded_any := false
	var wrong: Array = []
	var emptied: Array = []
	for c: Dictionary in Challenges.LIST:
		probe.challenge = c.duplicate(true)
		var grounded: bool = Challenges.grounded(c)
		if grounded:
			grounded_any = true
		for n in range(5, int(c["waves"]) + 1):
			var composition: Dictionary = probe.wave_composition(n)
			if composition.is_empty():
				emptied.append(str(c["id"]))
			for kind: String in composition:
				if flyers.has(kind) and grounded:
					wrong.append("%s wave %d" % [c["id"], n])
	check("at least one challenge is played on the ground alone", grounded_any)
	check("a kit that cannot shoot upwards never meets a flyer (%s)"
			% ", ".join(wrong.slice(0, 3)), wrong.is_empty())
	check("and its waves are not simply emptied out", emptied.is_empty())

	# The swap keeps the count: same number of creeps, different kinds.
	var air_kit := Challenges.by_id("gun_line")
	var ground_kit := Challenges.by_id("siege_line")
	probe.challenge = air_kit.duplicate(true)
	var with_air: Dictionary = probe.wave_composition(14)
	probe.challenge = ground_kit.duplicate(true)
	var without: Dictionary = probe.wave_composition(14)
	var total_air := 0
	for k: String in with_air:
		total_air += int(with_air[k])
	var total_ground := 0
	for k: String in without:
		total_ground += int(without[k])
	check("the wave is the same size either way (%d vs %d)" % [total_air, total_ground],
			total_air == total_ground)
	var swapped := false
	for kind: String in Challenges.GROUND_SWAP:
		if with_air.has(kind) and not without.has(kind) \
				and without.has(str(Challenges.GROUND_SWAP[kind])):
			swapped = true
	check("and the flyers became their counterparts on the ground", swapped)
	probe.queue_free()
	TDData.active_challenge = {}


func _check_rules_in_a_match() -> void:
	# Towers: only the named ones, and lent if the account has not got them.
	var was_unlock := Progress.unlock_all
	Progress.unlock_all = false
	var air: Node = await _start(Challenges.by_id("air_power"))
	check("a challenge lends towers the account has not unlocked",
			air.tower_available("airfield") and not Progress.tower_unlocked("airfield"))
	check("and leaves out the ones it does not name", not air.tower_available("gun"))
	check("the palette shows only the challenge's towers",
			air.hud.palette_cards.size() == 3 and air.hud.palette_cards.has("helipad"))
	check("the top bar names the challenge", air.hud.lbl_level.text == "Air Power")
	check("the goal is the challenge's", air.goal_wave() == int(Challenges.by_id("air_power")["waves"]))
	check("the starting purse is exact", air.gold == 500)
	air.queue_free()
	Progress.unlock_all = was_unlock

	var shoe: Node = await _start(Challenges.by_id("shoestring"))
	check("a tower limit holds", shoe.gold == 150)
	shoe.gold = 99999
	var built := 0
	for key: Vector2i in shoe.terrain:
		if shoe.can_place(key, "gun"):
			shoe.placing = "gun"
			shoe._try_place(key)
			built += 1
		if built >= 14:
			break
	check("no more than ten towers stand", shoe.occupied.size() == 10)
	shoe.queue_free()

	var glass: Node = await _start(Challenges.by_id("glass_base"))
	check("lives come from the challenge", glass.lives == 3)
	check("the map's handicaps do not ride along", glass.modifiers.is_empty())
	check("no walkthrough in a challenge", glass.tutorial == null)
	glass.queue_free()

	var metal: Node = await _start(Challenges.by_id("bare_metal"))
	metal.gold = 5000
	var spot := _first_cell(metal, "gun")
	metal.placing = "gun"
	metal._try_place(spot)
	var t: Tower = metal.occupied.get(spot)
	metal._select(t)
	var gold_before: int = metal.gold
	metal._upgrade_selected(0)
	check("no upgrades means none", t != null and t.ranks[0] == 0 and metal.gold == gold_before)
	metal._sell_selected()
	check("no selling means none", metal.occupied.has(spot))
	metal.queue_free()

	# Health, speed and gold: the same wave, under and not under the rule.
	var plain: Node = await _start({"id": "probe", "name": "Probe", "level": "crossroads",
		"waves": 14, "reward": 1, "rules": {}})
	var hp_plain: float = float(plain._build_wave(3)[0]["hp"])
	var spd_plain: float = float(plain._build_wave(3)[0]["spd"])
	plain.queue_free()
	var iron: Node = await _start(Challenges.by_id("iron_tide"))
	check("tougher creeps have more health",
			is_equal_approx(float(iron._build_wave(3)[0]["hp"]), hp_plain * 1.5))
	iron.queue_free()
	var blitz: Node = await _start(Challenges.by_id("blitz"))
	check("faster creeps are faster",
			is_equal_approx(float(blitz._build_wave(3)[0]["spd"]), spd_plain * 1.35))
	blitz.queue_free()
	var lean: Node = await _start(Challenges.by_id("lean_times"))
	check("a banned tower cannot be built", not lean.tower_available("mine")
			and lean.tower_available("gun"))
	lean.gold = 0
	lean.wave = 3
	lean._end_wave()
	check("half pay is half pay", lean.gold == int(round(float(35 + 3 * 8) * 0.5)))
	lean.queue_free()

	# Parking: a challenge run never touches the map's own parked run.
	var map_run := {"level": "verdant", "wave": 7, "gold": 1, "towers": []}
	Progress.runs["verdant"] = map_run
	var gun: Node = await _start(Challenges.by_id("gun_line"))
	gun.wave = 4
	var state: Dictionary = gun._capture_run()
	check("a challenge run is captured under its key", str(state["key"]) == "challenge:gun_line")
	Progress.save_run(state)
	check("parking it leaves the map's run alone",
			int(Progress.run_for("verdant").get("wave", 0)) == 7
			and Progress.has_run("challenge:gun_line"))
	gun.queue_free()
	var back: Node = await _start(Challenges.by_id("gun_line"))
	back.queue_free()
	TDData.resume_run = true
	TDData.active_challenge = Challenges.by_id("gun_line").duplicate(true)
	var resumed: Node = load("res://game.tscn").instantiate()
	add_child(resumed)
	await get_tree().process_frame
	check("continuing a challenge picks up its own run", resumed.wave == 4
			and resumed.run_key() == "challenge:gun_line")
	resumed.queue_free()
	Progress.runs.erase("verdant")
	Progress.runs.erase("challenge:gun_line")

	# Winning: the challenge pays, the map's records do not move.
	var stars_before := Progress.stars.duplicate()
	var cleared_before := Progress.cleared.duplicate()
	var bests_before := Progress.bests.duplicate()
	var coins_before := Progress.coins
	var win: Node = await _start(Challenges.by_id("cold_front"))
	win.wave = int(Challenges.by_id("cold_front")["waves"])
	win._trigger_victory()
	check("beating a challenge pays its coins",
			Progress.coins >= coins_before + int(Challenges.by_id("cold_front")["reward"]))
	check("and marks it beaten", Progress.challenge_done("cold_front"))
	check("and says so", win.hud.lbl_over_title.text == "Challenge complete")
	# A challenge is a fixed objective: meeting it ends the run, so no more
	# waves can be called in past the goal and there is no endless to drift
	# into.
	check("meeting the goal ends the run", bool(win.game_over))
	check("so no wave can be rushed past it", not win.can_rush())
	check("and no endless is offered", not win.hud.btn_continue.visible)
	check("a finished challenge is not left parked",
			not Progress.has_run(Challenges.run_key(Challenges.by_id("cold_front"))))
	Engine.time_scale = 1.0
	check("and leaves the map's stars, clears and bests alone",
			Progress.stars == stars_before and Progress.cleared == cleared_before
			and Progress.bests == bests_before)
	win.queue_free()
	Progress.challenges = {}
	TDData.active_challenge = {}


func _check_rewards_and_streaks() -> void:
	Progress.challenges = {}
	Progress.daily = {}
	var coins := Progress.coins
	var c := Challenges.by_id("gun_line")
	var first := Progress.complete_challenge(c, 15)
	var again := Progress.complete_challenge(c, 17)
	check("a challenge pays once", bool(first["first"]) and not bool(again["first"])
			and Progress.coins == coins + int(c["reward"]))
	check("and keeps the deepest wave", int(Progress.challenge_record("gun_line")["best"]) == 17)
	# A goal raised after it was beaten: the old win no longer counts, and
	# winning the harder version pays again.
	Progress.challenges["last_stand"] = {"best": 10, "done": true, "goal": 10}
	var raised := Challenges.by_id("last_stand")
	check("a challenge whose goal went up is unbeaten again",
			not Progress.challenge_done("last_stand"))
	coins = Progress.coins
	var rewon := Progress.complete_challenge(raised, int(raised["waves"]))
	check("and pays again when the new goal is met", bool(rewon["first"])
			and Progress.coins == coins + int(raised["reward"])
			and Progress.challenge_done("last_stand"))
	Progress.challenges["iron_tide"] = {"best": 20, "done": true}
	check("an old record with no goal counts if it got deep enough",
			Progress.challenge_done("iron_tide"))

	coins = Progress.coins
	var d1 := Challenges.daily_for("2026-10-22")
	var r1 := Progress.complete_challenge(d1, 13)
	check("the first daily starts a streak", int(r1["streak"]) == 1
			and Progress.coins == coins + int(d1["reward"]))
	var twice := Progress.complete_challenge(d1, 14)
	check("the same day pays once", not bool(twice["first"]))
	var d2 := Challenges.daily_for("2026-10-23")
	var r2 := Progress.complete_challenge(d2, 12)
	check("the next day carries the streak, with its bonus", int(r2["streak"]) == 2
			and int(r2["coins"]) == int(d2["reward"]) + Challenges.streak_bonus(2))
	check("a streak still stands the day after", Progress.daily_streak("2026-10-24") == 2)
	check("and is gone once a day is missed", Progress.daily_streak("2026-10-25") == 0)
	var d4 := Challenges.daily_for("2026-10-25")
	var r4 := Progress.complete_challenge(d4, 12)
	check("a missed day starts it over", int(r4["streak"]) == 1)
	check("a daily remembers its best wave", Progress.daily_best("2026-10-25") == 12
			and Progress.daily_best("2026-10-24") == 0)
	Progress.challenges = {}
	Progress.daily = {}
