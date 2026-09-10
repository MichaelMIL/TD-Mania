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
static func level_stat(level: Dictionary, key: String) -> float:
	if level.has(key):
		return float(level[key])
	return float(tier_of(level)[key])


static func level() -> Dictionary:
	return LEVELS[clampi(selected_level, 0, LEVELS.size() - 1)]


## Terrain patches are [x, y, width, height] rects in grid cells. They are
## applied water -> rock -> ground (islands), and the path always wins.
static var LEVELS: Array = [
	{
		"id": "verdant",
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
]

## Tower table.
##
## Each entry carries base stats plus a list of upgrade `tracks`. A track is
## an independently purchased line of ranks (Damage, Rate, Range, Blast...)
## chosen to suit that tower, and a track's last rank may also unlock a named
## capstone effect. Track mod keys combine by suffix: `_mult` multiplies per
## rank, `_add` sums per rank, and bare keys are set once.
static var TOWERS: Dictionary = {
	"gun": {
		"name": "Gunner", "short": "Gunner", "cost": 60, "color": Color("4fc3f7"),
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
		"name": "Wave Cannon", "short": "Wave Gun", "cost": 190, "color": Color("4fc3f7"),
		"range": 175.0, "rate": 0.5, "damage": 26.0, "proj_speed": 420.0,
		"splash": 52.0, "slow": 0.25, "slow_dur": 1.0, "knockback": 46.0,
		"beam": false, "pierce_armor": false,
		"terrain": Terrain.WATER, "air": false,
		"unlock_level": 14,
		"desc": "WATER ONLY. Breaks a wave over the road that shoves everything back down it.",
		"tracks": [
			{"key": "push", "name": "Storm Surge", "max": 4, "cost_frac": 0.5,
				"mods": {"knockback_add": 16.0},
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
		"note": "Late-game boss. Breaks into Wardens when it falls.",
	},
	"boss": {
		"name": "Behemoth", "hp": 1600.0, "speed": 40.0, "reward": 280,
		"damage": 6, "radius": 25.0, "armor": 9.0, "color": Color("e53935"),
	},
}

static var TOWER_ORDER: Array = ["gun", "cannon", "frost", "tarpit", "tesla", "marksman",
		"flame", "shock", "mortar", "ballista", "laser", "mine", "tide", "torpedo",
		"wavegun", "airfield", "helipad", "command"]

static func tracks(type_id: String) -> Array:
	return TOWERS[type_id]["tracks"]


## Coin cost of unlocking rank `rank + 1` of a track in the tech tree. Coins
## buy the *right* to install that rank; gold pays for it in each match.
static func track_cost(type_id: String, track: int, rank: int) -> int:
	var t: Dictionary = tracks(type_id)[track]
	var base := float(TOWERS[type_id]["cost"]) * float(t["cost_frac"]) / 3.5
	return maxi(4, int(round(base * pow(1.6, float(rank)))))


## Gold cost of installing rank `rank + 1` on a tower during a match.
static func track_gold_cost(type_id: String, track: int, rank: int) -> int:
	var t: Dictionary = tracks(type_id)[track]
	return int(float(TOWERS[type_id]["cost"]) * float(t["cost_frac"]) * 0.9
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
		_merge(out, list[i]["mods"], rank)
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
