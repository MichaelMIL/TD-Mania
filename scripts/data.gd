class_name TDData
extends RefCounted

## Static configuration for TD Mania: grid metrics, the enemy path,
## and the tower / enemy stat tables.

const CELL := 64
const COLS := 20
const ROWS := 11
const HUD_H := 64
const BAR_H := 134
const PALETTE_W := 240
const MAP_W := COLS * CELL
const MAP_H := ROWS * CELL

enum Terrain { GROUND, PATH, WATER, ROCK }

## Per-tower targeting priorities.
enum Target { FIRST, LAST, WEAKEST, STRONGEST, HURT, HEALTHY }

static var TARGET_NAMES: Array = ["First", "Last", "Weakest", "Strongest", "Lowest HP",
		"Highest HP"]
static var TARGET_HINTS: Array = [
	"the creep closest to your base",
	"the creep that just entered",
	"the lowest maximum health in range",
	"the toughest creep in range",
	"the most wounded creep in range",
	"the creep with the most health left",
]

## Which level the menu handed to the game scene. Static so it survives the
## scene change without an autoload.
static var selected_level: int = 0

## Tuned definitions, rebuilt whenever the overrides or the level change.
## Towers read their numbers every frame, so these are cached rather than
## merged on each lookup.
static var _tuned_defs: Dictionary = {}
static var _tuned_enemies: Dictionary = {}
static var _tuned_tracks: Dictionary = {}
static var _tuned_stamp: String = ""


## Drops every tuned cache when the overrides or the level move under them.
static func _tuning_ready() -> void:
	var stamp := "%d/%d" % [Tuning.version, selected_level]
	if stamp == _tuned_stamp:
		return
	_tuned_stamp = stamp
	_tuned_defs = {}
	_tuned_enemies = {}
	_tuned_tracks = {}
## Set by the menu when the player picks Continue rather than a fresh run.
static var resume_run: bool = false

## Difficulty tiers. A level names a tier and inherits its economy and enemy
## scaling; a level may override any of those keys individually.
static var TIERS: Array = [
	{"name": "Easy", "color": Color("81c784"),
		"hp_scale": 0.85, "speed_scale": 0.96, "gold": 250, "lives": 25},
	{"name": "Normal", "color": Color("64b5f6"),
		"hp_scale": 1.0, "speed_scale": 1.0, "gold": 220, "lives": 20},
	{"name": "Hard", "color": Color("ffb74d"),
		"hp_scale": 1.2, "speed_scale": 1.04, "gold": 210, "lives": 18},
	{"name": "Brutal", "color": Color("e57373"),
		"hp_scale": 1.4, "speed_scale": 1.08, "gold": 200, "lives": 16},
]


## Every route through a level, each a list of waypoints from an off-grid
## source to an off-grid base. Most maps have one; some have several.
static func routes_of(level: Dictionary) -> Array:
	if level.has("routes"):
		return level["routes"]
	return [level["waypoints"]]


## Map groups. Every level belongs to one area, and the menu lists them area
## by area so the campaign reads as a journey rather than a flat list.
static var AREAS: Array = [
	{"id": "greenlands", "name": "The Greenlands", "color": Color("81c784"),
		"blurb": "Rolling forest, grassland and moor. Where every commander starts."},
	{"id": "riverlands", "name": "The Riverlands", "color": Color("4fc3f7"),
		"blurb": "Lakes, autumn woods and the twin gates that guard the crossings."},
	{"id": "wastes", "name": "The Wastes", "color": Color("ffb74d"),
		"blurb": "Dune country, cooling lava fields and the ruins buried between them."},
	{"id": "frozen", "name": "The Frozen Coast", "color": Color("80deea"),
		"blurb": "Sea ice, cliff roads and a junction where two lanes cross."},
	{"id": "delta", "name": "The Iron Delta", "color": Color("e57373"),
		"blurb": "Mangrove swamp and foundry country. The hardest ground in the game."},
]


## ------------------------------------------------------------ wave tables
##
## A wave is built by walking these rules in order. A rule contributes a
## group of one creep kind:
##
##   from         first wave it can appear on
##   every/offset only on waves where n % every == offset (1 = every wave)
##   count        group size, plus n / count_every, plus n * count_mult
##   gap          seconds between its creeps, moving by gap_ramp a wave and
##                never below gap_min
##   lead         pause before the group starts
##
## Order matters: groups are laid down one after another, so the list reads
## top to bottom as the shape of the wave.
static var WAVE_RULES: Array = [
	{"kind": "grunt", "from": 1, "count": 4, "count_mult": 1.2,
		"gap": 1.0, "gap_ramp": -0.03, "gap_min": 0.4, "lead": 0.0},
	{"kind": "runner", "from": 4, "count": 2, "count_mult": 0.5,
		"gap": 0.5, "lead": 1.4},
	{"kind": "swarm", "from": 6, "every": 2, "offset": 0, "count": 6,
		"count_every": 2, "gap": 0.25, "lead": 1.2},
	{"kind": "bolt", "from": 6, "count": 1, "count_every": 6,
		"gap": 0.55, "lead": 1.0},
	{"kind": "brood", "from": 7, "every": 3, "offset": 1, "count": 1,
		"count_every": 8, "gap": 1.1, "lead": 1.2},
	{"kind": "ashwalker", "from": 8, "every": 3, "offset": 2, "count": 1,
		"count_every": 7, "gap": 0.7, "lead": 1.0},
	{"kind": "mender", "from": 9, "every": 2, "offset": 1, "count": 1,
		"count_every": 8, "gap": 1.6, "lead": 1.4},
	{"kind": "thief", "from": 10, "every": 4, "offset": 0, "count": 1,
		"count_every": 9, "gap": 0.5, "lead": 1.0},
	{"kind": "moth", "from": 5, "every": 3, "offset": 2, "count": 3,
		"count_every": 6, "gap": 0.45, "lead": 1.2},
	{"kind": "warden", "from": 12, "count": 1, "count_every": 14,
		"gap": 2.0, "lead": 1.6},
	{"kind": "drake", "from": 14, "every": 2, "offset": 0, "count": 1,
		"count_every": 12, "gap": 1.9, "lead": 1.5},
	{"kind": "tank", "from": 6, "count": 1, "count_every": 5,
		"gap": 1.8, "lead": 1.5},
]

## Occasional wave-wide modifiers. Cheap variety on top of the rules: the
## same creeps, but one thing about all of them is different, announced in
## the readout so it can be answered rather than discovered.
static var WAVE_AFFIXES: Array = [
	{"id": "armoured", "name": "Armoured", "armor_add": 6.0, "hp_mult": 1.0,
		"speed_mult": 1.0, "shield": 0,
		"note": "Everything is plated. Armour-piercing damage, or nothing."},
	{"id": "swift", "name": "Swift", "armor_add": 0.0, "hp_mult": 0.8,
		"speed_mult": 1.3, "shield": 0,
		"note": "Fast and frail. Slows buy the time your damage needs."},
	{"id": "shielded", "name": "Shielded", "armor_add": 0.0, "hp_mult": 1.0,
		"speed_mult": 1.0, "shield": 1,
		"note": "The first hit on each one is absorbed. Volleys strip shields; big single shots waste on them."},
	{"id": "hardy", "name": "Hardy", "armor_add": 2.0, "hp_mult": 1.35,
		"speed_mult": 0.9, "shield": 0,
		"note": "Slower, but there is a lot more of each one to chew through."},
]

## Which modifier a wave carries, if any. From wave 7, every third wave,
## cycling — often enough to plan around, rare enough to notice. Boss waves
## are left alone.
static func affix_for(n: int) -> Dictionary:
	if n % 10 == 0 or n < 7 or n % 3 != 1:
		return {}
	return WAVE_AFFIXES[(n / 3) % WAVE_AFFIXES.size()]


## Every tenth wave replaces the rules with an escorted heavy.
static var BOSS_WAVE: Dictionary = {
	"escort": {"kind": "grunt", "count": 6, "count_every": 2, "gap": 0.55},
	"pause": 1.5,
	"kind": "boss",
	## From wave 20 every other boss wave sends the bigger one instead.
	"alt_kind": "titan", "alt_from": 20, "alt_cycle": 2,
	"hp_step": 0.12, "after": 2.0,
	"trail": {"kind": "runner", "count": 4, "count_every": 5, "gap": 0.4},
}

## Per-area flavour, layered on WAVE_RULES: `tweak` edits a kind's rule,
## `add` appends a group, `drop` removes a kind entirely. This is what makes
## the Wastes feel unlike the Greenlands without touching the base curve.
static var AREA_WAVES: Dictionary = {
	"greenlands": {},
	"riverlands": {
		# River country runs fast and light: more sprinters, fewer swarms.
		"tweak": {
			"bolt": {"from": 4, "count": 2, "count_every": 5},
			"swarm": {"count": 4},
			"runner": {"count_mult": 0.7},
		},
	},
	"wastes": {
		# Ash country: burning does nothing to what already lives in fire.
		"tweak": {
			"ashwalker": {"from": 4, "every": 2, "offset": 0, "count": 2,
				"count_every": 5},
			"tank": {"count_every": 4},
			"swarm": {"from": 8},
		},
		# A second ash pack rolls in behind the first on the deep waves.
		"add": [
			{"kind": "ashwalker", "from": 12, "every": 4, "offset": 0, "count": 2,
				"count_every": 8, "gap": 0.6, "lead": 1.2},
		],
	},
	"frozen": {
		# Armour and healers: the coast punishes a defence that cannot focus.
		"tweak": {
			"warden": {"from": 9, "count_every": 10},
			"mender": {"from": 7, "every": 2, "offset": 1, "count_every": 6},
			"grunt": {"count_mult": 1.0},
		},
	},
	"delta": {
		# Everything, sooner, and thieves working the foundry gates.
		"tweak": {
			"thief": {"from": 6, "every": 2, "offset": 0, "count_every": 7},
			"brood": {"from": 6, "every": 2, "offset": 1},
			"warden": {"from": 10, "count_every": 11},
			"grunt": {"count_mult": 1.35},
		},
		# The foundry gates send a second armoured column late on.
		"add": [
			{"kind": "warden", "from": 16, "every": 3, "offset": 0, "count": 1,
				"count_every": 16, "gap": 2.2, "lead": 1.8},
		],
	},
}


## The rule list a level plays by: the base table with its area's flavour
## layered on top.
static func wave_rules(area_id: String) -> Array:
	var flavour: Dictionary = AREA_WAVES.get(area_id, {})
	if flavour.is_empty():
		return WAVE_RULES
	var drop: Array = flavour.get("drop", [])
	var tweak: Dictionary = flavour.get("tweak", {})
	var out: Array = []
	for rule: Dictionary in WAVE_RULES:
		var kind := str(rule["kind"])
		if drop.has(kind):
			continue
		if tweak.has(kind):
			var merged: Dictionary = rule.duplicate(true)
			merged.merge(tweak[kind], true)
			out.append(merged)
		else:
			out.append(rule)
	for extra: Dictionary in flavour.get("add", []):
		out.append(extra)
	return out


## Size of one group on wave `n`.
static func wave_group_count(rule: Dictionary, n: int) -> int:
	var count := int(rule.get("count", 1))
	if int(rule.get("count_every", 0)) > 0:
		count += n / int(rule["count_every"])
	if float(rule.get("count_mult", 0.0)) > 0.0:
		count += int(float(n) * float(rule["count_mult"]))
	return maxi(0, count)


## Whether a rule contributes anything to wave `n`.
static func wave_rule_active(rule: Dictionary, n: int) -> bool:
	if n < int(rule.get("from", 1)):
		return false
	var every := int(rule.get("every", 1))
	return every <= 1 or n % every == int(rule.get("offset", 0))


## ---------------------------------------------------------------- hazards
##
## A map-wide rule that bends one thing about how towers work. Most maps
## have none; the ones that do say so on the card and in the info panel,
## because a hazard you find out about by losing is an ambush.
static var HAZARDS: Dictionary = {
	"fog": {
		"name": "Fog", "range_mult": 0.88, "burn_mult": 1.0,
		"water_damage_mult": 1.0, "ground_damage_mult": 1.0, "air_drift": 0.0,
		"note": "Standing fog: every tower sees 12% less far.",
	},
	"ash": {
		"name": "Ashfall", "range_mult": 1.0, "burn_mult": 0.5,
		"water_damage_mult": 1.0, "ground_damage_mult": 1.0, "air_drift": 0.0,
		"note": "Ash smothers flame: burning damage is halved here.",
	},
	"gale": {
		"name": "Gale", "range_mult": 1.0, "burn_mult": 1.0,
		"water_damage_mult": 1.0, "ground_damage_mult": 1.0, "air_drift": 34.0,
		"note": "A crosswind pushes aircraft off their runs.",
	},
	"brine": {
		"name": "Brine", "range_mult": 1.0, "burn_mult": 1.0,
		"water_damage_mult": 1.15, "ground_damage_mult": 0.94, "air_drift": 0.0,
		"note": "Salt air: water towers hit 15% harder, everything else 6% softer.",
	},
}


## The hazard a map runs under, or an empty dictionary for most of them.
static func hazard_of(level: Dictionary) -> Dictionary:
	return HAZARDS.get(str(level.get("hazard", "")), {})


## ------------------------------------------------------------- objectives
##
## Three per map, worth a star each. Two come from the tier — get deep, and
## get deep without being touched — and the third is the map's own `goal`.
## They are what turns "go as deep as you can" into a reason to come back.
## The wave that finishes a map. Reaching it is a win — the run can carry on
## into endless afterwards, but the map counts as cleared and stays cleared.
static var TIER_CLEAR_WAVE: Array = [25, 24, 22, 20]

static var TIER_GOAL_WAVE: Array = [15, 14, 12, 10]
static var TIER_CLEAN_WAVE: Array = [8, 8, 7, 6]


## How many waves this map takes to clear.
static func clear_wave(level: Dictionary) -> int:
	var tier := clampi(int(level.get("tier", 0)), 0, TIER_CLEAR_WAVE.size() - 1)
	return int(level.get("clear_wave", TIER_CLEAR_WAVE[tier]))


static func objectives_for(level: Dictionary) -> Array:
	var tier := int(level.get("tier", 0))
	var deep := int(TIER_GOAL_WAVE[clampi(tier, 0, TIER_GOAL_WAVE.size() - 1)])
	var clean := int(TIER_CLEAN_WAVE[clampi(tier, 0, TIER_CLEAN_WAVE.size() - 1)])
	var out: Array = [
		{"kind": "waves", "n": deep, "text": "Clear wave %d" % deep,
			"short": "Wave %d" % deep},
		{"kind": "clean", "n": clean,
			"text": "Reach wave %d without losing a life" % clean,
			"short": "Wave %d unhurt" % clean},
	]
	var goal: Dictionary = level.get("goal", {})
	if not goal.is_empty():
		out.append(_goal_text(goal))
	return out


## Turns a map's goal entry into a labelled objective.
static func _goal_text(goal: Dictionary) -> Dictionary:
	var out: Dictionary = goal.duplicate(true)
	var n := int(goal.get("n", 10))
	match str(goal.get("kind", "")):
		"no_water":
			out["text"] = "Clear wave %d with no water towers" % n
			out["short"] = "Wave %d, no water" % n
		"few_towers":
			out["text"] = "Clear wave %d with %d towers or fewer" \
					% [n, int(goal.get("towers", 10))]
			out["short"] = "Wave %d, %d towers" % [n, int(goal.get("towers", 10))]
		"kills":
			out["text"] = "Destroy %d enemies in one run" % n
			out["short"] = "%d kills" % n
		"no_sell":
			out["text"] = "Clear wave %d without selling a tower" % n
			out["short"] = "Wave %d, no selling" % n
		"rich":
			out["text"] = "Hold $%d at once" % n
			out["short"] = "$%d at once" % n
		_:
			out["text"] = "Clear wave %d" % n
			out["short"] = "Wave %d" % n
	return out


static func area_of(level: Dictionary) -> Dictionary:
	for a: Dictionary in AREAS:
		if str(a["id"]) == str(level.get("area", "")):
			return a
	return AREAS[0]


## Account level a map opens at.
static func level_unlock(level: Dictionary) -> int:
	return int(level.get("unlock_level", 1))


static func levels_in_area(area_id: String) -> Array:
	var out: Array = []
	for i in LEVELS.size():
		if str(LEVELS[i].get("area", "")) == area_id:
			out.append(i)
	return out


## Colour used for a route's portal, preview line and lane markers.
static var ROUTE_COLORS: Array = [Color("9575cd"), Color("4fc3f7"), Color("ffb74d"),
		Color("81c784")]


static func route_color(index: int) -> Color:
	return ROUTE_COLORS[index % ROUTE_COLORS.size()]


static func tier_of(level: Dictionary) -> Dictionary:
	return TIERS[clampi(int(level["tier"]), 0, TIERS.size() - 1)]


## A level's setting, falling back to its difficulty tier.
## Extra gold and lives a map gets for each lane past the first. Defending
## two or three entrances means building two or three positions, and the
## balance report showed multi-lane maps landing about half as deep as
## single-lane maps of the same tier without this.
const LANE_GOLD_BONUS := 0.45
const LANE_LIVES_BONUS := 0.3


static func level_stat(level: Dictionary, key: String) -> float:
	if level.has(key):
		return float(level[key])
	var value := float(tier_of(level)[key])
	var extra_lanes := maxi(0, routes_of(level).size() - 1)
	if extra_lanes > 0 and (key == "gold" or key == "lives"):
		var per_lane := LANE_GOLD_BONUS if key == "gold" else LANE_LIVES_BONUS
		value = round(value * (1.0 + per_lane * float(extra_lanes)))
	return value


static func level() -> Dictionary:
	return LEVELS[clampi(selected_level, 0, LEVELS.size() - 1)]


## Terrain patches are [x, y, width, height] rects in grid cells. They are
## applied water -> rock -> ground (islands), and the path always wins.
static var LEVELS: Array = [
	{
		"id": "verdant",
		"goal": {"kind": "no_water", "n": 10},
		"unlock_level": 1,
		"area": "greenlands",
		"name": "Verdant Pass",
		"theme": "Forest",
		"decor": "trees",
		"path_style": "dirt", "ground_style": "checker", "water_style": "calm",
		"tint": Color(0.45, 0.75, 0.40, 0.045),
		"tier": 0,
		"blurb": "Five switchbacks of forest trail — the longest, friendliest road in the valley.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(4, 1), Vector2i(4, 5), Vector2i(1, 5), Vector2i(1, 9),
				Vector2i(6, 9), Vector2i(6, 4), Vector2i(10, 4), Vector2i(10, 9), Vector2i(14, 9),
				Vector2i(14, 2), Vector2i(17, 2), Vector2i(17, 6), Vector2i(13, 6), Vector2i(13, 10),
				Vector2i(20, 10),
			],
		],
		"water": [[7, 6, 2, 2], [15, 4, 2, 1]],
		"rock": [[12, 0, 2, 1]],
		"ground": [],
		"palette": {
			"ground_a": Color("22331f"), "ground_b": Color("1e2d1c"),
			"path_edge": Color("2b2117"), "path_fill": Color("5a4632"),
			"water_a": Color("123a4a"), "water_b": Color("17506a"),
			"rock": Color("3a3f45"),
		},
	},
	{
		"id": "meadow",
		"goal": {"kind": "few_towers", "n": 8, "towers": 10},
		"unlock_level": 2,
		"area": "greenlands",
		"name": "Meadow Loop",
		"theme": "Savanna",
		"decor": "grass",
		"path_style": "gravel", "ground_style": "dots", "water_style": "calm",
		"tint": Color(1.00, 0.85, 0.45, 0.055),
		"tier": 0,
		"blurb": "A spiral that winds all the way in and back out again. Firing angles everywhere.",
		"routes": [
			[
				Vector2i(-1, 0), Vector2i(18, 0), Vector2i(18, 9), Vector2i(2, 9), Vector2i(2, 3),
				Vector2i(14, 3), Vector2i(14, 6), Vector2i(6, 6), Vector2i(6, 10), Vector2i(20, 10),
			],
		],
		"water": [[9, 1, 3, 1], [16, 4, 2, 2]],
		"rock": [[4, 5, 1, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("4a4526"), "ground_b": Color("423d20"),
			"path_edge": Color("3a2a15"), "path_fill": Color("8a6a3c"),
			"water_a": Color("1a4a55"), "water_b": Color("23617a"),
			"rock": Color("4f4838"),
		},
	},
	{
		"id": "highlands",
		"goal": {"kind": "kills", "n": 250},
		"unlock_level": 3,
		"area": "greenlands",
		"name": "Windward Highlands",
		"theme": "Highlands",
		"decor": "heather",
		"path_style": "stone", "ground_style": "stripes", "water_style": "calm",
		"tint": Color(0.55, 0.85, 0.75, 0.050),
		"tier": 0,
		"blurb": "A figure-eight over the moor: the road crosses its own tail twice.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(5, 2), Vector2i(5, 8), Vector2i(10, 8), Vector2i(10, 1),
				Vector2i(15, 1), Vector2i(15, 6), Vector2i(8, 6), Vector2i(8, 10), Vector2i(3, 10),
				Vector2i(3, 5), Vector2i(18, 5), Vector2i(18, 9), Vector2i(20, 9),
			],
		],
		"water": [[12, 2, 2, 2], [0, 7, 2, 2]],
		"rock": [[6, 0, 2, 1], [16, 7, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("33402f"), "ground_b": Color("2c3829"),
			"path_edge": Color("2a2a22"), "path_fill": Color("6f6a55"),
			"water_a": Color("154a54"), "water_b": Color("1d6472"),
			"rock": Color("4a5048"),
		},
	},
	{
		"id": "riverfork",
		"goal": {"kind": "no_sell", "n": 12},
		"unlock_level": 4,
		"area": "riverlands",
		"name": "Riverfork",
		"theme": "River Valley",
		"decor": "reeds",
		"path_style": "mud", "ground_style": "checker", "water_style": "surf",
		"tint": Color(0.40, 0.70, 0.95, 0.050),
		"tier": 1,
		"blurb": "The road loops right around the lake, then doubles back along the shore.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(5, 1), Vector2i(5, 6), Vector2i(12, 6), Vector2i(12, 2),
				Vector2i(16, 2), Vector2i(16, 9), Vector2i(8, 9), Vector2i(8, 7), Vector2i(20, 7),
			],
		],
		"water": [[6, 2, 5, 3], [0, 8, 3, 2], [17, 0, 3, 2]],
		"rock": [[13, 4, 2, 1]],
		"ground": [],
		"palette": {
			"ground_a": Color("1d3a33"), "ground_b": Color("18322c"),
			"path_edge": Color("24211a"), "path_fill": Color("6b5a3a"),
			"water_a": Color("0e4a63"), "water_b": Color("166a86"),
			"rock": Color("384852"),
		},
	},
	{
		"id": "crossroads",
		"goal": {"kind": "rich", "n": 900},
		"unlock_level": 5,
		"area": "riverlands",
		"name": "Crossroads",
		"theme": "Autumn Wood",
		"decor": "leaves",
		"path_style": "brick", "ground_style": "flat", "water_style": "calm",
		"tint": Color(1.00, 0.55, 0.25, 0.055),
		"tier": 1,
		"blurb": "Two diagonal roads crossing in the middle of the wood, twice over.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(3, 1), Vector2i(9, 7), Vector2i(13, 7), Vector2i(13, 2),
				Vector2i(8, 2), Vector2i(2, 8), Vector2i(6, 8), Vector2i(11, 8), Vector2i(16, 3),
				Vector2i(16, 7), Vector2i(20, 7),
			],
		],
		"water": [[15, 9, 3, 2]],
		"rock": [[17, 0, 3, 2], [4, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3b2c1e"), "ground_b": Color("33261a"),
			"path_edge": Color("2a1d12"), "path_fill": Color("7a5230"),
			"water_a": Color("15414f"), "water_b": Color("1c5a6b"),
			"rock": Color("47403a"),
		},
	},
	{
		"id": "desert",
		"goal": {"kind": "kills", "n": 400},
		"unlock_level": 7,
		"area": "wastes",
		"name": "Desert Wash",
		"theme": "Desert",
		"decor": "cactus",
		"path_style": "sand", "ground_style": "dunes", "water_style": "calm",
		"tint": Color(1.00, 0.80, 0.40, 0.065),
		"tier": 1,
		"blurb": "Dune chevrons zigzag across the wash before the long run home.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(2, 2), Vector2i(7, 7), Vector2i(12, 2), Vector2i(16, 6),
				Vector2i(16, 9), Vector2i(7, 9), Vector2i(7, 6), Vector2i(11, 6), Vector2i(11, 3),
				Vector2i(14, 3), Vector2i(14, 0), Vector2i(20, 0),
			],
		],
		"water": [[4, 9, 3, 2], [18, 4, 2, 2]],
		"rock": [],
		"ground": [],
		"palette": {
			"ground_a": Color("5a4b2c"), "ground_b": Color("4f4226"),
			"path_edge": Color("3d2f18"), "path_fill": Color("9c8049"),
			"water_a": Color("1d5560"), "water_b": Color("276e7a"),
			"rock": Color("6b5c40"),
		},
	},
	{
		"id": "ashen",
		"hazard": "ash",
		"goal": {"kind": "few_towers", "n": 10, "towers": 14},
		"unlock_level": 9,
		"area": "wastes",
		"name": "Ashen Wastes",
		"theme": "Volcanic",
		"decor": "cracks",
		"path_style": "ember", "ground_style": "flat", "water_style": "murk",
		"tint": Color(1.00, 0.35, 0.20, 0.070),
		"tier": 2,
		"blurb": "A diagonal descent down lava terraces, hemmed in by boulder fields.",
		"routes": [
			[
				Vector2i(-1, 0), Vector2i(2, 0), Vector2i(6, 4), Vector2i(10, 4), Vector2i(10, 7),
				Vector2i(14, 7), Vector2i(14, 3), Vector2i(18, 3), Vector2i(18, 9), Vector2i(13, 9),
				Vector2i(13, 10), Vector2i(20, 10),
			],
		],
		"water": [[4, 6, 2, 2], [16, 0, 3, 2]],
		"rock": [[0, 3, 2, 3], [7, 0, 3, 3], [11, 0, 2, 3], [7, 6, 2, 2], [15, 5, 2, 2], [3, 8, 3, 1], [4, 2, 2, 2], [11, 8, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("332d28"), "ground_b": Color("2b2622"),
			"path_edge": Color("1c1512"), "path_fill": Color("6b3a26"),
			"water_a": Color("14403f"), "water_b": Color("1a5350"),
			"rock": Color("3b332d"),
		},
	},
	{
		"id": "frostbite",
		"goal": {"kind": "no_water", "n": 8},
		"unlock_level": 8,
		"area": "frozen",
		"name": "Frostbite Bay",
		"theme": "Arctic",
		"decor": "snow",
		"path_style": "ice", "ground_style": "tiles", "water_style": "floes",
		"tint": Color(0.70, 0.85, 1.00, 0.070),
		"tier": 2,
		"blurb": "The road weaves between frozen inlets with almost no dry ground beside it.",
		"routes": [
			[
				Vector2i(-1, 5), Vector2i(4, 5), Vector2i(4, 9), Vector2i(9, 9), Vector2i(9, 4),
				Vector2i(14, 4), Vector2i(14, 8), Vector2i(18, 8), Vector2i(18, 4), Vector2i(20, 4),
			],
		],
		"water": [[0, 0, 20, 3], [6, 6, 2, 3], [15, 0, 5, 3]],
		"rock": [[2, 7, 2, 2], [11, 6, 2, 3], [16, 5, 2, 2], [5, 3, 2, 2], [12, 3, 2, 1]],
		"ground": [],
		"palette": {
			"ground_a": Color("3a4652"), "ground_b": Color("313c47"),
			"path_edge": Color("2f3238"), "path_fill": Color("707784"),
			"water_a": Color("16394f"), "water_b": Color("1f5570"),
			"rock": Color("4a545e"),
		},
	},
	{
		"id": "ruins",
		"goal": {"kind": "no_water", "n": 10},
		"unlock_level": 12,
		"area": "wastes",
		"name": "Old Ruins",
		"theme": "Ruins",
		"decor": "columns",
		"path_style": "slabs", "ground_style": "tiles", "water_style": "calm",
		"tint": Color(0.75, 0.70, 0.95, 0.050),
		"tier": 2,
		"blurb": "A labyrinth of collapsed walls — short, tight, and hard to cover.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(6, 2), Vector2i(6, 6), Vector2i(2, 6), Vector2i(2, 9),
				Vector2i(13, 9), Vector2i(13, 4), Vector2i(17, 4), Vector2i(17, 8), Vector2i(20, 8),
			],
		],
		"water": [[8, 0, 3, 2], [15, 0, 3, 2]],
		"rock": [[0, 4, 2, 2], [4, 0, 2, 2], [8, 4, 3, 2], [11, 6, 2, 2], [15, 6, 2, 2], [18, 1, 2, 3], [9, 7, 2, 1], [4, 7, 1, 2], [14, 2, 2, 1], [0, 7, 2, 2], [7, 2, 1, 2], [11, 2, 2, 1], [3, 3, 2, 1], [5, 7, 2, 1], [14, 5, 1, 2], [18, 9, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3a3a44"), "ground_b": Color("32323b"),
			"path_edge": Color("26262e"), "path_fill": Color("7b7686"),
			"water_a": Color("1b3d55"), "water_b": Color("24536e"),
			"rock": Color("55505c"),
		},
	},
	{
		"id": "delta",
		"hazard": "brine",
		"goal": {"kind": "few_towers", "n": 8, "towers": 10},
		"unlock_level": 14,
		"area": "delta",
		"name": "Serpent Delta",
		"theme": "Swamp",
		"decor": "vines",
		"path_style": "boardwalk", "ground_style": "dots", "water_style": "murk",
		"tint": Color(0.35, 0.80, 0.60, 0.050),
		"tier": 3,
		"blurb": "One long S through the mangroves. Blink and the creeps are at your base.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(4, 2), Vector2i(9, 7), Vector2i(13, 7), Vector2i(13, 4),
				Vector2i(17, 4), Vector2i(17, 8), Vector2i(20, 8),
			],
		],
		"water": [[0, 5, 6, 3], [10, 0, 5, 3], [15, 9, 5, 2]],
		"rock": [[7, 1, 2, 2], [11, 5, 2, 2], [2, 9, 3, 2], [7, 9, 2, 2], [18, 0, 2, 3]],
		"ground": [],
		"palette": {
			"ground_a": Color("1e3330"), "ground_b": Color("192b29"),
			"path_edge": Color("241f16"), "path_fill": Color("55452f"),
			"water_a": Color("0f3b41"), "water_b": Color("155059"),
			"rock": Color("35403f"),
		},
	},
	{
		"id": "comb",
		"goal": {"kind": "kills", "n": 250},
		"unlock_level": 16,
		"area": "delta",
		"name": "Iron Comb",
		"theme": "Foundry",
		"decor": "bolts",
		"path_style": "rail", "ground_style": "tiles", "water_style": "murk",
		"tint": Color(0.90, 0.60, 0.35, 0.050),
		"tier": 3,
		"blurb": "Three switchback teeth through the foundry. Short and merciless.",
		"routes": [
			[
				Vector2i(-1, 9), Vector2i(4, 9), Vector2i(4, 4), Vector2i(9, 4), Vector2i(9, 9),
				Vector2i(14, 9), Vector2i(14, 4), Vector2i(20, 4),
			],
		],
		"water": [[6, 6, 2, 3], [16, 6, 4, 3], [0, 0, 4, 2]],
		"rock": [[2, 5, 2, 3], [11, 0, 3, 4], [6, 0, 2, 4], [17, 0, 3, 4], [11, 6, 2, 3], [0, 5, 2, 3], [5, 8, 3, 2], [15, 0, 2, 3], [12, 9, 3, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("2d2f36"), "ground_b": Color("26282e"),
			"path_edge": Color("191a1e"), "path_fill": Color("4c4f57"),
			"water_a": Color("14343f"), "water_b": Color("1b4a58"),
			"rock": Color("444a52"),
		},
	},
	{
		"id": "coast",
		"hazard": "gale",
		"goal": {"kind": "no_sell", "n": 12},
		"unlock_level": 11,
		"area": "frozen",
		"name": "Coastal Cliffs",
		"theme": "Coast",
		"decor": "driftwood",
		"path_style": "planks", "ground_style": "flat", "water_style": "surf",
		"tint": Color(0.50, 0.80, 0.95, 0.060),
		"tier": 3,
		"blurb": "A single diagonal plunge down the cliffs — the shortest road in the game.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(3, 1), Vector2i(12, 10), Vector2i(20, 10),
			],
		],
		"water": [[0, 3, 9, 3], [13, 0, 7, 4], [14, 6, 6, 2]],
		"rock": [[10, 4, 2, 2], [4, 7, 3, 2], [9, 8, 2, 2], [1, 7, 2, 2], [12, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3d4a44"), "ground_b": Color("35413c"),
			"path_edge": Color("2e2a24"), "path_fill": Color("8a7a5e"),
			"water_a": Color("12475e"), "water_b": Color("1a6480"),
			"rock": Color("4d5a5c"),
		},
	},
	{
		"id": "twingates",
		"goal": {"kind": "rich", "n": 900},
		"unlock_level": 6,
		"area": "riverlands",
		"name": "Twin Gates",
		"theme": "Twin Gates",
		"decor": "banners",
		"path_style": "cobble", "ground_style": "checker", "water_style": "calm",
		"tint": Color(0.60, 0.75, 0.95, 0.050),
		"tier": 1,
		"blurb": "TWO LANES. Separate gates, separate bases — split your gold or lose one.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(6, 1), Vector2i(6, 4), Vector2i(12, 4),
				Vector2i(12, 1), Vector2i(20, 1),
			],
			[
				Vector2i(-1, 9), Vector2i(6, 9), Vector2i(6, 6), Vector2i(12, 6),
				Vector2i(12, 9), Vector2i(20, 9),
			],
		],
		"water": [[8, 0, 3, 1], [15, 4, 3, 3]],
		"rock": [[3, 4, 2, 3], [16, 0, 2, 2], [16, 9, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("2b3440"), "ground_b": Color("242d38"),
			"path_edge": Color("22242c"), "path_fill": Color("6a7180"),
			"water_a": Color("16455e"), "water_b": Color("1e5f7e"),
			"rock": Color("454e5a"),
		},
	},
	{
		"id": "junction",
		"goal": {"kind": "kills", "n": 400},
		"unlock_level": 13,
		"area": "frozen",
		"name": "Fork Junction",
		"theme": "Junction",
		"decor": "sleepers",
		"path_style": "grit", "ground_style": "stripes", "water_style": "floes",
		"tint": Color(0.70, 0.82, 0.95, 0.055),
		"tier": 2,
		"blurb": "TWO LANES that cross in the middle of the yard, each with its own base.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(3, 2), Vector2i(9, 8), Vector2i(16, 8),
				Vector2i(20, 8),
			],
			[
				Vector2i(-1, 8), Vector2i(3, 8), Vector2i(9, 2), Vector2i(16, 2),
				Vector2i(20, 2),
			],
		],
		"water": [[10, 4, 3, 3], [0, 0, 3, 2]],
		"rock": [[5, 0, 2, 2], [5, 9, 2, 2], [17, 4, 3, 3]],
		"ground": [],
		"palette": {
			"ground_a": Color("36414d"), "ground_b": Color("2e3843"),
			"path_edge": Color("242830"), "path_fill": Color("5f6875"),
			"water_a": Color("15384d"), "water_b": Color("1d5470"),
			"rock": Color("49535f"),
		},
	},
	{
		"id": "convergence",
		"goal": {"kind": "few_towers", "n": 10, "towers": 14},
		"unlock_level": 18,
		"area": "delta",
		"name": "Convergence",
		"theme": "Convergence",
		"decor": "spires",
		"path_style": "basalt", "ground_style": "flat", "water_style": "murk",
		"tint": Color(0.85, 0.45, 0.55, 0.060),
		"tier": 3,
		"blurb": "THREE LANES funnelling into one base. Everything arrives at once.",
		"routes": [
			[Vector2i(-1, 1), Vector2i(7, 1), Vector2i(13, 7), Vector2i(20, 7)],
			[Vector2i(-1, 5), Vector2i(9, 5), Vector2i(11, 7), Vector2i(20, 7)],
			[Vector2i(-1, 9), Vector2i(9, 9), Vector2i(11, 7), Vector2i(20, 7)],
		],
		"water": [[2, 3, 3, 1], [2, 7, 3, 1], [16, 0, 4, 3]],
		"rock": [[10, 0, 2, 3], [10, 8, 2, 3], [16, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("332a33"), "ground_b": Color("2b232c"),
			"path_edge": Color("1e1820"), "path_fill": Color("5a4a58"),
			"water_a": Color("2a1f3a"), "water_b": Color("3b2b4f"),
			"rock": Color("463a48"),
		},
	},
	{
		"id": "fernhollow",
		"hazard": "fog",
		"goal": {"kind": "kills", "n": 300},
		"area": "greenlands",
		"unlock_level": 5,
		"name": "Fernhollow",
		"theme": "Fern Hollow",
		"decor": "ferns",
		"path_style": "flagstone", "ground_style": "dots", "water_style": "calm",
		"tint": Color(0.45, 0.85, 0.60, 0.050),
		"tier": 0,
		"blurb": "A damp hollow of ferns and old flagstones, switching back on itself five times.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(3, 1), Vector2i(3, 5), Vector2i(1, 5),
				Vector2i(1, 9), Vector2i(7, 9), Vector2i(7, 3), Vector2i(11, 3),
				Vector2i(11, 9), Vector2i(15, 9), Vector2i(15, 1), Vector2i(18, 1),
				Vector2i(18, 6), Vector2i(20, 6),
			],
		],
		"water": [[5, 6, 2, 2], [16, 8, 3, 2]],
		"rock": [[9, 0, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("1f3a2b"), "ground_b": Color("1a3225"),
			"path_edge": Color("26261f"), "path_fill": Color("5f6650"),
			"water_a": Color("11414a"), "water_b": Color("175c68"),
			"rock": Color("3d4741"),
		},
	},
	{
		"id": "saltmarsh",
		"hazard": "brine",
		"goal": {"kind": "no_sell", "n": 10},
		"area": "riverlands",
		"unlock_level": 9,
		"name": "Saltmarsh",
		"theme": "Saltmarsh",
		"decor": "buoys",
		"path_style": "duckboard", "ground_style": "stripes", "water_style": "surf",
		"tint": Color(0.55, 0.80, 0.85, 0.055),
		"tier": 1,
		"blurb": "Duckboards zigzag over the tidal flats, with brine pools crowding the turns.",
		"routes": [
			[
				Vector2i(-1, 7), Vector2i(5, 7), Vector2i(5, 2), Vector2i(9, 2),
				Vector2i(9, 7), Vector2i(13, 7), Vector2i(13, 2), Vector2i(17, 2),
				Vector2i(17, 8), Vector2i(12, 8), Vector2i(12, 10), Vector2i(20, 10),
			],
		],
		"water": [[0, 0, 4, 2], [7, 4, 2, 2], [15, 4, 2, 2]],
		"rock": [[11, 0, 2, 2], [2, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("2c3a3a"), "ground_b": Color("253232"),
			"path_edge": Color("2a2620"), "path_fill": Color("7a6a4e"),
			"water_a": Color("134350"), "water_b": Color("1b6070"),
			"rock": Color("3f4a4a"),
		},
	},
	{
		"id": "obelisk",
		"goal": {"kind": "rich", "n": 1200},
		"area": "wastes",
		"unlock_level": 15,
		"name": "Obelisk Field",
		"theme": "Obelisks",
		"decor": "obelisks",
		"path_style": "clinker", "ground_style": "flat", "water_style": "murk",
		"tint": Color(0.85, 0.65, 0.95, 0.055),
		"tier": 2,
		"blurb": "A short diagonal cut between standing stones. Little room, less time.",
		"routes": [
			[
				Vector2i(-1, 4), Vector2i(5, 4), Vector2i(9, 8), Vector2i(13, 8),
				Vector2i(13, 4), Vector2i(17, 4), Vector2i(17, 9), Vector2i(13, 9),
				Vector2i(13, 10), Vector2i(20, 10),
			],
		],
		"water": [[7, 1, 3, 2], [15, 0, 3, 2]],
		"rock": [[2, 7, 2, 2], [11, 5, 2, 2], [0, 8, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("35303c"), "ground_b": Color("2d2934"),
			"path_edge": Color("221f27"), "path_fill": Color("5d5468"),
			"water_a": Color("1d2f45"), "water_b": Color("27425e"),
			"rock": Color("474154"),
		},
	},
	{
		"id": "glacier",
		"goal": {"kind": "few_towers", "n": 8, "towers": 12},
		"area": "frozen",
		"unlock_level": 17,
		"name": "Glacier Run",
		"theme": "Glacier",
		"decor": "crystals",
		"path_style": "crystal", "ground_style": "tiles", "water_style": "floes",
		"tint": Color(0.65, 0.85, 1.0, 0.065),
		"tier": 3,
		"blurb": "One long slide down the glacier face. Twenty cells and it is over.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(4, 2), Vector2i(11, 9), Vector2i(16, 9),
				Vector2i(20, 9),
			],
		],
		"water": [[0, 4, 7, 3], [13, 0, 7, 4], [8, 7, 3, 2]],
		"rock": [[6, 0, 2, 2], [12, 5, 2, 3], [17, 6, 3, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("41505e"), "ground_b": Color("384654"),
			"path_edge": Color("38424e"), "path_fill": Color("8fa3b5"),
			"water_a": Color("18405a"), "water_b": Color("225f7f"),
			"rock": Color("54606d"),
		},
	},
	{
		"id": "pipeworks",
		"goal": {"kind": "kills", "n": 500},
		"area": "delta",
		"unlock_level": 20,
		"name": "Pipeworks",
		"theme": "Pipeworks",
		"decor": "pipes",
		"path_style": "conduit", "ground_style": "dunes", "water_style": "murk",
		"tint": Color(0.95, 0.55, 0.30, 0.055),
		"tier": 3,
		"blurb": "TWO LANES through the pipe yard, one long and one short, ending apart.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(6, 2), Vector2i(6, 6), Vector2i(13, 6),
				Vector2i(13, 2), Vector2i(20, 2),
			],
			[
				Vector2i(-1, 9), Vector2i(9, 9), Vector2i(16, 9), Vector2i(16, 5),
				Vector2i(20, 5),
			],
		],
		"water": [[2, 4, 3, 2], [17, 0, 3, 3]],
		"rock": [[8, 0, 3, 2], [10, 3, 2, 2], [4, 7, 3, 2], [14, 7, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("36302a"), "ground_b": Color("2e2924"),
			"path_edge": Color("201d1a"), "path_fill": Color("6b5a48"),
			"water_a": Color("21323a"), "water_b": Color("2c4652"),
			"rock": Color("4a423a"),
		},
	},
	{
		"id": "willow",
		"goal": {"kind": "no_sell", "n": 12},
		"area": "greenlands",
		"unlock_level": 4,
		"name": "Willow Bend",
		"theme": "Willow Marsh",
		"decor": "blossom",
		"path_style": "towpath", "ground_style": "checker", "water_style": "calm",
		"tint": Color(0.55, 0.80, 0.55, 0.050),
		"tier": 0,
		"blurb": "The long way round the willows: six bends and a diagonal cut across the meadow.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(5, 1), Vector2i(5, 5), Vector2i(1, 5),
				Vector2i(1, 9), Vector2i(8, 9), Vector2i(8, 2), Vector2i(12, 6),
				Vector2i(12, 9), Vector2i(16, 9), Vector2i(16, 5), Vector2i(13, 2),
				Vector2i(18, 2), Vector2i(18, 7), Vector2i(20, 7),
			],
		],
		"water": [[9, 0, 3, 2], [2, 7, 2, 2], [6, 6, 2, 2]],
		"rock": [[14, 4, 1, 2], [9, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("24361f"), "ground_b": Color("1f2f1b"),
			"path_edge": Color("2b2116"), "path_fill": Color("5c4833"),
			"water_a": Color("14404a"), "water_b": Color("1c5a६b".replace("६", "6")),
			"rock": Color("3d4239"),
		},
	},
	{
		"id": "orchard",
		"goal": {"kind": "kills", "n": 260},
		"area": "greenlands",
		"unlock_level": 6,
		"name": "Orchard Rows",
		"theme": "Orchard",
		"decor": "hedges",
		"path_style": "chalk", "ground_style": "stripes", "water_style": "calm",
		"tint": Color(0.85, 0.75, 0.40, 0.050),
		"tier": 0,
		"blurb": "Up and down every row of the orchard. Nothing here is in a hurry.",
		"routes": [
			[
				Vector2i(-1, 9), Vector2i(3, 9), Vector2i(3, 5), Vector2i(6, 2),
				Vector2i(6, 9), Vector2i(9, 9), Vector2i(9, 3), Vector2i(12, 3),
				Vector2i(12, 9), Vector2i(15, 9), Vector2i(15, 3), Vector2i(18, 3),
				Vector2i(18, 8), Vector2i(14, 8), Vector2i(14, 10), Vector2i(20, 10),
			],
		],
		"water": [[0, 0, 3, 2], [16, 5, 2, 2]],
		"rock": [[7, 0, 2, 2], [10, 6, 1, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("2f3a1e"), "ground_b": Color("28331a"),
			"path_edge": Color("332614"), "path_fill": Color("7a6340"),
			"water_a": Color("17414f"), "water_b": Color("1f5a६f".replace("६", "6")),
			"rock": Color("484433"),
		},
	},
	{
		"id": "millrace",
		"goal": {"kind": "rich", "n": 950},
		"area": "riverlands",
		"unlock_level": 7,
		"name": "Millrace",
		"theme": "Mill",
		"decor": "lilies",
		"path_style": "causeway", "ground_style": "dots", "water_style": "surf",
		"tint": Color(0.50, 0.75, 0.90, 0.055),
		"tier": 1,
		"blurb": "Four turns between the millponds. Water on both sides of every corner.",
		"routes": [
			[
				Vector2i(-1, 3), Vector2i(4, 3), Vector2i(4, 8), Vector2i(8, 8),
				Vector2i(8, 2), Vector2i(12, 2), Vector2i(12, 8), Vector2i(16, 8),
				Vector2i(16, 3), Vector2i(19, 3), Vector2i(19, 9), Vector2i(20, 9),
			],
		],
		"water": [[5, 0, 3, 2], [9, 9, 3, 2], [17, 0, 2, 2], [5, 5, 2, 3],
			[13, 4, 2, 3]],
		"rock": [[6, 4, 1, 1], [9, 6, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("27343a"), "ground_b": Color("212d33"),
			"path_edge": Color("2b2419"), "path_fill": Color("7d6a49"),
			"water_a": Color("11414f"), "water_b": Color("18606f"),
			"rock": Color("3c4750"),
		},
	},
	{
		"id": "heron",
		"goal": {"kind": "few_towers", "n": 9, "towers": 13},
		"area": "riverlands",
		"unlock_level": 8,
		"name": "Heron Flats",
		"theme": "Wetland",
		"decor": "nets",
		"path_style": "reedmat", "ground_style": "flat", "water_style": "calm",
		"tint": Color(0.60, 0.80, 0.70, 0.050),
		"tier": 1,
		"blurb": "Three long combs across the flats, with standing water in every gap.",
		"routes": [
			[
				Vector2i(-1, 6), Vector2i(3, 6), Vector2i(3, 2), Vector2i(7, 2),
				Vector2i(7, 8), Vector2i(11, 8), Vector2i(11, 2), Vector2i(15, 2),
				Vector2i(15, 8), Vector2i(18, 8), Vector2i(18, 2), Vector2i(20, 2),
			],
		],
		"water": [[0, 8, 3, 2], [8, 0, 3, 2], [12, 4, 3, 2], [16, 0, 1, 2],
			[5, 4, 2, 3]],
		"rock": [[9, 9, 3, 2], [13, 9, 2, 2], [0, 0, 2, 2], [8, 3, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("29372f"), "ground_b": Color("233029"),
			"path_edge": Color("2a2418"), "path_fill": Color("77684a"),
			"water_a": Color("13454d"), "water_b": Color("1b6270"),
			"rock": Color("3e4a44"),
		},
	},
	{
		"id": "quarry",
		"hazard": "ash",
		"goal": {"kind": "no_water", "n": 9},
		"area": "wastes",
		"unlock_level": 11,
		"name": "Sunken Quarry",
		"theme": "Quarry",
		"decor": "rubble",
		"path_style": "haulroad", "ground_style": "tiles", "water_style": "murk",
		"tint": Color(0.85, 0.70, 0.45, 0.050),
		"tier": 2,
		"blurb": "Down the quarry benches and out the haul road. Rock everywhere you want to build.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(5, 2), Vector2i(5, 8), Vector2i(11, 8),
				Vector2i(11, 4), Vector2i(15, 4), Vector2i(15, 9), Vector2i(18, 9),
				Vector2i(18, 6), Vector2i(20, 6),
			],
		],
		"water": [[7, 0, 3, 2]],
		"rock": [[2, 5, 2, 3], [8, 5, 2, 2], [13, 0, 3, 3], [17, 1, 3, 2],
			[9, 9, 2, 2], [3, 0, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3a3228"), "ground_b": Color("322b22"),
			"path_edge": Color("241f18"), "path_fill": Color("6b5d49"),
			"water_a": Color("26343a"), "water_b": Color("32474f"),
			"rock": Color("4e4639"),
		},
	},
	{
		"id": "glassflats",
		"hazard": "fog",
		"goal": {"kind": "kills", "n": 420},
		"area": "wastes",
		"unlock_level": 13,
		"name": "Glass Flats",
		"theme": "Salt Flats",
		"decor": "glass",
		"path_style": "saltcrust", "ground_style": "flat", "water_style": "murk",
		"tint": Color(0.90, 0.85, 0.60, 0.050),
		"tier": 2,
		"blurb": "Two long diagonals over fused sand, with nothing to hide behind.",
		"routes": [
			[
				Vector2i(-1, 1), Vector2i(4, 1), Vector2i(9, 6), Vector2i(13, 6),
				Vector2i(13, 2), Vector2i(17, 2), Vector2i(17, 8), Vector2i(11, 8),
				Vector2i(11, 10), Vector2i(20, 10),
			],
		],
		"water": [[5, 8, 3, 2], [14, 9, 3, 2]],
		"rock": [[1, 4, 2, 3], [10, 0, 3, 3], [15, 4, 2, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3d3a2e"), "ground_b": Color("353227"),
			"path_edge": Color("272419"), "path_fill": Color("74705a"),
			"water_a": Color("2b3a3d"), "water_b": Color("3a4f52"),
			"rock": Color("52503f"),
		},
	},
	{
		"id": "floes",
		"hazard": "gale",
		"goal": {"kind": "no_sell", "n": 9},
		"area": "frozen",
		"unlock_level": 10,
		"name": "Drift Floes",
		"theme": "Pack Ice",
		"decor": "hummocks",
		"path_style": "snowpack", "ground_style": "checker", "water_style": "floes",
		"tint": Color(0.60, 0.85, 1.00, 0.060),
		"tier": 2,
		"blurb": "Ice bridges between drifting floes. Three combs, and open water at every end.",
		"routes": [
			[
				Vector2i(-1, 8), Vector2i(4, 8), Vector2i(4, 3), Vector2i(9, 3),
				Vector2i(9, 8), Vector2i(14, 8), Vector2i(14, 3), Vector2i(18, 3),
				Vector2i(18, 6), Vector2i(20, 6),
			],
		],
		"water": [[0, 0, 4, 2], [6, 5, 2, 3], [11, 0, 3, 3], [16, 7, 4, 4]],
		"rock": [[5, 0, 1, 3], [10, 6, 1, 2]],
		"ground": [],
		"palette": {
			"ground_a": Color("3c4a58"), "ground_b": Color("34424e"),
			"path_edge": Color("33404c"), "path_fill": Color("879db0"),
			"water_a": Color("163b54"), "water_b": Color("1f5877"),
			"rock": Color("4f5b68"),
		},
	},
	{
		"id": "whiteout",
		"goal": {"kind": "rich", "n": 1100},
		"area": "frozen",
		"unlock_level": 19,
		"name": "Whiteout Ridge",
		"theme": "Blizzard",
		"decor": "drifts",
		"path_style": "glaze", "ground_style": "flat", "water_style": "floes",
		"tint": Color(0.80, 0.90, 1.00, 0.070),
		"tier": 3,
		"blurb": "A diagonal off the ridge and a straight run to the gate. Blink and it is over.",
		"routes": [
			[
				Vector2i(-1, 3), Vector2i(5, 3), Vector2i(10, 8), Vector2i(14, 8),
				Vector2i(14, 4), Vector2i(20, 4),
			],
		],
		"water": [[0, 6, 5, 5], [6, 0, 4, 2], [15, 7, 5, 4]],
		"rock": [[6, 4, 2, 3], [11, 2, 3, 3], [16, 0, 4, 3]],
		"ground": [],
		"palette": {
			"ground_a": Color("47535f"), "ground_b": Color("3e4955"),
			"path_edge": Color("3a4550"), "path_fill": Color("9aabbb"),
			"water_a": Color("1a3f57"), "water_b": Color("245c7c"),
			"rock": Color("59636f"),
		},
	},
	{
		"id": "foundry",
		"goal": {"kind": "few_towers", "n": 8, "towers": 11},
		"area": "delta",
		"unlock_level": 15,
		"name": "Foundry Yard",
		"theme": "Slag Yard",
		"decor": "slag",
		"path_style": "cinder", "ground_style": "tiles", "water_style": "murk",
		"tint": Color(0.95, 0.55, 0.30, 0.050),
		"tier": 3,
		"blurb": "Two turns through the slag heaps. Barely a yard of it is worth building on.",
		"routes": [
			[
				Vector2i(-1, 2), Vector2i(6, 2), Vector2i(6, 7), Vector2i(12, 7),
				Vector2i(12, 3), Vector2i(20, 3),
			],
		],
		"water": [[0, 8, 5, 3], [14, 7, 6, 4], [0, 4, 2, 3]],
		"rock": [[2, 4, 3, 3], [8, 0, 3, 3], [8, 9, 4, 2], [13, 0, 3, 2],
			[16, 4, 4, 2], [4, 5, 1, 2], [10, 4, 1, 3], [7, 3, 1, 3]],
		"ground": [],
		"palette": {
			"ground_a": Color("332e2c"), "ground_b": Color("2c2825"),
			"path_edge": Color("1c1917"), "path_fill": Color("585049"),
			"water_a": Color("2a2f24"), "water_b": Color("3a4130"),
			"rock": Color("4a443e"),
		},
	},
	{
		"id": "locks",
		"goal": {"kind": "no_water", "n": 8},
		"area": "delta",
		"unlock_level": 19,
		"name": "Tidal Locks",
		"theme": "Lock Gates",
		"decor": "bollards",
		"path_style": "pontoon", "ground_style": "stripes", "water_style": "surf",
		"tint": Color(0.45, 0.70, 0.85, 0.055),
		"tier": 3,
		"blurb": "Lock gates on three sides. The road is the only dry ground worth the name.",
		"routes": [
			[
				Vector2i(-1, 5), Vector2i(4, 5), Vector2i(4, 9), Vector2i(9, 9),
				Vector2i(9, 5), Vector2i(13, 5), Vector2i(13, 9), Vector2i(20, 9),
			],
		],
		"water": [[0, 0, 6, 4], [10, 0, 5, 4], [16, 0, 4, 5], [5, 6, 2, 3],
			[14, 6, 2, 3]],
		"rock": [[2, 7, 1, 2], [10, 6, 2, 2], [17, 6, 3, 2], [6, 4, 3, 1],
			[11, 4, 2, 1]],
		"ground": [],
		"palette": {
			"ground_a": Color("2b3540"), "ground_b": Color("242d37"),
			"path_edge": Color("1d2229"), "path_fill": Color("56626d"),
			"water_a": Color("123c4e"), "water_b": Color("195a70"),
			"rock": Color("3f4a55"),
		},
	},
]

## Tower table.
##
## Each entry carries base stats plus a list of upgrade `tracks`. A track is
## an independently purchased line of ranks (Damage, Rate, Range, Blast...)
## chosen to suit that tower, and a track's last rank may also unlock a named
## capstone effect. Track mod keys combine by suffix: `_mult` multiplies per
## rank, `_add` sums per rank, and bare keys are set once.
## A tower's numbers with any tuning overrides applied — global ones first,
## then this level's. Everything that reads a tower stat should come through
## here rather than indexing TOWERS directly, or the tuning panel (F2) will
## not reach it.
static func tower_def(id: String) -> Dictionary:
	_tuning_ready()
	if _tuned_defs.has(id):
		return _tuned_defs[id]
	_tuned_defs[id] = _apply_numbers(TOWERS[id], Tuning.effective(id, selected_level))
	return _tuned_defs[id]


## A creep's numbers with any tuning overrides applied. Same layering as
## towers: global first, then this level's.
static func enemy_def(kind: String) -> Dictionary:
	_tuning_ready()
	if _tuned_enemies.has(kind):
		return _tuned_enemies[kind]
	_tuned_enemies[kind] = _apply_numbers(ENEMIES[kind],
			Tuning.effective(Tuning.enemy_subject(kind), selected_level))
	return _tuned_enemies[kind]


## A tower's upgrade tracks with any tuning applied — rank caps, coin cost
## and the per-rank modifiers themselves. Everything that reads a track goes
## through here, so `mods_for`, the costs and the capstones all follow.
static func tracks(type_id: String) -> Array:
	_tuning_ready()
	if _tuned_tracks.has(type_id):
		return _tuned_tracks[type_id]
	var base: Array = TOWERS[type_id]["tracks"]
	var out: Array = base
	var tuned := false
	for i in base.size():
		var over := Tuning.effective(Tuning.track_subject(type_id, i), selected_level)
		if over.is_empty():
			continue
		if not tuned:
			out = base.duplicate(true)
			tuned = true
		var track: Dictionary = out[i]
		for key: String in over:
			# Keys ending in "#N" belong to rank N alone; the rest apply to
			# the whole track. See Tuning for where these are written.
			var rank := 0
			var field := key
			var hash_at := key.find("#")
			if hash_at > 0:
				rank = int(key.substr(hash_at + 1))
				field = key.substr(0, hash_at)
			if rank > 0:
				if field == "cost":
					_put_rank(track, "rank_costs", rank, int(round(float(over[key]))))
				elif field == "gold":
					_put_rank(track, "rank_gold", rank, int(round(float(over[key]))))
				elif field.begins_with("mods."):
					if not track.has("rank_mods"):
						track["rank_mods"] = {}
					var per: Dictionary = track["rank_mods"]
					if not per.has(rank):
						# Ranks left alone keep the track's own modifier.
						per[rank] = (track["mods"] as Dictionary).duplicate()
					(per[rank] as Dictionary)[field.substr(5)] = float(over[key])
				continue
			if field.begins_with("mods."):
				(track["mods"] as Dictionary)[field.substr(5)] = float(over[key])
			elif typeof(track.get(field)) == TYPE_INT:
				track[field] = int(round(float(over[field])))
			else:
				track[field] = float(over[key])
	_tuned_tracks[type_id] = out
	return out


static func _put_rank(track: Dictionary, bag: String, rank: int, value: int) -> void:
	if not track.has(bag):
		track[bag] = {}
	(track[bag] as Dictionary)[rank] = value


## Copies a table entry with the overridden numbers written over it, keeping
## whole numbers whole so a cost never prints as "$115.0".
static func _apply_numbers(base: Dictionary, over: Dictionary) -> Dictionary:
	if over.is_empty():
		return base
	var out := base.duplicate(true)
	for key: String in over:
		out[key] = int(round(float(over[key]))) if typeof(base.get(key)) == TYPE_INT \
				else float(over[key])
	return out


static var TOWERS: Dictionary = {
	"gun": {
		"name": "Gunner", "short": "Gunner", "cost": 60, "color": Color("4fc3f7"),
		"hits_air": true,
		"range": 132.0, "rate": 1.8, "damage": 11.0, "proj_speed": 540.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 1,
		"desc": "Rapid single-target bullets. Cheap and reliable.",
		"tracks": [
			{"key": "dmg", "name": "Heavy Rounds", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.22},
				"capstone": {"name": "Sabot Rounds", "desc": "Rounds punch through armor.",
					"mods": {"pierce": true}}},
			{"key": "rate", "name": "Feed System", "max": 4, "cost_frac": 0.5,
				"mods": {"rate_mult": 1.18},
				"capstone": {"name": "Twin Barrels", "desc": "Two rounds per volley.",
					"mods": {"shots_add": 1}}},
			{"key": "range", "name": "Long Barrel", "requires": {"track": "dmg", "rank": 2}, "level": 2, "max": 3, "cost_frac": 0.4,
				"mods": {"range_mult": 1.12}},
		],
	},
	"cannon": {
		"name": "Cannon", "short": "Cannon", "cost": 115, "color": Color("ff8a65"),
		"range": 154.0, "rate": 0.6, "damage": 28.0, "proj_speed": 300.0,
		"splash": 58.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 1,
		"desc": "Slow lobbed shells with splash damage. Great vs swarms.",
		"tracks": [
			{"key": "dmg", "name": "Heavy Shells", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.24},
				"capstone": {"name": "Siege Charge", "desc": "Blasts ignore armor entirely.",
					"mods": {"pierce": true}}},
			{"key": "blast", "name": "Wide Blast", "max": 4, "cost_frac": 0.5,
				"mods": {"splash_mult": 1.16},
				"capstone": {"name": "Cluster Munitions", "desc": "Shells scatter secondary blasts.",
					"mods": {"cluster": 3}}},
			{"key": "rate", "name": "Auto Rammer", "requires": {"track": "blast", "rank": 2}, "max": 3, "cost_frac": 0.5,
				"mods": {"rate_mult": 1.18}},
			{"key": "range", "name": "Rangefinder", "requires": {"track": "dmg", "rank": 2}, "level": 4, "max": 3, "cost_frac": 0.4,
				"mods": {"range_mult": 1.12}},
		],
	},
	"frost": {
		"name": "Frost", "short": "Frost", "cost": 95, "color": Color("81d4fa"),
		"hits_air": true,
		"range": 124.0, "rate": 1.0, "damage": 5.0, "proj_speed": 420.0,
		"splash": 34.0, "slow": 0.45, "slow_dur": 1.8,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 2,
		"desc": "Chills enemies in a small area, slowing them sharply.",
		"tracks": [
			{"key": "slow", "name": "Cryo Core", "max": 4, "cost_frac": 0.5,
				"mods": {"slow_add": 0.05},
				"capstone": {"name": "Deep Freeze", "desc": "Chill deepens to a 75% slow.",
					"mods": {"slow_set": 0.75}}},
			{"key": "dur", "name": "Coolant Tanks", "max": 4, "cost_frac": 0.4,
				"mods": {"slow_dur_add": 0.5}},
			{"key": "dmg", "name": "Chill Damage", "requires": {"track": "slow", "rank": 2}, "max": 3, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.3},
				"capstone": {"name": "Shatter", "desc": "+80% damage to chilled enemies.",
					"mods": {"shatter": 1.8}}},
			{"key": "blast", "name": "Frost Cloud", "requires": {"track": "dur", "rank": 2}, "level": 5, "max": 3, "cost_frac": 0.45,
				"mods": {"splash_mult": 1.2, "range_mult": 1.06}},
		],
	},
	"tesla": {
		"name": "Tesla", "short": "Tesla", "cost": 175, "color": Color("ba68c8"),
		"hits_air": true,
		"range": 142.0, "rate": 1.0, "damage": 36.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": true, "pierce_armor": true,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 5,
		"desc": "Continuous beam, damage per second, ignores armor.",
		"tracks": [
			{"key": "dmg", "name": "Overcharge", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.26}},
			{"key": "chain", "name": "Arc Splitter", "requires": {"track": "dmg", "rank": 2}, "level": 7, "max": 3, "cost_frac": 0.7,
				"mods": {"chain_add": 1},
				"capstone": {"name": "Ion Storm", "desc": "The storm burns hotter still.",
					"mods": {"damage_mult": 1.15}}},
			{"key": "range", "name": "Coil Array", "max": 3, "cost_frac": 0.45,
				"mods": {"range_mult": 1.14}},
		],
	},
	"marksman": {
		"name": "Marksman", "short": "Marksman", "cost": 190, "color": Color("9ccc65"),
		"hits_air": true,
		"range": 300.0, "rate": 0.5, "damage": 62.0, "proj_speed": 900.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": true, "pierce_count": 1,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 3,
		"desc": "Very long range rifle. Armor-piercing rounds bore through a target.",
		"tracks": [
			{"key": "dmg", "name": "Match Barrel", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.28},
				"capstone": {"name": "Armor Breaker", "desc": "Rounds tear through one more enemy.",
					"mods": {"pierce_add": 1}}},
			{"key": "range", "name": "Scope", "max": 4, "cost_frac": 0.45,
				"mods": {"range_mult": 1.13}},
			{"key": "rate", "name": "Cycle Action", "requires": {"track": "dmg", "rank": 2}, "level": 5, "max": 3, "cost_frac": 0.6,
				"mods": {"rate_mult": 1.22}},
		],
	},
	"flame": {
		"name": "Flamethrower", "short": "Flamer", "cost": 130, "color": Color("ff7043"),
		"range": 96.0, "rate": 1.0, "damage": 26.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0, "burn": 8.0,
		"beam": true, "pierce_armor": false, "chain": 2,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 6,
		"desc": "Short-range cone of fire. Roasts several creeps at once and leaves them burning.",
		"tracks": [
			{"key": "dmg", "name": "Fuel Mix", "max": 4, "cost_frac": 0.5,
				"mods": {"damage_mult": 1.26}},
			{"key": "chain", "name": "Wide Nozzle", "requires": {"track": "dmg", "rank": 2}, "max": 3, "cost_frac": 0.6,
				"mods": {"chain_add": 1},
				"capstone": {"name": "Firestorm", "desc": "The cone reaches further out.",
					"mods": {"range_mult": 1.2}}},
			{"key": "burn", "name": "Napalm", "level": 8, "max": 3, "cost_frac": 0.55,
				"mods": {"burn_add": 7.0}},
		],
	},
	"mortar": {
		"name": "Mortar", "short": "Mortar", "cost": 260, "color": Color("a1887f"),
		"range": 420.0, "min_range": 130.0, "rate": 0.3, "damage": 78.0,
		"proj_speed": 260.0, "splash": 74.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 9,
		"desc": "Map-wide artillery with a heavy blast. Cannot hit anything close by.",
		"tracks": [
			{"key": "dmg", "name": "Big Shells", "max": 4, "cost_frac": 0.5,
				"mods": {"damage_mult": 1.26},
				"capstone": {"name": "Bunker Buster", "desc": "Shells ignore armor.",
					"mods": {"pierce": true}}},
			{"key": "blast", "name": "Wide Blast", "max": 3, "cost_frac": 0.5,
				"mods": {"splash_mult": 1.2}},
			{"key": "rate", "name": "Auto Loader", "requires": {"track": "dmg", "rank": 2}, "max": 3, "cost_frac": 0.6,
				"mods": {"rate_mult": 1.25}},
			{"key": "range", "name": "Spotter Drone", "requires": {"track": "blast", "rank": 1}, "level": 10, "max": 2, "cost_frac": 0.45,
				"mods": {"range_mult": 1.15, "min_range_mult": 0.75}},
		],
	},
	"tide": {
		"name": "Tide Caller", "short": "Tide", "cost": 150, "color": Color("26c6da"),
		"hits_air": true,
		"range": 205.0, "rate": 0.85, "damage": 30.0, "proj_speed": 380.0,
		"splash": 46.0, "slow": 0.2, "slow_dur": 0.9,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.WATER, "air": false,
		"unlock_level": 4,
		"desc": "WATER ONLY. Long-range torrents that splash and briefly slow.",
		"tracks": [
			{"key": "range", "name": "Pressure Jets", "max": 4, "cost_frac": 0.45,
				"mods": {"range_mult": 1.12}},
			{"key": "slow", "name": "Riptide", "max": 3, "cost_frac": 0.5,
				"mods": {"slow_add": 0.08, "slow_dur_add": 0.3},
				"capstone": {"name": "Undertow", "desc": "Drags enemies to a 65% crawl.",
					"mods": {"slow_set": 0.65}}},
			{"key": "dmg", "name": "Tsunami", "requires": {"track": "range", "rank": 2}, "level": 6, "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.22, "splash_mult": 1.12}},
		],
	},
	"torpedo": {
		"name": "Torpedo Battery", "short": "Torpedo", "cost": 180, "color": Color("4dd0e1"),
		"range": 260.0, "rate": 0.55, "damage": 54.0, "proj_speed": 430.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false, "pierce_count": 2,
		"terrain": Terrain.WATER, "air": false,
		"unlock_level": 8,
		"desc": "WATER ONLY. Torpedoes run in a straight line and hit everything they pass.",
		"tracks": [
			{"key": "dmg", "name": "Warheads", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.26}},
			{"key": "pierce", "name": "Spread Tubes", "requires": {"track": "dmg", "rank": 2}, "level": 9, "max": 3, "cost_frac": 0.65,
				"mods": {"pierce_add": 1},
				"capstone": {"name": "Sea Lance", "desc": "Torpedoes ignore armor.",
					"mods": {"pierce": true}}},
			{"key": "rate", "name": "Loading Gear", "max": 3, "cost_frac": 0.55,
				"mods": {"rate_mult": 1.2}},
		],
	},
	"airfield": {
		"name": "Airfield", "short": "Airfield", "cost": 210, "color": Color("aed581"),
		"hits_air": true,
		"range": 340.0, "rate": 0.18, "damage": 58.0, "proj_speed": 0.0,
		"splash": 62.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": true,
		"unlock_level": 7,
		"unit": "plane", "unit_speed": 270.0, "unit_count": 1, "unit_shots": 1,
		"desc": "Launches a bomber that flies out, bombs the leaders, and lands to rearm.",
		"tracks": [
			{"key": "rate", "name": "Ground Crew", "max": 4, "cost_frac": 0.45,
				"mods": {"rate_mult": 1.2}},
			{"key": "bombs", "name": "Bomb Racks", "max": 3, "cost_frac": 0.55,
				"mods": {"unit_shots_add": 1},
				"capstone": {"name": "Carpet Bombing", "desc": "Every bomb blasts wider.",
					"mods": {"splash_mult": 1.25}}},
			{"key": "dmg", "name": "Heavy Payload", "requires": {"track": "bombs", "rank": 1}, "max": 3, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.24}},
			{"key": "squad", "name": "Second Bomber", "requires": {"track": "rate", "rank": 2}, "level": 9, "max": 1, "cost_frac": 1.1,
				"mods": {"unit_count_add": 1, "unit_speed_mult": 1.15}},
		],
	},
	"helipad": {
		"name": "Helipad", "short": "Helipad", "cost": 240, "color": Color("ffb74d"),
		"hits_air": true,
		"range": 300.0, "rate": 0.14, "damage": 15.0, "proj_speed": 620.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": true,
		"unlock_level": 10,
		"unit": "heli", "unit_speed": 190.0, "unit_count": 1, "unit_shots": 14,
		"desc": "Sends a gunship that hovers over the path and strafes until out of ammo.",
		"tracks": [
			{"key": "dmg", "name": "Autocannon", "max": 4, "cost_frac": 0.5,
				"mods": {"damage_mult": 1.28}},
			{"key": "ammo", "name": "Ammo Belts", "max": 3, "cost_frac": 0.45,
				"mods": {"unit_shots_add": 5}},
			{"key": "speed", "name": "Uprated Rotors", "requires": {"track": "ammo", "rank": 1}, "max": 3, "cost_frac": 0.4,
				"mods": {"unit_speed_mult": 1.2, "rate_mult": 1.1}},
			{"key": "squad", "name": "Wing Escort", "requires": {"track": "dmg", "rank": 2}, "level": 11, "max": 1, "cost_frac": 1.1,
				"mods": {"unit_count_add": 1}},
		],
	},
	"tarpit": {
		"name": "Tar Pit", "short": "Tar Pit", "cost": 110, "color": Color("8d6e63"),
		"range": 118.0, "rate": 1.0, "damage": 0.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.5, "slow_dur": 0.5,
		"beam": false, "pierce_armor": false, "field": true,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 4,
		"desc": "Fires nothing. Everything inside the pit wades through tar and slows down.",
		"tracks": [
			{"key": "slow", "name": "Thicker Tar", "max": 4, "cost_frac": 0.5,
				"mods": {"slow_add": 0.06},
				"capstone": {"name": "Quagmire", "desc": "The pit slows by 80%.",
					"mods": {"slow_set": 0.8}}},
			{"key": "range", "name": "Wider Pit", "max": 4, "cost_frac": 0.45,
				"mods": {"range_mult": 1.12}},
			{"key": "dur", "name": "Clinging Tar", "requires": {"track": "slow", "rank": 2},
				"level": 6, "max": 3, "cost_frac": 0.5,
				"mods": {"slow_dur_add": 0.4}},
		],
	},
	"mine": {
		"name": "Gold Mine", "short": "Mine", "cost": 150, "color": Color("ffca28"),
		"range": 90.0, "rate": 1.0, "damage": 0.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false, "income": 26.0,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 6,
		"desc": "Fires nothing. Pays out gold at the end of every wave — build it early.",
		"tracks": [
			{"key": "income", "name": "Deeper Shaft", "max": 4, "cost_frac": 0.55,
				"mods": {"income_mult": 1.3},
				"capstone": {"name": "Mother Lode", "desc": "A big final boost to the payout.",
					"mods": {"income_mult": 1.4}}},
			{"key": "rate", "name": "Night Shift", "max": 3, "cost_frac": 0.5,
				"mods": {"income_mult": 1.18}},
			{"key": "range", "name": "Survey Team", "requires": {"track": "income", "rank": 2},
				"level": 8, "max": 2, "cost_frac": 0.5,
				"mods": {"income_mult": 1.25}},
		],
	},
	"shock": {
		"name": "Shockwave", "short": "Shock", "cost": 170, "color": Color("4db6ac"),
		"range": 108.0, "rate": 0.7, "damage": 30.0, "proj_speed": 0.0,
		"splash": 108.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false, "pulse": true,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 8,
		"desc": "Slams the ground on a timer, damaging everything around it. No aiming needed.",
		"tracks": [
			{"key": "dmg", "name": "Heavier Slam", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.26},
				"capstone": {"name": "Fault Line", "desc": "Shockwaves ignore armor.",
					"mods": {"pierce": true}}},
			{"key": "range", "name": "Wider Ring", "max": 3, "cost_frac": 0.5,
				"mods": {"range_mult": 1.14, "splash_mult": 1.14}},
			{"key": "rate", "name": "Piston Drive", "requires": {"track": "dmg", "rank": 2},
				"level": 10, "max": 3, "cost_frac": 0.55,
				"mods": {"rate_mult": 1.22}},
		],
	},
	"ballista": {
		"name": "Ballista", "short": "Ballista", "cost": 200, "color": Color("a1887f"),
		"hits_air": true,
		"range": 210.0, "rate": 0.55, "damage": 44.0, "proj_speed": 620.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false, "pierce_count": 2, "volley": 2,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 10,
		"desc": "Looses bolts at several creeps at once, and each bolt skewers the line behind it.",
		"tracks": [
			{"key": "dmg", "name": "Iron Bolts", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.24}},
			{"key": "volley", "name": "Extra Arms", "max": 2, "cost_frac": 0.9,
				"mods": {"volley_add": 1},
				"capstone": {"name": "Storm of Bolts", "desc": "Bolts pierce one more enemy.",
					"mods": {"pierce_add": 1}}},
			{"key": "rate", "name": "Winch Crew", "requires": {"track": "dmg", "rank": 2},
				"level": 12, "max": 3, "cost_frac": 0.55,
				"mods": {"rate_mult": 1.2}},
		],
	},
	"laser": {
		"name": "Focus Laser", "short": "Laser", "cost": 230, "color": Color("f06292"),
		"hits_air": true,
		"range": 150.0, "rate": 1.0, "damage": 22.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": true, "pierce_armor": true, "focus": 2.5, "focus_time": 3.0,
		"terrain": Terrain.GROUND, "air": false,
		"unlock_level": 12,
		"desc": "A beam that bores harder the longer it stays on one creep. Melts anything slow.",
		"tracks": [
			{"key": "dmg", "name": "Pump Array", "max": 4, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.24}},
			{"key": "focus", "name": "Lens Stack", "max": 3, "cost_frac": 0.6,
				"mods": {"focus_add": 0.8},
				"capstone": {"name": "Burn Through", "desc": "Focused fire sets the target alight.",
					"mods": {"burn_add": 14.0}}},
			{"key": "range", "name": "Collimator", "requires": {"track": "dmg", "rank": 2},
				"level": 14, "max": 3, "cost_frac": 0.5,
				"mods": {"range_mult": 1.14}},
		],
	},
	"wavegun": {
		"name": "Wave Cannon", "short": "Wave Gun", "cost": 205, "color": Color("4fc3f7"),
		"range": 175.0, "rate": 0.5, "damage": 23.0, "proj_speed": 420.0,
		"splash": 52.0, "slow": 0.25, "slow_dur": 1.0, "knockback": 32.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.WATER, "air": false,
		"unlock_level": 14,
		"desc": "WATER ONLY. Breaks a wave over the road that shoves everything back down it.",
		"tracks": [
			{"key": "push", "name": "Storm Surge", "max": 4, "cost_frac": 0.5,
				"mods": {"knockback_add": 10.0},
				"capstone": {"name": "Riptide Wall", "desc": "The surge also drags them to a crawl.",
					"mods": {"slow_set": 0.6}}},
			{"key": "dmg", "name": "Pressure Charge", "max": 3, "cost_frac": 0.55,
				"mods": {"damage_mult": 1.24, "splash_mult": 1.1}},
			{"key": "rate", "name": "Pump Room", "requires": {"track": "push", "rank": 2},
				"level": 16, "max": 3, "cost_frac": 0.55,
				"mods": {"rate_mult": 1.2}},
		],
	},
	"command": {
		"name": "Command Post", "short": "Command", "cost": 200, "color": Color("f5f5f5"),
		"range": 190.0, "rate": 1.0, "damage": 0.0, "proj_speed": 0.0,
		"splash": 0.0, "slow": 0.0, "slow_dur": 0.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.GROUND, "air": false, "support": true,
		"unlock_level": 11,
		"aura_damage": 0.15, "aura_rate": 0.15,
		"desc": "Fires nothing. Boosts the damage and fire rate of every tower in its radius.",
		"tracks": [
			{"key": "aura_dmg", "name": "Doctrine", "max": 3, "cost_frac": 0.6,
				"mods": {"aura_damage_add": 0.1}},
			{"key": "aura_rate", "name": "Logistics", "max": 3, "cost_frac": 0.6,
				"mods": {"aura_rate_add": 0.1}},
			{"key": "range", "name": "Comms Array", "requires": {"track": "aura_dmg", "rank": 1}, "level": 12, "max": 3, "cost_frac": 0.5,
				"mods": {"range_mult": 1.18}},
		],
	},
}


static var ENEMIES: Dictionary = {
	"grunt": {
		"name": "Grunt", "hp": 38.0, "speed": 62.0, "reward": 12,
		"damage": 1, "radius": 13.0, "armor": 0.0, "color": Color("8bc34a"),
	},
	"runner": {
		"name": "Runner", "hp": 30.0, "speed": 134.0, "reward": 13,
		"damage": 1, "radius": 10.0, "armor": 0.0, "color": Color("ffd54f"),
	},
	"swarm": {
		"name": "Swarmling", "hp": 17.0, "speed": 102.0, "reward": 5,
		"damage": 1, "radius": 8.0, "armor": 0.0, "color": Color("f06292"),
	},
	"tank": {
		"name": "Tank", "hp": 215.0, "speed": 44.0, "reward": 30,
		"damage": 2, "radius": 17.0, "armor": 5.0, "color": Color("90a4ae"),
	},
	"brood": {
		"name": "Brood Mother", "hp": 74.0, "speed": 58.0, "reward": 15,
		"damage": 1, "radius": 15.0, "armor": 2.0, "color": Color("7cb342"),
		"split_into": "swarm", "split_count": 2,
		"note": "Bursts into swarmlings when killed.",
	},
	"mender": {
		"name": "Mender", "hp": 96.0, "speed": 66.0, "reward": 22,
		"damage": 1, "radius": 13.0, "armor": 1.0, "color": Color("4dd0e1"),
		"heal": 9.0, "heal_range": 88.0,
		"note": "Heals every wounded creep around it. Kill it first.",
	},
	"warden": {
		"name": "Warden", "hp": 290.0, "speed": 38.0, "reward": 46,
		"damage": 2, "radius": 19.0, "armor": 12.0, "color": Color("78909c"),
		"note": "Slabs of plate. Only armor-piercing fire really hurts it.",
	},
	"ashwalker": {
		"name": "Ashwalker", "hp": 130.0, "speed": 74.0, "reward": 20,
		"damage": 1, "radius": 14.0, "armor": 3.0, "color": Color("ff7043"),
		"slow_immune": true, "burn_immune": true,
		"note": "Runs hot: cannot be slowed or set alight.",
	},
	"bolt": {
		"name": "Bolt", "hp": 48.0, "speed": 92.0, "reward": 16,
		"damage": 1, "radius": 11.0, "armor": 0.0, "color": Color("ffee58"),
		"charge_period": 3.6, "charge_time": 1.0, "charge_mult": 2.1,
		"note": "Sprints in bursts, so it crosses kill zones fast.",
	},
	"moth": {
		"name": "Cinder Moth", "hp": 62.0, "speed": 74.0, "reward": 18, "damage": 1,
		"radius": 11.0, "armor": 0.0, "color": Color("f06292"), "flying": true,
		"burn_immune": true,
		"note": "Flies straight at the base — only towers that reach up can hit it.",
	},
	"drake": {
		"name": "Iron Drake", "hp": 340.0, "speed": 52.0, "reward": 46, "damage": 3,
		"radius": 16.0, "armor": 6.0, "color": Color("7986cb"), "flying": true,
		"slow_immune": true,
		"note": "Armoured flyer that ignores the road and shrugs off slows.",
	},
	"thief": {
		"name": "Cutpurse", "hp": 64.0, "speed": 122.0, "reward": 18,
		"damage": 1, "radius": 12.0, "armor": 0.0, "color": Color("ba68c8"),
		"steal_gold": 22,
		"note": "Steals gold if it reaches your base.",
	},
	"titan": {
		"name": "Titan", "hp": 2600.0, "speed": 34.0, "reward": 420,
		"damage": 8, "radius": 30.0, "armor": 16.0, "color": Color("6a1b9a"),
		"split_into": "warden", "split_count": 2,
		"ability": "quake", "ability_period": 8.0, "ability_radius": 165.0,
		"note": "Breaks into Wardens when it falls, and stuns nearby towers as it comes.",
	},
	"boss": {
		"name": "Behemoth", "hp": 1600.0, "speed": 40.0, "reward": 280,
		"damage": 6, "radius": 25.0, "armor": 9.0, "color": Color("e53935"),
		"ability": "rally", "ability_period": 9.0, "ability_radius": 190.0,
		"note": "Bellows every few seconds and drags its escort forward with it.",
	},
}

static var TOWER_ORDER: Array = ["gun", "cannon", "frost", "tarpit", "tesla", "marksman",
		"flame", "shock", "mortar", "ballista", "laser", "mine", "tide", "torpedo",
		"wavegun", "airfield", "helipad", "command"]

## Coin cost of unlocking rank `rank + 1` of a track in the tech tree. Coins
## buy the *right* to install that rank; gold pays for it in each match.
static func track_cost(type_id: String, track: int, rank: int) -> int:
	var t: Dictionary = tracks(type_id)[track]
	# `rank` is how many are already owned, so this prices rank + 1.
	var per: Dictionary = t.get("rank_costs", {})
	if per.has(rank + 1):
		return maxi(1, int(per[rank + 1]))
	var base := float(tower_def(type_id)["cost"]) * float(t["cost_frac"]) / 3.5
	return maxi(4, int(round(base * pow(1.6, float(rank)))))


## Gold cost of installing rank `rank + 1` on a tower during a match.
static func track_gold_cost(type_id: String, track: int, rank: int) -> int:
	var t: Dictionary = tracks(type_id)[track]
	var per: Dictionary = t.get("rank_gold", {})
	if per.has(rank + 1):
		return maxi(1, int(per[rank + 1]))
	return int(float(tower_def(type_id)["cost"]) * float(t["cost_frac"]) * 0.9
			* pow(1.4, float(rank)))


## Merges every purchased rank into one modifier dictionary. Keys ending in
## `_mult` multiply per rank, `_add` sum per rank, and anything else is set
## (ints and floats keep the largest value, bools OR together).
static func mods_for(type_id: String, ranks: Array) -> Dictionary:
	var out: Dictionary = {}
	var list: Array = tracks(type_id)
	for i in mini(ranks.size(), list.size()):
		var rank: int = int(ranks[i])
		if rank <= 0:
			continue
		var per_rank: Dictionary = list[i].get("rank_mods", {})
		if per_rank.is_empty():
			_merge(out, list[i]["mods"], rank)
		else:
			# Tuning has given at least one rank its own numbers, so the
			# ranks are merged one at a time rather than raised to a power.
			for r in range(1, rank + 1):
				_merge(out, per_rank.get(r, list[i]["mods"]), 1)
		if rank >= int(list[i]["max"]) and list[i].has("capstone"):
			_merge(out, list[i]["capstone"]["mods"], 1)
	return out


static func _merge(out: Dictionary, add: Dictionary, times: int) -> void:
	for key: String in add:
		var value: Variant = add[key]
		if key.ends_with("_mult"):
			out[key] = float(out.get(key, 1.0)) * pow(float(value), float(times))
		elif key.ends_with("_add"):
			out[key] = float(out.get(key, 0.0)) + float(value) * float(times)
		elif typeof(value) == TYPE_BOOL:
			out[key] = bool(out.get(key, false)) or bool(value)
		else:
			out[key] = maxf(float(out.get(key, 0.0)), float(value))


## Plain-language description of one rank of a mod set, e.g.
## "+22% damage, +1 target". Used by the upgrade tooltips.
static func describe_mods(mods: Dictionary) -> String:
	var parts: Array = []
	for key: String in mods:
		var value: Variant = mods[key]
		match key:
			"damage_mult": parts.append("+%d%% damage" % _pct(value))
			"rate_mult": parts.append("+%d%% fire rate" % _pct(value))
			"range_mult": parts.append("+%d%% range" % _pct(value))
			"splash_mult": parts.append("+%d%% blast radius" % _pct(value))
			"unit_speed_mult": parts.append("+%d%% aircraft speed" % _pct(value))
			"income_mult": parts.append("+%d%% gold per wave" % _pct(value))
			"knockback_add": parts.append("+%d knockback" % int(value))
			"focus_add": parts.append("+%.1fx focused damage" % float(value))
			"volley_add": parts.append("+%d bolt per volley" % int(value))
			"min_range_mult": parts.append("-%d%% dead zone" % (100 - int(float(value) * 100.0)))
			"slow_add": parts.append("+%d%% slow" % int(float(value) * 100.0))
			"slow_dur_add": parts.append("+%.1fs slow" % float(value))
			"burn_add": parts.append("+%d burn damage/s" % int(float(value)))
			"shots_add": parts.append("+%d shot per volley" % int(value))
			"chain_add": parts.append("+%d target hit at once" % int(value))
			"pierce_add": parts.append("+%d enemy pierced per shot" % int(value))
			"unit_count_add": parts.append("+%d aircraft" % int(value))
			"unit_shots_add": parts.append("+%d rounds per sortie" % int(value))
			"aura_damage_add": parts.append("+%d%% damage aura" % int(float(value) * 100.0))
			"aura_rate_add": parts.append("+%d%% fire rate aura" % int(float(value) * 100.0))
			"slow_set": parts.append("slow becomes %d%%" % int(float(value) * 100.0))
			"shatter": parts.append("+%d%% damage to chilled enemies"
					% int((float(value) - 1.0) * 100.0))
			"cluster": parts.append("%d secondary blasts" % int(value))
			"pierce": parts.append("ignores armor")
			_: parts.append(key)
	return ", ".join(parts)


static func _pct(value: Variant) -> int:
	return int(round((float(value) - 1.0) * 100.0))


## In-tower prerequisite for a track: {"track": key, "rank": n} or {}.
static func track_requirement(type_id: String, track: int) -> Dictionary:
	var t: Dictionary = tracks(type_id)[track]
	return t["requires"] if t.has("requires") else {}


## Index of the track with this key, or -1.
static func track_index(type_id: String, key: String) -> int:
	var list: Array = tracks(type_id)
	for i in list.size():
		if str(list[i]["key"]) == key:
			return i
	return -1


## The capstone a track unlocks at its final rank, or {} if it has none.
static func capstone(type_id: String, track: int) -> Dictionary:
	var t: Dictionary = tracks(type_id)[track]
	return t["capstone"] if t.has("capstone") else {}
