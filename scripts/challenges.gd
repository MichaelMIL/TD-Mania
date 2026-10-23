class_name Challenges
extends RefCounted

## Challenges: a map, a set of rules that bend how it is played, a wave to
## reach, and coins for reaching it the first time. Plus one daily challenge,
## built from the date so it is the same all day and different tomorrow.
##
## A challenge run is an ordinary match with `TDData.active_challenge` set.
## The match reads the rules from it (see game.gd `rule`); everything else —
## waves, towers, upgrades, parking a run — works as it always does. Because
## the rules are not the map's, a challenge run pays its normal XP and coins
## but never touches the map's records, clears or stars.
##
## Rules a challenge may set, all optional:
##   towers       only these towers may be built (and are lent if locked)
##   banned       these towers may not be built
##   gold         start with exactly this much gold
##   gold_pct     start with this share of the map's usual gold
##   lives        start with exactly this many lives
##   max_towers   at most this many towers standing at once
##   no_sell      nothing can be sold
##   no_upgrades  no upgrade ranks can be installed
##   hp_mult      enemy health multiplier
##   speed_mult   enemy speed multiplier
##   gold_mult    multiplier on gold from kills and cleared waves

const SCENE := "res://challenges.tscn"

## How hard each challenge is meant to be, easiest first, with the colour
## its card wears. Goals were set against the balance harness's crude
## player in two forms (dev/dev_challenges.tscn -- --depth, with and
## without --tech): a beginner that never upgrades, and a veteran that has
## bought every rank. Easy and Medium goals sit at or just past where the
## beginner gives out. Hard goals sit about where the veteran does. Brutal
## goals are well past the veteran: they need placement the harness does
## not have, which is the point. (Last Stand at ten waves sat one wave under
## the veteran and was still beaten comfortably by hand, so the gap between
## the harness and a real player is wide; Brutal is sized for that.)
const GRADES: Array = [
	{"name": "Easy", "color": Color("81c784")},
	{"name": "Medium", "color": Color("4fc3f7")},
	{"name": "Hard", "color": Color("ffb74d")},
	{"name": "Brutal", "color": Color("ef5350")},
]

## The set, easiest first. The comment on each says where the beginner and
## the veteran gave out, in waves, when its goal was set.
static var LIST: Array = [
	# beginner 15, veteran 24
	{"id": "gun_line", "name": "Gun Line", "grade": 0, "level": "verdant", "waves": 15,
		"reward": 80,
		"blurb": "Nothing but Gunners. Cheap, quick, and there had better be a lot of them.",
		"rules": {"towers": ["gun"]}},
	# beginner 13, veteran 21
	{"id": "cold_front", "name": "Cold Front", "grade": 0, "level": "meadow", "waves": 14,
		"reward": 90,
		"blurb": "Slow them with frost, then shell them while they wade.",
		"rules": {"towers": ["frost", "cannon"]}},
	# beginner 17, veteran 27
	{"id": "hold_the_ford", "name": "Hold the Ford", "grade": 0, "level": "millrace",
		"waves": 16, "reward": 100,
		"blurb": "Only what floats. Tide Callers, Torpedo Batteries and Wave Cannons hold the river.",
		"rules": {"towers": ["tide", "torpedo", "wavegun"], "gold": 400}},
	# beginner 11, veteran 25
	{"id": "shoestring", "name": "Shoestring", "grade": 1, "level": "orchard", "waves": 13,
		"reward": 130,
		"blurb": "Pocket change and room for ten towers. Every one has to count.",
		"rules": {"gold": 150, "max_towers": 10}},
	# beginner 9, veteran 17
	{"id": "glass_base", "name": "Glass Base", "grade": 1, "level": "willow", "waves": 12,
		"reward": 140,
		"blurb": "Three lives. Every creep that gets through is a third of the run.",
		"rules": {"lives": 3}},
	# beginner 12, veteran 15
	{"id": "bare_metal", "name": "Bare Metal", "grade": 2, "level": "ruins", "waves": 16,
		"reward": 200,
		"blurb": "No upgrades and no refunds. What you build is what you get.",
		"rules": {"no_upgrades": true, "no_sell": true}},
	# beginner 20, veteran 27. A ground-only kit, so the waves arrive
	# without flyers at all; see GROUND_SWAP.
	{"id": "siege_line", "name": "Siege Line", "grade": 2, "level": "quarry", "waves": 24,
		"reward": 200,
		"blurb": "Two guns that only shoot along the ground — so nothing flies over them.",
		"rules": {"towers": ["cannon", "mortar"], "gold": 450}},
	# beginner 13, veteran 17
	{"id": "lean_times", "name": "Lean Times", "grade": 2, "level": "fernhollow", "waves": 17,
		"reward": 200,
		"blurb": "Kills and cleared waves pay half, and there are no Gold Mines to make it up.",
		"rules": {"gold_mult": 0.5, "banned": ["mine"]}},
	# beginner 13, veteran 19
	{"id": "iron_tide", "name": "Iron Tide", "grade": 2, "level": "crossroads", "waves": 18,
		"reward": 200,
		"blurb": "Every creep comes in with half again as much health.",
		"rules": {"hp_mult": 1.5}},
	# beginner 12, veteran 21
	{"id": "blitz", "name": "Blitz", "grade": 2, "level": "desert", "waves": 20, "reward": 200,
		"blurb": "They run a third faster. Build where the road doubles back.",
		"rules": {"speed_mult": 1.35}},
	# beginner 13, veteran 21
	{"id": "sparks", "name": "Sparks", "grade": 2, "level": "obelisk", "waves": 20,
		"reward": 220,
		"blurb": "Tesla Coils, Shockwaves and Focus Lasers. Nothing that fires a shell.",
		"rules": {"towers": ["tesla", "shock", "laser"], "gold": 600}},
	# beginner 13, veteran 27
	{"id": "air_power", "name": "Air Power", "grade": 2, "level": "highlands", "waves": 24,
		"reward": 220,
		"blurb": "Airfields, Helipads and Command Posts. Nothing fires from the ground.",
		"rules": {"towers": ["airfield", "helipad", "command"], "gold": 500}},
	# beginner 9, veteran 10
	{"id": "iron_gauntlet", "name": "Iron Gauntlet", "grade": 3, "level": "comb", "waves": 15,
		"reward": 400,
		"blurb": "Tougher and faster at once, with ten lives, on the Iron Comb.",
		"rules": {"hp_mult": 1.4, "speed_mult": 1.15, "lives": 10}},
	# beginner 9, veteran 11 (at ten waves and twelve lives; beaten by hand)
	{"id": "last_stand", "name": "Last Stand", "grade": 3, "level": "convergence",
		"waves": 20, "reward": 450,
		"blurb": "All twenty waves of the hardest board: three roads into one base, eight lives.",
		"rules": {"lives": 8, "gold": 450}},
	# beginner 17, veteran 25
	{"id": "marathon", "name": "Marathon", "grade": 3, "level": "highlands", "waves": 35,
		"reward": 500,
		"blurb": "No tricks. Just the waves, ten past where the map would have let you stop.",
		"rules": {}},
]


## What a flying creep becomes in a challenge whose towers cannot reach the
## air: the nearest thing on the ground by role, a fast harasser for the
## Cinder Moth and an armoured heavy for the Iron Drake. The wave keeps its
## shape and its pressure — it just becomes answerable by the kit the
## challenge handed you, instead of walking over it untouched.
const GROUND_SWAP: Dictionary = {"moth": "runner", "drake": "tank"}


## Whether anything this challenge allows can shoot at a flyer.
static func hits_air(c: Dictionary) -> bool:
	if c.is_empty():
		return true
	for type_id: String in TDData.TOWER_ORDER:
		if allows(c, type_id) and bool(TDData.TOWERS[type_id].get("hits_air", false)):
			return true
	return false


## A challenge whose kit is blind to the air is played without flyers.
static func grounded(c: Dictionary) -> bool:
	return not c.is_empty() and not hits_air(c)


static func grade_of(c: Dictionary) -> Dictionary:
	return GRADES[clampi(int(c.get("grade", 1)), 0, GRADES.size() - 1)]


static func by_id(id: String) -> Dictionary:
	for c: Dictionary in LIST:
		if str(c["id"]) == id:
			return c
	return {}


## The level index a challenge is played on.
static func level_index(c: Dictionary) -> int:
	for i in TDData.LEVELS.size():
		if str(TDData.LEVELS[i]["id"]) == str(c.get("level", "")):
			return i
	return 0


static func level_of(c: Dictionary) -> Dictionary:
	return TDData.LEVELS[level_index(c)]


## Where a challenge run is parked. Separate from the map's own key, so a
## challenge never overwrites a normal run on the same map.
static func run_key(c: Dictionary) -> String:
	if c.has("daily"):
		return "daily:%s" % str(c["daily"])
	return "challenge:%s" % str(c.get("id", ""))


## Whether a tower may be built under these rules (lent if it is locked).
static func allows(c: Dictionary, type_id: String) -> bool:
	var rules: Dictionary = c.get("rules", {})
	if rules.has("towers"):
		return (rules["towers"] as Array).has(type_id)
	if rules.has("banned") and (rules["banned"] as Array).has(type_id):
		return false
	return true


## The rules in words, one line each, goal first.
static func rule_lines(c: Dictionary) -> Array:
	var rules: Dictionary = c.get("rules", {})
	var out: Array = ["Reach wave %d" % int(c.get("waves", 15))]
	if rules.has("towers"):
		var names: Array = []
		for t: String in rules["towers"]:
			names.append(str(TDData.TOWERS[t].get("short", TDData.TOWERS[t]["name"])))
		out.append("Only " + _join_and(names))
	if rules.has("banned"):
		var names: Array = []
		for t: String in rules["banned"]:
			names.append(str(TDData.TOWERS[t]["name"]))
		out.append("No " + _join_and(names))
	if grounded(c):
		out.append("Nothing flies — none of these towers could reach it")
	if rules.has("gold"):
		out.append("Start with $%d" % int(rules["gold"]))
	if rules.has("gold_pct"):
		out.append("Start with %d%% of the usual gold" % int(round(float(rules["gold_pct"]) * 100.0)))
	if rules.has("lives"):
		var n := int(rules["lives"])
		out.append("1 life" if n == 1 else "%d lives" % n)
	if rules.has("max_towers"):
		out.append("At most %d towers" % int(rules["max_towers"]))
	if bool(rules.get("no_upgrades", false)):
		out.append("No upgrades")
	if bool(rules.get("no_sell", false)):
		out.append("No selling")
	if rules.has("hp_mult"):
		out.append("Enemies have +%d%% health" % int(round((float(rules["hp_mult"]) - 1.0) * 100.0)))
	if rules.has("speed_mult"):
		out.append("Enemies move %d%% faster" % int(round((float(rules["speed_mult"]) - 1.0) * 100.0)))
	if rules.has("gold_mult"):
		var g := float(rules["gold_mult"])
		out.append("Kills and waves pay half" if is_equal_approx(g, 0.5)
				else "Kills and waves pay %d%%" % int(round(g * 100.0)))
	return out


static func _join_and(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])


# ------------------------------------------------------------------ daily

## The twists a daily can carry: one per day, on top of its tower kit.
const TWISTS: Array = [
	{"name": "Lean purse", "rules": {"gold_pct": 0.7}},
	{"name": "Thin line", "rules": {"lives": 10}},
	{"name": "Hardened", "rules": {"hp_mult": 1.25}},
	{"name": "Quickstep", "rules": {"speed_mult": 1.2}},
	{"name": "No refunds", "rules": {"no_sell": true}},
	{"name": "Bare metal", "rules": {"no_upgrades": true}},
	{"name": "Short supply", "rules": {"max_towers": 18}},
	{"name": "Bounty drought", "rules": {"gold_mult": 0.75}},
]

## How far a daily asks you to go, by the map's difficulty tier.
const DAILY_WAVES: Array = [14, 13, 12, 10]
const DAILY_REWARD: Array = [70, 90, 110, 140]
## Extra coins per day of an unbroken streak, up to a cap.
const STREAK_STEP := 10
const STREAK_CAP := 50
## Towers a daily never hands out: a mine earns but cannot defend, a
## Command Post buffs but cannot shoot, so a kit of four with either is a
## kit of three.
const DAILY_EXCLUDED: Array = ["mine", "command"]
## Water a map needs before a daily will put a water tower in its kit.
const DAILY_WATER_CELLS := 20
## Every kit opens with one of these: cheap enough to build twice from any
## starting purse, quick, and able to hit flyers. Without one a kit could be
## four towers the opening gold cannot buy, or open on a Tar Pit that hurts
## nothing. (The Cannon was tried as a second opener; slow and blind to the
## air, it lost most dailies by wave five in the harness.)
const DAILY_OPENERS: Array = ["gun"]


## Today's date as the daily's key, in the player's own time zone so the
## challenge turns over at their midnight.
static func today() -> String:
	return date_key(Time.get_date_dict_from_system())


static func date_key(d: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## The day before a key, for keeping a streak.
static func previous_day(key: String) -> String:
	var parts := key.split("-")
	if parts.size() != 3:
		return ""
	var noon := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]),
		"month": int(parts[1]), "day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	return date_key(Time.get_date_dict_from_unix_time(int(noon) - 86400))


## "Thursday 22 October".
static func pretty_date(key: String) -> String:
	var parts := key.split("-")
	if parts.size() != 3:
		return key
	const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	const MONTHS := ["January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"]
	var noon := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]),
		"month": int(parts[1]), "day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	var d := Time.get_datetime_dict_from_unix_time(int(noon))
	return "%s %d %s" % [DAYS[int(d["weekday"])], int(parts[2]), MONTHS[int(parts[1]) - 1]]


static func streak_bonus(streak: int) -> int:
	return mini(STREAK_CAP, maxi(0, streak - 1) * STREAK_STEP)


## A number from a string that is the same on every machine and every
## build (FNV-1a), so a date always deals the same daily.
static func stable_hash(text: String) -> int:
	var h := 2166136261
	for b: int in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xffffffff
	return h


## The daily challenge for a date key. Everything comes from one generator
## seeded by the date: the map, a kit of four towers (a cheap opener, at
## least one that hits flyers, a water tower only where there is water for
## it), one twist, and the seed the run itself plays on.
static func daily_for(key: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stable_hash("td-mania-daily/" + key)
	var level: Dictionary = TDData.LEVELS[rng.randi_range(0, TDData.LEVELS.size() - 1)]
	var tier := clampi(int(level.get("tier", 0)), 0, DAILY_WAVES.size() - 1)

	var water := 0
	for patch: Array in level.get("water", []):
		water += int(patch[2]) * int(patch[3])
	var ground: Array = []
	var wet: Array = []
	for t: String in TDData.TOWER_ORDER:
		if DAILY_EXCLUDED.has(t):
			continue
		if int(TDData.TOWERS[t]["terrain"]) == TDData.Terrain.WATER:
			wet.append(t)
		else:
			ground.append(t)
	var kit: Array = [DAILY_OPENERS[rng.randi_range(0, DAILY_OPENERS.size() - 1)]]
	if water >= DAILY_WATER_CELLS and rng.randf() < 0.5:
		kit.append(wet[rng.randi_range(0, wet.size() - 1)])
	while kit.size() < 4:
		var pick: String = ground[rng.randi_range(0, ground.size() - 1)]
		if not kit.has(pick):
			kit.append(pick)
	# Flyers arrive from wave 5; a kit that cannot touch them is a loss.
	var anti_air := false
	for t: String in kit:
		if bool(TDData.TOWERS[t].get("hits_air", false)):
			anti_air = true
	if not anti_air:
		var shooters: Array = []
		for t: String in ground:
			if bool(TDData.TOWERS[t].get("hits_air", false)) and not kit.has(t):
				shooters.append(t)
		kit[kit.size() - 1] = shooters[rng.randi_range(0, shooters.size() - 1)]
	# Cheapest first, so the card reads the way a run starts.
	kit.sort_custom(func(a, b): return int(TDData.TOWERS[a]["cost"]) < int(TDData.TOWERS[b]["cost"]))

	var twist: Dictionary = TWISTS[rng.randi_range(0, TWISTS.size() - 1)]
	var rules: Dictionary = (twist["rules"] as Dictionary).duplicate()
	rules["towers"] = kit
	# A tower limit is shared between every road: allow more where there
	# are more roads to cover.
	if rules.has("max_towers"):
		rules["max_towers"] = int(rules["max_towers"]) + 6 * (TDData.routes_of(level).size() - 1)
	return {
		"id": "daily",
		"daily": key,
		"name": "Daily Challenge",
		"twist": str(twist["name"]),
		"level": str(level["id"]),
		"waves": int(DAILY_WAVES[tier]),
		"reward": int(DAILY_REWARD[tier]),
		"blurb": "%s, with a %s twist. The same for everyone today." % [pretty_date(key),
				str(twist["name"]).to_lower()],
		"rules": rules,
		"seed": stable_hash("td-mania-run/" + key) & 0x7fffffff,
	}


static func daily() -> Dictionary:
	return daily_for(today())


## Seconds until the daily turns over at the player's midnight.
static func seconds_to_next_daily() -> int:
	var now := Time.get_datetime_dict_from_system()
	return maxi(0, 86400 - (int(now["hour"]) * 3600 + int(now["minute"]) * 60
			+ int(now["second"])))


# --------------------------------------------------------------- starting

## Sets up the match for a challenge and goes to it. `resume` continues its
## parked run; otherwise any parked run of this challenge is dropped.
static func play(tree: SceneTree, c: Dictionary, resume: bool = false) -> void:
	TDData.active_challenge = c.duplicate(true)
	TDData.selected_level = level_index(c)
	TDData.resume_run = resume
	if not resume:
		Progress.clear_run(run_key(c))
	tree.change_scene_to_file("res://game.tscn")
