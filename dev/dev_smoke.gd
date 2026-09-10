extends Node

## Full-speed smoke test. Every other harness runs at an accelerated
## `time_scale`, which is exactly how the freed-object crashes slipped past
## hundreds of assertions: they only appear when the frame loop, the audio
## pool and the spawn timers run at the speed a player sees.
##
##   godot --headless --fixed-fps 60 --quit-after 20000 dev/dev_smoke.tscn
##
## `--fixed-fps 60` is what makes this honest: every frame advances exactly
## 1/60 s, the delta a player's machine produces, while the loop itself runs
## as fast as the CPU allows. Four minutes of game time takes about twenty
## seconds of wall clock.
##
## It plays a few waves at 1x while a watchdog checks, every single frame,
## that nothing on the board has been freed out from under a reference.
## Anything the engine complains about lands on stderr, so the wrapper in
## `dev/run_checks.sh` greps for that too.

var game: Node
var fails: int = 0
var frames: int = 0
var act_timer: float = 0.0
var stage: int = 0
var stage_timer: float = 0.0
var peak_enemies: int = 0
var saw_flyer: bool = false
var saw_boss: bool = false
## The wave picked because it contains flyers.
var air_wave: int = 0
var sold: int = 0
var upgraded: int = 0
## Towers worth building here: ground, water, support and air, so every
## behaviour in tower.gd gets exercised at real speed.
var wish: Array = ["gun", "cannon", "frost", "tide", "marksman", "command",
		"airfield", "tesla", "torpedo", "mortar", "helipad", "laser"]
var wish_index: int = 0


func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])


func _ready() -> void:
	Progress.use_clean_state()
	Progress.unlock_all = true
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	# Explicitly real time: no time_scale anywhere in this harness.
	Engine.time_scale = 1.0
	game.gold = 4000
	print("[SMOKE] playing %s at 1x" % str(game.level_def["name"]))


func _process(delta: float) -> void:
	frames += 1
	_watch()
	peak_enemies = maxi(peak_enemies, game.enemies.size())
	act_timer -= delta
	if act_timer <= 0.0:
		act_timer = 0.7
		_act()
	stage_timer += delta
	_advance()


## The watchdog. These are the invariants that break when something is freed
## while still referenced — the class of bug that only shows up live.
func _watch() -> void:
	for e in game.enemies:
		if is_instance_valid(e):
			saw_flyer = saw_flyer or e.flying
			saw_boss = saw_boss or e.kind == "boss" or e.kind == "titan"
		if not is_instance_valid(e):
			check("a freed creep was left on the roster (frame %d)" % frames, false)
			game.enemies.erase(e)
			return
		if e.dead and e.hp > 0.0:
			check("a dead creep still has health (frame %d)" % frames, false)
			return
	for cell: Vector2i in game.occupied:
		if not is_instance_valid(game.occupied[cell]):
			check("a freed tower is still on the board (frame %d)" % frames, false)
			return
	if game.lives < 0:
		check("lives went negative (frame %d)" % frames, false)
	if game.gold < 0:
		check("gold went negative (frame %d)" % frames, false)


## A crude player: builds, occasionally upgrades, occasionally sells.
func _act() -> void:
	if game.game_over:
		return
	if game.gold > 900 and not game.occupied.is_empty() and upgraded < 6:
		var pick: Tower = game.occupied.values()[randi() % game.occupied.size()]
		if is_instance_valid(pick):
			game._select(pick)
			game._upgrade_selected()
			upgraded += 1
			return
	if game.occupied.size() > 6 and sold < 2:
		# Selling is where freed-object bugs bite: creeps may still be
		# burning from the tower that just vanished.
		var victim: Tower = game.occupied.values()[0]
		if is_instance_valid(victim):
			game._select(victim)
			game._sell_selected()
			sold += 1
			return
	for offset in wish.size():
		var want: String = wish[(wish_index + offset) % wish.size()]
		if game.gold < game.tower_cost(want):
			continue
		var spot := _spot_for(want)
		if spot.x < -50:
			continue
		game.placing = want
		game._try_place(spot)
		game.placing = ""
		wish_index += offset + 1
		return


func _spot_for(type_id: String) -> Vector2i:
	for y in TDData.ROWS:
		for x in TDData.COLS:
			var c := Vector2i(x, y)
			if game.can_place(c, type_id):
				return c
	return Vector2i(-99, -99)


## Walks the run through the things worth testing live, then reports.
func _advance() -> void:
	match stage:
		0:
			# Let a couple of waves play out from the start.
			if game.wave >= 2 and not game.in_wave:
				stage = 1
				stage_timer = 0.0
				game.skip_waves(6)
				game.gold += 3000
				print("[SMOKE] jumped to wave %d for the boss" % (game.wave + 1))
		1:
			# Wave 10: boss escort, and the aircraft that answer it.
			if game.wave >= 10 and not game.in_wave:
				stage = 2
				stage_timer = 0.0
				# Skip to the next wave that actually contains a flyer rather
				# than guessing a number the tables might move. The next wave
				# played is `wave + 1`, so that is what has to line up.
				air_wave = _next_air_wave()
				if air_wave - 1 > game.wave:
					game.skip_waves(air_wave - 1 - game.wave)
				print("[SMOKE] wave %d is next, and it has flyers in it" % air_wave)
		2:
			# A wave with flyers in it, then a save/restore round trip.
			if game.wave >= air_wave and not game.in_wave:
				stage = 3
				_finish()
		3:
			pass
	if stage < 3 and stage_timer > 120.0:
		check("stage %d finished within two minutes of real time" % stage, false)
		_finish()


## The first upcoming wave that sends something airborne.
func _next_air_wave() -> int:
	for n in range(game.wave + 1, game.wave + 14):
		for kind: String in game.wave_composition(n):
			if bool(TDData.ENEMIES[kind].get("flying", false)):
				return n
	return game.wave + 1


func _finish() -> void:
	check("the run survived to wave %d" % game.wave, game.wave >= 10)
	check("creeps actually spawned (%d at once)" % peak_enemies, peak_enemies > 0)
	check("creeps actually died", int(game.run_stats.get("kills", 0)) > 0)
	check("a boss came and went at real speed", saw_boss)
	check("so did flyers", saw_flyer)
	check("towers were built", game.occupied.size() > 0)
	check("towers were upgraded and sold", upgraded > 0 and sold > 0)
	check("gold moved", int(game.run_stats.get("gold_earned", 0)) > 0)
	check("something is still standing", game.lives > 0 or game.game_over)

	# Parking and resuming a run is the other thing only real play exercises.
	var state: Dictionary = game._capture_run()
	check("a run can be parked", not state.is_empty())
	game._restore_run(state)
	check("and restored without losing the board",
			game.occupied.size() > 0 and game.wave >= 10)
	_watch()

	print("[SMOKE] %d frames at 1x, peak %d creeps, %d towers (%d failures)"
			% [frames, peak_enemies, game.occupied.size(), fails])
	get_tree().quit()
