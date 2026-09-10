class_name Tuning
extends RefCounted

## Live balance overrides for tower numbers.
##
## Every tower stat in `TDData.TOWERS` can be overridden globally or for one
## level, so a tower that is fair on Easy and absurd on Brutal can be pegged
## back only where it misbehaves. The tuning panel (F2 in a match) writes
## here; `TDData.tower_def()` reads it, so a change lands on the next frame
## with no restart. Overrides live in their own file and never touch a save
## slot — deleting it puts every number back to the table in `data.gd`.

const FILE_PATH := "user://td_mania_tuning.cfg"

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

## Global overrides, then per-level ones layered on top:
## {tower_id: {stat: value}} and {level_id: {tower_id: {stat: value}}}.
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
	for tower_id: String in global_values:
		cfg.set_value("global", tower_id, global_values[tower_id])
	for level_id: int in level_values:
		for tower_id: String in level_values[level_id]:
			cfg.set_value("level_%d" % level_id, tower_id, level_values[level_id][tower_id])
	return cfg.save(FILE_PATH) == OK


## True when the file on disk still matches what is in memory.
static func has_overrides() -> bool:
	return not global_values.is_empty() or not level_values.is_empty()


## Overrides that apply to `tower_id` on `level_id` — global first, then the
## level's own, which wins. `level_id` of -1 asks for the global set alone.
static func effective(tower_id: String, level_id: int) -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	if global_values.has(tower_id):
		out.merge(global_values[tower_id], true)
	if level_id >= 0 and level_values.has(level_id) \
			and (level_values[level_id] as Dictionary).has(tower_id):
		out.merge(level_values[level_id][tower_id], true)
	return out


## The value a stat currently has: an override if one exists, else the table.
static func value_of(tower_id: String, key: String, level_id: int) -> float:
	var over := effective(tower_id, level_id)
	if over.has(key):
		return float(over[key])
	return float(TDData.TOWERS[tower_id].get(key, 0.0))


static func is_overridden(tower_id: String, key: String, level_id: int) -> bool:
	return effective(tower_id, level_id).has(key)


## Writes one stat. `level_id` of -1 changes it everywhere; anything else
## changes it on that level only.
static func set_value(tower_id: String, key: String, value: float, level_id: int) -> void:
	ensure_loaded()
	var bucket: Dictionary = global_values
	if level_id >= 0:
		if not level_values.has(level_id):
			level_values[level_id] = {}
		bucket = level_values[level_id]
	if not bucket.has(tower_id):
		bucket[tower_id] = {}
	bucket[tower_id][key] = value
	version += 1


## Drops one override so the stat falls back to the layer beneath it.
static func clear_value(tower_id: String, key: String, level_id: int) -> void:
	ensure_loaded()
	var bucket: Dictionary = global_values
	if level_id >= 0:
		bucket = level_values.get(level_id, {})
	if bucket.has(tower_id):
		(bucket[tower_id] as Dictionary).erase(key)
		if (bucket[tower_id] as Dictionary).is_empty():
			bucket.erase(tower_id)
	if level_id >= 0 and level_values.has(level_id) \
			and (level_values[level_id] as Dictionary).is_empty():
		level_values.erase(level_id)
	version += 1


static func clear_tower(tower_id: String, level_id: int) -> void:
	ensure_loaded()
	if level_id < 0:
		global_values.erase(tower_id)
	elif level_values.has(level_id):
		(level_values[level_id] as Dictionary).erase(tower_id)
		if (level_values[level_id] as Dictionary).is_empty():
			level_values.erase(level_id)
	version += 1


static func clear_all() -> void:
	ensure_loaded()
	global_values = {}
	level_values = {}
	version += 1


## The stats this tower actually has, as panel rows.
static func rows_for(tower_id: String) -> Array:
	var def: Dictionary = TDData.TOWERS.get(tower_id, {})
	var out: Array = []
	for row: Dictionary in TUNABLE:
		if def.has(row["key"]):
			out.append(row)
	return out
