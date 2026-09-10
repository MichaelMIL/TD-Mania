extends VerifySuite

## Combat: what shoots what, and what the creeps do about it.

func suite_name() -> String:
	return "combat"


func run() -> void:
	_check_combat_extras()
	_check_air()
	_check_targeting()
	_check_targeting_grid()
	_check_knockback_fatigue()
	_check_boss_abilities()
	_check_flyers()
	_check_board_tooltips()
	_check_enemy_kinds()

## Targeting modes must each pick the creep they promise.
func _check_targeting() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var here := Vector2(500.0, 400.0)

	# Three creeps: a wounded weakling at the front, a fresh tank at the back.
	var lead := Enemy.new()
	lead.setup("runner", 1.0, 1.0, game.routes[0])
	lead.position = here + Vector2(40.0, 0.0)
	lead.progress = 900.0
	lead.hp = lead.max_hp * 0.2
	var tank := Enemy.new()
	tank.setup("tank", 1.0, 1.0, game.routes[0])
	tank.position = here + Vector2(-40.0, 0.0)
	tank.progress = 100.0
	var middle := Enemy.new()
	middle.setup("grunt", 1.0, 1.0, game.routes[0])
	middle.position = here
	middle.progress = 500.0
	middle.hp = middle.max_hp * 0.9
	for e: Enemy in [lead, tank, middle]:
		add_child(e)
		game.enemies.append(e)
		game.invalidate_targeting_grid()

	check("First picks the creep nearest the base",
			game.find_target(here, 300.0, 0.0, TDData.Target.FIRST) == lead)
	check("Last picks the newest arrival",
			game.find_target(here, 300.0, 0.0, TDData.Target.LAST) == tank)
	check("Weakest picks the smallest health pool",
			game.find_target(here, 300.0, 0.0, TDData.Target.WEAKEST) == lead)
	check("Strongest picks the biggest health pool",
			game.find_target(here, 300.0, 0.0, TDData.Target.STRONGEST) == tank)
	check("Lowest HP picks the most wounded",
			game.find_target(here, 300.0, 0.0, TDData.Target.HURT) == lead)
	check("Highest HP picks the healthiest",
			game.find_target(here, 300.0, 0.0, TDData.Target.HEALTHY) == tank)
	var chain: Array = game.find_targets(here, 300.0, 2, 0.0, TDData.Target.LAST)
	check("chaining follows the same order", chain.size() == 2 and chain[0] == tank
			and chain[1] == middle)
	check("modes still respect range",
			game.find_target(Vector2(-900.0, 0.0), 100.0, 0.0, TDData.Target.FIRST) == null)

	var t := Tower.new()
	t.game = game
	t.setup("gun", Vector2i.ZERO)
	check("towers start on First", t.target_mode == TDData.Target.FIRST)
	var seen: Array = []
	for i in TDData.TARGET_NAMES.size():
		if not seen.has(t.target_mode_name()):
			seen.append(t.target_mode_name())
		t.cycle_target_mode()
	check("cycling visits every mode and wraps",
			seen.size() == TDData.TARGET_NAMES.size() and t.target_mode == TDData.Target.FIRST)
	t.free()

	for e in [lead, tank, middle]:
		game.enemies.erase(e)
		game.invalidate_targeting_grid()
		e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

## Bucketing creeps is a speed change only: every query must answer exactly
## what the old full scan answered.
func _check_targeting_grid() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910
	var kinds: Array = TDData.ENEMIES.keys()
	var mob: Array = []
	for i in 90:
		var e := Enemy.new()
		e.setup(str(kinds[i % kinds.size()]), 1.0, 1.0, game.routes[0])
		# Spread them past the edges too, so off-board buckets are exercised.
		e.position = Vector2(rng.randf_range(-90.0, float(TDData.MAP_W) + 90.0),
				rng.randf_range(-90.0, float(TDData.MAP_H) + 90.0))
		e.progress = rng.randf() * 1000.0
		e.hp = e.max_hp * rng.randf_range(0.1, 1.0)
		add_child(e)
		mob.append(e)
		game.enemies.append(e)
	game.invalidate_targeting_grid()

	var culled := 0
	var picked_wrong := 0
	var chain_wrong := 0
	for probe in 150:
		var origin := Vector2(rng.randf_range(0.0, float(TDData.MAP_W)),
				rng.randf_range(0.0, float(TDData.MAP_H)))
		var reach := rng.randf_range(60.0, 420.0)
		var near: Array = game.enemies_near(origin, reach)
		for e: Enemy in mob:
			if origin.distance_to(e.position) <= reach + e.radius * 0.5 and not near.has(e):
				culled += 1
		var mode: int = rng.randi_range(0, TDData.TARGET_NAMES.size() - 1)
		var want: Enemy = _brute_target(origin, reach, mode)
		var got: Enemy = game.find_target(origin, reach, 0.0, mode)
		# Equal-scoring creeps are separated only by iteration order, so the
		# comparison is on desirability rather than identity.
		if (want == null) != (got == null):
			picked_wrong += 1
		elif want != null and not is_equal_approx(game.target_score(want, mode),
				game.target_score(got, mode)):
			picked_wrong += 1
		var want_many: Array = _brute_targets(origin, reach, 4, mode)
		var got_many: Array = game.find_targets(origin, reach, 4, 0.0, mode)
		if want_many.size() != got_many.size():
			chain_wrong += 1
		else:
			for i in want_many.size():
				if not is_equal_approx(game.target_score(want_many[i], mode),
						game.target_score(got_many[i], mode)):
					chain_wrong += 1
					break
	check("the grid never culls a creep that is in range", culled == 0)
	check("grid targeting agrees with a full scan over 150 probes", picked_wrong == 0)
	check("grid chain targeting agrees with a full scan", chain_wrong == 0)

	# Book-keeping: a kill inside the frame, and a roster edited from outside.
	var victim: Enemy = mob[0]
	check("a live creep is in its bucket",
			game.enemies_near(victim.position, 8.0).has(victim))
	victim.dead = true
	check("a creep killed mid-frame stops being a candidate",
			not game.enemies_near(victim.position, 8.0).has(victim))
	var late := Enemy.new()
	late.setup("grunt", 1.0, 1.0, game.routes[0])
	late.position = Vector2(float(TDData.MAP_W) * 0.5, float(TDData.MAP_H) * 0.5)
	add_child(late)
	game.enemies.append(late)
	check("a creep appended from outside is still found",
			game.enemies_near(late.position, 8.0).has(late))
	mob.append(late)

	# Splash damage must reach the same creeps the old full scan reached.
	var centre := Vector2(float(TDData.MAP_W) * 0.5, float(TDData.MAP_H) * 0.5)
	var blast := 220.0
	var expected: Array = []
	for e: Enemy in game.enemies:
		if is_instance_valid(e) and not e.dead \
				and centre.distance_to(e.position) - e.radius <= blast:
			expected.append(e)
	var reached: Array = []
	for e: Enemy in game.enemies_near(centre, blast):
		if centre.distance_to(e.position) - e.radius <= blast:
			reached.append(e)
	check("a blast covers the same creeps a full scan would (%d)" % expected.size(),
			expected.size() == reached.size())

	for e: Enemy in mob:
		game.enemies.erase(e)
		e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

## A full scan of the roster, kept as the reference the bucketed grid must
## agree with.
func _brute_target(origin: Vector2, reach: float, mode: int) -> Enemy:
	var best: Enemy = null
	var best_score := -INF
	for e: Enemy in game.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		if origin.distance_to(e.position) > reach + e.radius * 0.5:
			continue
		var s: float = game.target_score(e, mode)
		if s > best_score:
			best_score = s
			best = e
	return best

func _brute_targets(origin: Vector2, reach: float, count: int, mode: int) -> Array:
	var found: Array = []
	for e: Enemy in game.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		if origin.distance_to(e.position) <= reach + e.radius * 0.5:
			found.append(e)
	found.sort_custom(func(a, b): return game.target_score(a, mode) > game.target_score(b, mode))
	return found.slice(0, count)

## Flyers ignore the road and only half the roster can shoot at them.
func _check_flyers() -> void:
	var kinds: Array = []
	for kind: String in TDData.ENEMIES:
		if bool(TDData.ENEMIES[kind].get("flying", false)):
			kinds.append(kind)
	check("the roster has flyers (%d)" % kinds.size(), kinds.size() >= 2)

	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var road: PackedVector2Array = game.routes[0]
	var flyer := Enemy.new()
	flyer.setup(str(kinds[0]), 1.0, 1.0, road)
	add_child(flyer)
	check("a flyer's path is a straight line to the base",
			flyer.path.size() == 2 and flyer.path[0] == road[0]
			and flyer.path[1] == road[road.size() - 1])
	check("which is shorter than the road it ignores",
			road.size() < 3 or flyer.path[0].distance_to(flyer.path[1]) < _road_length(road))
	var walker := Enemy.new()
	walker.setup("grunt", 1.0, 1.0, road)
	add_child(walker)
	check("a ground creep still walks every corner", walker.path.size() == road.size())

	# Put both in the same place and see who can shoot what.
	var spot := Vector2(400.0, 400.0)
	flyer.position = spot
	walker.position = spot
	game.enemies.append(flyer)
	game.enemies.append(walker)
	game.invalidate_targeting_grid()

	var ground_only := Tower.new()
	ground_only.game = game
	ground_only.setup("cannon", Vector2i.ZERO)
	ground_only.position = spot
	var anti_air := Tower.new()
	anti_air.game = game
	anti_air.setup("gun", Vector2i.ZERO)
	anti_air.position = spot
	check("a ground tower knows it cannot reach up", not ground_only.hits_air())
	check("and an anti-air one knows it can", anti_air.hits_air())
	check("the ground tower picks the walker, not the flyer",
			game.find_target(spot, 300.0, 0.0, TDData.Target.FIRST,
					ground_only.hits_air()) == walker)
	var seen: Array = game.find_targets(spot, 300.0, 8, 0.0, TDData.Target.FIRST,
			ground_only.hits_air())
	check("and never sees it in a chain either", not seen.has(flyer))
	check("the anti-air tower sees both",
			game.find_targets(spot, 300.0, 8, 0.0, TDData.Target.FIRST,
					anti_air.hits_air()).size() == 2)

	# Splash inherits the firer's reach: a shell cannot swat something overhead.
	var before := flyer.hp
	var walker_before := walker.hp
	game.explode(spot, 120.0, 50.0, Color.WHITE, 0.0, 0.0, false, 1.0, null, 0.0, false)
	check("a ground blast leaves flyers alone", is_equal_approx(flyer.hp, before))
	check("while still hitting what is on the ground", walker.hp < walker_before)
	game.explode(spot, 120.0, 50.0, Color.WHITE, 0.0, 0.0, false, 1.0, null, 0.0, true)
	check("an anti-air blast does reach them", flyer.hp < before)

	# The defence has to be mixed, but not impossible.
	var can := 0
	for type_id: String in TDData.TOWERS:
		var probe := Tower.new()
		probe.game = game
		probe.setup(type_id, Vector2i.ZERO)
		if probe.hits_air():
			can += 1
		probe.free()
	check("roughly half the roster can answer an air wave (%d of %d)"
			% [can, TDData.TOWERS.size()],
			can >= 5 and can <= TDData.TOWERS.size() - 4)

	# And they have to actually turn up in waves.
	var air_waves := 0
	for n in range(1, 31):
		var comp: Dictionary = game.wave_composition(n)
		for kind: String in kinds:
			if comp.has(kind):
				air_waves += 1
				break
	check("air waves appear through the run (%d of 30)" % air_waves, air_waves >= 6)

	ground_only.free()
	anti_air.free()
	game.enemies.erase(flyer)
	game.enemies.erase(walker)
	flyer.queue_free()
	walker.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

func _road_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total

## Bosses do something rather than only being large.
func _check_boss_abilities() -> void:
	var with_ability: Array = []
	for kind: String in TDData.ENEMIES:
		if str(TDData.ENEMIES[kind].get("ability", "")) != "":
			with_ability.append(kind)
	check("the heavies have abilities (%s)" % ", ".join(with_ability),
			with_ability.has("boss") and with_ability.has("titan"))
	var explained := true
	for kind: String in with_ability:
		if not str(TDData.ENEMIES[kind].get("note", "")).length() > 20:
			explained = false
	check("and their cards say what they do", explained)

	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	# Rally hurries the escort along.
	var behemoth := Enemy.new()
	behemoth.setup("boss", 1.0, 1.0, game.routes[0])
	behemoth.position = Vector2(400.0, 400.0)
	var escort := Enemy.new()
	escort.setup("grunt", 1.0, 1.0, game.routes[0])
	escort.position = behemoth.position + Vector2(60.0, 0.0)
	for e in [behemoth, escort]:
		add_child(e)
		game.enemies.append(e)
	game.invalidate_targeting_grid()
	var walk_speed := escort.speed()
	behemoth.ability_clock = 0.0
	game._process_abilities(0.1)
	check("a rally hurries the escort", escort.speed() > walk_speed * 1.2)
	check("and wears off", escort.haste_timer > 0.0)
	for i in 40:
		escort._process(0.1)
	check("leaving them at their own pace",
			is_equal_approx(escort.speed(), walk_speed))
	check("the boss puts its ability back on the clock",
			behemoth.ability_clock > 0.0)

	# Quake silences the towers covering it.
	var titan := Enemy.new()
	titan.setup("titan", 1.0, 1.0, game.routes[0])
	var near := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun"):
			near = key
			break
	game.placing = "gun"
	game.gold = 999
	game._try_place(near)
	game.placing = ""
	var covered: Tower = game.occupied[near]
	titan.position = covered.position
	add_child(titan)
	game.enemies.append(titan)
	game.invalidate_targeting_grid()
	titan.ability_clock = 0.0
	game._process_abilities(0.1)
	check("a quake stuns the towers on top of it", covered.stun_timer > 0.0)
	var far := Tower.new()
	far.game = game
	far.setup("gun", Vector2i.ZERO)
	far.position = titan.position + Vector2(900.0, 0.0)
	check("and leaves the rest alone", far.stun_timer == 0.0)
	# A stunned tower holds its fire.
	covered.target = null
	covered._process(0.05)
	check("a stunned tower does not fire", covered.target == null)
	covered.stun_timer = 0.0
	far.free()

	game.occupied.erase(near)
	covered.queue_free()
	for e in [behemoth, escort, titan]:
		game.enemies.erase(e)
		e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

## Shoving the same creep over and over has to lose its grip, or a pair of
## Wave Cannons holds a lane still forever.
func _check_knockback_fatigue() -> void:
	var creep := Enemy.new()
	creep.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(creep)
	for i in 40:
		creep._process(0.05)
	var start := creep.progress
	creep.push_back(60.0)
	var first := start - creep.progress
	var second_start := creep.progress
	creep.push_back(60.0)
	var second := second_start - creep.progress
	check("the first shove moves the creep", first > 1.0)
	check("the second shove in a row moves it less", second < first * 0.8)
	# Left alone it recovers.
	for i in 60:
		creep._process(0.1)
	var third_start := creep.progress
	creep.push_back(60.0)
	check("after a breather a shove lands in full",
			third_start - creep.progress > second * 1.4)
	creep.queue_free()

## Each enemy kind has to actually behave differently.
func _check_enemy_kinds() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	check("the roster has grown", TDData.ENEMIES.size() >= 12)
	var ok_shape := true
	for kind: String in TDData.ENEMIES:
		var d: Dictionary = TDData.ENEMIES[kind]
		if float(d["hp"]) <= 0.0 or float(d["speed"]) <= 0.0 or int(d["reward"]) <= 0 \
				or float(d["radius"]) <= 0.0 or str(d["name"]) == "":
			ok_shape = false
	check("every enemy kind is well formed", ok_shape)

	# Armour: a Warden shrugs off small hits but not piercing ones.
	var warden := Enemy.new()
	warden.setup("warden", 1.0, 1.0, game.routes[0])
	add_child(warden)
	var before := warden.hp
	warden.take_damage(10.0)
	var soaked := before - warden.hp
	warden.take_damage(10.0, true)
	var pierced := before - warden.hp - soaked
	check("heavy armour soaks most of a small hit", soaked < 10.0 and soaked >= 1.0)
	check("piercing ignores that armour", is_equal_approx(pierced, 10.0))
	warden.queue_free()

	# Ashwalkers ignore slows and fire.
	var ash := Enemy.new()
	ash.setup("ashwalker", 1.0, 1.0, game.routes[0])
	add_child(ash)
	ash.apply_slow(0.6, 3.0)
	ash.apply_burn(30.0, 3.0)
	check("ashwalkers cannot be slowed", is_equal_approx(ash.speed(), ash.base_speed))
	check("ashwalkers cannot be set alight", ash.burn_timer <= 0.0)
	var grunt := Enemy.new()
	grunt.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(grunt)
	grunt.apply_slow(0.6, 3.0)
	check("ordinary creeps still slow", grunt.speed() < grunt.base_speed)
	ash.queue_free()
	grunt.queue_free()

	# Bolts sprint in bursts.
	var bolt := Enemy.new()
	bolt.setup("bolt", 1.0, 1.0, game.routes[0])
	add_child(bolt)
	var cruise := bolt.speed()
	bolt.charge_clock = bolt.charge_period
	bolt._process(0.05)
	check("bolts burst forward", bolt.speed() > cruise * 2.0)
	bolt.charging = 0.0
	check("and then settle back", is_equal_approx(bolt.speed(), cruise))
	bolt.queue_free()

	# Brood mothers split, and the children join the same lane.
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var brood := Enemy.new()
	brood.setup("brood", 1.0, 1.0, game.routes[0])
	brood.died.connect(game._on_enemy_died)
	brood.split.connect(game._on_enemy_split)
	game.layer_enemies.add_child(brood)
	game.enemies.append(brood)
	game.invalidate_targeting_grid()
	brood.progress = 400.0
	brood.take_damage(99999.0, true)
	var brood_count: int = int(TDData.ENEMIES["brood"]["split_count"])
	check("a brood mother leaves children behind",
			game.enemies.size() >= brood_count and brood_count >= 2)
	var inherited := true
	for child in game.enemies:
		if is_instance_valid(child) and child != brood:
			if not is_equal_approx(child.progress, 400.0) or child.path != brood.path:
				inherited = false
	check("the children start where the parent fell", inherited)
	for child in game.enemies.duplicate():
		if is_instance_valid(child):
			child.queue_free()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	# Menders heal their neighbours.
	var medic := Enemy.new()
	medic.setup("mender", 1.0, 1.0, game.routes[0])
	add_child(medic)
	medic.position = Vector2(400.0, 400.0)
	var patient := Enemy.new()
	patient.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(patient)
	patient.position = Vector2(430.0, 400.0)
	patient.hp = patient.max_hp * 0.3
	game.enemies.append(medic)
	game.invalidate_targeting_grid()
	game.enemies.append(patient)
	game.invalidate_targeting_grid()
	var hurt := patient.hp
	game._process_menders(0.5)
	check("menders heal the wounded", patient.hp > hurt)
	check("healing cannot exceed full health", patient.hp <= patient.max_hp)
	var far := Enemy.new()
	far.setup("grunt", 1.0, 1.0, game.routes[0])
	add_child(far)
	far.position = Vector2(1200.0, 400.0)
	far.hp = far.max_hp * 0.3
	game.enemies.append(far)
	game.invalidate_targeting_grid()
	var far_hp := far.hp
	game._process_menders(0.5)
	check("healing has a range", is_equal_approx(far.hp, far_hp))
	medic.queue_free()
	patient.queue_free()
	far.queue_free()
	game.enemies.clear()
	game.invalidate_targeting_grid()

	# Cutpurses take gold when they get through.
	var thief := Enemy.new()
	thief.setup("thief", 1.0, 1.0, game.routes[0])
	thief.leaked.connect(game._on_enemy_leaked)
	add_child(thief)
	game.enemies.append(thief)
	game.invalidate_targeting_grid()
	game.gold = 500
	var lives_before: int = game.lives
	thief._leak()
	check("a cutpurse steals gold", game.gold < 500)
	check("and still costs a life", game.lives < lives_before)
	thief.queue_free()

	# Titans appear as the alternate late boss and break into Wardens.
	var late: Array = game._build_wave(20)
	var kinds: Array = []
	for entry: Dictionary in late:
		if not kinds.has(str(entry["kind"])):
			kinds.append(str(entry["kind"]))
	check("late boss waves field a Titan", kinds.has("titan"))
	check("the Titan breaks into Wardens",
			str(TDData.ENEMIES["titan"]["split_into"]) == "warden")

	# The new kinds actually appear in the wave schedule.
	var seen: Array = []
	for n in range(1, 25):
		for entry: Dictionary in game._build_wave(n):
			if not seen.has(str(entry["kind"])):
				seen.append(str(entry["kind"]))
	var missing := ""
	for kind: String in TDData.ENEMIES:
		if not seen.has(kind):
			missing += kind + " "
	check("every enemy kind shows up within 24 waves (%s)" % missing, missing == "")

	game.enemies.assign(saved)
	game.invalidate_targeting_grid()
	game.lives = lives_before

## Air towers should put an aircraft in the air and reserve a squadron slot.
func _check_air() -> void:
	var spot := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "airfield"):
			spot = key
			break
	game.gold = 500
	game.placing = "airfield"
	game._try_place(spot)
	game.placing = ""
	var pad: Tower = game.occupied[spot]
	check("airfield placed", pad != null and pad.is_air())

	var e := Enemy.new()
	e.setup("grunt", 1.0, 1.0, game.path_points)
	e.died.connect(game._on_enemy_died)
	e.leaked.connect(game._on_enemy_leaked)
	game.layer_enemies.add_child(e)
	e.position = game.cell_center(spot) + Vector2(60.0, 0.0)
	game.enemies.append(e)
	game.invalidate_targeting_grid()

	pad._process(0.1)
	check("airfield launches a bomber", pad.units.size() == 1)
	check("bomber is in the air layer", game.layer_air.get_child_count() == 1)
	pad._process(0.1)
	check("squadron slot respected", pad.units.size() == 1)
	var craft = pad.units[0]
	check("bomber knows its pad", craft.pad == pad.position)
	check("bomber carries the payload", craft.shots == pad.unit_shots())

## Dead zones, burning, and line-piercing shots.
func _check_combat_extras() -> void:
	# Earlier sections leave creeps on the board; the range maths below only
	# means something with a clean list.
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var e := Enemy.new()
	e.setup("grunt", 20.0, 1.0, game.path_points)
	add_child(e)
	e.position = Vector2(500.0, 400.0)
	game.enemies.append(e)
	game.invalidate_targeting_grid()
	check("mortar ignores enemies inside its dead zone",
			game.find_target(e.position + Vector2(40.0, 0.0), 420.0, 130.0) == null)
	check("mortar hits enemies past its dead zone",
			game.find_target(e.position + Vector2(300.0, 0.0), 420.0, 130.0) == e)

	var before := e.hp
	e.apply_burn(20.0, 2.0)
	e._process(0.5)
	check("burning creeps lose health over time", e.hp < before)
	check("burn expires", e.burn_timer < 2.0)

	# A piercing shot fired along a row of creeps should hit two of them.
	var line: Array = []
	for i in 3:
		var c := Enemy.new()
		c.setup("grunt", 20.0, 1.0, game.path_points)
		add_child(c)
		c.position = Vector2(700.0 + 40.0 * float(i), 300.0)
		game.enemies.append(c)
		game.invalidate_targeting_grid()
		line.append(c)
	var p := Projectile.new()
	p.game = game
	p.position = Vector2(660.0, 300.0)
	p.dest = Vector2(900.0, 300.0)
	p.damage = 10.0
	p.speed = 400.0
	p.pierce_count = 2
	p.max_travel = 400.0
	add_child(p)
	for i in 40:
		if is_instance_valid(p):
			p._process(0.02)
	var hurt := 0
	for c in line:
		if is_instance_valid(c) and c.hp < c.max_hp:
			hurt += 1
	check("piercing shot hits several creeps in a line", hurt >= 2)
	for c in line:
		if is_instance_valid(c):
			game.enemies.erase(c)
			game.invalidate_targeting_grid()
			c.queue_free()
	game.enemies.erase(e)
	game.invalidate_targeting_grid()
	e.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()

## Hovering a creep has to teach the roster: what it is, what it shrugs off,
## and how to answer it.
func _check_board_tooltips() -> void:
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	game.invalidate_targeting_grid()
	var warden := Enemy.new()
	warden.setup("warden", 1.0, 1.0, game.routes[0])
	warden.position = Vector2(500.0, 300.0)
	warden.hp = warden.max_hp * 0.5
	add_child(warden)
	game.enemies.append(warden)
	game.invalidate_targeting_grid()

	check("the cursor finds the creep under it",
			game.enemy_at(warden.position) == warden)
	check("and finds nothing where there is none",
			game.enemy_at(warden.position + Vector2(300.0, 0.0)) == null)

	var card: String = game.hud.describe_enemy(warden)
	check("the card names the creep", card.contains(warden.display_name))
	check("and shows how much of it is left",
			card.contains("%d" % int(round(warden.max_hp))))
	check("armour is spelled out, since it decides the answer",
			card.contains("armour") == (warden.armor > 0.0))
	var mender := Enemy.new()
	mender.setup("mender", 1.0, 1.0, game.routes[0])
	check("a healer says so", str(game.hud.describe_enemy(mender)).contains("heals"))
	var ash := Enemy.new()
	ash.setup("ashwalker", 1.0, 1.0, game.routes[0])
	check("and a fireproof creep says so",
			str(game.hud.describe_enemy(ash)).contains("ignores fire"))
	var flyer := Enemy.new()
	flyer.setup("drake", 1.0, 1.0, game.routes[0])
	check("a flyer says it flies", str(game.hud.describe_enemy(flyer)).contains("flying"))
	var thief := Enemy.new()
	thief.setup("thief", 1.0, 1.0, game.routes[0])
	check("and a thief says what it takes",
			str(game.hud.describe_enemy(thief)).contains("steals"))
	# Every roster entry must produce a card without erroring.
	var blank := ""
	for kind: String in TDData.ENEMIES:
		var probe := Enemy.new()
		probe.setup(kind, 1.0, 1.0, game.routes[0])
		if str(game.hud.describe_enemy(probe)).strip_edges() == "":
			blank = kind
		probe.free()
	check("every creep in the roster has a card (%s)" % blank, blank == "")

	for e in [mender, ash, flyer, thief]:
		e.free()
	game.enemies.erase(warden)
	warden.queue_free()
	game.enemies.assign(saved)
	game.invalidate_targeting_grid()
