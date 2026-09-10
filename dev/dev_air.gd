extends Node

## Air-support regression harness.
##
## Launches an Airfield and a Helipad against slow, very tanky creeps — the
## case that used to make aircraft orbit forever — and asserts that every
## sortie takes off, deals damage, lands, and is replaced by another.

var game: Node
var fails: int = 0
var damage_dealt: float = 0.0
var tracked: Array = []
var max_alive: float = 0.0
var pads: Dictionary = {}


func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])


func _ready() -> void:
	# Isolated account: full unlocks, no tech, and nothing written to disk.
	Progress.use_clean_state()
	TDData.selected_level = 0
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	game.gold = 5000
	for pair in [["airfield", Vector2i(1, 3)], ["helipad", Vector2i(4, 6)]]:
		game.placing = pair[0]
		game._try_place(pair[1])
		game.placing = ""
		pads[pair[0]] = game.occupied[pair[1]]
	check("both air towers placed", pads.size() == 2)

	Engine.time_scale = 4.0
	var elapsed := 0.0
	while elapsed < 40.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_top_up_enemies()
		_sample()
	Engine.time_scale = 1.0

	var air: Tower = pads["airfield"]
	var heli: Tower = pads["helipad"]
	# 40s of game time at one sortie per 5.5s / 7.1s should be several each.
	check("airfield flew repeat sorties", air.sorties_flown >= 4)
	check("helipad flew repeat sorties", heli.sorties_flown >= 3)
	check("bombers all came home", air.sorties_landed >= air.sorties_flown - 1)
	check("gunships all came home", heli.sorties_landed >= heli.sorties_flown - 1)
	check("air support actually dealt damage", damage_dealt > 0.0)
	check("no aircraft outlived its sortie limit", max_alive <= Aircraft.MAX_SORTIE)
	check("no squadron slot leaked",
			air.units.size() <= air.unit_count() and heli.units.size() <= heli.unit_count())
	print("[AIR] airfield %d/%d  helipad %d/%d (flown/landed)  damage=%.0f  longest=%.1fs (%d failures)"
			% [air.sorties_flown, air.sorties_landed, heli.sorties_flown,
			heli.sorties_landed, damage_dealt, max_alive, fails])
	get_tree().quit()


## Parks one stationary, effectively unkillable creep beside each pad. A
## target that never moves is the worst case for a banking aircraft: if the
## turn radius exceeds the arrival threshold it orbits forever instead of
## attacking, which is exactly the bug this harness guards.
func _top_up_enemies() -> void:
	for key: String in pads:
		var pad = pads[key]
		var covered := false
		for e in game.enemies:
			if is_instance_valid(e) and pad.position.distance_to(e.position) < 150.0:
				covered = true
				break
		if covered:
			continue
		var point := _nearest_path_point(pad.position)
		var creep := Enemy.new()
		creep.setup("tank", 400.0, 1.0, game.path_points)
		creep.died.connect(game._on_enemy_died)
		creep.leaked.connect(game._on_enemy_leaked)
		game.layer_enemies.add_child(creep)
		# Pin it in place: a one-segment path means Enemy._sync_position keeps
		# it exactly here instead of snapping it back to the map spawn.
		creep.path = PackedVector2Array([point, point + Vector2(0.01, 0.0)])
		creep.walk_pos = point
		creep.lane = 0.0
		creep.seg = 0
		creep.base_speed = 0.0
		creep.position = point
		game.enemies.append(creep)
		game.invalidate_targeting_grid()


## Closest point of the creep path to `from`, so parked test creeps sit where
## a real creep would walk.
func _nearest_path_point(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_dist := INF
	for key: Vector2i in game.terrain:
		if game.terrain_at(key) != TDData.Terrain.PATH:
			continue
		var c: Vector2 = game.cell_center(key)
		if from.distance_to(c) < best_dist:
			best_dist = from.distance_to(c)
			best = c
	return best


func _sample() -> void:
	for e in game.enemies:
		if is_instance_valid(e) and not tracked.has(e):
			tracked.append(e)
	damage_dealt = 0.0
	for e in tracked:
		if is_instance_valid(e):
			damage_dealt += e.max_hp - e.hp
	for key: String in pads:
		for craft in pads[key].units:
			if is_instance_valid(craft):
				max_alive = maxf(max_alive, craft.sortie_time)
