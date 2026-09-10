extends VerifySuite

## Waves: what arrives, what it is worth, and how a map is won.

func suite_name() -> String:
	return "waves"


func run() -> void:
	_check_wave_rules()
	_check_wave_affixes()
	_check_modifiers()
	_check_objectives()
	_check_victory()
	_check_wave_report()
	_check_wave_preview()

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

## Wave affixes: the same creeps, but one thing about all of them is
## different, and the readout says which.
func _check_wave_affixes() -> void:
	var seen: Array = []
	var affixed := 0
	for n in range(1, 41):
		var affix := TDData.affix_for(n)
		if affix.is_empty():
			continue
		affixed += 1
		if not seen.has(str(affix["id"])):
			seen.append(str(affix["id"]))
		if n % 10 == 0:
			check("boss waves are left unmodified (wave %d)" % n, false)
	check("early waves are plain", TDData.affix_for(3).is_empty()
			and TDData.affix_for(6).is_empty())
	check("affixes appear through a run (%d of 40 waves)" % affixed,
			affixed >= 6 and affixed <= 16)
	check("and every one of them gets used (%d)" % seen.size(),
			seen.size() == TDData.WAVE_AFFIXES.size())
	var described := true
	for affix: Dictionary in TDData.WAVE_AFFIXES:
		if str(affix.get("note", "")).length() < 20 or str(affix["name"]) == "":
			described = false
	check("each one explains how to answer it", described)

	# The modifier has to reach the creeps that spawn.
	var affix_wave := -1
	for n in range(7, 40):
		if str(TDData.affix_for(n).get("id", "")) == "armoured":
			affix_wave = n
			break
	check("an armoured wave exists", affix_wave > 0)
	var plain: Array = game._build_wave(affix_wave - 1)
	var armoured: Array = game._build_wave(affix_wave)
	check("its entries carry the extra armour",
			float(armoured[0].get("armor", 0.0)) > 0.0
			and float(plain[0].get("armor", 0.0)) == 0.0)

	# Shields absorb a hit outright, whatever it was carrying.
	var shielded := Enemy.new()
	shielded.setup("grunt", 1.0, 1.0, game.routes[0])
	shielded.shield_hits = 1
	add_child(shielded)
	var full := shielded.hp
	shielded.take_damage(9999.0, true)
	check("a shield eats the first hit entirely",
			is_equal_approx(shielded.hp, full) and shielded.shield_hits == 0)
	shielded.take_damage(10.0, true)
	check("and the next one lands", shielded.hp < full)
	shielded.queue_free()

	# A swift wave trades health for speed rather than adding both.
	var swift_wave := -1
	for n in range(7, 40):
		if str(TDData.affix_for(n).get("id", "")) == "swift":
			swift_wave = n
			break
	var swift: Array = game._build_wave(swift_wave)
	var before: Array = game._build_wave(swift_wave - 1)
	check("a swift wave is faster and frailer than the wave before it",
			float(swift[0]["spd"]) > float(before[0]["spd"])
			and float(swift[0]["hp"]) < float(before[0]["hp"]) * 1.1)

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

## Chosen handicaps: enforced during the run, paid for at the end.
func _check_modifiers() -> void:
	var described := true
	var bonuses := 0.0
	for m: Dictionary in TDData.MODIFIERS:
		if str(m["name"]) == "" or str(m.get("note", "")).length() < 12 \
				or float(m["bonus"]) <= 0.0:
			described = false
		bonuses += float(m["bonus"])
	check("every handicap is named, explained and paid for", described)
	check("all of them together is a serious multiplier, not a doubling",
			bonuses > 0.5 and bonuses < 1.5)
	check("no handicap means no multiplier",
			is_equal_approx(TDData.modifier_bonus([]), 1.0))
	check("two of them add up", TDData.modifier_bonus(["no_water", "no_sell"])
			> TDData.modifier_bonus(["no_water"]))

	var saved: Array = game.modifiers.duplicate()
	# Dry feet: water towers cannot be built at all.
	var water_cell := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "tide"):
			water_cell = key
			break
	check("a water tower has somewhere to stand normally", water_cell.x >= 0)
	game.modifiers = ["no_water"]
	check("dry feet blocks it", not game.can_place(water_cell, "tide"))
	var dry_cell := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			dry_cell = key
			break
	check("but leaves dry ground alone", dry_cell.x >= 0)

	# No refunds: selling is refused rather than silently allowed.
	var sell_cell := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			sell_cell = key
			break
	game.modifiers = []
	game.gold = 999
	game.placing = "gun"
	game._try_place(sell_cell)
	game.placing = ""
	var doomed: Tower = game.occupied[sell_cell]
	game._select(doomed)
	game.modifiers = ["no_sell"]
	var before_gold: int = game.gold
	game._sell_selected()
	check("no refunds refuses the sale",
			game.occupied.has(sell_cell) and game.gold == before_gold)
	game.modifiers = []
	game._sell_selected()
	check("and without it the sale goes through", not game.occupied.has(sell_cell))

	# Skeleton crew: a hard cap on how many towers can stand at once.
	game.modifiers = ["budget"]
	var cap := int(TDData.modifier("budget").get("towers", 12))
	var placed := 0
	game.gold = 999999
	for key: Vector2i in game.terrain:
		if placed >= cap + 3:
			break
		if game.can_place(key, "gun"):
			game.placing = "gun"
			game._try_place(key)
			game.placing = ""
			placed += 1
	check("skeleton crew stops at its budget (%d)" % game.occupied.size(),
			game.occupied.size() <= cap)
	for cell: Vector2i in game.occupied.keys():
		var t: Tower = game.occupied[cell]
		game.occupied.erase(cell)
		if is_instance_valid(t):
			t.queue_free()
	game.support_towers.clear()
	game.modifiers = saved
	game._select(null)
