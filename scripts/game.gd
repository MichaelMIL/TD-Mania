extends Node2D

## TD Mania — in-level controller.
##
## Owns game state (gold, lives, waves), builds the chosen level and the HUD
## in code, handles tower placement, and acts as the service locator that
## towers, aircraft and projectiles query for targets and effects.

const PREP_TIME := 14.0
const BREAK_TIME := 16.0
const SPEEDS: Array = [1.0, 2.0, 3.0]
const MENU_SCENE := "res://menu.tscn"

var level_def: Dictionary = {}
var gold: int = 200
var lives: int = 20
var wave: int = 0
var score: int = 0
var leaked_total: int = 0
var game_over: bool = false
var best_wave: int = 0
var rewarded: bool = false
## Tallies for this run, folded into the lifetime stats when it ends.
var run_stats: Dictionary = _blank_run_stats()

var in_wave: bool = false
var wave_time: float = 0.0
var spawn_queue: Array = []
var spawn_index: int = 0
var break_timer: float = PREP_TIME
var speed_index: int = 0
var paused: bool = false
var auto_start: bool = false
## Highest wave whose early-start bonus has already been paid. Parking a run
## and coming back must not hand it out again.
var early_claimed: int = 0

var placing: String = ""
var dragging: bool = false
var selected: Tower = null
var hover_cell: Vector2i = Vector2i(-99, -99)
var hovered_track: int = -1

## One entry per route: the world-space waypoints enemies walk. Single-route
## maps simply have one. `path_points` mirrors the first for convenience.
var routes: Array = []
var path_points: PackedVector2Array = PackedVector2Array()
var terrain: Dictionary = {}
var occupied: Dictionary = {}
## Command Posts only, so aura lookups do not walk the whole board.
var support_towers: Array = []
var enemies: Array = []

## Creeps bucketed by a coarse grid so a tower tests the handful of enemies
## near it instead of the whole board — the mender pass in particular used to
## be O(creeps squared). The grid is rebuilt at most once per frame (creeps
## have moved by then) and patched in place as they spawn and die. Anything
## that mutates `enemies` outside `_spawn` and the death handlers must call
## `invalidate_targeting_grid()`.
const GRID_CELL := 128.0
## Intra-frame displacement — knockback, a mid-frame spawn — that a bucket
## span is widened by so a creep is never missed for having drifted.
const GRID_SLACK := 16.0
var _grid: Dictionary = {}
var _grid_frame: int = -1
var _grid_count: int = -1
var _grid_pad: float = 0.0

var layer_map: TDMap
var layer_water: WaterLayer
var layer_enemies: Node2D
var layer_towers: Node2D
var layer_proj: Node2D
var layer_air: Node2D
var layer_fx: Node2D
var preview: RoutePreview
var cursor: Cursor

var surrender_armed: bool = false
var surrendered: bool = false
## Set when a developer cheat is used; keeps the run out of the record books.
var cheats_used: bool = false
var cheats: Cheats
var tuning_panel: TuningPanel
## Every widget lives on this; see hud.gd.
var hud: GameHUD


## Fresh tallies for a run. Also used to backfill a parked run saved before a
## counter existed, so older saves keep working.
static func _blank_run_stats() -> Dictionary:
	return {"kills": 0, "leaks": 0, "towers_built": 0, "gold_earned": 0, "damage": 0,
		"tower_kills": {}, "tower_built": {}, "enemy_kills": {}, "enemy_leaks": {},
		# Objective book-keeping: what the run did, not just how it went.
		"sold": 0, "water_built": 0, "peak_gold": 0, "cleared": 0, "untouched": true}


func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	Progress.load_state()
	# Auto-start always begins off: every run is a fresh decision.
	auto_start = false
	level_def = TDData.level()
	gold = int(TDData.level_stat(level_def, "gold") + Progress.bonus_add("start_gold_add"))
	lives = int(TDData.level_stat(level_def, "lives") + Progress.bonus_add("start_lives_add"))
	best_wave = Progress.best_wave(str(level_def["id"]))
	_build_terrain()
	_build_world()
	if TDData.resume_run:
		_restore_run(Progress.run_for(str(level_def["id"])))
	TDData.resume_run = false
	preview.announce()
	if Cheats.available():
		Cheats.reset_toggles()
		cheats = Cheats.new()
		cheats.game = self
		var cheat_layer := CanvasLayer.new()
		cheat_layer.layer = 20
		add_child(cheat_layer)
		cheat_layer.add_child(cheats)
		# The balance editor shares the debug gate: F2 opens it.
		tuning_panel = TuningPanel.new()
		tuning_panel.game = self
		cheat_layer.add_child(tuning_panel)
	hud = GameHUD.new()
	hud.game = self
	add_child(hud)
	hud.build()
	hud.btn_auto.text = "Auto: On" if auto_start else "Auto: Off"
	hud.btn_auto.modulate = Color("9ce89c") if auto_start else Color.WHITE
	hud.sync_sound_button()
	hud.refresh_info()


# ---------------------------------------------------------------- playfield

func _build_terrain() -> void:
	for y in TDData.ROWS:
		for x in TDData.COLS:
			terrain[Vector2i(x, y)] = TDData.Terrain.GROUND
	_apply_patches(level_def["water"], TDData.Terrain.WATER)
	_apply_patches(level_def["rock"], TDData.Terrain.ROCK)
	_apply_patches(level_def["ground"], TDData.Terrain.GROUND)

	for waypoints: Array in TDData.routes_of(level_def):
		var points := PackedVector2Array()
		for wp: Vector2i in waypoints:
			points.append(cell_center(wp))
		routes.append(points)
		for i in range(waypoints.size() - 1):
			var a: Vector2i = waypoints[i]
			var b: Vector2i = waypoints[i + 1]
			var delta := b - a
			var steps: int = maxi(absi(delta.x), absi(delta.y))
			var step := Vector2i(signi(delta.x), signi(delta.y))
			var c := a
			for _n in steps:
				_set_terrain(c, TDData.Terrain.PATH)
				# Diagonal runs stay one cell wide; the ribbon drawn over them
				# keeps the road visually continuous through the corner gaps.
				c += step
			_set_terrain(b, TDData.Terrain.PATH)
	path_points = routes[0]


func _apply_patches(rects: Array, kind: int) -> void:
	for r: Array in rects:
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				_set_terrain(Vector2i(x, y), kind)


func _set_terrain(c: Vector2i, kind: int) -> void:
	if in_bounds(c):
		terrain[c] = kind


func _build_world() -> void:
	layer_map = TDMap.new()
	layer_map.game = self
	add_child(layer_map)

	layer_water = WaterLayer.new()
	layer_water.game = self
	add_child(layer_water)

	layer_fx = Node2D.new()
	layer_enemies = Node2D.new()
	layer_towers = Node2D.new()
	layer_proj = Node2D.new()
	layer_air = Node2D.new()
	layer_air.z_index = 40
	for n: Node2D in [layer_fx, layer_enemies, layer_towers, layer_proj, layer_air]:
		add_child(n)

	preview = RoutePreview.new()
	preview.game = self
	preview.z_index = 30
	add_child(preview)

	cursor = Cursor.new()
	cursor.game = self
	cursor.z_index = 100
	add_child(cursor)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(float(c.x) * TDData.CELL + TDData.CELL * 0.5,
			TDData.HUD_H + float(c.y) * TDData.CELL + TDData.CELL * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / float(TDData.CELL)),
			floori((pos.y - float(TDData.HUD_H)) / float(TDData.CELL)))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < TDData.COLS and c.y < TDData.ROWS


func terrain_at(c: Vector2i) -> int:
	return int(terrain.get(c, TDData.Terrain.ROCK))


func is_path(c: Vector2i) -> bool:
	return terrain_at(c) == TDData.Terrain.PATH


## Placement rule: land towers need GROUND, Tide Callers need WATER, and
## nothing may share a cell with the path, a rock, or another tower.
## Build price after the Rapid Deployment tech discount.
func tower_cost(type_id: String) -> int:
	if Cheats.free_build:
		return 0
	return int(round(float(TDData.tower_def(type_id)["cost"])
			* Progress.bonus_mult("build_cost_mult")))


func can_place(c: Vector2i, type_id: String = "") -> bool:
	if not in_bounds(c) or occupied.has(c):
		return false
	if type_id != "" and not Progress.tower_unlocked(type_id):
		return false
	var kind := terrain_at(c)
	if type_id == "":
		return kind == TDData.Terrain.GROUND or kind == TDData.Terrain.WATER
	return kind == int(TDData.tower_def(type_id)["terrain"])


## True if any rock cell would accept a tower — it never should.
func can_place_any_rock() -> bool:
	for key: Vector2i in terrain:
		if terrain_at(key) == TDData.Terrain.ROCK:
			for type_id: String in TDData.TOWER_ORDER:
				if can_place(key, type_id):
					return true
	return false


# -------------------------------------------------------------------- input

## Drag and drop is handled here rather than through Control drag data: the
## map is a Node2D, and this way a release anywhere on screen resolves the
## drag exactly once.
func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		hover_cell = world_to_cell(get_global_mouse_position())
		cursor.queue_redraw()
		hud.refresh_creep_tip()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		dragging = false
		var pos := get_global_mouse_position()
		if map_rect().has_point(pos) and not game_over:
			_try_place(world_to_cell(pos))
		cursor.queue_redraw()


func begin_drag(type_id: String) -> void:
	if game_over or not Progress.tower_unlocked(type_id):
		return
	placing = type_id
	dragging = true
	_select(null)
	hover_cell = world_to_cell(get_global_mouse_position())
	hud.refresh_info()
	cursor.queue_redraw()


func map_rect() -> Rect2:
	return Rect2(0.0, float(TDData.HUD_H), float(TDData.MAP_W), float(TDData.MAP_H))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := world_to_cell(get_global_mouse_position())
		if c != hover_cell:
			hover_cell = c
			cursor.queue_redraw()
		hud.refresh_creep_tip()
		return
	if event is InputEventMouseButton and event.pressed:
		if game_over:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(world_to_cell(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placing = ""
			_select(null)
			hud.refresh_info()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Keys are looked up as actions, so rebinding needs no change here.
		match Progress.action_for(event.keycode):
			"cancel":
				placing = ""
				_select(null)
				hud.refresh_info()
			"start_wave":
				if not game_over and not in_wave:
					_start_wave_early()
			"pause":
				_toggle_pause()
			"speed":
				_cycle_speed()
			"auto":
				_toggle_auto()
			"upgrade":
				if selected != null:
					_upgrade_selected()
			"sell":
				if selected != null:
					_sell_selected()
			"target":
				_cycle_target_mode()
			"restart":
				if game_over:
					_restart()
			"menu":
				_to_menu()
			"cheats":
				if cheats != null:
					cheats.toggle()
			"tuning":
				if tuning_panel != null:
					tuning_panel.toggle()


func _click(c: Vector2i) -> void:
	if placing != "":
		_try_place(c)
		return
	_select(occupied.get(c) as Tower)
	hud.refresh_info()


func _pick_tower(type_id: String) -> void:
	dragging = false
	if not Progress.tower_unlocked(type_id):
		fx_text(Vector2(640.0, 150.0), "%s unlocks at level %d"
				% [TDData.TOWERS[type_id]["name"], Progress.tower_unlock_level(type_id)],
				Color("ef5350"), 18)
		return
	placing = "" if placing == type_id else type_id
	_select(null)
	hud.refresh_info()
	cursor.queue_redraw()


func _try_place(c: Vector2i) -> void:
	var d: Dictionary = TDData.tower_def(placing)
	var cost := tower_cost(placing)
	if not Progress.tower_unlocked(placing):
		fx_text(cell_center(c), "Unlocks at level %d" % Progress.tower_unlock_level(placing),
				Color("ef5350"))
		return
	if not can_place(c, placing):
		var why := "Blocked"
		if in_bounds(c) and not occupied.has(c):
			if int(d["terrain"]) == TDData.Terrain.WATER:
				why = "Water only"
			elif terrain_at(c) == TDData.Terrain.WATER:
				why = "Needs dry land"
		fx_text(cell_center(c), why, Color("ef5350"))
		return
	if gold < cost:
		fx_text(cell_center(c), "Need $%d" % cost, Color("ef5350"))
		return
	var t := _place_tower(placing, c)
	gold -= cost
	fx_ring(t.position, 40.0, d["color"])
	hud.refresh_info()


## Builds a tower on a cell and registers it. Shared by normal placement and
## the developer cheats, so bookkeeping can never drift between them.
func _place_tower(type_id: String, c: Vector2i) -> Tower:
	var t := Tower.new()
	t.game = self
	t.setup(type_id, c)
	t.position = cell_center(c)
	layer_towers.add_child(t)
	occupied[c] = t
	if t.is_support():
		support_towers.append(t)
	run_stats["towers_built"] = int(run_stats.get("towers_built", 0)) + 1
	if int(TDData.tower_def(type_id)["terrain"]) == TDData.Terrain.WATER:
		run_stats["water_built"] = int(run_stats.get("water_built", 0)) + 1
	var built: Dictionary = run_stats.get("tower_built", {})
	built[type_id] = int(built.get(type_id, 0)) + 1
	run_stats["tower_built"] = built
	return t


## Cheat helper: covers every free cell with a random tower that suits the
## terrain, each fully upgraded.
func fill_with_random_towers() -> int:
	var was_max := Cheats.max_towers
	Cheats.max_towers = true
	var placed := 0
	for key: Vector2i in terrain.keys():
		if occupied.has(key):
			continue
		var options: Array = []
		for type_id: String in TDData.TOWER_ORDER:
			if can_place(key, type_id):
				options.append(type_id)
		if options.is_empty():
			continue
		_place_tower(str(options[randi() % options.size()]), key)
		placed += 1
	Cheats.max_towers = was_max
	hud.refresh_info()
	return placed


func _select(t: Tower) -> void:
	if selected != null and is_instance_valid(selected):
		selected.show_range = false
		selected.queue_redraw()
	selected = t
	if selected != null:
		placing = ""
		dragging = false
		selected.show_range = true
		selected.queue_redraw()
	cursor.queue_redraw()


## Installs one rank with gold. -1 picks the cheapest installable track, which
## is what the quick-upgrade key uses. Ranks must first be unlocked with coins
## in the tech tree.
func _upgrade_selected(track: int = -1) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	if track < 0:
		track = selected.cheapest_track()
	if track < 0:
		fx_text(selected.position + Vector2(0.0, -34.0), "Unlock more ranks in the Tech Tree",
				Color("ffca28"), 14)
		return
	if not selected.can_upgrade_track(track):
		var why := "Unlock rank %d in the Tech Tree" % (selected.track_rank(track) + 1)
		var blocked: Dictionary = selected.track_block(track)
		if not blocked.is_empty():
			why = "Needs %s %d first" % [blocked["name"], int(blocked["rank"])]
		fx_text(selected.position + Vector2(0.0, -34.0), why, Color("ffca28"), 14)
		return
	var cost := selected.track_cost(track)
	if gold < cost:
		fx_text(selected.position, "Need $%d" % cost, Color("ef5350"))
		return
	gold -= cost
	var info: Dictionary = TDData.tracks(selected.type_id)[track]
	var was_last: bool = selected.track_rank(track) + 1 >= selected.track_max(track)
	selected.upgrade_track(track)
	fx_ring(selected.position, 46.0, Color("ffd54f"))
	Audio.play("upgrade", -6.0)
	var cap: Dictionary = TDData.capstone(selected.type_id, track)
	var label := str(cap["name"]) if was_last and not cap.is_empty() else str(info["name"])
	fx_text(selected.position + Vector2(0.0, -34.0), label, Color("ffd54f"), 16)
	hud.refresh_info()



## Cycles the selected tower between First / Last / Weakest / Strongest /
## Lowest HP / Highest HP.
func _cycle_target_mode() -> void:
	if selected == null or not is_instance_valid(selected) or selected.is_support():
		return
	selected.cycle_target_mode()
	selected.target = null
	fx_text(selected.position + Vector2(0.0, -34.0), selected.target_mode_name(),
			Color("4fc3f7"), 15)
	hud.refresh_info()


func _sell_selected() -> void:
	if selected == null:
		return
	var value := selected.sell_value()
	gold += value
	fx_text(selected.position, "+$%d" % value, Color("ffd54f"))
	fx_ring(selected.position, 40.0, Color("90a4ae"))
	Audio.play("sell", -8.0)
	run_stats["sold"] = int(run_stats.get("sold", 0)) + 1
	occupied.erase(selected.cell)
	support_towers.erase(selected)
	selected.queue_free()
	_select(null)
	hud.refresh_info()


# -------------------------------------------------------------------- waves

func _process(delta: float) -> void:
	if game_over:
		return
	_process_menders(delta)
	if in_wave:
		wave_time += delta
		while spawn_index < spawn_queue.size() \
				and float(spawn_queue[spawn_index]["t"]) <= wave_time:
			_spawn(str(spawn_queue[spawn_index]["kind"]))
			spawn_index += 1
		if spawn_index >= spawn_queue.size() and enemies.is_empty():
			_end_wave()
	else:
		break_timer -= delta
		# Auto-start leaves a moment to place a tower, then calls the wave in
		# early — which banks the early-start bonus automatically.
		if auto_start and break_timer <= BREAK_TIME - 1.5:
			_start_wave_early()
		elif break_timer <= 0.0:
			_start_wave()
	hud.update()
	# Gold peaks mid-wave, so the "hold $N" objective is watched live.
	run_stats["peak_gold"] = maxi(int(run_stats.get("peak_gold", 0)), gold)
	# Creeps walk out from under a still cursor, so the card is re-checked
	# every frame rather than only on mouse movement.
	hud.refresh_creep_tip()


## Menders top up wounded neighbours, which is what makes burst damage and
## killing them first matter.
func _process_menders(delta: float) -> void:
	for medic: Enemy in enemies:
		if not is_instance_valid(medic) or medic.dead or medic.heal <= 0.0:
			continue
		for other: Enemy in enemies_near(medic.position, medic.heal_range):
			if other == medic or other.hp >= other.max_hp:
				continue
			if medic.position.distance_to(other.position) <= medic.heal_range:
				other.mend(medic.heal * delta)


func _start_wave() -> void:
	wave += 1
	spawn_queue = _build_wave(wave)
	spawn_index = 0
	wave_time = 0.0
	in_wave = true
	Audio.play("wave_start", -6.0, 0.0)
	fx_text(Vector2(640.0, 130.0), "Wave %d" % wave, Color("ffffff"), 30)


func _start_wave_early() -> void:
	var bonus := int(maxf(0.0, break_timer) * 3.0 * Progress.bonus_mult("early_bonus_mult"))
	if wave + 1 <= early_claimed:
		# This wave's bonus was already collected before the run was parked.
		bonus = 0
	if bonus > 0:
		early_claimed = wave + 1
		gold += bonus
		fx_text(Vector2(640.0, 170.0), "Early bonus +$%d" % bonus, Color("ffd54f"), 20)
	break_timer = 0.0
	_start_wave()


## Which objectives this run has satisfied, as a bitmask over
## `TDData.objectives_for(level_def)`.
func objective_mask() -> int:
	var mask := 0
	var cleared := int(run_stats.get("cleared", 0))
	var objectives: Array = TDData.objectives_for(level_def)
	for i in objectives.size():
		var goal: Dictionary = objectives[i]
		var n := int(goal.get("n", 0))
		var met := false
		match str(goal["kind"]):
			"waves":
				met = cleared >= n
			"clean":
				met = cleared >= n and bool(run_stats.get("untouched", true))
			"no_water":
				met = cleared >= n and int(run_stats.get("water_built", 0)) == 0
			"few_towers":
				met = cleared >= n \
						and int(run_stats.get("towers_built", 0)) <= int(goal.get("towers", 10))
			"no_sell":
				met = cleared >= n and int(run_stats.get("sold", 0)) == 0
			"kills":
				met = int(run_stats.get("kills", 0)) >= n
			"rich":
				met = int(run_stats.get("peak_gold", 0)) >= n
		if met:
			mask |= 1 << i
	return mask


## Banks whatever the run has earned. Cheated runs earn nothing.
func _award_stars() -> void:
	if cheats_used:
		return
	var gained := Progress.record_stars(str(level_def["id"]), objective_mask())
	if gained == 0:
		return
	var objectives: Array = TDData.objectives_for(level_def)
	for i in objectives.size():
		if gained & (1 << i) != 0:
			fx_text(Vector2(640.0, 210.0 + float(i) * 26.0),
					"★  %s" % str(objectives[i]["text"]), Color("ffd54f"), 20)


func _end_wave() -> void:
	in_wave = false
	run_stats["cleared"] = wave
	# Gold Mines pay out between waves.
	var mined := 0
	for t: Tower in occupied.values():
		if is_instance_valid(t):
			mined += int(round(t.income()))
	if mined > 0:
		gold += mined
		run_stats["gold_earned"] = int(run_stats.get("gold_earned", 0)) + mined
		fx_text(Vector2(640.0, 170.0), "Mines paid +$%d" % mined, Color("ffca28"), 20)
	var bonus := 35 + wave * 8
	gold += bonus
	score += bonus
	break_timer = BREAK_TIME
	# The build phase is when the next wave's roads are worth showing.
	preview.announce()
	Audio.play("wave_clear", -6.0, 0.0)
	fx_text(Vector2(640.0, 130.0), "Wave %d cleared  +$%d" % [wave, bonus], Color("66bb6a"), 24)
	run_stats["peak_gold"] = maxi(int(run_stats.get("peak_gold", 0)), gold)
	_award_stars()


## Builds a flat, time-stamped spawn list for the given wave number, scaled by
## the level's difficulty knobs.
## Builds one wave from the rule table in `data.gd` — the level's area can
## bend those rules, which is what makes the Wastes feel unlike the
## Greenlands. Boss waves ignore the table and run their own shape.
func _build_wave(n: int) -> Array:
	var hp_mult := pow(1.125, float(n - 1)) * (1.0 + 0.012 * float(max(0, n - 12))) \
			* TDData.level_stat(level_def, "hp_scale")
	var speed_mult := (1.0 + 0.01 * float(n - 1)) \
			* TDData.level_stat(level_def, "speed_scale")
	var entries: Array = []
	var t := 0.0

	if n % 10 == 0:
		var boss: Dictionary = TDData.BOSS_WAVE
		var escort: Dictionary = boss["escort"]
		for i in TDData.wave_group_count(escort, n):
			entries.append({"kind": str(escort["kind"]), "t": t, "hp": hp_mult,
					"spd": speed_mult})
			t += float(escort["gap"])
		t += float(boss["pause"])
		var big := str(boss["kind"])
		if n >= int(boss["alt_from"]) and (n / 10) % int(boss["alt_cycle"]) == 0:
			big = str(boss["alt_kind"])
		entries.append({"kind": big, "t": t,
				"hp": hp_mult * (1.0 + float(boss["hp_step"]) * float(n / 10 - 1)),
				"spd": speed_mult})
		t += float(boss["after"])
		var trail: Dictionary = boss["trail"]
		for i in TDData.wave_group_count(trail, n):
			entries.append({"kind": str(trail["kind"]), "t": t, "hp": hp_mult,
					"spd": speed_mult})
			t += float(trail["gap"])
		_assign_routes(entries, wave_lanes(n))
		return entries

	for rule: Dictionary in TDData.wave_rules(str(level_def.get("area", ""))):
		if not TDData.wave_rule_active(rule, n):
			continue
		var count := TDData.wave_group_count(rule, n)
		if count <= 0:
			continue
		t += float(rule.get("lead", 0.0))
		var gap: float = maxf(float(rule.get("gap_min", 0.0)),
				float(rule["gap"]) + float(rule.get("gap_ramp", 0.0)) * float(n))
		for i in count:
			entries.append({"kind": str(rule["kind"]), "t": t, "hp": hp_mult,
					"spd": speed_mult})
			t += gap

	entries.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	_assign_routes(entries, wave_lanes(n))
	return entries


## Which lanes wave `n` arrives from. Single-road maps always answer [0]. On
## multi-lane maps most waves come down every lane, but every other wave
## picks a single lane and the choice rotates, so the preview has something
## worth reading.
func wave_lanes(n: int) -> Array:
	var count: int = maxi(1, routes.size())
	if count == 1:
		return [0]
	if n % 10 == 0:
		return range(count)          # bosses bring everything at once
	if n % 2 == 1:
		return [((n - 1) / 2) % count]
	return range(count)


## What the next wave is made of: kind -> count, in the order the roster
## defines so the readout does not jump around between waves.
func wave_composition(n: int) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in _build_wave(n):
		var kind := str(entry["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	var ordered: Dictionary = {}
	for kind: String in TDData.ENEMIES:
		if counts.has(kind):
			ordered[kind] = counts[kind]
	return ordered


## Lanes the next wave will use, for the build-phase preview.
func next_wave_lanes() -> Array:
	return wave_lanes(wave + 1) if not in_wave else wave_lanes(wave)


## Spreads a wave across the lanes it uses. Bosses take the first active lane.
func _assign_routes(entries: Array, lanes: Array) -> void:
	if lanes.is_empty():
		lanes = [0]
	var next := 0
	for entry: Dictionary in entries:
		if str(entry["kind"]) == "boss":
			entry["route"] = int(lanes[0])
			continue
		entry["route"] = int(lanes[next % lanes.size()])
		next += 1


func _spawn(kind: String) -> void:
	var entry: Dictionary = spawn_queue[spawn_index]
	var e := Enemy.new()
	var route: int = int(entry.get("route", 0)) % routes.size()
	e.route_index = route
	e.setup(kind, float(entry["hp"]), float(entry["spd"]), routes[route])
	e.died.connect(_on_enemy_died)
	e.leaked.connect(_on_enemy_leaked)
	e.split.connect(_on_enemy_split)
	layer_enemies.add_child(e)
	enemies.append(e)
	_grid_add(e)
	if kind == "boss" or kind == "titan":
		Audio.play("boss", -2.0, 0.0)


## A creep that breaks apart drops its brood where it fell, already part-way
## along the road.
func _on_enemy_split(parent: Enemy, kind: String, count: int) -> void:
	for i in count:
		var child := Enemy.new()
		child.setup(kind, parent.max_hp / float(TDData.ENEMIES[kind]["hp"]) * 0.45,
				1.0, parent.path)
		child.died.connect(_on_enemy_died)
		child.leaked.connect(_on_enemy_leaked)
		child.split.connect(_on_enemy_split)
		child.route_index = parent.route_index
		child.seg = parent.seg
		child.walk_pos = parent.walk_pos
		child.progress = parent.progress
		child.lane = parent.lane + (float(i) - float(count - 1) * 0.5) * 9.0
		child._sync_position()
		layer_enemies.add_child(child)
		enemies.append(child)
		_grid_add(child)
	fx_ring(parent.position, parent.radius * 2.0, parent.color)


func _on_enemy_died(e: Enemy) -> void:
	enemies.erase(e)
	_grid_remove(e)
	var payout := int(round(float(e.reward) * Progress.bonus_mult("kill_gold_mult")))
	gold += payout
	score += payout
	run_stats["kills"] = int(run_stats.get("kills", 0)) + 1
	run_stats["gold_earned"] = int(run_stats.get("gold_earned", 0)) + payout
	var by_kind: Dictionary = run_stats.get("enemy_kills", {})
	by_kind[e.kind] = int(by_kind.get(e.kind, 0)) + 1
	run_stats["enemy_kills"] = by_kind
	fx_ring(e.position, e.radius * 2.2, e.color)
	fx_text(e.position, "+$%d" % payout, Color("ffd54f"), 13)
	Audio.play("death", -14.0 if e.radius < 16.0 else -8.0)


func _on_enemy_leaked(e: Enemy) -> void:
	enemies.erase(e)
	_grid_remove(e)
	leaked_total += 1
	run_stats["leaks"] = int(run_stats.get("leaks", 0)) + 1
	var leaked_kinds: Dictionary = run_stats.get("enemy_leaks", {})
	leaked_kinds[e.kind] = int(leaked_kinds.get(e.kind, 0)) + 1
	run_stats["enemy_leaks"] = leaked_kinds
	if not Cheats.god_mode:
		lives -= e.leak_damage
		run_stats["untouched"] = false
	if e.steal_gold > 0 and gold > 0 and not Cheats.god_mode:
		# Cutpurses take gold on their way past.
		var stolen: int = mini(gold, e.steal_gold)
		gold -= stolen
		fx_text(e.position + Vector2(0.0, -40.0), "-$%d stolen" % stolen, Color("ba68c8"), 18)
	fx_ring(e.position, 60.0, Color("ef5350"))
	fx_text(e.position + Vector2(0.0, -20.0), "-%d" % e.leak_damage, Color("ef5350"), 20)
	Audio.play("leak", -4.0, 0.02)
	if lives <= 0:
		lives = 0
		_trigger_game_over()


## Everything needed to pick this run up again. Creeps in flight are not kept,
## so an interrupted wave simply starts over.
func _capture_run() -> Dictionary:
	var towers: Array = []
	for cell_key: Vector2i in occupied:
		var t: Tower = occupied[cell_key]
		if not is_instance_valid(t):
			continue
		towers.append({"x": cell_key.x, "y": cell_key.y, "type": t.type_id,
			"mode": t.target_mode, "kills": t.kills, "damage": t.damage_dealt,
			"invested": t.invested})
	return {
		# Leaving mid-wave forfeits the rest of it rather than replaying it,
		# so a wave can never be farmed by parking and resuming.
		"level": str(level_def["id"]), "wave": wave,
		"gold": gold, "lives": lives, "score": score, "leaked": leaked_total,
		"claimed": maxi(early_claimed, wave if in_wave else early_claimed),
		"stats": run_stats.duplicate(true), "towers": towers,
	}


## Rebuilds a parked run: board, economy and every tower that was standing.
func _restore_run(state: Dictionary) -> void:
	support_towers.clear()
	if state.is_empty():
		return
	wave = int(state.get("wave", 0))
	gold = int(state.get("gold", gold))
	lives = int(state.get("lives", lives))
	score = int(state.get("score", 0))
	leaked_total = int(state.get("leaked", 0))
	# Merge onto a blank set so a save from an older build cannot leave a
	# counter missing.
	run_stats = _blank_run_stats()
	for key: String in (state.get("stats", {}) as Dictionary):
		run_stats[key] = (state["stats"] as Dictionary)[key]
	early_claimed = int(state.get("claimed", wave))
	best_wave = Progress.best_wave(str(level_def["id"]))
	for entry: Dictionary in state.get("towers", []):
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var type_id := str(entry["type"])
		if not can_place(cell, type_id):
			continue
		var t := Tower.new()
		t.game = self
		t.setup(type_id, cell)
		t.position = cell_center(cell)
		t.target_mode = int(entry.get("mode", 0))
		t.kills = int(entry.get("kills", 0))
		t.damage_dealt = float(entry.get("damage", 0.0))
		t.invested = int(entry.get("invested", TDData.tower_def(type_id)["cost"]))
		layer_towers.add_child(t)
		occupied[cell] = t
		if t.is_support():
			support_towers.append(t)
	break_timer = PREP_TIME


## Cheat helper: ends the current wave immediately.
func finish_wave_now() -> void:
	for e in enemies.duplicate():
		if is_instance_valid(e):
			enemies.erase(e)
			e.queue_free()
	invalidate_targeting_grid()
	if in_wave:
		spawn_index = spawn_queue.size()
		_end_wave()


## Cheat helper: jumps several waves ahead without playing them.
func skip_waves(count: int) -> void:
	finish_wave_now()
	wave += count
	early_claimed = wave
	break_timer = BREAK_TIME


## Cheat helper: drops one creep of any kind onto the first lane.
func spawn_kind(kind: String) -> void:
	spawn_queue = [{"kind": kind, "t": 0.0, "hp": pow(1.125, float(maxi(1, wave) - 1)),
		"spd": 1.0, "route": 0}]
	spawn_index = 0
	_spawn(kind)
	spawn_index = 1


## Banks the run's XP and coins. Called on defeat and when leaving for the
## menu, so a run in progress is never worth nothing.
func _bank_reward() -> Dictionary:
	if rewarded:
		return {}
	rewarded = true
	var waves := maxi(0, wave - 1)
	if waves <= 0:
		return {}
	var reward := Progress.award(waves, score, int(level_def["tier"]))
	# Roll the run's tallies into the lifetime stats alongside the payout.
	var tallies := run_stats.duplicate(true)
	tallies["runs"] = 1
	tallies["waves"] = waves
	tallies["xp_earned"] = int(reward["xp"])
	tallies["coins_earned"] = int(reward["coins"])
	var damage := 0.0
	var kills_by_tower: Dictionary = {}
	for t: Tower in occupied.values():
		if not is_instance_valid(t):
			continue
		damage += t.damage_dealt
		if t.kills > 0:
			kills_by_tower[t.type_id] = int(kills_by_tower.get(t.type_id, 0)) + t.kills
	tallies["damage"] = int(damage)
	tallies["tower_kills"] = kills_by_tower
	Progress.add_run_stats(tallies)
	return reward


## Gives up the run: it pays out like a defeat and stops being resumable.
func _surrender() -> void:
	if game_over:
		return
	if not surrender_armed:
		surrender_armed = true
		hud.btn_surrender.text = "Sure?"
		hud.btn_surrender.modulate = Color("ef5350")
		return
	surrendered = true
	_trigger_game_over()


func _trigger_game_over() -> void:
	game_over = true
	placing = ""
	_select(null)
	Progress.clear_run(str(level_def["id"]))
	var reached := maxi(0, wave - 1)
	_award_stars()
	var reward := _bank_reward()
	# A cheated run never sets a record.
	var record := not cheats_used and Progress.record_wave(str(level_def["id"]), reached)
	if record:
		best_wave = reached
	var payout := "No reward — the first wave never finished."
	if not reward.is_empty():
		payout = "+%d XP   +%d coins" % [int(reward["xp"]), int(reward["coins"])]
		if bool(reward["levelled"]):
			payout += "     LEVEL %d!" % int(reward["level_after"])
	hud.lbl_over.text = "%s (%s) — you held out for %d waves.\nScore %d   Towers %d   Leaks %d\n%s\n%s\n%s" \
			% [level_def["name"], str(TDData.tier_of(level_def)["name"]), reached, score,
			occupied.size(), leaked_total,
			"New record!" if record else "Best on this map: wave %d" % best_wave, payout,
			objective_summary()]
	hud.update()
	if surrendered:
		hud.lbl_over_title.text = "Run ended"
	if cheats_used:
		hud.lbl_over_title.text += "  (cheats used)"
	Audio.play("game_over", -3.0, 0.0)
	Audio.play_music(false)
	hud.over_root.visible = true
	Engine.time_scale = 0.0


func _restart() -> void:
	Engine.time_scale = 1.0
	Progress.clear_run(str(level_def["id"]))
	TDData.resume_run = false
	get_tree().reload_current_scene()


## Leaving mid-run parks it: the map offers Continue next time. A finished or
## surrendered run has already paid out, so nothing is parked.
func _to_menu() -> void:
	Audio.play_music(false)
	if not game_over and wave >= 1:
		Progress.save_run(_capture_run())
	else:
		_bank_reward()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


# ----------------------------------------------------- combat services / fx

## Highest-progress enemy inside `rng` of `origin` — i.e. the one closest to
## the base, the standard "first" targeting priority.
## Which bucket a point falls in. Buckets are plain integer coordinates, so
## the board needs no bounds and creeps off the edge still land somewhere.
static func _grid_key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.y / GRID_CELL)))


func _rebuild_grid() -> void:
	_grid.clear()
	_grid_pad = 0.0
	for e: Enemy in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var key := _grid_key(e.position)
		if _grid.has(key):
			_grid[key].append(e)
		else:
			_grid[key] = [e]
		_grid_pad = maxf(_grid_pad, e.radius)
	_grid_frame = Engine.get_process_frames()
	_grid_count = enemies.size()


## Rebuild when the frame has turned over (creeps have moved since) or when
## the roster changed behind the grid's back.
func _ensure_grid() -> void:
	if _grid_frame != Engine.get_process_frames() or _grid_count != enemies.size():
		_rebuild_grid()


## Forces a rebuild. Call after editing `enemies` directly — the size check
## alone cannot see a swap that leaves the count unchanged.
func invalidate_targeting_grid() -> void:
	_grid_frame = -1
	_grid_count = -1


func _grid_add(e: Enemy) -> void:
	if _grid_frame != Engine.get_process_frames():
		return  # Stale anyway; the next query rebuilds it wholesale.
	var key := _grid_key(e.position)
	if _grid.has(key):
		_grid[key].append(e)
	else:
		_grid[key] = [e]
	_grid_pad = maxf(_grid_pad, e.radius)
	_grid_count = enemies.size()


func _grid_remove(e: Enemy) -> void:
	if _grid_frame != Engine.get_process_frames():
		return
	# Knockback can have moved the creep out of the bucket it was filed in;
	# missing it here is harmless, since queries skip dead creeps anyway.
	var key := _grid_key(e.position)
	if _grid.has(key):
		_grid[key].erase(e)
	_grid_count = enemies.size()


## The occupied buckets overlapping `radius` of `pos`, as the bucket arrays
## themselves — hot paths walk these directly rather than paying for a copy
## of every candidate.
func _buckets(pos: Vector2, radius: float) -> Array:
	_ensure_grid()
	var reach := radius + _grid_pad + GRID_SLACK
	var lo := _grid_key(pos - Vector2(reach, reach))
	var hi := _grid_key(pos + Vector2(reach, reach))
	var out: Array = []
	var cx := lo.x
	while cx <= hi.x:
		var cy := lo.y
		while cy <= hi.y:
			var key := Vector2i(cx, cy)
			if _grid.has(key):
				out.append(_grid[key])
			cy += 1
		cx += 1
	return out


## Every live creep that could be within `radius` of `pos`. Callers still run
## the exact distance test — this only narrows the field, and may hand back a
## few creeps just outside. The returned array is fresh, so killing what is in
## it while iterating is safe.
func enemies_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for bucket: Array in _buckets(pos, radius):
		for e: Enemy in bucket:
			if is_instance_valid(e) and not e.dead:
				out.append(e)
	return out


## How desirable a creep is under a targeting mode; the highest score wins.
static func target_score(e: Enemy, mode: int) -> float:
	match mode:
		TDData.Target.LAST: return -e.progress
		TDData.Target.WEAKEST: return -e.max_hp
		TDData.Target.STRONGEST: return e.max_hp
		TDData.Target.HURT: return -e.hp
		TDData.Target.HEALTHY: return e.hp
	return e.progress


## Best creep in range under `mode` — by default the one closest to the base.
func find_target(origin: Vector2, rng: float, min_rng: float = 0.0,
		mode: int = TDData.Target.FIRST, air_ok: bool = true) -> Enemy:
	var best: Enemy = null
	var best_score := -INF
	var min_sq := min_rng * min_rng
	for bucket: Array in _buckets(origin, rng):
		for e: Enemy in bucket:
			if not is_instance_valid(e) or e.dead:
				continue
			if e.flying and not air_ok:
				continue
			# Squared distances: no square root on the hottest loop in the game.
			var reach := rng + e.radius * 0.5
			var dist_sq := origin.distance_squared_to(e.position)
			if dist_sq > reach * reach or dist_sq < min_sq:
				continue
			var score := target_score(e, mode)
			if score > best_score:
				best_score = score
				best = e
	return best


## Up to `count` enemies in range, ordered by path progress. Used by chaining
## beams and by hovering gunships.
func find_targets(origin: Vector2, rng: float, count: int, min_rng: float = 0.0,
		mode: int = TDData.Target.FIRST, air_ok: bool = true) -> Array:
	var found: Array = []
	var min_sq := min_rng * min_rng
	for bucket: Array in _buckets(origin, rng):
		for e: Enemy in bucket:
			if not is_instance_valid(e) or e.dead:
				continue
			if e.flying and not air_ok:
				continue
			var reach := rng + e.radius * 0.5
			var dist_sq := origin.distance_squared_to(e.position)
			if dist_sq <= reach * reach and dist_sq >= min_sq:
				found.append(e)
	found.sort_custom(func(a, b): return target_score(a, mode) > target_score(b, mode))
	return found.slice(0, count)


func explode(pos: Vector2, radius: float, damage: float, color: Color,
		slow: float = 0.0, slow_dur: float = 0.0, pierce_armor: bool = false,
		shatter: float = 1.0, source: Node = null, knockback: float = 0.0,
		air_ok: bool = true) -> void:
	fx_ring(pos, radius * 1.6, color)
	Audio.play("explosion", -12.0 + minf(6.0, radius * 0.05))
	if not is_instance_valid(source):
		source = null
	# enemies_near hands back a fresh array, so kills during the blast are safe.
	for e: Enemy in enemies_near(pos, radius):
		if not is_instance_valid(e) or e.dead:
			continue
		if e.flying and not air_ok:
			continue
		var dist := pos.distance_to(e.position) - e.radius
		if dist > radius:
			continue
		var falloff: float = clampf(1.0 - dist / radius, 0.35, 1.0)
		var dmg := damage * falloff
		if shatter > 1.0 and e.slow_timer > 0.0:
			dmg *= shatter
		e.take_damage(dmg, pierce_armor, source)
		if knockback > 0.0 and is_instance_valid(e) and not e.dead:
			e.push_back(knockback * falloff)
		if slow > 0.0 and is_instance_valid(e) and not e.dead:
			e.apply_slow(slow, slow_dur)


## Best buff offered by any Command Post covering `pos`. Auras deliberately
## do not stack: the strongest post wins, so spamming them is pointless.
func aura_at(pos: Vector2) -> Dictionary:
	var best_damage := 0.0
	var best_rate := 0.0
	# Only the posts are worth checking. Walking every tower here was
	# quadratic in the number of towers on the board.
	for t: Tower in support_towers:
		if not is_instance_valid(t):
			continue
		if t.position.distance_to(pos) > t.stat("range"):
			continue
		best_damage = maxf(best_damage, t.aura_damage())
		best_rate = maxf(best_rate, t.aura_rate())
	return {"damage": best_damage, "rate": best_rate}


func fx_ring(pos: Vector2, radius: float, color: Color) -> void:
	var f := Fx.new()
	f.mode = Fx.Mode.RING
	f.position = pos
	f.radius = radius
	f.color = color
	f.life = 0.45
	layer_fx.add_child(f)


func fx_spark(pos: Vector2, color: Color) -> void:
	var f := Fx.new()
	f.mode = Fx.Mode.SPARK
	f.position = pos
	f.color = color
	f.radius = randf() * TAU
	f.life = 0.22
	layer_fx.add_child(f)


func fx_text(pos: Vector2, text: String, color: Color, size: int = 15) -> void:
	var f := Fx.new()
	f.mode = Fx.Mode.TEXT
	f.position = pos
	f.text = text
	f.color = color
	f.font_size = size
	f.life = 1.1
	f.z_index = 90
	layer_fx.add_child(f)


# ----------------------------------------------------------------------- UI


## The creep under a point, if the cursor is actually on one.
func enemy_at(pos: Vector2) -> Enemy:
	var best: Enemy = null
	var best_dist := INF
	for e: Enemy in enemies_near(pos, 8.0):
		var reach: float = e.radius + 6.0
		# Flyers sit above their shadow, so aim at where they are drawn.
		var centre: Vector2 = e.position - Vector2(0.0, e.radius * 1.15 if e.flying else 0.0)
		var dist := centre.distance_to(pos)
		if dist <= reach and dist < best_dist:
			best_dist = dist
			best = e
	return best


## The three objectives with a tick against the ones this run has managed
## and a star against the ones the account already holds.
func objective_lines(short: bool = false) -> Array:
	var mask := objective_mask()
	var held := Progress.stars_for(str(level_def["id"]))
	var out: Array = []
	for i in TDData.objectives_for(level_def).size():
		var goal: Dictionary = TDData.objectives_for(level_def)[i]
		var bit := 1 << i
		var mark := "☆"
		if mask & bit != 0:
			mark = "★"
		elif held & bit != 0:
			mark = "✓"
		out.append("%s %s" % [mark, str(goal["short"] if short else goal["text"])])
	return out


func objective_summary() -> String:
	var held := Progress.star_count(str(level_def["id"]))
	return "Stars %d/3 — %s" % [held, "  ".join(objective_lines())]


func _on_start_pressed() -> void:
	if game_over or in_wave:
		return
	_start_wave_early()


func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	hud.btn_speed.text = "%dx" % int(SPEEDS[speed_index])
	if not paused:
		Engine.time_scale = float(SPEEDS[speed_index])


## Steps the mix between full, quiet and silent, and remembers the choice.
func _cycle_volume() -> void:
	var sfx := Progress.volume("sfx")
	var step := 0
	if sfx > 0.5:
		step = 1
	elif sfx > 0.001:
		step = 2
	var levels: Array = [[0.8, 0.35], [0.35, 0.15], [0.0, 0.0]]
	var pick: Array = levels[step]
	Progress.set_volume("sfx", float(pick[0]))
	Progress.set_volume("music", float(pick[1]))
	Audio.set_volumes(float(pick[0]), float(pick[1]))
	hud.sync_sound_button()
	Audio.play("click", -10.0, 0.0)


func _toggle_auto() -> void:
	auto_start = not auto_start
	hud.btn_auto.text = "Auto: On" if auto_start else "Auto: Off"
	hud.btn_auto.modulate = Color("9ce89c") if auto_start else Color.WHITE


func _toggle_pause() -> void:
	paused = not paused
	hud.btn_pause.text = "Resume" if paused else "Pause"
	Engine.time_scale = 0.0 if paused else float(SPEEDS[speed_index])
