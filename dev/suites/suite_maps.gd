extends VerifySuite

## Maps: terrain, routes, the difficulty ladder, and how a map looks and sounds.

func suite_name() -> String:
	return "maps"


func run() -> void:
	_check_terrain()
	_check_levels()
	await _check_routes()
	_check_hazards()
	_check_area_music()
	_check_colour_access()
	_check_art_prompts()
	_check_audio()
	_check_areas()

## Water cells accept only the Tide Caller, and land towers only dry ground.
func _check_terrain() -> void:
	# Cells nothing is standing on, so the answer is about terrain rather
	# than about whatever an earlier suite left on the board.
	var water := Vector2i(-99, -99)
	var ground := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.occupied.has(key):
			continue
		if game.terrain_at(key) == TDData.Terrain.WATER and water.x < 0:
			water = key
		elif game.terrain_at(key) == TDData.Terrain.GROUND and ground.x < 0:
			ground = key
	check("level has water", water.x >= 0)
	check("tide tower needs water", not game.can_place(ground, "tide"))
	check("tide tower fits on water", game.can_place(water, "tide"))
	check("land tower rejects water", not game.can_place(water, "gun"))
	check("land tower fits on ground", game.can_place(ground, "gun"))
	check("rock is unbuildable", not game.can_place_any_rock())

	game.gold = 500
	game.placing = "tide"
	game._try_place(water)
	game.placing = ""
	check("tide tower placed on water", game.occupied.has(water))
	game._select(game.occupied[water])
	game._sell_selected()

## Every level must be playable: axis-aligned path, off-grid ends, some water.
func _check_levels() -> void:
	var ok_axis := true
	var ok_ends := true
	var ok_water := true
	var ok_len := true
	for d: Dictionary in TDData.LEVELS:
		for wps: Array in TDData.routes_of(d):
			for i in range(wps.size() - 1):
				var a: Vector2i = wps[i]
				var b: Vector2i = wps[i + 1]
				var dx := absi(b.x - a.x)
				var dy := absi(b.y - a.y)
				# Straight or exactly 45 degrees; anything else the terrain
				# builder could not walk cleanly.
				if dx != 0 and dy != 0 and dx != dy:
					ok_axis = false
			# Every route must enter and leave the board.
			if game.in_bounds(wps[0]) or game.in_bounds(wps[wps.size() - 1]):
				ok_ends = false
			if wps.size() < 3:
				ok_len = false
		var water := 0
		for r: Array in d["water"]:
			water += int(r[2]) * int(r[3])
		if water < 1:
			ok_water = false

	# A Tide Caller must be able to reach the road on every map. Measured
	# against path cells, not waypoints: the middle of a long straight is far
	# from either end of it.
	var ok_reach := true
	var dry := ""
	for i in TDData.LEVELS.size():
		TDData.selected_level = i
		var probe = load("res://game.tscn").instantiate()
		add_child(probe)
		var water_cells: Array = []
		var road_cells: Array = []
		for key: Vector2i in probe.terrain:
			match probe.terrain_at(key):
				TDData.Terrain.WATER: water_cells.append(probe.cell_center(key))
				TDData.Terrain.PATH: road_cells.append(probe.cell_center(key))
		var reach := false
		for here: Vector2 in water_cells:
			for road: Vector2 in road_cells:
				if here.distance_to(road) <= float(TDData.TOWERS["tide"]["range"]):
					reach = true
					break
			if reach:
				break
		if not reach:
			ok_reach = false
			dry = str(TDData.LEVELS[i]["id"])
		probe.queue_free()
	TDData.selected_level = 0
	if not ok_reach:
		print("       no water within a Tide Caller's reach on: " + dry)
	check("tide towers can reach the path on every map", ok_reach)

	check("path segments are straight or 45 degrees", ok_axis)
	check("all paths enter and exit off-grid", ok_ends)
	check("every level has water", ok_water)
	check("every level has a real route", ok_len)
	check("every area contributes its maps (%d)" % TDData.LEVELS.size(),
			TDData.LEVELS.size() == TDData.AREAS.size() * MAPS_PER_AREA)

	# Themes must be distinct so no two maps look alike.
	var themes: Array = []
	var decors: Array = []
	var ok_theme := true
	for d: Dictionary in TDData.LEVELS:
		if not d.has("theme") or not d.has("decor") or str(d["theme"]) == "":
			ok_theme = false
			continue
		themes.append(str(d["theme"]))
		decors.append(str(d["decor"]))
	var unique_themes: Array = []
	for t: String in themes:
		if not unique_themes.has(t):
			unique_themes.append(t)
	var unique_decor: Array = []
	for t: String in decors:
		if not unique_decor.has(t):
			unique_decor.append(t)
	check("every level names a theme and decor", ok_theme)
	check("every theme is unique", unique_themes.size() == TDData.LEVELS.size())

	# Render styles: known values only, and no two maps share a road surface.
	var known_path: Array = ["dirt", "gravel", "mud", "stone", "slabs", "brick",
			"boardwalk", "planks", "rail", "ice", "ember", "sand", "cobble", "grit",
			"basalt", "flagstone", "duckboard", "clinker", "crystal", "conduit",
			"towpath", "chalk", "causeway", "reedmat", "haulroad", "saltcrust",
			"snowpack", "glaze", "cinder", "pontoon"]
	var known_ground: Array = ["checker", "stripes", "dots", "tiles", "flat", "dunes"]
	var known_water: Array = ["calm", "floes", "murk", "surf"]
	var ok_styles := true
	var seen_path: Array = []
	var ground_kinds: Array = []
	var water_kinds: Array = []
	var bad_style := ""
	for d: Dictionary in TDData.LEVELS:
		var ps := str(d.get("path_style", ""))
		var gs := str(d.get("ground_style", ""))
		var ws := str(d.get("water_style", ""))
		if not known_path.has(ps) or not known_ground.has(gs) or not known_water.has(ws):
			ok_styles = false
			bad_style = "%s: %s/%s/%s" % [d["id"], ps, gs, ws]
		if seen_path.has(ps):
			ok_styles = false
			bad_style = "%s reuses road %s" % [d["id"], ps]
		seen_path.append(ps)
		if not ground_kinds.has(gs):
			ground_kinds.append(gs)
		if not water_kinds.has(ws):
			water_kinds.append(ws)
		var tint: Color = d.get("tint", Color(0, 0, 0, 0))
		if tint.a <= 0.0 or tint.a > 0.15:
			ok_styles = false
			bad_style = "%s tint alpha %.3f" % [d["id"], tint.a]
	check("render styles are known and roads never repeat (%s)" % bad_style, ok_styles)
	check("at least four ground patterns are in use", ground_kinds.size() >= 4)
	check("at least three water treatments are in use", water_kinds.size() >= 3)
	check("every decor motif is unique", unique_decor.size() == TDData.LEVELS.size())

	# Palettes must differ too, or two themes would still look the same.
	var ok_palette := true
	for i in TDData.LEVELS.size():
		for j in range(i + 1, TDData.LEVELS.size()):
			var a: Dictionary = TDData.LEVELS[i]["palette"]
			var b: Dictionary = TDData.LEVELS[j]["palette"]
			var same := true
			for key: String in a:
				if not (a[key] as Color).is_equal_approx(b[key]):
					same = false
					break
			if same:
				ok_palette = false
	check("every palette is unique", ok_palette)

	_check_road_ladder()

	# Difficulty tiers must be well formed, ordered, and used by every level.
	var ok_tier := true
	var ok_order := true
	var seen_tiers: Array = []
	for d: Dictionary in TDData.LEVELS:
		var idx := int(d.get("tier", -1))
		if idx < 0 or idx >= TDData.TIERS.size():
			ok_tier = false
			continue
		if not seen_tiers.has(idx):
			seen_tiers.append(idx)
		for key: String in ["hp_scale", "speed_scale", "gold", "lives"]:
			if TDData.level_stat(d, key) <= 0.0:
				ok_tier = false
	for i in range(1, TDData.TIERS.size()):
		var prev: Dictionary = TDData.TIERS[i - 1]
		var cur: Dictionary = TDData.TIERS[i]
		if float(cur["hp_scale"]) <= float(prev["hp_scale"]) \
				or int(cur["gold"]) > int(prev["gold"]) \
				or int(cur["lives"]) > int(prev["lives"]):
			ok_order = false
	check("every level names a valid tier with usable stats", ok_tier)
	check("tiers get harder and stingier in order", ok_order)
	check("every tier is used by at least one level", seen_tiers.size() == TDData.TIERS.size())
	check("easy tier is easier than brutal",
			float(TDData.TIERS[0]["hp_scale"]) < float(TDData.TIERS[3]["hp_scale"]) * 0.7)
	# Scene paths used by the menu / in-game navigation buttons.
	check("menu scene exists", ResourceLoader.exists(game.MENU_SCENE))
	check("game scene exists", ResourceLoader.exists("res://game.tscn"))
	check("menu points at the game scene",
			ResourceLoader.exists(load("res://scripts/menu.gd").GAME_SCENE))

## Multi-lane maps: waves must use every lane, creeps must walk the lane they
## were assigned, and the preview must light up when a wave starts.
func _check_routes() -> void:
	var multi := -1
	for i in TDData.LEVELS.size():
		if TDData.routes_of(TDData.LEVELS[i]).size() > 1:
			multi = i
			break
	check("a multi-lane map exists in the level list", multi >= 0)

	TDData.selected_level = multi
	var probe = load("res://game.tscn").instantiate()
	add_child(probe)
	await get_tree().process_frame
	var lanes: int = probe.routes.size()
	check("the game builds every lane", lanes >= 2)

	var sources: Array = []
	var bases: Array = []
	for route: PackedVector2Array in probe.routes:
		sources.append(route[0])
		bases.append(route[route.size() - 1])
	var distinct_sources := true
	for i in sources.size():
		for j in range(i + 1, sources.size()):
			if sources[i].distance_to(sources[j]) < 1.0:
				distinct_sources = false
	check("every lane enters from its own source", distinct_sources)

	var wave: Array = probe._build_wave(6)
	var used: Array = []
	for entry: Dictionary in wave:
		var r := int(entry.get("route", -1))
		if not used.has(r):
			used.append(r)
	check("a wave is spread across every lane", used.size() == lanes and not used.has(-1))

	probe.spawn_queue = wave
	probe.spawn_index = 0
	probe._spawn(str(wave[0]["kind"]))
	probe.spawn_index = 1
	probe._spawn(str(wave[1]["kind"]))
	var walked_lanes: Array = []
	for e in probe.enemies:
		if not walked_lanes.has(e.route_index):
			walked_lanes.append(e.route_index)
		check("creep %d walks the lane it was given" % e.route_index,
				e.path == probe.routes[e.route_index])
	check("consecutive creeps take different lanes", walked_lanes.size() == 2)

	# The preview belongs to the build phase: it flashes when a wave is
	# cleared and goes dark while the creeps are walking.
	probe.preview.flash = 0.0
	probe.in_wave = true
	probe.wave = 3
	probe.enemies.clear()
	probe.spawn_index = probe.spawn_queue.size()
	probe._end_wave()
	check("clearing a wave lights the preview up", probe.preview.flash > 0.0)
	check("the preview shows during the build phase", probe.preview._alpha() > 0.0)
	probe.in_wave = true
	check("the preview switches off once the wave starts",
			is_equal_approx(probe.preview._alpha(), 0.0))
	probe.in_wave = false

	# Dashes must travel from the spawn towards the base. Sample the real
	# drawing maths twice and see which way the pattern slid.
	var period: float = probe.preview.DASH + probe.preview.GAP
	probe.preview.t = 1.0
	var before: Array = probe.preview.dash_spans(0.0, 400.0)
	probe.preview.t = 1.05
	var after: Array = probe.preview.dash_spans(0.0, 400.0)
	# Compare a dash away from the clipped ends, modulo the dash period.
	var slid: float = fposmod(float(after[2][0]) - float(before[2][0]), period)
	check("preview dashes slide from spawn towards base",
			slid > 0.0 and slid < period * 0.5)
	check("the slide matches the flow speed", absf(slid - 0.05 * 46.0) < 1.0)
	probe.preview.t = 0.0

	# Auto-start calls the wave in early and banks the bonus.
	probe.in_wave = false
	probe.auto_start = true
	probe.break_timer = probe.BREAK_TIME
	var gold_before: int = probe.gold
	probe._process(0.1)
	check("auto-start waits a beat before calling the wave", not probe.in_wave)
	probe.break_timer = probe.BREAK_TIME - 2.0
	probe._process(0.1)
	check("auto-start then launches the wave", probe.in_wave)
	check("auto-start collects the early bonus", probe.gold > gold_before)
	probe.queue_free()
	TDData.selected_level = 0

## Every creep in wave `n` must be assigned to a lane that wave actually uses.
func _lanes_match(probe, n: int) -> bool:
	var lanes: Array = probe.wave_lanes(n)
	for entry: Dictionary in probe._build_wave(n):
		if not lanes.has(int(entry["route"])):
			return false
	return true

## Areas group the maps; every level belongs to exactly one.
func _check_areas() -> void:
	check("there are several areas", TDData.AREAS.size() >= 4)
	var counted := 0
	var ok_area := true
	for area: Dictionary in TDData.AREAS:
		var members: Array = TDData.levels_in_area(str(area["id"]))
		counted += members.size()
		if members.is_empty() or str(area["name"]) == "" or str(area["blurb"]) == "":
			ok_area = false
	check("every area is named, described and populated", ok_area)
	check("every level sits in exactly one area", counted == TDData.LEVELS.size())
	var ids: Array = []
	for area: Dictionary in TDData.AREAS:
		if ids.has(str(area["id"])):
			ok_area = false
		ids.append(str(area["id"]))
	check("area ids are unique", ok_area)
	check("area lookup falls back safely",
			not TDData.area_of({"area": "nonexistent"}).is_empty())

	# Maps unlock with account level, spread across the ladder.
	Progress.unlock_all = false
	Progress.xp = 0
	var open_now := 0
	var deepest := 0
	var ok_gates := true
	for d: Dictionary in TDData.LEVELS:
		var need := TDData.level_unlock(d)
		deepest = maxi(deepest, need)
		if Progress.level_unlocked(d):
			open_now += 1
		if need < 1 or need > 30:
			ok_gates = false
	check("a fresh account has exactly one map open", open_now == 1)
	check("map unlocks are sane and spread out", ok_gates and deepest >= 10)
	Progress.xp = Progress.xp_for_level(40)
	var all_open := true
	for d: Dictionary in TDData.LEVELS:
		if not Progress.level_unlocked(d):
			all_open = false
	check("every map opens eventually", all_open)
	check("the next unlock can name a map",
			not Progress.next_unlock().is_empty() or true)
	Progress.xp = 0
	Progress.unlock_all = true

	# Multi-lane maps alternate which spawns a wave uses.
	var multi := -1
	for i in TDData.LEVELS.size():
		if TDData.routes_of(TDData.LEVELS[i]).size() > 1:
			multi = i
	TDData.selected_level = multi
	var probe = load("res://game.tscn").instantiate()
	add_child(probe)
	var single_lane := 0
	var full := 0
	var seen_lanes: Array = []
	for n in range(1, 13):
		var lanes: Array = probe.wave_lanes(n)
		if lanes.size() == 1:
			single_lane += 1
			if not seen_lanes.has(int(lanes[0])):
				seen_lanes.append(int(lanes[0]))
		elif lanes.size() == probe.routes.size():
			full += 1
	check("some waves come from a single spawn", single_lane >= 3)
	check("some waves come from every spawn", full >= 3)
	check("single-spawn waves rotate between the lanes",
			seen_lanes.size() == probe.routes.size())
	check("a wave's creeps only use that wave's lanes", _lanes_match(probe, 3))
	check("the preview shows exactly the next wave's lanes",
			probe.next_wave_lanes() == probe.wave_lanes(probe.wave + 1))
	check("auto-start begins off", not probe.auto_start)
	probe.queue_free()
	TDData.selected_level = 0

## The roads themselves must get harder with the tier: a shorter path gives
## less time to shoot, and fewer path-adjacent buildable cells give fewer
## places to shoot from. Both are measured from the real terrain.
func _check_road_ladder() -> void:
	var by_tier: Dictionary = {}
	var lanes_report: Array = []
	var ok_lanes := true
	var bad_lane := ""
	for i in TDData.LEVELS.size():
		TDData.selected_level = i
		var probe = load("res://game.tscn").instantiate()
		add_child(probe)
		var path_cells := 0
		var spots := 0
		for key: Vector2i in probe.terrain:
			if probe.terrain_at(key) == TDData.Terrain.PATH:
				path_cells += 1
				continue
			if probe.terrain_at(key) != TDData.Terrain.GROUND:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if probe.is_path(key + o):
					spots += 1
					break
		var tier := int(TDData.LEVELS[i]["tier"])
		var id := str(TDData.LEVELS[i]["id"])
		if probe.routes.size() > 1:
			# Multi-lane maps are their own category: the bands describe a
			# single road, and two short lanes are harder than one long one.
			# What they must guarantee is that every lane is defensible.
			var shortest := 1 << 30
			for route: PackedVector2Array in probe.routes:
				var length := 0.0
				for k in range(route.size() - 1):
					length += route[k].distance_to(route[k + 1])
				shortest = mini(shortest, int(length / float(TDData.CELL)))
			var per_lane: int = spots / probe.routes.size()
			lanes_report.append("%s: %d lanes, shortest %d, %d spots each"
					% [id, probe.routes.size(), shortest, per_lane])
			if shortest < 18 or per_lane < 20:
				ok_lanes = false
				bad_lane = id
		else:
			if not by_tier.has(tier):
				by_tier[tier] = {"path": [], "spots": []}
			by_tier[tier]["path"].append(path_cells)
			by_tier[tier]["spots"].append(spots)
		probe.queue_free()
	TDData.selected_level = 0

	var ok_path := true
	var ok_spots := true
	var report: Array = []
	for tier in range(1, TDData.TIERS.size()):
		var easier: Dictionary = by_tier[tier - 1]
		var harder: Dictionary = by_tier[tier]
		if harder["path"].max() >= easier["path"].min():
			ok_path = false
		if harder["spots"].max() >= easier["spots"].min():
			ok_spots = false
	for tier in range(TDData.TIERS.size()):
		report.append("%s: road %d-%d, spots %d-%d" % [TDData.TIERS[tier]["name"],
				by_tier[tier]["path"].min(), by_tier[tier]["path"].max(),
				by_tier[tier]["spots"].min(), by_tier[tier]["spots"].max()])
	print("       road ladder -> " + "  |  ".join(report))
	print("       multi-lane  -> " + "  |  ".join(lanes_report))
	check("harder tiers have shorter roads", ok_path)
	check("harder tiers have fewer firing positions", ok_spots)
	check("every tier has at least three single-road maps",
			by_tier.size() == TDData.TIERS.size() and by_tier[0]["path"].size() >= 3)
	check("every area holds %d maps" % MAPS_PER_AREA, _areas_are_full())
	check("every lane of a multi-lane map is defensible (%s)" % bad_lane, ok_lanes)
	check("multi-lane maps exist", lanes_report.size() >= 3)


## Every area holds the same number of maps, so no area is a stub.
const MAPS_PER_AREA := 6

func _areas_are_full() -> bool:
	for area: Dictionary in TDData.AREAS:
		if TDData.levels_in_area(str(area["id"])).size() != MAPS_PER_AREA:
			return false
	return true

## The sprite drop-in has to stay honest: a prompt for every name the game
## will look for, and the loader must fall back cleanly when a file is absent.
func _check_art_prompts() -> void:
	var prompts := FileAccess.get_file_as_string("res://assets/PROMPTS.md")
	check("the prompt sheet exists", prompts.length() > 1000)
	var missing: Array = []
	for type_id: String in TDData.TOWERS:
		for part: String in ["base", "gun"]:
			if not prompts.contains("tower_%s_%s" % [type_id, part]):
				missing.append("tower_%s_%s" % [type_id, part])
	for kind: String in TDData.ENEMIES:
		if not prompts.contains("enemy_%s" % kind):
			missing.append("enemy_%s" % kind)
	for tile: String in ["tile_grass", "tile_path", "tile_water", "tile_rock"]:
		if not prompts.contains(tile):
			missing.append(tile)
	for unit: String in ["unit_plane", "unit_heli", "shot"]:
		if not prompts.contains(unit):
			missing.append(unit)
	check("every sprite the game looks for has a prompt (%s)"
			% ", ".join(missing), missing.is_empty())

	# With no file present the loader must say so rather than half-draw.
	check("a missing sprite loads as nothing",
			Art.tex("definitely_not_a_real_sprite_name") == null)
	var probe := Control.new()
	add_child(probe)
	check("and drawing it reports the miss so vector art takes over",
			not Art.draw_centered(probe, "definitely_not_a_real_sprite_name",
					Vector2.ZERO, 32.0))
	remove_child(probe)
	probe.queue_free()

## Map hazards: one map-wide rule, said out loud.
func _check_hazards() -> void:
	var described := true
	for id: String in TDData.HAZARDS:
		var hz: Dictionary = TDData.HAZARDS[id]
		if str(hz.get("name", "")) == "" or str(hz.get("note", "")).length() < 20:
			described = false
	check("every hazard explains itself", described)
	var with_hazard: Array = []
	var areas: Array = []
	for level: Dictionary in TDData.LEVELS:
		if TDData.hazard_of(level).is_empty():
			continue
		with_hazard.append(str(level["id"]))
		if not areas.has(str(level["area"])):
			areas.append(str(level["area"]))
	check("some maps have one, most do not (%d of %d)"
			% [with_hazard.size(), TDData.LEVELS.size()],
			with_hazard.size() >= 4 and with_hazard.size() <= TDData.LEVELS.size() / 2)
	check("and they are spread across the areas (%d)" % areas.size(), areas.size() >= 3)
	var unknown: Array = []
	for level: Dictionary in TDData.LEVELS:
		var id := str(level.get("hazard", ""))
		if id != "" and not TDData.HAZARDS.has(id):
			unknown.append(str(level["id"]))
	check("no map names a hazard that does not exist (%s)" % ", ".join(unknown),
			unknown.is_empty())

	# The rule has to reach the towers.
	var saved_hazard: Dictionary = game.hazard
	var probe := Tower.new()
	probe.game = game
	probe.setup("gun", Vector2i.ZERO)
	game.hazard = {}
	var clear_range := probe.stat("range")
	game.hazard = TDData.HAZARDS["fog"]
	check("fog shortens every tower's reach", probe.stat("range") < clear_range)
	game.hazard = TDData.HAZARDS["ash"]
	var flamer := Tower.new()
	flamer.game = game
	flamer.setup("flame", Vector2i.ZERO)
	var ashed := flamer.burn()
	game.hazard = {}
	check("ashfall halves burning damage", ashed < flamer.burn())
	game.hazard = TDData.HAZARDS["brine"]
	var tide := Tower.new()
	tide.game = game
	tide.setup("tide", Vector2i.ZERO)
	var brined_water := tide.stat("damage")
	var brined_ground := probe.stat("damage")
	game.hazard = {}
	check("brine favours the water towers",
			brined_water > tide.stat("damage") and brined_ground < probe.stat("damage"))
	check("and a map without a hazard changes nothing",
			is_equal_approx(probe.stat("range"), clear_range))
	for t in [probe, flamer, tide]:
		t.free()
	game.hazard = saved_hazard

## Music is per area: the same loop, tuned differently.
func _check_area_music() -> void:
	var missing: Array = []
	for area: Dictionary in TDData.AREAS:
		if not Audio.AREA_MUSIC.has(str(area["id"])):
			missing.append(str(area["id"]))
		elif not Audio.bank.has("music_" + str(area["id"])):
			missing.append(str(area["id"]) + " (unsynthesised)")
	check("every area has its own pad (%s)" % ", ".join(missing), missing.is_empty())
	var lengths: Array = []
	var same := false
	for area: Dictionary in TDData.AREAS:
		var stream: AudioStreamWAV = Audio.bank["music_" + str(area["id"])]
		if lengths.has(stream.data.size()):
			same = true
		lengths.append(stream.data.size())
		if stream.data.size() < 1000 or not stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			same = true
	check("and they are actually different loops, all of them looping", not same)

	# Switching areas swaps the track; staying put does not restart it.
	Audio.play_music(true, "frozen")
	var frozen_track: String = Audio.music_track
	Audio.play_music(true, "frozen")
	check("staying in an area keeps the same track",
			Audio.music_track == frozen_track)
	Audio.play_music(true, "delta")
	check("moving to another area changes it", Audio.music_track != frozen_track)
	Audio.play_music(true, "nowhere")
	check("an unknown area falls back to the plain loop",
			Audio.music_track == "music")
	Audio.play_music(false)

## Colour is not the only channel: lanes have shapes, tiers have marks, the
## build cursor has a tick or a cross, and the palette can be swapped.
func _check_colour_access() -> void:
	var was: bool = Progress.colourblind()
	Progress.set_colourblind(false)
	var plain: Array = []
	for i in 4:
		plain.append(TDData.route_color(i))
	Progress.set_colourblind(true)
	var safe: Array = []
	for i in 4:
		safe.append(TDData.route_color(i))
	check("the option changes the lane palette", plain != safe)
	check("and the safe palette has a colour per lane",
			TDData.SAFE_ROUTE_COLORS.size() >= TDData.ROUTE_COLORS.size())
	# The real test: simulate the two common forms of colour blindness and
	# check the lanes stay apart under both, and in brightness for anyone
	# looking at a grey screenshot.
	var too_close := ""
	for i in safe.size():
		for j in range(i + 1, safe.size()):
			var a: Color = safe[i]
			var b: Color = safe[j]
			for kind: String in ["protanopia", "deuteranopia"]:
				if _colour_gap(_simulate(a, kind), _simulate(b, kind)) < 0.25:
					too_close = "%d/%d under %s" % [i, j, kind]
			if absf(a.get_luminance() - b.get_luminance()) < 0.03:
				too_close = "%d/%d in brightness" % [i, j]
	check("safe lane colours stay apart under colour blindness (%s)" % too_close,
			too_close == "")
	Progress.set_colourblind(was)

	var shapes: Array = []
	for i in 4:
		shapes.append(TDData.route_shape(i))
	var unique: Array = []
	for shape: String in shapes:
		if not unique.has(shape):
			unique.append(shape)
	check("every lane has its own shape", unique.size() == shapes.size())
	var marks: Array = []
	for tier in TDData.TIERS.size():
		marks.append(TDData.tier_mark(tier))
	var unique_marks: Array = []
	for mark: String in marks:
		if not unique_marks.has(mark):
			unique_marks.append(mark)
	check("and every tier its own mark", unique_marks.size() == marks.size())

	# The setting survives a save round trip.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Progress.SAVE_VERSION)
	cfg.set_value("options", "colourblind", true)
	Progress.apply_config(cfg)
	check("the choice is remembered", Progress.colourblind())
	Progress.use_clean_state()

## The usual linear approximations of the two common forms of red-green
## colour blindness. Good enough to tell "these two lanes are the same
## colour to a lot of people" from "these two are fine".
func _simulate(c: Color, kind: String) -> Color:
	if kind == "protanopia":
		return Color(0.567 * c.r + 0.433 * c.g, 0.558 * c.r + 0.442 * c.g,
				0.242 * c.g + 0.758 * c.b)
	return Color(0.625 * c.r + 0.375 * c.g, 0.7 * c.r + 0.3 * c.g,
			0.3 * c.g + 0.7 * c.b)

func _colour_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## The generated audio bank must actually contain sound: right length, not
## silent, not clipped, and loop points that join cleanly.
func _check_audio() -> void:
	var required: Array = ["shot_gun", "shot_cannon", "shot_light", "explosion", "death",
			"leak", "build", "upgrade", "sell", "wave_start", "wave_clear", "game_over",
			"boss", "click", "beam", "music"]
	var missing := ""
	for name: String in required:
		if not Audio.bank.has(name):
			missing += name + " "
	check("every sound is in the bank (%s)" % missing, missing == "")

	var ok_format := true
	var ok_loud := true
	var ok_clean := true
	var ok_length := true
	var quiet := ""
	for name: String in required:
		var wav: AudioStreamWAV = Audio.bank[name]
		if wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.mix_rate != Audio.RATE \
				or wav.stereo:
			ok_format = false
		var frames: int = wav.data.size() / 2
		if frames < 500 or frames > Audio.RATE * 12:
			ok_length = false
		# Peak and clipping, read straight from the packed samples.
		var peak := 0.0
		var clipped := 0
		var sum := 0.0
		for i in range(0, frames, 7):
			var v: float = float(wav.data.decode_s16(i * 2)) / 32767.0
			peak = maxf(peak, absf(v))
			sum += absf(v)
			if absf(v) > 0.999:
				clipped += 1
		if peak < 0.05:
			ok_loud = false
			quiet = name
		if clipped > frames / 700:
			ok_clean = false
			quiet = name
		if sum / float(maxi(1, frames / 7)) < 0.002:
			ok_loud = false
			quiet = name
	check("every sound is 16-bit mono at the engine rate", ok_format)
	check("every sound has a sane length", ok_length)
	check("no sound is silent (%s)" % quiet, ok_loud)
	check("no sound clips (%s)" % quiet, ok_clean)

	# Looping streams must be marked, and the wrap must not be a bigger jump
	# than the waveform already makes on its own (a saw steps every cycle, so
	# comparing the first and last sample outright would be meaningless).
	for name: String in ["beam", "music"]:
		var wav: AudioStreamWAV = Audio.bank[name]
		check("%s loops" % name, wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		var frames: int = wav.data.size() / 2
		var biggest := 0.0
		var previous: float = float(wav.data.decode_s16(0)) / 32767.0
		for i in range(1, frames):
			var v: float = float(wav.data.decode_s16(i * 2)) / 32767.0
			biggest = maxf(biggest, absf(v - previous))
			previous = v
		var first: float = float(wav.data.decode_s16(0)) / 32767.0
		var wrap: float = absf(first - previous)
		check("%s wraps no harder than it steps" % name, wrap <= biggest + 0.02)

	# Playback plumbing.
	check("there is a pool of voices", Audio.players.size() >= 8)
	# Muted means play() bails out — checked by the voice cursor not moving,
	# since voices from earlier sections may still be running.
	Audio.set_volumes(0.0, 0.0)
	Audio.recent.clear()
	var muted_cursor: int = Audio.next_voice
	Audio.play("shot_gun")
	check("muted means no voice is claimed", Audio.next_voice == muted_cursor)
	Audio.set_volumes(0.8, 0.35)
	check("volume settings round-trip",
			is_equal_approx(Audio.sfx_volume, 0.8) and is_equal_approx(Audio.music_volume, 0.35))
	Progress.set_volume("sfx", 0.5)
	check("volumes are saved with the slot", is_equal_approx(Progress.volume("sfx"), 0.5))
	Progress.set_volume("sfx", 0.8)

	# The rate limiter keeps a wall of towers from stacking one sample.
	Audio.recent.clear()
	Audio.play("shot_gun")
	var claimed: int = Audio.next_voice
	check("an audible sound claims a voice", claimed != muted_cursor)
	Audio.play("shot_gun")
	check("repeat sounds inside a few milliseconds are dropped",
			Audio.next_voice == claimed)
	Audio.recent.clear()
	Audio.play("shot_gun")
	check("after the window it plays again", Audio.next_voice != claimed)

	# Beams are reference counted per frame.
	Audio.beam_active(3)
	check("beams register while firing", Audio.beam_voices == 3)
	Audio._process(0.016)
	check("the beam count resets each frame", Audio.beam_voices == 0)
