class_name Progress
extends RefCounted

## Persistent meta progression: account XP and level, coins, and purchased
## tech. Lives in the same ConfigFile as the per-map records and is loaded
## once per process into static state.

const LEGACY_PATH := "user://td_mania_best.cfg"
const GLOBAL_PATH := "user://td_mania.cfg"
const SLOTS := 3

## Set by the dev harnesses so tests can build anything regardless of level.
static var unlock_all: bool = false

## Also set by the harnesses: keeps simulated runs from writing XP, coins or
## tech into the player's real save file.
static var read_only: bool = false

static var loaded: bool = false
static var slot: int = 0
static var xp: int = 0
static var coins: int = 0
static var ranks: Dictionary = {}
static var bests: Dictionary = {}
static var options: Dictionary = {}
## Purchased tower upgrade ranks: type_id -> [rank per track].
static var tower_ranks: Dictionary = {}
## Lifetime totals for the stats page.
static var stats: Dictionary = {}
## Runs the player left mid-way, keyed by level id: every map keeps its own,
## so starting one map never discards the save on another.
static var runs: Dictionary = {}
## Objective stars earned per map: level id -> bitmask of objectives met.
static var stars: Dictionary = {}

## Reward weights. A run pays out on waves survived and score, scaled by the
## map's difficulty tier.
const XP_PER_WAVE := 40.0
const XP_PER_SCORE := 0.125
const COINS_PER_WAVE := 4.0
const COINS_PER_SCORE := 0.02
static var TIER_REWARD: Array = [1.0, 1.15, 1.3, 1.5]

## Three branches of four nodes. `requires` names the node directly above it,
## so each branch is a chain and the whole thing reads as a tree.
static var TECH: Array = [
	{"id": "munitions", "name": "Munitions", "branch": 0, "requires": "",
		"max": 3, "cost": 40, "cost_mult": 1.7, "mods": {"damage_mult": 1.06},
		"desc": "Every tower deals more damage."},
	{"id": "optics", "name": "Optics", "branch": 0, "requires": "munitions",
		"max": 3, "cost": 55, "cost_mult": 1.7, "mods": {"range_mult": 1.06},
		"desc": "Every tower sees further."},
	{"id": "drill", "name": "Drill Sergeant", "branch": 0, "requires": "optics",
		"max": 3, "cost": 70, "cost_mult": 1.7, "mods": {"rate_mult": 1.05},
		"desc": "Every tower fires faster."},
	{"id": "blast", "name": "Blast Engineering", "branch": 0, "requires": "drill",
		"max": 2, "cost": 110, "cost_mult": 1.8, "mods": {"splash_mult": 1.12},
		"desc": "Splash weapons cover more ground."},

	{"id": "warchest", "name": "War Chest", "branch": 1, "requires": "",
		"max": 3, "cost": 35, "cost_mult": 1.7, "mods": {"start_gold_add": 30.0},
		"desc": "Start every map with more gold."},
	{"id": "bounty", "name": "Bounty Hunter", "branch": 1, "requires": "warchest",
		"max": 3, "cost": 55, "cost_mult": 1.7, "mods": {"kill_gold_mult": 1.08},
		"desc": "Kills pay better."},
	{"id": "salvage", "name": "Salvage Crew", "branch": 1, "requires": "bounty",
		"max": 2, "cost": 75, "cost_mult": 1.8, "mods": {"sell_refund_add": 0.08},
		"desc": "Selling a tower refunds more of what you paid."},
	{"id": "logistics", "name": "Rapid Deployment", "branch": 1, "requires": "salvage",
		"max": 2, "cost": 120, "cost_mult": 1.8, "mods": {"build_cost_mult": 0.94},
		"desc": "Towers cost less to build."},

	{"id": "fortify", "name": "Fortifications", "branch": 2, "requires": "",
		"max": 3, "cost": 45, "cost_mult": 1.7, "mods": {"start_lives_add": 2.0},
		"desc": "Start every map with more lives."},
	{"id": "cryo", "name": "Cryogenics", "branch": 2, "requires": "fortify",
		"max": 2, "cost": 70, "cost_mult": 1.8, "mods": {"slow_add": 0.05},
		"desc": "Every slowing effect bites harder."},
	{"id": "airdoctrine", "name": "Air Doctrine", "branch": 2, "requires": "cryo",
		"max": 3, "cost": 85, "cost_mult": 1.7, "mods": {"air_damage_mult": 1.1},
		"desc": "Bombers and gunships hit harder."},
	{"id": "overtime", "name": "Overtime", "branch": 2, "requires": "airdoctrine",
		"max": 2, "cost": 95, "cost_mult": 1.8, "mods": {"early_bonus_mult": 1.3},
		"desc": "Starting a wave early pays a bigger bonus."},
]


static func slot_path(index: int) -> String:
	return "user://td_mania_slot_%d.cfg" % clampi(index, 0, SLOTS - 1)


## Slot chosen on the title screen. Remembered between sessions.
static func use_slot(index: int) -> void:
	slot = clampi(index, 0, SLOTS - 1)
	loaded = false
	xp = 0
	coins = 0
	ranks = {}
	bests = {}
	load_state()
	if not read_only:
		var g := ConfigFile.new()
		g.load(GLOBAL_PATH)
		g.set_value("app", "last_slot", slot)
		g.save(GLOBAL_PATH)


static func last_slot() -> int:
	var g := ConfigFile.new()
	if g.load(GLOBAL_PATH) != OK:
		return 0
	return clampi(int(g.get_value("app", "last_slot", 0)), 0, SLOTS - 1)


## A save from before slots existed becomes slot 1 the first time it is seen.
static func migrate_legacy() -> void:
	if read_only or not FileAccess.file_exists(LEGACY_PATH) \
			or FileAccess.file_exists(slot_path(0)):
		return
	var old := ConfigFile.new()
	if old.load(LEGACY_PATH) != OK:
		return
	old.save(slot_path(0))


## Bumped whenever the shape of a save changes. Every older version has a
## migration step below, so an old file is upgraded on load instead of
## crashing the first time new code reads a key that was never written.
##
##   1  pre-slots, at most one parked run under [run] state
##   2  one parked run per map under [runs], run stats without the per-kind
##      kill and leak tallies
##   3  versioned, and every parked run carries the full stat set
##   4  current: per-map objective stars under [stars]
const SAVE_VERSION := 4

## The keys a parked run's stats must have. Kept here rather than imported
## from game.gd so migration does not depend on the match scene.
const RUN_STAT_KEYS: Array = ["kills", "leaks", "towers_built", "gold_earned",
		"damage", "tower_kills", "tower_built", "enemy_kills", "enemy_leaks"]

## Set when the slot was written by a newer build than this one. Saving is
## refused for that slot so a downgrade cannot quietly delete what it could
## not read.
static var slot_too_new: bool = false


## What version a file claims, inferring one for saves written before the
## field existed.
static func detect_version(cfg: ConfigFile) -> int:
	var stamped := int(cfg.get_value("meta", "version", 0))
	if stamped > 0:
		return stamped
	return 1 if cfg.has_section("run") else 2


## Walks a loaded config forward to SAVE_VERSION, one step at a time, so a
## save that skipped several builds still arrives in the right shape.
static func migrate_config(cfg: ConfigFile, from_version: int) -> int:
	var at := from_version
	while at < SAVE_VERSION:
		match at:
			1:
				# One parked run became one per map.
				var legacy: Dictionary = cfg.get_value("run", "state", {})
				var level_id := str(legacy.get("level", ""))
				if not legacy.is_empty() and level_id != "" \
						and not cfg.has_section_key("runs", level_id):
					cfg.set_value("runs", level_id, legacy)
				if cfg.has_section("run"):
					cfg.erase_section("run")
			3:
				# Stars are new in 4. An older save simply has none yet, so
				# there is nothing to convert - the arm exists so the chain
				# stays explicit and the next change has a pattern to copy.
				pass
			2:
				# Run stats gained per-kind tallies; fill them in so the
				# match does not index a key that was never saved.
				if cfg.has_section("runs"):
					for key: String in cfg.get_section_keys("runs"):
						var run: Dictionary = cfg.get_value("runs", key, {})
						if run.is_empty():
							continue
						var run_stats: Dictionary = run.get("stats", {})
						for stat_key: String in RUN_STAT_KEYS:
							if not run_stats.has(stat_key):
								run_stats[stat_key] = {} if stat_key.ends_with("kills") \
										or stat_key.ends_with("leaks") \
										or stat_key.ends_with("built") else 0
						# kills and leaks themselves are counters, not maps.
						for counter: String in ["kills", "leaks"]:
							if typeof(run_stats.get(counter)) == TYPE_DICTIONARY:
								run_stats[counter] = 0
						run["stats"] = run_stats
						cfg.set_value("runs", key, run)
		at += 1
	cfg.set_value("meta", "version", SAVE_VERSION)
	return at


static func load_state() -> void:
	if loaded:
		return
	loaded = true
	slot_too_new = false
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return
	var found := detect_version(cfg)
	if found > SAVE_VERSION:
		# Read what we understand, but never write this slot back.
		slot_too_new = true
		push_warning("Save slot %d was written by a newer build (v%d > v%d); it will not be overwritten."
				% [slot + 1, found, SAVE_VERSION])
	elif found < SAVE_VERSION:
		migrate_config(cfg, found)
	apply_config(cfg)


## Reads a migrated config into the live account. Split out from load_state
## so it can be exercised without a file on disk.
static func apply_config(cfg: ConfigFile) -> void:
	# Every table is cleared first: switching slots must not leave the
	# previous account's tech, records or lifetime stats behind.
	ranks = {}
	bests = {}
	runs = {}
	stats = {}
	stars = {}
	tower_ranks = {}
	xp = int(cfg.get_value("progress", "xp", 0))
	coins = int(cfg.get_value("progress", "coins", 0))
	if cfg.has_section("tech"):
		for key: String in cfg.get_section_keys("tech"):
			ranks[key] = int(cfg.get_value("tech", key, 0))
	if cfg.has_section("best_wave"):
		for key: String in cfg.get_section_keys("best_wave"):
			bests[key] = int(cfg.get_value("best_wave", key, 0))
	if cfg.has_section("runs"):
		for key: String in cfg.get_section_keys("runs"):
			runs[key] = cfg.get_value("runs", key, {})
	options["sfx"] = float(cfg.get_value("options", "sfx", 0.8))
	options["music"] = float(cfg.get_value("options", "music", 0.35))
	if cfg.has_section("stats"):
		for key: String in cfg.get_section_keys("stats"):
			stats[key] = cfg.get_value("stats", key, 0)
	if cfg.has_section("towers"):
		for key: String in cfg.get_section_keys("towers"):
			tower_ranks[key] = Array(cfg.get_value("towers", key, []))
	if cfg.has_section("stars"):
		for key: String in cfg.get_section_keys("stars"):
			stars[key] = int(cfg.get_value("stars", key, 0))


static func save_state() -> void:
	if read_only or slot_too_new:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "coins", coins)
	for key: String in ranks:
		cfg.set_value("tech", key, int(ranks[key]))
	for key: String in bests:
		cfg.set_value("best_wave", key, int(bests[key]))
	for key: String in tower_ranks:
		cfg.set_value("towers", key, tower_ranks[key])
	for key: String in stats:
		cfg.set_value("stats", key, stats[key])
	cfg.set_value("options", "sfx", volume("sfx"))
	cfg.set_value("options", "music", volume("music"))
	for key: String in stars:
		cfg.set_value("stars", key, int(stars[key]))
	for key: String in runs:
		cfg.set_value("runs", key, runs[key])
	cfg.save(slot_path(slot))


# --------------------------------------------------------------- audio

## Volume for "sfx" or "music", 0..1.
static func volume(kind: String) -> float:
	load_state()
	return clampf(float(options.get(kind, 0.8 if kind == "sfx" else 0.35)), 0.0, 1.0)


static func set_volume(kind: String, value: float) -> void:
	load_state()
	options[kind] = clampf(value, 0.0, 1.0)
	save_state()


# ------------------------------------------------------------ saved run

## Parks a run under its own map, leaving other maps' saves alone.
static func save_run(state: Dictionary) -> void:
	load_state()
	runs[str(state.get("level", ""))] = state
	save_state()


## Forgets the parked run for one map (or all of them when given nothing).
static func clear_run(level_id: String = "") -> void:
	load_state()
	if level_id == "":
		if runs.is_empty():
			return
		runs = {}
	else:
		if not runs.has(level_id):
			return
		runs.erase(level_id)
	save_state()


## The saved run for a map, or {} when there is none.
static func run_for(level_id: String) -> Dictionary:
	load_state()
	return runs.get(level_id, {})


## How many maps currently hold a parked run.
static func parked_count() -> int:
	load_state()
	return runs.size()


static func has_run(level_id: String) -> bool:
	return not run_for(level_id).is_empty()


# ------------------------------------------------------- lifetime statistics

static func stat(key: String, fallback: Variant = 0) -> Variant:
	load_state()
	return stats.get(key, fallback)


static func stat_int(key: String) -> int:
	return int(stat(key, 0))


## Folds one run's tallies into the lifetime totals.
static func add_run_stats(run: Dictionary) -> void:
	load_state()
	for key: String in ["runs", "waves", "kills", "leaks", "towers_built", "gold_earned",
			"damage", "xp_earned", "coins_earned"]:
		stats[key] = stat_int(key) + int(run.get(key, 0))
	stats["best_wave"] = maxi(stat_int("best_wave"), int(run.get("waves", 0)))
	# Per-tower kills and builds, kept as small dictionaries.
	for field: String in ["tower_kills", "tower_built", "enemy_kills", "enemy_leaks"]:
		var totals: Dictionary = stats.get(field, {})
		for type_id: String in run.get(field, {}):
			totals[type_id] = int(totals.get(type_id, 0)) + int(run[field][type_id])
		stats[field] = totals
	save_state()


# ------------------------------------------------- tower upgrade purchases

## Purchased ranks for one tower type, one entry per upgrade track.
static func ranks_for(type_id: String) -> Array:
	load_state()
	var size: int = TDData.tracks(type_id).size()
	if not tower_ranks.has(type_id) or (tower_ranks[type_id] as Array).size() != size:
		var fresh: Array = []
		fresh.resize(size)
		fresh.fill(0)
		var kept: Array = tower_ranks.get(type_id, [])
		for i in mini(kept.size(), size):
			fresh[i] = int(kept[i])
		tower_ranks[type_id] = fresh
	return tower_ranks[type_id]


static func track_rank_for(type_id: String, track: int) -> int:
	return int(ranks_for(type_id)[track])


static func track_next_cost(type_id: String, track: int) -> int:
	return TDData.track_cost(type_id, track, track_rank_for(type_id, track))


## In-tower prerequisite: the named track must already be at the given rank.
static func track_prereq_met(type_id: String, track: int) -> bool:
	var need: Dictionary = TDData.track_requirement(type_id, track)
	if need.is_empty():
		return true
	var parent := TDData.track_index(type_id, str(need["track"]))
	return parent >= 0 and track_rank_for(type_id, parent) >= int(need["rank"])


## Everything that has to be true before a rank can be bought.
static func track_buy_state(type_id: String, track: int) -> Dictionary:
	var maxed: bool = track_rank_for(type_id, track) >= int(TDData.tracks(type_id)[track]["max"])
	var level_ok: bool = unlock_all or level() >= track_unlock_level(type_id, track)
	var prereq_ok: bool = track_prereq_met(type_id, track)
	var cost: int = track_next_cost(type_id, track)
	return {
		"maxed": maxed, "level_ok": level_ok, "prereq_ok": prereq_ok,
		"affordable": coins >= cost, "cost": cost,
		"can_buy": not maxed and level_ok and prereq_ok and coins >= cost,
	}


static func buy_track(type_id: String, track: int) -> bool:
	var state := track_buy_state(type_id, track)
	if not bool(state["can_buy"]):
		return false
	coins -= int(state["cost"])
	var list: Array = ranks_for(type_id)
	list[track] = int(list[track]) + 1
	tower_ranks[type_id] = list
	save_state()
	return true


## Total ranks bought on a tower, for the tech tree's rail counters.
static func tower_rank_total(type_id: String) -> int:
	var total := 0
	for r in ranks_for(type_id):
		total += int(r)
	return total


# --------------------------------------------------------------- best waves

## Objectives are a bitmask so a run can pick up whichever it managed and
## the account keeps the union of every attempt.
static func stars_for(level_id: String) -> int:
	load_state()
	return int(stars.get(level_id, 0))


static func star_count(level_id: String) -> int:
	var mask := stars_for(level_id)
	var count := 0
	for bit in 3:
		if mask & (1 << bit) != 0:
			count += 1
	return count


static func total_stars() -> int:
	load_state()
	var total := 0
	for key: String in stars:
		total += star_count(key)
	return total


## Adds whatever this run earned. Returns the newly earned bits, so the game
## can say which star just dropped.
static func record_stars(level_id: String, mask: int) -> int:
	load_state()
	var had := int(stars.get(level_id, 0))
	var gained := mask & ~had
	if gained == 0:
		return 0
	stars[level_id] = had | mask
	save_state()
	return gained


static func best_wave(level_id: String) -> int:
	load_state()
	return int(bests.get(level_id, 0))


## Records a new personal best for a map. Returns true when it beat the old.
static func record_wave(level_id: String, waves: int) -> bool:
	load_state()
	if waves <= best_wave(level_id):
		return false
	bests[level_id] = waves
	save_state()
	return true


## Everything the slot picker needs about a save, read without disturbing the
## slot currently in play.
static func slot_summary(index: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(index)) != OK:
		return {"used": false, "level": 1, "xp": 0, "coins": 0, "maps": 0, "best": 0,
			"tech": 0}
	var slot_xp := int(cfg.get_value("progress", "xp", 0))
	var maps := 0
	var best := 0
	if cfg.has_section("best_wave"):
		for key: String in cfg.get_section_keys("best_wave"):
			maps += 1
			best = maxi(best, int(cfg.get_value("best_wave", key, 0)))
	var tech_ranks := 0
	if cfg.has_section("tech"):
		for key: String in cfg.get_section_keys("tech"):
			tech_ranks += int(cfg.get_value("tech", key, 0))
	return {"used": slot_xp > 0 or maps > 0 or tech_ranks > 0,
		"level": level_for_xp(slot_xp), "xp": slot_xp,
		"coins": int(cfg.get_value("progress", "coins", 0)),
		"maps": maps, "best": best, "tech": tech_ranks}


static func erase_slot(index: int) -> void:
	if read_only:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(index)))
	if index == slot:
		loaded = false
		xp = 0
		coins = 0
		ranks = {}
		bests = {}


## Blank in-memory account used by the dev harnesses so a developer's own
## progress never changes what a test or simulation measures.
static func use_clean_state() -> void:
	loaded = true
	read_only = true
	unlock_all = true
	slot_too_new = false
	xp = 0
	coins = 0
	ranks = {}
	bests = {}
	options = {}
	tower_ranks = {}
	stats = {}
	stars = {}
	runs = {}
	# Balance overrides are excluded too, so a simulation measures the numbers
	# in data.gd rather than whatever the developer was last experimenting with.
	Tuning.use_clean_state()


static func reset() -> void:
	xp = 0
	coins = 0
	ranks = {}
	bests = {}
	options = {}
	tower_ranks = {}
	stats = {}
	stars = {}
	runs = {}
	if not read_only:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


# ------------------------------------------------------------------- levels

## Total XP needed to reach `level`. Quadratic, so early levels come quickly
## and the last tower unlocks take a few good runs.
static func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var l := float(level - 1)
	return int(300.0 * l + 100.0 * l * l)


## Account level for an arbitrary XP total.
static func level_for_xp(total: int) -> int:
	var l := 1
	while l < 40 and total >= xp_for_level(l + 1):
		l += 1
	return l


static func level() -> int:
	load_state()
	return level_for_xp(xp)


## Progress through the current level, 0-1, and the XP either side of it.
static func level_progress() -> Dictionary:
	var l := level()
	var from := xp_for_level(l)
	var to := xp_for_level(l + 1)
	var span: int = maxi(1, to - from)
	return {"level": l, "from": from, "to": to,
		"ratio": clampf(float(xp - from) / float(span), 0.0, 1.0)}


static func tower_unlock_level(type_id: String) -> int:
	return int(TDData.TOWERS[type_id].get("unlock_level", 1))


static func tower_unlocked(type_id: String) -> bool:
	return unlock_all or level() >= tower_unlock_level(type_id)


static func track_unlock_level(type_id: String, track: int) -> int:
	return int(TDData.tracks(type_id)[track].get("level", 1))


static func track_unlocked(type_id: String, track: int) -> bool:
	return unlock_all or level() >= track_unlock_level(type_id, track)


## The next thing the player will unlock, or {} once everything is open.
static func level_unlocked(level_def: Dictionary) -> bool:
	return unlock_all or level() >= TDData.level_unlock(level_def)


static func next_unlock() -> Dictionary:
	var current := level()
	var best: Dictionary = {}
	for d: Dictionary in TDData.LEVELS:
		var need := TDData.level_unlock(d)
		if need <= current:
			continue
		if best.is_empty() or need < int(best["level"]):
			best = {"level": need, "what": str(d["name"]), "kind": "map"}
	for type_id: String in TDData.TOWER_ORDER:
		var need := tower_unlock_level(type_id)
		if need <= current:
			continue
		if best.is_empty() or need < int(best["level"]):
			best = {"level": need, "what": str(TDData.TOWERS[type_id]["name"]), "kind": "tower"}
	for type_id: String in TDData.TOWER_ORDER:
		for i in TDData.tracks(type_id).size():
			var need := track_unlock_level(type_id, i)
			if need <= current:
				continue
			if best.is_empty() or need < int(best["level"]):
				best = {"level": need, "kind": "upgrade",
					"what": "%s: %s" % [TDData.TOWERS[type_id]["name"],
					TDData.tracks(type_id)[i]["name"]]}
	return best


# --------------------------------------------------------------------- tech

static func node(id: String) -> Dictionary:
	for t: Dictionary in TECH:
		if str(t["id"]) == id:
			return t
	return {}


static func rank(id: String) -> int:
	load_state()
	return int(ranks.get(id, 0))


static func node_cost(id: String) -> int:
	var t := node(id)
	if t.is_empty():
		return 0
	return int(float(t["cost"]) * pow(float(t["cost_mult"]), float(rank(id))))


## A node needs its parent maxed before it can be bought at all.
static func node_available(id: String) -> bool:
	var t := node(id)
	if t.is_empty():
		return false
	var parent := str(t["requires"])
	if parent == "":
		return true
	return rank(parent) >= int(node(parent)["max"])


static func can_buy(id: String) -> bool:
	var t := node(id)
	if t.is_empty():
		return false
	return node_available(id) and rank(id) < int(t["max"]) and coins >= node_cost(id)


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	coins -= node_cost(id)
	ranks[id] = rank(id) + 1
	save_state()
	return true


## Multiplicative tech bonus for `key` (1.0 when nothing is bought).
static func bonus_mult(key: String) -> float:
	load_state()
	var total := 1.0
	for t: Dictionary in TECH:
		var mods: Dictionary = t["mods"]
		if mods.has(key):
			total *= pow(float(mods[key]), float(rank(str(t["id"]))))
	return total


## Additive tech bonus for `key` (0.0 when nothing is bought).
static func bonus_add(key: String) -> float:
	load_state()
	var total := 0.0
	for t: Dictionary in TECH:
		var mods: Dictionary = t["mods"]
		if mods.has(key):
			total += float(mods[key]) * float(rank(str(t["id"])))
	return total


## Plain-language summary of a tech node's per-rank effect.
static func describe(mods: Dictionary) -> String:
	var parts: Array = []
	for key: String in mods:
		var value := float(mods[key])
		match key:
			"damage_mult": parts.append("+%d%% damage" % _pct(value))
			"rate_mult": parts.append("+%d%% fire rate" % _pct(value))
			"range_mult": parts.append("+%d%% range" % _pct(value))
			"splash_mult": parts.append("+%d%% blast radius" % _pct(value))
			"air_damage_mult": parts.append("+%d%% aircraft damage" % _pct(value))
			"kill_gold_mult": parts.append("+%d%% gold from kills" % _pct(value))
			"build_cost_mult": parts.append("-%d%% build cost" % (100 - int(value * 100.0)))
			"early_bonus_mult": parts.append("+%d%% early-wave bonus" % _pct(value))
			"start_gold_add": parts.append("+%d starting gold" % int(value))
			"start_lives_add": parts.append("+%d starting lives" % int(value))
			"sell_refund_add": parts.append("+%d%% sell refund" % int(value * 100.0))
			"slow_add": parts.append("+%d%% slow" % int(value * 100.0))
			_: parts.append(key)
	return ", ".join(parts)


static func _pct(value: float) -> int:
	return int(round((value - 1.0) * 100.0))


# ------------------------------------------------------------------ rewards

## What a finished run pays out. `waves` is the number completed.
static func run_reward(waves: int, score: int, tier: int) -> Dictionary:
	var mult: float = TIER_REWARD[clampi(tier, 0, TIER_REWARD.size() - 1)]
	return {
		"xp": int((float(waves) * XP_PER_WAVE + float(score) * XP_PER_SCORE) * mult),
		"coins": int((float(waves) * COINS_PER_WAVE + float(score) * COINS_PER_SCORE) * mult),
	}


## Banks a run's reward and reports what changed, including any level-ups.
static func award(waves: int, score: int, tier: int) -> Dictionary:
	load_state()
	var reward := run_reward(waves, score, tier)
	var before := level()
	xp += int(reward["xp"])
	coins += int(reward["coins"])
	save_state()
	var after := level()
	reward["level_before"] = before
	reward["level_after"] = after
	reward["levelled"] = after > before
	return reward
