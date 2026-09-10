class_name Tuning
extends RefCounted

## Live balance overrides for towers, upgrade tracks and creeps.
##
## Any number in `TDData.TOWERS`, in one of a tower's upgrade tracks, or in
## `TDData.ENEMIES` can be overridden globally or for one level — so a tower
## that is fair on Easy and absurd on Brutal, an upgrade that outclasses the
## rest of its tree, or a creep that lands too hard on one map can each be
## pegged back exactly where they misbehave.
##
## The tuning panel (F2 in a match) writes here; `TDData.tower_def()`,
## `TDData.tracks()` and `TDData.enemy_def()` read it, so a change lands on
## the next frame with no restart. Overrides live in their own file and
## never touch a save slot — deleting it puts every number back to the
## tables in `data.gd`.

const FILE_PATH := "user://td_mania_tuning.cfg"

## Subjects are addressed by id: a bare tower id ("gun"), a creep as
## "enemy:grunt", one upgrade track as "track:gun#0". Towers stay bare so
## files written before enemies and upgrades were tunable still load.
const ENEMY_PREFIX := "enemy:"
const TRACK_PREFIX := "track:"

## The stats worth exposing, in the order the panel lists them, with the step
## a single click moves them by. A tower only shows the ones it defines.
const TUNABLE: Array = [
	{"key": "damage", "name": "Damage", "step": 1.0, "min": 0.0, "max": 400.0},
	{"key": "rate", "name": "Fire rate", "step": 0.05, "min": 0.05, "max": 8.0},
	{"key": "range", "name": "Range", "step": 5.0, "min": 40.0, "max": 600.0},
	{"key": "cost", "name": "Cost", "step": 5.0, "min": 5.0, "max": 2000.0},
	{"key": "splash", "name": "Splash", "step": 4.0, "min": 0.0, "max": 260.0},
	{"key": "slow", "name": "Slow", "step": 0.05, "min": 0.0, "max": 0.85},
	{"key": "slow_dur", "name": "Slow time", "step": 0.1, "min": 0.0, "max": 8.0},
	{"key": "knockback", "name": "Knockback", "step": 4.0, "min": 0.0, "max": 200.0},
	{"key": "proj_speed", "name": "Shot speed", "step": 20.0, "min": 60.0, "max": 1600.0},
	{"key": "min_range", "name": "Dead zone", "step": 5.0, "min": 0.0, "max": 300.0},
	{"key": "beam_dps", "name": "Beam DPS", "step": 2.0, "min": 0.0, "max": 400.0},
	{"key": "income", "name": "Income", "step": 1.0, "min": 0.0, "max": 200.0},
	{"key": "units", "name": "Aircraft", "step": 1.0, "min": 1.0, "max": 6.0},
	{"key": "volley", "name": "Volley", "step": 1.0, "min": 1.0, "max": 12.0},
	{"key": "chain", "name": "Chain", "step": 1.0, "min": 1.0, "max": 12.0},
	{"key": "pierce_count", "name": "Pierce", "step": 1.0, "min": 1.0, "max": 12.0},
]

## Creep numbers. Health and speed carry the difficulty of a wave; the rest
## decide how a kind has to be answered.
const ENEMY_TUNABLE: Array = [
	{"key": "hp", "name": "Health", "step": 5.0, "min": 1.0, "max": 20000.0},
	{"key": "speed", "name": "Speed", "step": 2.0, "min": 5.0, "max": 400.0},
	{"key": "armor", "name": "Armour", "step": 1.0, "min": 0.0, "max": 200.0},
	{"key": "reward", "name": "Bounty", "step": 1.0, "min": 0.0, "max": 2000.0},
	{"key": "damage", "name": "Lives lost", "step": 1.0, "min": 0.0, "max": 50.0},
	{"key": "radius", "name": "Size", "step": 1.0, "min": 4.0, "max": 60.0},
	{"key": "heal", "name": "Heal rate", "step": 2.0, "min": 0.0, "max": 400.0},
	{"key": "heal_range", "name": "Heal range", "step": 5.0, "min": 0.0, "max": 400.0},
	{"key": "steal_gold", "name": "Gold stolen", "step": 5.0, "min": 0.0, "max": 999.0},
	{"key": "split_count", "name": "Splits into", "step": 1.0, "min": 0.0, "max": 12.0},
	{"key": "charge_period", "name": "Sprint every", "step": 0.2, "min": 0.2, "max": 30.0},
	{"key": "charge_time", "name": "Sprint for", "step": 0.1, "min": 0.1, "max": 10.0},
	{"key": "charge_mult", "name": "Sprint speed", "step": 0.1, "min": 1.0, "max": 6.0},
]

## What an upgrade track exposes beyond its modifiers.
const TRACK_TUNABLE: Array = [
	{"key": "max", "name": "Ranks", "step": 1.0, "min": 1.0, "max": 8.0},
	{"key": "cost_frac", "name": "Cost share", "step": 0.05, "min": 0.05, "max": 3.0},
	{"key": "level", "name": "Unlocks at", "step": 1.0, "min": 1.0, "max": 60.0},
]

## Global overrides, then per-level ones layered on top:
## {subject: {stat: value}} and {level_id: {subject: {stat: value}}}.
static var global_values: Dictionary = {}
static var level_values: Dictionary = {}
## Bumped on every change so caches know to drop what they hold.
static var version: int = 0
static var loaded: bool = false
## Harnesses tune freely without ever writing the file.
static var read_only: bool = false


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	load_file()


## Wipes the overrides and stops anything reaching disk. Used by the dev
## harnesses so a simulation cannot rewrite real balance.
static func use_clean_state() -> void:
	global_values = {}
	level_values = {}
	loaded = true
	read_only = true
	version += 1


static func load_file() -> void:
	global_values = {}
	level_values = {}
	var cfg := ConfigFile.new()
	if cfg.load(FILE_PATH) != OK:
		version += 1
		return
	for section: String in cfg.get_sections():
		var bucket: Dictionary = {}
		for key: String in cfg.get_section_keys(section):
			var entry: Variant = cfg.get_value(section, key)
			if entry is Dictionary and not (entry as Dictionary).is_empty():
				bucket[key] = (entry as Dictionary).duplicate()
		if bucket.is_empty():
			continue
		if section == "global":
			global_values = bucket
		elif section.begins_with("level_"):
			level_values[int(section.trim_prefix("level_"))] = bucket
	version += 1


static func save_file() -> bool:
	if read_only:
		return false
	var cfg := ConfigFile.new()
	for subject: String in global_values:
		cfg.set_value("global", subject, global_values[subject])
	for level_id: int in level_values:
		for subject: String in level_values[level_id]:
			cfg.set_value("level_%d" % level_id, subject,
					level_values[level_id][subject])
	return cfg.save(FILE_PATH) == OK


## True when the file on disk still matches what is in memory.
static func has_overrides() -> bool:
	return not global_values.is_empty() or not level_values.is_empty()


## Overrides that apply to `subject` on `level_id` — global first, then the
## level's own, which wins. `level_id` of -1 asks for the global set alone.
static func effective(subject: String, level_id: int) -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	if global_values.has(subject):
		out.merge(global_values[subject], true)
	if level_id >= 0 and level_values.has(level_id) \
			and (level_values[level_id] as Dictionary).has(subject):
		out.merge(level_values[level_id][subject], true)
	return out


## The value a stat currently has: an override if one exists, else the table.
static func value_of(subject: String, key: String, level_id: int) -> float:
	var over := effective(subject, level_id)
	if over.has(key):
		return float(over[key])
	return float(base_of(subject).get(key, 0.0))


static func is_overridden(subject: String, key: String, level_id: int) -> bool:
	return effective(subject, level_id).has(key)


## Writes one stat. `level_id` of -1 changes it everywhere; anything else
## changes it on that level only.
static func set_value(subject: String, key: String, value: float, level_id: int) -> void:
	ensure_loaded()
	var bucket: Dictionary = global_values
	if level_id >= 0:
		if not level_values.has(level_id):
			level_values[level_id] = {}
		bucket = level_values[level_id]
	if not bucket.has(subject):
		bucket[subject] = {}
	bucket[subject][key] = value
	version += 1


## Drops one override so the stat falls back to the layer beneath it.
static func clear_value(subject: String, key: String, level_id: int) -> void:
	ensure_loaded()
	var bucket: Dictionary = global_values
	if level_id >= 0:
		bucket = level_values.get(level_id, {})
	if bucket.has(subject):
		(bucket[subject] as Dictionary).erase(key)
		if (bucket[subject] as Dictionary).is_empty():
			bucket.erase(subject)
	if level_id >= 0 and level_values.has(level_id) \
			and (level_values[level_id] as Dictionary).is_empty():
		level_values.erase(level_id)
	version += 1


static func clear_subject(subject: String, level_id: int) -> void:
	ensure_loaded()
	if level_id < 0:
		global_values.erase(subject)
	elif level_values.has(level_id):
		(level_values[level_id] as Dictionary).erase(subject)
		if (level_values[level_id] as Dictionary).is_empty():
			level_values.erase(level_id)
	version += 1


static func clear_all() -> void:
	ensure_loaded()
	global_values = {}
	level_values = {}
	version += 1


static func enemy_subject(kind: String) -> String:
	return ENEMY_PREFIX + kind


static func track_subject(tower_id: String, track: int) -> String:
	return "%s%s#%d" % [TRACK_PREFIX, tower_id, track]


static func is_enemy(subject: String) -> bool:
	return subject.begins_with(ENEMY_PREFIX)


static func is_track(subject: String) -> bool:
	return subject.begins_with(TRACK_PREFIX)


## The table entry a subject's untouched numbers come from.
static func base_of(subject: String) -> Dictionary:
	if is_enemy(subject):
		return TDData.ENEMIES.get(subject.trim_prefix(ENEMY_PREFIX), {})
	if is_track(subject):
		var body := subject.trim_prefix(TRACK_PREFIX).split("#")
		if body.size() != 2 or not TDData.TOWERS.has(body[0]):
			return {}
		var list: Array = TDData.TOWERS[body[0]]["tracks"]
		var index := int(body[1])
		if index < 0 or index >= list.size():
			return {}
		# Flattened so a modifier reads like any other number: the track's
		# own fields, plus "mods.<key>" for each per-rank modifier.
		var flat: Dictionary = {}
		var track: Dictionary = list[index]
		for key: String in track:
			if typeof(track[key]) == TYPE_INT or typeof(track[key]) == TYPE_FLOAT:
				flat[key] = track[key]
		for key: String in track.get("mods", {}):
			var value: Variant = (track["mods"] as Dictionary)[key]
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				flat["mods." + key] = value
		return flat
	return TDData.TOWERS.get(subject, {})


## What this subject is called on screen.
static func label_of(subject: String) -> String:
	if is_enemy(subject):
		var kind := subject.trim_prefix(ENEMY_PREFIX)
		return str(TDData.ENEMIES.get(kind, {}).get("name", kind))
	if is_track(subject):
		var body := subject.trim_prefix(TRACK_PREFIX).split("#")
		if body.size() != 2 or not TDData.TOWERS.has(body[0]):
			return subject
		var list: Array = TDData.TOWERS[body[0]]["tracks"]
		var index := int(body[1])
		if index < 0 or index >= list.size():
			return subject
		return "%s — %s" % [TDData.TOWERS[body[0]]["short"], list[index]["name"]]
	return str(TDData.TOWERS.get(subject, {}).get("name", subject))


## The rows the panel shows for a subject: only numbers it actually has.
static func rows_for(subject: String) -> Array:
	var base := base_of(subject)
	var out: Array = []
	if is_track(subject):
		for row: Dictionary in TRACK_TUNABLE:
			if base.has(row["key"]):
				out.append(row)
		# Modifiers vary per track, so their rows are built from the table.
		for key: String in base:
			if not key.begins_with("mods."):
				continue
			out.append(_mod_row(key, float(base[key])))
		return out
	var table: Array = ENEMY_TUNABLE if is_enemy(subject) else TUNABLE
	for row: Dictionary in table:
		if base.has(row["key"]):
			out.append(row)
	return out


## A sensible step for a modifier, from what kind of modifier it is: a
## multiplier moves in percents, an addition in small absolute steps.
static func _mod_row(key: String, value: float) -> Dictionary:
	var name := key.substr(5).replace("_", " ")
	if key.ends_with("_mult"):
		return {"key": key, "name": name, "step": 0.02, "min": 0.1, "max": 4.0}
	if absf(value) >= 10.0:
		return {"key": key, "name": name, "step": 1.0, "min": -400.0, "max": 400.0}
	return {"key": key, "name": name, "step": 0.02, "min": -20.0, "max": 20.0}
