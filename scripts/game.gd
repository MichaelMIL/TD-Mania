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

var info_hover: Label
var track_buttons: Array = []
var palette_cards: Dictionary = {}
var palette_costs: Dictionary = {}
var creep_tip: PanelContainer
var creep_tip_label: Label
var lbl_level: Label
var lbl_lives: Label
var lbl_gold: Label
var lbl_wave: Label
var lbl_status: Label
var preview_row: HBoxContainer
var lbl_wave_note: Label
var preview_wave: int = -1
var btn_start: Button
var btn_speed: Button
var btn_pause: Button
var btn_auto: Button
var lbl_coins: Label
var tower_buttons: Dictionary = {}
var info_title: Label
var info_body: Label
var info_perk: Label
var btn_upgrade: Button
var btn_sell: Button
var btn_target: Button
var over_root: Control
var lbl_over_title: Label
var btn_surrender: Button
var btn_sound: Button
var surrender_armed: bool = false
var surrendered: bool = false
## Set when a developer cheat is used; keeps the run out of the record books.
var cheats_used: bool = false
var cheats: Cheats
var tuning_panel: TuningPanel
var lbl_over: Label


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
	_build_ui()
	btn_auto.text = "Auto: On" if auto_start else "Auto: Off"
	btn_auto.modulate = Color("9ce89c") if auto_start else Color.WHITE
	_sync_sound_button()
	_refresh_info()


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
		_refresh_creep_tip()
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
	_refresh_info()
	cursor.queue_redraw()


func map_rect() -> Rect2:
	return Rect2(0.0, float(TDData.HUD_H), float(TDData.MAP_W), float(TDData.MAP_H))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := world_to_cell(get_global_mouse_position())
		if c != hover_cell:
			hover_cell = c
			cursor.queue_redraw()
		_refresh_creep_tip()
		return
	if event is InputEventMouseButton and event.pressed:
		if game_over:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(world_to_cell(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placing = ""
			_select(null)
			_refresh_info()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				placing = ""
				_select(null)
				_refresh_info()
			KEY_SPACE:
				if not game_over and not in_wave:
					_start_wave_early()
			KEY_P:
				_toggle_pause()
			KEY_F:
				_cycle_speed()
			KEY_A:
				_toggle_auto()
			KEY_U:
				if selected != null:
					_upgrade_selected()
			KEY_X:
				if selected != null:
					_sell_selected()
			KEY_T:
				_cycle_target_mode()
			KEY_R:
				if game_over:
					_restart()
			KEY_M:
				_to_menu()
			KEY_F1:
				if cheats != null:
					cheats.toggle()
			KEY_F2:
				if tuning_panel != null:
					tuning_panel.toggle()


func _click(c: Vector2i) -> void:
	if placing != "":
		_try_place(c)
		return
	_select(occupied.get(c) as Tower)
	_refresh_info()


func _pick_tower(type_id: String) -> void:
	dragging = false
	if not Progress.tower_unlocked(type_id):
		fx_text(Vector2(640.0, 150.0), "%s unlocks at level %d"
				% [TDData.TOWERS[type_id]["name"], Progress.tower_unlock_level(type_id)],
				Color("ef5350"), 18)
		return
	placing = "" if placing == type_id else type_id
	_select(null)
	_refresh_info()
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
	_refresh_info()


## Builds a tower on a cell and registers it. Shared by normal placement and
## the developer cheats, so bookkeeping can never drift between them.
func _place_tower(type_id: String, c: Vector2i) -> Tower:
	var t := Tower.new()
	t.game = self
	t.setup(type_id, c)
	t.position = cell_center(c)
	layer_towers.add_child(t)
	occupied[c] = t
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
	_refresh_info()
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
	_refresh_info()



## Cycles the selected tower between First / Last / Weakest / Strongest /
## Lowest HP / Highest HP.
func _cycle_target_mode() -> void:
	if selected == null or not is_instance_valid(selected) or selected.is_support():
		return
	selected.cycle_target_mode()
	selected.target = null
	fx_text(selected.position + Vector2(0.0, -34.0), selected.target_mode_name(),
			Color("4fc3f7"), 15)
	_refresh_info()


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
	selected.queue_free()
	_select(null)
	_refresh_info()


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
	_update_hud()
	# Gold peaks mid-wave, so the "hold $N" objective is watched live.
	run_stats["peak_gold"] = maxi(int(run_stats.get("peak_gold", 0)), gold)
	# Creeps walk out from under a still cursor, so the card is re-checked
	# every frame rather than only on mouse movement.
	_refresh_creep_tip()


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
		btn_surrender.text = "Sure?"
		btn_surrender.modulate = Color("ef5350")
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
	lbl_over.text = "%s (%s) — you held out for %d waves.\nScore %d   Towers %d   Leaks %d\n%s\n%s\n%s" \
			% [level_def["name"], str(TDData.tier_of(level_def)["name"]), reached, score,
			occupied.size(), leaked_total,
			"New record!" if record else "Best on this map: wave %d" % best_wave, payout,
			objective_summary()]
	_update_hud()
	if surrendered:
		lbl_over_title.text = "Run ended"
	if cheats_used:
		lbl_over_title.text += "  (cheats used)"
	Audio.play("game_over", -3.0, 0.0)
	Audio.play_music(false)
	over_root.visible = true
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
	for t: Tower in occupied.values():
		if not is_instance_valid(t) or not t.is_support():
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

func _sb(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Audio.play("click", -12.0, 0.0))
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_topbar(root)
	_build_palette(root)
	_build_info_bar(root)
	_build_status_label(root)
	_build_creep_tip(root)
	_build_game_over(root)


## A card that follows the cursor over a creep. Reading the roster off the
## board beats keeping a wiki open.
func _build_creep_tip(root: Control) -> void:
	creep_tip = PanelContainer.new()
	creep_tip.add_theme_stylebox_override("panel",
			_sb(Color(0.04, 0.06, 0.09, 0.94), Color("546e7a"), 6))
	creep_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creep_tip.visible = false
	creep_tip_label = _label("", 12, Color("e3f2fd"))
	creep_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creep_tip.add_child(creep_tip_label)
	root.add_child(creep_tip)


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


## What a creep is, in one card: health, what it shrugs off, and the note
## that says how to answer it.
static func describe_enemy(e: Enemy) -> String:
	var d: Dictionary = TDData.ENEMIES.get(e.kind, {})
	var text := "%s   %d / %d hp" % [e.display_name, int(ceil(e.hp)), int(round(e.max_hp))]
	var traits: Array = []
	if e.armor > 0.0:
		traits.append("armour %d" % int(round(e.armor)))
	traits.append("%d px/s" % int(round(e.base_speed)))
	if e.flying:
		traits.append("flying")
	if e.slow_immune:
		traits.append("ignores slows")
	if e.burn_immune:
		traits.append("ignores fire")
	if e.heal > 0.0:
		traits.append("heals nearby")
	if e.steal_gold > 0:
		traits.append("steals $%d" % e.steal_gold)
	if e.split_count > 0:
		traits.append("splits into %d" % e.split_count)
	if e.charge_period > 0.0:
		traits.append("sprints in bursts")
	if e.leak_damage > 1:
		traits.append("costs %d lives" % e.leak_damage)
	text += "\n" + "  ·  ".join(traits)
	var note := str(d.get("note", ""))
	if note != "":
		text += "\n" + note
	return text


## The three objectives with a tick against the ones this run has managed
## and a star against the ones the account already holds.
func objective_lines() -> Array:
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
		out.append("%s  %s" % [mark, str(goal["text"])])
	return out


func objective_summary() -> String:
	var held := Progress.star_count(str(level_def["id"]))
	return "Stars %d/3 — %s" % [held, "  ".join(objective_lines())]


func _refresh_creep_tip() -> void:
	if creep_tip == null:
		return
	var pos := get_global_mouse_position()
	var over: Enemy = null if not map_rect().has_point(pos) else enemy_at(pos)
	if over == null:
		creep_tip.visible = false
		return
	creep_tip_label.text = describe_enemy(over)
	creep_tip.visible = true
	# Keep the card on screen, and out from under the cursor.
	var wanted := pos + Vector2(18.0, 18.0)
	var card := creep_tip.get_combined_minimum_size()
	wanted.x = minf(wanted.x, float(TDData.MAP_W) - card.x - 8.0)
	wanted.y = minf(wanted.y, float(TDData.MAP_H) - card.y - 8.0)
	creep_tip.position = wanted


func _build_topbar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.offset_right = float(TDData.MAP_W)
	bar.offset_bottom = float(TDData.HUD_H)
	bar.add_theme_stylebox_override("panel", _sb(Color("111823"), Color("2c3a52"), 0))
	root.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	lbl_level = _label(str(level_def["name"]), 17, Color("b0bec5"))
	lbl_level.custom_minimum_size.x = 148
	lbl_lives = _label("", 18, Color("ef5350"))
	lbl_lives.custom_minimum_size.x = 92
	lbl_gold = _label("", 18, Color("ffd54f"))
	lbl_gold.custom_minimum_size.x = 104
	lbl_wave = _label("", 18, Color("e3f2fd"))
	lbl_wave.custom_minimum_size.x = 86
	lbl_coins = _label("", 15, Color("ffca28"))
	lbl_coins.custom_minimum_size.x = 118
	lbl_coins.tooltip_text = "Coins banked on this save, plus what this run has earned so far"
	var tier: Dictionary = TDData.tier_of(level_def)
	var badge := _label("%s %d/4" % [str(tier["name"]).to_upper(),
			int(level_def["tier"]) + 1], 13, tier["color"])
	badge.custom_minimum_size.x = 92
	for l: Label in [lbl_level, badge, lbl_lives, lbl_gold, lbl_wave, lbl_coins]:
		row.add_child(l)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	btn_start = _button("Start Wave", 14, Vector2(116.0, 44.0))
	btn_start.pressed.connect(_on_start_pressed)
	row.add_child(btn_start)

	btn_speed = _button("1x", 14, Vector2(50.0, 44.0))
	btn_speed.pressed.connect(_cycle_speed)
	row.add_child(btn_speed)

	btn_pause = _button("Pause", 14, Vector2(74.0, 44.0))
	btn_pause.pressed.connect(_toggle_pause)
	row.add_child(btn_pause)

	btn_auto = _button("Auto: Off", 13, Vector2(88.0, 44.0))
	btn_auto.tooltip_text = "Automatically call each wave in early and collect the bonus gold"
	btn_auto.pressed.connect(_toggle_auto)
	row.add_child(btn_auto)

	btn_sound = _button("", 13, Vector2(58.0, 44.0))
	btn_sound.tooltip_text = "Cycle volume: full, quiet, muted"
	btn_sound.pressed.connect(_cycle_volume)
	row.add_child(btn_sound)

	btn_surrender = _button("Give up", 13, Vector2(80.0, 44.0))
	btn_surrender.tooltip_text = "End this run now and collect what it earned"
	btn_surrender.pressed.connect(_surrender)
	row.add_child(btn_surrender)

	var menu := _button("Menu", 14, Vector2(66.0, 44.0))
	menu.tooltip_text = "Park this run and come back to it later"
	menu.pressed.connect(_to_menu)
	row.add_child(menu)


## Right-hand build palette: one card per tower, dragged onto the map.
func _build_palette(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -float(TDData.PALETTE_W)
	panel.add_theme_stylebox_override("panel", _sb(Color("0e141d"), Color("2c3a52"), 0))
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	col.add_child(_label("BUILD", 15, Color("90a4ae")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for i in TDData.TOWER_ORDER.size():
		grid.add_child(_palette_card(TDData.TOWER_ORDER[i], i))

	var hint := _label("Drag a card onto the map,\nor click it then click a cell.", 12,
			Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)


func _palette_card(type_id: String, index: int) -> Control:
	var d: Dictionary = TDData.tower_def(type_id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(102.0, 88.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s  $%d\n%s" % [d["name"], int(d["cost"]), d["desc"]]
	card.add_theme_stylebox_override("panel", _sb(Color("16202e"), Color("32425c"), 6))
	card.gui_input.connect(_palette_input.bind(type_id))
	card.mouse_entered.connect(_refresh_info.bind(type_id))
	card.mouse_exited.connect(_refresh_info)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	card.add_child(col)

	var icon := TowerIcon.new()
	icon.type_id = type_id
	icon.custom_minimum_size = Vector2(0.0, 38.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)

	var name_row := _label(str(d.get("short", d["name"])), 12, Color("e3f2fd"))
	name_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)

	var locked := not Progress.tower_unlocked(type_id)
	var cost := _label("Lv %d" % Progress.tower_unlock_level(type_id) if locked
			else "$%d" % tower_cost(type_id), 12,
			Color("90a4ae") if locked else Color("ffd54f"))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cost)
	# Kept so a price retuned with F2 shows up without rebuilding the palette.
	palette_costs[type_id] = cost
	if locked:
		card.tooltip_text = "%s — unlocks at account level %d\n%s" % [d["name"],
				Progress.tower_unlock_level(type_id), d["desc"]]

	palette_cards[type_id] = card
	return card


func _palette_input(event: InputEvent, type_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			begin_drag(type_id)
		elif dragging:
			# Released back over the palette: keep the tower selected for
			# click-to-place instead of building anything.
			dragging = false
			cursor.queue_redraw()


## Strip along the top of the bottom bar naming what the next wave brings,
## with a note for any kind that needs a specific answer.
func _build_wave_preview(parent: Control) -> void:
	preview_row = HBoxContainer.new()
	preview_row.custom_minimum_size.y = 24
	preview_row.add_theme_constant_override("separation", 6)
	preview_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview_row)



## The advice line is rebuilt with the chips rather than kept: it lives inside
## `preview_row`, which is emptied and freed on every refresh.
func _wave_note_label(text: String) -> Label:
	var note := _label(text, 12, Color("ffca28"))
	note.clip_text = true
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return note


func _enemy_chip(kind: String, count: int) -> Control:
	var d: Dictionary = TDData.ENEMIES[kind]
	var chip := PanelContainer.new()
	var box := _sb(Color(0.05, 0.07, 0.1, 0.72), Color(d["color"]).darkened(0.2), 9)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	var dot := EnemyDot.new()
	dot.tint = d["color"]
	dot.winged = bool(d.get("flying", false))
	dot.custom_minimum_size = Vector2(12.0, 12.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var label := _label("%d %s" % [count, d["name"]], 12, Color("e3f2fd"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return chip


## Rebuilds the chips when the upcoming wave changes. During a wave the strip
## keeps its height but just states what is running, so the bar never jumps.
func _refresh_wave_preview() -> void:
	if preview_row == null:
		return
	var upcoming := wave + 1
	var key: int = -1 if game_over else (0 if in_wave else upcoming)
	if preview_wave == key:
		return
	preview_wave = key
	for child in preview_row.get_children():
		preview_row.remove_child(child)
		child.queue_free()
	lbl_wave_note = null
	if game_over:
		return
	if in_wave:
		var running := _label("Wave %d in progress" % wave, 13, Color(1, 1, 1, 0.4))
		running.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_row.add_child(running)
		return

	var composition := wave_composition(upcoming)
	var boss := composition.has("boss") or composition.has("titan")
	var heading := _label("BOSS WAVE %d" % upcoming if boss else "Wave %d incoming" % upcoming,
			13, Color("ef5350") if boss else Color(1, 1, 1, 0.65))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(heading)
	for kind: String in composition:
		preview_row.add_child(_enemy_chip(kind, int(composition[kind])))

	# One line of advice, drawn from the roster's own notes, right-aligned in
	# whatever space the chips leave.
	var notes: Array = []
	for kind: String in composition:
		var note := str(TDData.ENEMIES[kind].get("note", ""))
		if note != "":
			notes.append("%s: %s" % [TDData.ENEMIES[kind]["name"], note])
	lbl_wave_note = _wave_note_label(str(notes[0]) if not notes.is_empty() else "")
	preview_row.add_child(lbl_wave_note)


func _build_status_label(root: Control) -> void:
	lbl_status = _label("", 15, Color(1, 1, 1, 0.75))
	lbl_status.offset_right = float(TDData.MAP_W)
	lbl_status.offset_top = float(TDData.HUD_H) + 6.0
	lbl_status.offset_bottom = float(TDData.HUD_H) + 30.0
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_status)


## Bottom bar: selected tower stats on the left, one button per upgrade track
## in the middle, sell on the right.
func _build_info_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -float(TDData.BAR_H)
	bar.offset_right = float(TDData.MAP_W)
	bar.add_theme_stylebox_override("panel", _sb(Color("0b1119"), Color("2c3a52"), 0))
	root.add_child(bar)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	bar.add_child(stack)
	_build_wave_preview(stack)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 432
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	info_title = _label("", 16, Color("e3f2fd"))
	left.add_child(info_title)

	info_body = _label("", 12, Color(1, 1, 1, 0.78))
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	left.add_child(info_body)

	info_hover = _label("", 12, Color("ffd54f"))
	info_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_hover.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info_hover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(info_hover)

	var tracks_row := HBoxContainer.new()
	tracks_row.add_theme_constant_override("separation", 6)
	tracks_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tracks_row)

	for i in 4:
		var b := _button("", 12, Vector2(0.0, 74.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_upgrade_selected.bind(i))
		b.mouse_entered.connect(_hover_track.bind(i))
		b.mouse_exited.connect(_hover_track.bind(-1))
		b.visible = false
		tracks_row.add_child(b)
		track_buttons.append(b)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 124
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)

	btn_target = _button("Target: First", 12, Vector2(118.0, 34.0))
	btn_target.pressed.connect(_cycle_target_mode)
	right.add_child(btn_target)

	btn_sell = _button("Sell", 13, Vector2(118.0, 34.0))
	btn_sell.pressed.connect(_sell_selected)
	right.add_child(btn_sell)


func _build_game_over(root: Control) -> void:
	over_root = Control.new()
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.mouse_filter = Control.MOUSE_FILTER_STOP
	over_root.visible = false
	root.add_child(over_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	over_root.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -250.0
	panel.offset_right = 250.0
	panel.offset_top = -125.0
	panel.offset_bottom = 125.0
	panel.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("ef5350"), 10))
	over_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	lbl_over_title = _label("The base has fallen", 28, Color("ef5350"))
	var title := lbl_over_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	lbl_over = _label("", 15, Color(1, 1, 1, 0.85))
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lbl_over)

	var again := _button("Play again  (R)", 16, Vector2(0.0, 42.0))
	again.pressed.connect(_restart)
	col.add_child(again)

	var menu := _button("Level select  (M)", 15, Vector2(0.0, 38.0))
	menu.pressed.connect(_to_menu)
	col.add_child(menu)


func _on_start_pressed() -> void:
	if game_over or in_wave:
		return
	_start_wave_early()


func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	btn_speed.text = "%dx" % int(SPEEDS[speed_index])
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
	_sync_sound_button()
	Audio.play("click", -10.0, 0.0)


func _sync_sound_button() -> void:
	var sfx := Progress.volume("sfx")
	btn_sound.text = "Vol 3" if sfx > 0.5 else ("Vol 1" if sfx > 0.001 else "Muted")
	btn_sound.modulate = Color.WHITE if sfx > 0.001 else Color(0.6, 0.62, 0.68)


func _toggle_auto() -> void:
	auto_start = not auto_start
	btn_auto.text = "Auto: On" if auto_start else "Auto: Off"
	btn_auto.modulate = Color("9ce89c") if auto_start else Color.WHITE


func _toggle_pause() -> void:
	paused = not paused
	btn_pause.text = "Resume" if paused else "Pause"
	Engine.time_scale = 0.0 if paused else float(SPEEDS[speed_index])


func _update_hud() -> void:
	lbl_lives.text = "Lives %d" % lives
	lbl_gold.text = "Gold $%d" % gold
	lbl_wave.text = "Wave %d" % maxi(1, wave)
	# Banked coins plus what the run would pay out if it ended now.
	var pending := 0
	if not rewarded and wave > 1:
		pending = int(Progress.run_reward(wave - 1, score, int(level_def["tier"]))["coins"])
	lbl_coins.text = "%d c" % Progress.coins if pending <= 0 \
			else "%d c (+%d)" % [Progress.coins, pending]
	if game_over:
		lbl_status.text = "Base destroyed on wave %d" % wave
		btn_start.disabled = true
		btn_start.text = "Game over"
		return
	if in_wave:
		var left := spawn_queue.size() - spawn_index + enemies.size()
		lbl_status.text = "Wave %d in progress — %d enemies left" % [wave, left]
		btn_start.disabled = true
		btn_start.text = "Fighting..."
	else:
		var bonus := int(maxf(0.0, break_timer) * 3.0
				* Progress.bonus_mult("early_bonus_mult"))
		var lanes: Array = next_wave_lanes()
		var from := ""
		if routes.size() > 1:
			if lanes.size() == 1:
				from = "  ·  from Spawn %d only" % (int(lanes[0]) + 1)
			else:
				from = "  ·  from all %d spawns" % lanes.size()
		if wave + 1 <= early_claimed:
			lbl_status.text = "Next wave in %.1fs — bonus for this wave already collected%s" \
					% [maxf(0.0, break_timer), from]
		elif auto_start:
			lbl_status.text = "Auto-start armed — wave %d rolls in with a +$%d bonus%s" \
					% [wave + 1, bonus, from]
		else:
			lbl_status.text = "Next wave in %.1fs — Start now for +$%d bonus (Space)%s" \
					% [maxf(0.0, break_timer), bonus, from]
		btn_start.disabled = false
		btn_start.text = "Start Wave"
	_refresh_wave_preview()
	for type_id: String in palette_cards:
		var card: Control = palette_cards[type_id]
		if not Progress.tower_unlocked(type_id):
			card.modulate = Color(0.45, 0.5, 0.58, 0.75)
		elif placing == type_id:
			card.modulate = Color("9ce89c")
		elif gold < tower_cost(type_id):
			card.modulate = Color(1, 1, 1, 0.42)
		else:
			card.modulate = Color.WHITE
		if Progress.tower_unlocked(type_id) and palette_costs.has(type_id):
			var price := "$%d" % tower_cost(type_id)
			if palette_costs[type_id].text != price:
				palette_costs[type_id].text = price
	if selected != null and is_instance_valid(selected):
		_sync_track_buttons()


## Shows the selected tower's live stats and upgrade tracks, a hovered tower
## type's blurb, or the default hint text.
func _refresh_info(preview: String = "") -> void:
	if selected != null and is_instance_valid(selected):
		_show_selected_info()
		return

	for b: Button in track_buttons:
		b.visible = false
	btn_sell.visible = false
	btn_target.visible = false
	info_hover.text = ""

	var type_id: String = preview if preview != "" else placing
	if type_id != "":
		var d: Dictionary = TDData.tower_def(type_id)
		var where := "water only" if int(d["terrain"]) == TDData.Terrain.WATER else "dry ground"
		if not Progress.tower_unlocked(type_id):
			where = "locked until level %d" % Progress.tower_unlock_level(type_id)
		if not bool(d.get("hits_air", false)) and not bool(d.get("air", false)):
			where += ", ground only"
		info_title.text = "%s  —  $%d  (%s)" % [d["name"], tower_cost(type_id), where]
		var stats := "%s\n" % d["desc"]
		if bool(d.get("support", false)):
			stats += "Aura +%d%% damage, +%d%% fire rate   Radius %.0f" % [
				int(float(d["aura_damage"]) * 100.0), int(float(d["aura_rate"]) * 100.0),
				float(d["range"])]
		else:
			stats += "Damage %.0f   Range %.0f   Rate %.2f/s" % [
				float(d["damage"]), float(d["range"]), float(d["rate"])]
			if float(d.get("min_range", 0.0)) > 0.0:
				stats += "   Dead zone %.0f" % float(d["min_range"])
		info_body.text = stats
		_preview_track_buttons(type_id)
		return

	info_title.text = str(level_def["name"])
	info_body.text = "%s\n%s\nDrag a tower onto the map, or click a card then a cell. Click a placed tower to install ranks (U buys the cheapest, X sells). Space starts a wave early for gold. A auto, T target, P pause, F speed, M menu." \
			% [level_def["blurb"], "\n".join(objective_lines())]


func _show_selected_info() -> void:
	var d: Dictionary = selected.def()
	info_title.text = "%s  ·  %d upgrades" % [d["name"], selected.level()]

	var lines := ""
	if selected.income() > 0.0:
		lines = "Pays $%.0f at the end of every wave. Build early, profit later." \
				% selected.income()
	elif selected.is_field():
		lines = "Slows everything within %.0f by %d%% while they stand in it." % [
			selected.stat("range"), int(selected.slow_factor() * 100.0)]
	elif selected.is_pulse():
		lines = "Slams every %.1fs for %.0f damage in a %.0f radius." % [
			1.0 / maxf(0.05, selected.stat("rate")), selected.stat("damage"),
			selected.splash()]
	elif selected.is_support():
		lines = "Support aura: +%d%% damage, +%d%% fire rate to towers within %.0f.\nAuras do not stack — the strongest post wins." % [
			int(selected.aura_damage() * 100.0), int(selected.aura_rate() * 100.0),
			selected.stat("range")]
	elif selected.is_air():
		lines = "Sortie every %.1fs   Radius %.0f\n%s x%d   Payload %.0f x%d   Blast %.0f" % [
			1.0 / maxf(0.01, selected.stat("rate")), selected.stat("range"),
			str(d["unit"]).capitalize(), selected.unit_count(),
			selected.stat("damage"), selected.unit_shots(), selected.splash()]
	else:
		lines = "Damage %.0f   Range %.0f   %s" % [selected.stat("damage"),
			selected.stat("range"),
			"beam" if bool(d["beam"]) else "%.2f/s" % selected.stat("rate")]
		var extras: Array = []
		if selected.shots() > 1:
			extras.append("x%d shots" % selected.shots())
		if selected.chain() > 1:
			extras.append("hits %d" % selected.chain())
		if selected.pierce_count() > 0:
			extras.append("bores through %d" % selected.pierce_count())
		if selected.splash() > 0.0:
			extras.append("splash %.0f" % selected.splash())
		if selected.slow_factor() > 0.0:
			extras.append("slow %d%% / %.1fs" % [int(selected.slow_factor() * 100.0),
					selected.slow_duration()])
		if selected.burn() > 0.0:
			extras.append("burn %.0f/s" % selected.burn())
		if selected.min_range() > 0.0:
			extras.append("dead zone %.0f" % selected.min_range())
		if selected.pierces():
			extras.append("ignores armor")
		if selected.knockback() > 0.0:
			extras.append("knocks back %.0f" % selected.knockback())
		if selected.focus_peak() > 1.0:
			extras.append("focuses to x%.1f" % selected.focus_peak())
		if selected.volley() > 1:
			extras.append("%d bolts" % selected.volley())
		extras.append("targets %s" % selected.target_mode_name().to_lower())
		if selected.shatter() > 1.0:
			extras.append("+%d%% vs chilled" % int((selected.shatter() - 1.0) * 100.0))
		if selected.buff_damage > 0.0 or selected.buff_rate > 0.0:
			extras.append("buffed +%d%%/+%d%%" % [int(selected.buff_damage * 100.0),
					int(selected.buff_rate * 100.0)])
		lines += "\n" + "   ".join(extras)
	lines += "\nKills %d   ·   damage dealt %s" % [selected.kills,
			_short_number(selected.damage_dealt)]
	info_body.text = lines

	btn_sell.visible = true
	btn_sell.text = "Sell  +$%d" % selected.sell_value()
	btn_target.visible = true
	btn_target.disabled = selected.is_support()
	btn_target.text = "Target: %s" % selected.target_mode_name()
	btn_target.tooltip_text = "Shoot %s. Click or press T to change." \
			% TDData.TARGET_HINTS[selected.target_mode]
	_sync_track_buttons()


## Greyed-out preview of what a tower type can be upgraded into, shown while
## hovering its palette card.
func _preview_track_buttons(type_id: String) -> void:
	var list: Array = TDData.tracks(type_id)
	for i in track_buttons.size():
		var b: Button = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		var t: Dictionary = list[i]
		var cap: Dictionary = TDData.capstone(type_id, i)
		b.visible = true
		b.disabled = true
		var unlocked := Progress.track_rank_for(type_id, i)
		b.text = "%s%s\nunlocked %d/%d   $%d" % [t["name"],
				"  *" if not cap.is_empty() else "", unlocked, int(t["max"]),
				TDData.track_gold_cost(type_id, i, 0)]
		b.tooltip_text = _track_explanation(type_id, i, null)
	var caps: Array = []
	for i in list.size():
		var cap: Dictionary = TDData.capstone(type_id, i)
		if not cap.is_empty():
			caps.append(str(cap["name"]))
	if hovered_track < 0:
		info_hover.text = ("* unlocks " + ", ".join(caps)) if not caps.is_empty() else ""


## Called when the pointer enters or leaves an upgrade button (-1 = left).
func _hover_track(track: int) -> void:
	hovered_track = track
	if track < 0:
		_refresh_info()
		return
	var type_id := ""
	var tower: Tower = null
	if selected != null and is_instance_valid(selected):
		type_id = selected.type_id
		tower = selected
	elif placing != "":
		type_id = placing
	if type_id == "" or track >= TDData.tracks(type_id).size():
		return
	info_hover.text = _track_explanation(type_id, track, tower)


## What one more rank of this track actually does, in words and — when the
## tower already exists — in before/after numbers.
func _track_explanation(type_id: String, track: int, tower: Tower) -> String:
	var t: Dictionary = TDData.tracks(type_id)[track]
	var rank: int = tower.track_rank(track) if tower != null else 0
	var unlocked: int = Progress.track_rank_for(type_id, track)
	var top := int(t["max"])
	var lines: Array = []
	lines.append("%s  %d/%d — %s per rank" % [t["name"], rank, top,
			TDData.describe_mods(t["mods"])])
	if tower != null:
		var block: Dictionary = tower.track_block(track)
		if not block.is_empty():
			lines.append("Locked: needs %s at rank %d (you have %d)."
					% [block["name"], int(block["rank"]), int(block["have"])])
	else:
		var need: Dictionary = TDData.track_requirement(type_id, track)
		if not need.is_empty():
			var parent := TDData.track_index(type_id, str(need["track"]))
			lines.append("Opens after %s reaches rank %d."
					% [TDData.tracks(type_id)[parent]["name"], int(need["rank"])])
	if rank < top:
		var deltas := _rank_deltas(type_id, track, tower)
		if deltas != "":
			lines.append("This rank: " + deltas)
		if rank < mini(top, unlocked):
			lines.append("Install for $%d" % TDData.track_gold_cost(type_id, track, rank))
		else:
			lines.append("Unlock rank %d for %d coins in the Tech Tree, then install for $%d"
					% [rank + 1, TDData.track_cost(type_id, track, unlocked),
					TDData.track_gold_cost(type_id, track, rank)])
	var cap: Dictionary = TDData.capstone(type_id, track)
	if cap.is_empty():
		if rank >= top:
			lines.append("Fully upgraded.")
	elif rank >= top:
		lines.append("%s active — %s" % [cap["name"], cap["desc"]])
	elif rank + 1 >= top:
		lines.append("This rank unlocks %s — %s" % [cap["name"], cap["desc"]])
	else:
		lines.append("At %d/%d unlocks %s — %s" % [top, top, cap["name"], cap["desc"]])
	return "\n".join(lines)


## Concrete stat changes from buying one rank, measured by comparing a scratch
## copy of the tower rather than restating the data table.
func _rank_deltas(type_id: String, track: int, tower: Tower) -> String:
	var before := Tower.new()
	before.game = self
	before.setup(type_id, Vector2i.ZERO)
	var after := Tower.new()
	after.game = self
	after.setup(type_id, Vector2i.ZERO)
	if tower != null:
		before.ranks = tower.ranks.duplicate()
		after.ranks = tower.ranks.duplicate()
	after.ranks[track] = int(after.ranks[track]) + 1

	var parts: Array = []
	for spec: Array in [["Damage", "damage", 0], ["Rate", "rate", 2], ["Range", "range", 0]]:
		var a := before.stat(str(spec[1]))
		var b := after.stat(str(spec[1]))
		if not is_equal_approx(a, b):
			parts.append("%s %.*f -> %.*f" % [spec[0], int(spec[2]), a, int(spec[2]), b])
	if not is_equal_approx(before.splash(), after.splash()):
		parts.append("Blast %.0f -> %.0f" % [before.splash(), after.splash()])
	if not is_equal_approx(before.slow_factor(), after.slow_factor()):
		parts.append("Slow %d%% -> %d%%" % [int(before.slow_factor() * 100.0),
				int(after.slow_factor() * 100.0)])
	if not is_equal_approx(before.slow_duration(), after.slow_duration()):
		parts.append("Slow lasts %.1fs -> %.1fs" % [before.slow_duration(),
				after.slow_duration()])
	if not is_equal_approx(before.burn(), after.burn()):
		parts.append("Burn %.0f -> %.0f/s" % [before.burn(), after.burn()])
	if not is_equal_approx(before.min_range(), after.min_range()):
		parts.append("Dead zone %.0f -> %.0f" % [before.min_range(), after.min_range()])
	if before.shots() != after.shots():
		parts.append("Shots %d -> %d" % [before.shots(), after.shots()])
	if before.chain() != after.chain():
		parts.append("Targets %d -> %d" % [before.chain(), after.chain()])
	if before.pierce_count() != after.pierce_count():
		parts.append("Pierces %d -> %d" % [before.pierce_count(), after.pierce_count()])
	if before.unit_count() != after.unit_count():
		parts.append("Aircraft %d -> %d" % [before.unit_count(), after.unit_count()])
	if before.unit_shots() != after.unit_shots():
		parts.append("Rounds %d -> %d" % [before.unit_shots(), after.unit_shots()])
	if not is_equal_approx(before.aura_damage(), after.aura_damage()):
		parts.append("Damage aura +%d%% -> +%d%%" % [int(before.aura_damage() * 100.0),
				int(after.aura_damage() * 100.0)])
	if not is_equal_approx(before.aura_rate(), after.aura_rate()):
		parts.append("Rate aura +%d%% -> +%d%%" % [int(before.aura_rate() * 100.0),
				int(after.aura_rate() * 100.0)])
	if not is_equal_approx(before.income(), after.income()):
		parts.append("Gold per wave %.0f -> %.0f" % [before.income(), after.income()])
	if not is_equal_approx(before.knockback(), after.knockback()):
		parts.append("Knockback %.0f -> %.0f" % [before.knockback(), after.knockback()])
	if not is_equal_approx(before.focus_peak(), after.focus_peak()):
		parts.append("Focused damage x%.1f -> x%.1f" % [before.focus_peak(),
				after.focus_peak()])
	if before.volley() != after.volley():
		parts.append("Bolts %d -> %d" % [before.volley(), after.volley()])
	if not before.pierces() and after.pierces():
		parts.append("starts ignoring armor")
	before.free()
	after.free()
	return ", ".join(parts)


## 1234 -> "1.2k", for stat lines that must stay short.
func _short_number(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fm" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%.0f" % value


func _sync_track_buttons() -> void:
	var list: Array = TDData.tracks(selected.type_id)
	var hint := ""
	for i in track_buttons.size():
		var b: Button = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		b.visible = true
		var t: Dictionary = list[i]
		var rank := selected.track_rank(i)
		var top := selected.track_max(i)
		var cap_rank := selected.track_cap(i)
		var capstone: Dictionary = TDData.capstone(selected.type_id, i)
		var star := "  *" if not capstone.is_empty() else ""
		var blocked: Dictionary = selected.track_block(i)
		if rank >= top:
			b.disabled = true
			b.text = "%s%s\n%d/%d  MAX" % [t["name"], star, rank, top]
		elif not blocked.is_empty():
			b.disabled = true
			b.text = "%s\n%d/%d  needs %s %d" % [t["name"], rank, top, blocked["name"],
					int(blocked["rank"])]
		elif rank >= cap_rank:
			# Installed everything the account has unlocked; the next rank is
			# a coin purchase in the tech tree.
			b.disabled = true
			var state: Dictionary = Progress.track_buy_state(selected.type_id, i)
			if not bool(state["level_ok"]):
				b.text = "%s\n%d/%d  Lv %d" % [t["name"], rank, top,
						Progress.track_unlock_level(selected.type_id, i)]
			else:
				b.text = "%s\n%d/%d  unlock %d c" % [t["name"], rank, top,
						int(state["cost"])]
				hint = "Unlock more ranks with coins in the Tech Tree."
		else:
			var cost := selected.track_cost(i)
			b.disabled = gold < cost
			b.text = "%s%s\n%d/%d   $%d" % [t["name"], star, rank, top, cost]
			if rank + 1 >= top and not capstone.is_empty():
				hint = "* Next rank of %s unlocks %s: %s" % [t["name"], capstone["name"],
						capstone["desc"]]
		b.tooltip_text = _track_explanation(selected.type_id, i, selected)
	if hovered_track < 0:
		info_hover.text = hint
