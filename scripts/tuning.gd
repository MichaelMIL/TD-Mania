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
##
## Inside a track subject, a key ending in "#N" belongs to rank N alone —
## "cost#2" is what the second rank costs in coins, "gold#2" what it costs
## to install in a match, "mods.damage_mult#2" what that rank actually
## does. Without the suffix the key applies to the whole track, which is
## the curve every rank follows unless it has been given its own number.
const ENEMY_PREFIX := "enemy:"
const TRACK_PREFIX := "track:"

## The stats worth exposing, in the order the panel lists them, with the step
## a single click moves them by. A tower only shows the ones it defines.
const TUNABLE: Array = [
	{"key": "damage", "name": "Damage", "step": 1.0, "min": 0.0, "max": 400.0,
		"info": "Damage per shot, before armour. Armour comes off every hit, so small fast shots suffer most."},
	{"key": "rate", "name": "Fire rate", "step": 0.05, "min": 0.05, "max": 8.0,
		"info": "Shots a second. Damage x rate is raw output; the two trade off for DPS but not for feel."},
	{"key": "range", "name": "Range", "step": 5.0, "min": 40.0, "max": 600.0,
		"info": "How far it reaches, in pixels — a cell is 64. Range decides how much road a tower covers, which usually matters more than damage."},
	{"key": "cost", "name": "Cost", "step": 5.0, "min": 5.0, "max": 2000.0,
		"info": "Gold to build. Also scales every upgrade rank, which are priced as a share of it."},
	{"key": "splash", "name": "Splash", "step": 4.0, "min": 0.0, "max": 260.0,
		"info": "Blast radius in pixels. Damage falls off to 35% at the edge."},
	{"key": "slow", "name": "Slow", "step": 0.05, "min": 0.0, "max": 0.85,
		"info": "How much a hit slows, as a fraction: 0.25 leaves the creep at 75% speed."},
	{"key": "slow_dur", "name": "Slow time", "step": 0.1, "min": 0.0, "max": 8.0,
		"info": "How long that slow lasts, in seconds."},
	{"key": "knockback", "name": "Knockback", "step": 4.0, "min": 0.0, "max": 200.0,
		"info": "How far a hit shoves a creep back down the road. Creeps build resistance to repeated shoves."},
	{"key": "proj_speed", "name": "Shot speed", "step": 20.0, "min": 60.0, "max": 1600.0,
		"info": "How fast the shot flies. Slow shots trail fast creeps and miss."},
	{"key": "min_range", "name": "Dead zone", "step": 5.0, "min": 0.0, "max": 300.0,
		"info": "A hole in the middle it cannot shoot into — what long-range towers pay for their reach."},
	{"key": "beam_dps", "name": "Beam DPS", "step": 2.0, "min": 0.0, "max": 400.0,
		"info": "Damage a second while the beam holds on a target."},
	{"key": "income", "name": "Income", "step": 1.0, "min": 0.0, "max": 200.0,
		"info": "Gold paid at the end of every wave, whatever happens on the board."},
	{"key": "units", "name": "Aircraft", "step": 1.0, "min": 1.0, "max": 6.0,
		"info": "How many aircraft the pad keeps in the air at once."},
	{"key": "volley", "name": "Volley", "step": 1.0, "min": 1.0, "max": 12.0,
		"info": "How many separate creeps one salvo fires at."},
	{"key": "chain", "name": "Chain", "step": 1.0, "min": 1.0, "max": 12.0,
		"info": "How many creeps the beam splits between."},
	{"key": "pierce_count", "name": "Pierce", "step": 1.0, "min": 1.0, "max": 12.0,
		"info": "How many creeps one shot passes through before stopping."},
]

## Creep numbers. Health and speed carry the difficulty of a wave; the rest
## decide how a kind has to be answered.
const ENEMY_TUNABLE: Array = [
	{"key": "hp", "name": "Health", "step": 5.0, "min": 1.0, "max": 20000.0,
		"info": "Health at wave 1. Every wave multiplies it, so a change here compounds across the run."},
	{"key": "speed", "name": "Speed", "step": 2.0, "min": 5.0, "max": 400.0,
		"info": "Pixels a second. Speed decides how long it spends inside a kill zone, which is as good as health."},
	{"key": "armor", "name": "Armour", "step": 1.0, "min": 0.0, "max": 200.0,
		"info": "Comes off every hit that is not armour-piercing. Brutal against fast weak shots, barely felt by heavy ones."},
	{"key": "reward", "name": "Bounty", "step": 1.0, "min": 0.0, "max": 2000.0,
		"info": "Gold paid for the kill — the main dial on how rich a run feels."},
	{"key": "damage", "name": "Lives lost", "step": 1.0, "min": 0.0, "max": 50.0,
		"info": "Lives lost if it reaches the base."},
	{"key": "radius", "name": "Size", "step": 1.0, "min": 4.0, "max": 60.0,
		"info": "How big it is: its hitbox for splash, and for the cursor."},
	{"key": "heal", "name": "Heal rate", "step": 2.0, "min": 0.0, "max": 400.0,
		"info": "Health a second it restores to wounded creeps nearby."},
	{"key": "heal_range", "name": "Heal range", "step": 5.0, "min": 0.0, "max": 400.0,
		"info": "How far that healing reaches, in pixels."},
	{"key": "steal_gold", "name": "Gold stolen", "step": 5.0, "min": 0.0, "max": 999.0,
		"info": "Gold taken from you if it gets through."},
	{"key": "split_count", "name": "Splits into", "step": 1.0, "min": 0.0, "max": 12.0,
		"info": "How many smaller creeps it breaks into when killed."},
	{"key": "charge_period", "name": "Sprint every", "step": 0.2, "min": 0.2, "max": 30.0,
		"info": "Seconds between sprint bursts."},
	{"key": "charge_time", "name": "Sprint for", "step": 0.1, "min": 0.1, "max": 10.0,
		"info": "How long a sprint burst lasts."},
	{"key": "charge_mult", "name": "Sprint speed", "step": 0.1, "min": 1.0, "max": 6.0,
		"info": "Speed multiplier during a burst."},
]

## What an upgrade track exposes beyond its modifiers.
const TRACK_TUNABLE: Array = [
	{"key": "max", "name": "Ranks", "step": 1.0, "min": 1.0, "max": 8.0,
		"info": "How many ranks this track has. Each rank costs more coins than the last, and more gold to install."},
	{"key": "cost_frac", "name": "Cost share", "step": 0.05, "min": 0.05, "max": 3.0,
		"info": "What a rank costs, as a share of the tower's price — both the coin price in the tech tree and the gold price in a match."},
	{"key": "level", "name": "Unlocks at", "step": 1.0, "min": 1.0, "max": 60.0,
		"info": "Account level this track unlocks at."},
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
		# Flattened so every number reads alike: the track's own fields,
		# "mods.<key>" for the modifier each rank applies, and then one set
		# per rank — cost, gold and modifier — defaulting to what the curve
		# would charge and do.
		var flat: Dictionary = {}
		var track: Dictionary = list[index]
		for key: String in track:
			if typeof(track[key]) == TYPE_INT or typeof(track[key]) == TYPE_FLOAT:
				flat[key] = track[key]
		var mod_keys: Array = []
		for key: String in track.get("mods", {}):
			var value: Variant = (track["mods"] as Dictionary)[key]
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				flat["mods." + key] = value
				mod_keys.append(key)
		# The tuned track decides how many ranks there are to show.
		var tuned: Dictionary = TDData.tracks(body[0])[index]
		for rank in range(1, int(tuned["max"]) + 1):
			flat["cost#%d" % rank] = TDData.track_cost(body[0], index, rank - 1)
			flat["gold#%d" % rank] = TDData.track_gold_cost(body[0], index, rank - 1)
			for key: String in mod_keys:
				flat["mods.%s#%d" % [key, rank]] = float(
						(tuned["mods"] as Dictionary).get(key, track["mods"][key]))
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
				var whole: Dictionary = row.duplicate()
				whole["group"] = "THE WHOLE TRACK"
				out.append(whole)
		# Modifiers vary per track, so their rows are built from the table.
		for key: String in base:
			if not key.begins_with("mods.") or key.contains("#"):
				continue
			var mod_row := _mod_row(key, float(base[key]))
			mod_row["group"] = "THE WHOLE TRACK"
			mod_row["info"] = "%s Every rank does this unless that rank has been given its own number below." % mod_row["info"]
			out.append(mod_row)
		# Then one block per rank: what it costs, and what it does.
		var rank := 1
		while base.has("cost#%d" % rank):
			var group := "RANK %d" % rank
			out.append({"key": "cost#%d" % rank, "name": "Coins", "step": 5.0,
				"min": 1.0, "max": 100000.0, "group": group,
				"info": "Coins to unlock rank %d in the tech tree. Overrides the cost curve for this rank alone." % rank})
			out.append({"key": "gold#%d" % rank, "name": "Gold", "step": 5.0,
				"min": 1.0, "max": 100000.0, "group": group,
				"info": "Gold to install rank %d during a match, once it is unlocked." % rank})
			for key: String in base:
				if not key.begins_with("mods.") or not key.ends_with("#%d" % rank):
					continue
				var per := _mod_row(key.substr(0, key.find("#")), float(base[key]))
				per["key"] = key
				per["group"] = group
				per["info"] = "What rank %d alone does. Set it to give a rank a different step from the rest of the track." % rank
				out.append(per)
			rank += 1
		return out
	var table: Array = ENEMY_TUNABLE if is_enemy(subject) else TUNABLE
	for row: Dictionary in table:
		if base.has(row["key"]):
			out.append(row)
	return out


## A sensible step for a modifier, from what kind of modifier it is: a
## multiplier moves in percents, an addition in small absolute steps.
static func _mod_row(key: String, value: float) -> Dictionary:
	var mod_key := key.substr(5)
	var name := mod_key.replace("_", " ")
	# The game already knows how to say what a modifier does; borrow it.
	var effect := TDData.describe_mods({mod_key: value})
	var info := "What one rank of this track does: %s." % effect if effect != "" \
			else "What one rank of this track changes."
	if mod_key.ends_with("_mult"):
		info += " A multiplier applied once per rank, so 1.22 is +22% a rank and compounds."
	elif mod_key.ends_with("_add"):
		info += " Added once per rank."
	if mod_key.ends_with("_mult"):
		return {"key": key, "name": name, "step": 0.02, "min": 0.1, "max": 4.0,
			"info": info}
	if absf(value) >= 10.0:
		return {"key": key, "name": name, "step": 1.0, "min": -400.0, "max": 400.0,
			"info": info}
	return {"key": key, "name": name, "step": 0.02, "min": -20.0, "max": 20.0,
		"info": info}


## What the subject as a whole is and does, shown under the panel title:
## a tower's blurb, a creep's note, or the full text of an upgrade track.
static func describe(subject: String) -> String:
	if is_enemy(subject):
		var kind := subject.trim_prefix(ENEMY_PREFIX)
		var d: Dictionary = TDData.ENEMIES.get(kind, {})
		var traits: Array = []
		if bool(d.get("flying", false)):
			traits.append("flies over the road")
		if bool(d.get("slow_immune", false)):
			traits.append("ignores slows")
		if bool(d.get("burn_immune", false)):
			traits.append("ignores fire")
		var text := str(d.get("note", ""))
		if not traits.is_empty():
			text += "  (%s)" % ", ".join(traits)
		return text.strip_edges()
	if is_track(subject):
		var body := subject.trim_prefix(TRACK_PREFIX).split("#")
		if body.size() != 2 or not TDData.TOWERS.has(body[0]):
			return ""
		var track: Dictionary = TDData.TOWERS[body[0]]["tracks"][int(body[1])]
		var text := "%d ranks, each %s." % [int(track["max"]),
				TDData.describe_mods(track["mods"])]
		if track.has("requires"):
			var need: Dictionary = track["requires"]
			text += " Needs %s rank %d first." % [need.get("track", ""),
					int(need.get("rank", 1))]
		if int(track.get("level", 0)) > 1:
			text += " Unlocks at account level %d." % int(track["level"])
		if track.has("capstone"):
			text += "  Last rank also: %s — %s" % [track["capstone"]["name"],
					track["capstone"]["desc"]]
		return text
	return str(TDData.TOWERS.get(subject, {}).get("desc", ""))
