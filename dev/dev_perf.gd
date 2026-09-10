extends Node

## What the game costs the machine. Runs a windowed session with the board
## saturated and a wave in flight, vsync off and the frame cap lifted, and
## reports what the engine actually spends per frame:
##
##   godot --quit-after 1400 dev/dev_perf.tscn
##   godot --quit-after 1400 dev/dev_perf.tscn -- --wave 20 --towers 60
##
## Vsync off is the point: with it on, everything looks like 16.6 ms and the
## fan noise is invisible. Raw frame time is what the laptop is paying.

var game: Node
var samples: Array = []
var draw_calls: Array = []
var objects: Array = []
var process_us: Array = []
var settle := 1.0
var silenced := ""
var freeze_enemies := false


func _ready() -> void:
	Progress.use_clean_state()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--churn"):
		_measure_churn()
		get_tree().quit()
		return
	var wave := 12
	var towers := 0
	for i in args.size():
		if args[i] == "--wave" and i + 1 < args.size():
			wave = int(args[i + 1])
		if args[i] == "--towers" and i + 1 < args.size():
			towers = int(args[i + 1])
	game.gold = 9999999
	if towers > 0:
		_build_some(towers)
	else:
		game.fill_with_random_towers()
	# "-- --off towers,enemies,water,hud" silences parts of the frame so the
	# cost can be attributed rather than guessed at.
	var off: PackedStringArray = PackedStringArray()
	for i in args.size():
		if args[i] == "--off" and i + 1 < args.size():
			off = args[i + 1].split(",")
	if off.has("towers"):
		for t: Tower in game.occupied.values():
			t.set_process(false)
	if off.has("water") and game.layer_water != null:
		game.layer_water.set_process(false)
	if off.has("hud"):
		game.hud.set_process(false)
		game.hud.frozen = true
	if off.has("map"):
		game.layer_map.visible = false
	if off.has("draw"):
		game.layer_towers.visible = false
	silenced = ",".join(off)
	game.wave = wave - 1
	game._start_wave()
	if off.has("enemies"):
		freeze_enemies = true
	print("[PERF] %d towers, wave %d, vsync off" % [game.occupied.size(), wave])


## How much a wave costs simply in creeps arriving and leaving: allocate,
## set up, walk a frame, and free. Run before deciding whether pooling is
## worth the stale-state risk.
##
##   godot --headless --quit-after 200 dev/dev_perf.tscn -- --churn
func _measure_churn() -> void:
	var road: PackedVector2Array = game.routes[0]
	var rounds := 20
	var per_round := 200
	var made_us := 0
	var freed_us := 0
	for r in rounds:
		var batch: Array = []
		var t0 := Time.get_ticks_usec()
		for i in per_round:
			var e := Enemy.new()
			e.setup("grunt", 1.0, 1.0, road)
			game.layer_enemies.add_child(e)
			batch.append(e)
		made_us += Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		for e: Enemy in batch:
			game.layer_enemies.remove_child(e)
			e.free()
		freed_us += Time.get_ticks_usec() - t0
	var total := float(made_us + freed_us) / float(rounds) / 1000.0
	print("[CHURN] %d creeps: %.2f ms to create, %.2f ms to free, %.2f ms a wave's worth"
			% [per_round, float(made_us) / float(rounds) / 1000.0,
			float(freed_us) / float(rounds) / 1000.0, total])
	print("[CHURN] a heavy wave spawns about 70 creeps over ~45 s, so that is roughly %.3f ms per second of play"
			% (total * 70.0 / float(per_round) / 45.0))


func _build_some(count: int) -> void:
	var kinds: Array = ["gun", "cannon", "frost", "tesla", "marksman", "laser"]
	var placed := 0
	for y in TDData.ROWS:
		for x in TDData.COLS:
			if placed >= count:
				return
			var c := Vector2i(x, y)
			var kind: String = kinds[placed % kinds.size()]
			if game.can_place(c, kind):
				game.placing = kind
				game._try_place(c)
				game.placing = ""
				placed += 1


func _process(delta: float) -> void:
	# Ignore the first second: window creation and shader compilation.
	if settle > 0.0:
		settle -= delta
		return
	# The App autoload re-applies the player's frame cap when the window
	# takes focus; measuring raw cost means overriding it every frame.
	Engine.max_fps = 0
	samples.append(delta)
	process_us.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
	draw_calls.append(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	objects.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# Keep a wave running for the whole measurement.
	if freeze_enemies:
		for e in game.enemies:
			if is_instance_valid(e):
				e.set_process(false)
	if not game.in_wave and not game.game_over:
		game._start_wave()
	if samples.size() >= 600:
		_report()


func _average(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var total := 0.0
	for v in list:
		total += float(v)
	return total / float(list.size())


## The 95th percentile matters more than the mean: the stutters are what a
## player feels, and what makes the fan spin up.
func _percentile(list: Array, fraction: float) -> float:
	if list.is_empty():
		return 0.0
	var sorted := list.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1,
			int(float(sorted.size()) * fraction))])


func _report() -> void:
	var frame_ms := _average(samples) * 1000.0
	print("[PERF] %s | frame %.2f ms avg, %.2f ms p95  (%.0f fps)  script %.0f us  draw calls %.0f  nodes %.0f"
			% ["off:" + silenced if silenced != "" else "full", frame_ms,
			_percentile(samples, 0.95) * 1000.0,
			1000.0 / maxf(0.01, frame_ms), _average(process_us),
			_average(draw_calls), _average(objects)])
	get_tree().quit()
