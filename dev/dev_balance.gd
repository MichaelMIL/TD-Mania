extends Node

## Temporary dev harness: plays with a crude auto-builder and reports how
## far a competent-but-not-clever player gets. Used only for balancing.

var game: Node
var act_timer: float = 0.0
var player: ProxyPlayer
var last_wave: int = 0
var last_leaks: int = 0


func _ready() -> void:
	# Optional "-- --level N" picks the map to simulate.
	# Isolated account: full unlocks, no tech, and nothing written to disk.
	Progress.use_clean_state()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--level" and i + 1 < args.size():
			TDData.selected_level = int(args[i + 1])
	game = load("res://game.tscn").instantiate()
	add_child(game)
	if args.has("--perf"):
		_run_perf()
		get_tree().quit()
		return
	player = ProxyPlayer.new(game)
	Engine.time_scale = 12.0


## `godot --headless --quit-after 20 dev/dev_balance.tscn -- --perf`
## Measures what targeting costs on a saturated board — every buildable cell
## firing into a late wave — with a full scan and with the bucket grid.
func _run_perf() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var road: PackedVector2Array = game.routes[0]
	# "-- --perf --creeps 500" shows how the gap widens with the roster.
	var creeps := 220
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--creeps" and i + 1 < argv.size():
			creeps = int(argv[i + 1])
	for i in creeps:
		var e := Enemy.new()
		e.setup("grunt", 1.0, 1.0, road)
		# Strung along the road with some lane spread, the way a wave sits.
		var at: Vector2 = road[rng.randi_range(0, road.size() - 1)]
		e.position = at + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		e.progress = rng.randf() * 1000.0
		add_child(e)
		game.enemies.append(e)
	game.invalidate_targeting_grid()

	var origins: Array = []
	for cell: Vector2i in game.terrain:
		if game.can_place(cell, "gun"):
			origins.append(game.cell_center(cell))
	var reach := 190.0
	var sweeps := 20

	var t0 := Time.get_ticks_usec()
	for pass_i in sweeps:
		for origin: Vector2 in origins:
			var best: Enemy = null
			var best_score := -INF
			for e: Enemy in game.enemies:
				if not is_instance_valid(e) or e.dead:
					continue
				if origin.distance_to(e.position) > reach + e.radius * 0.5:
					continue
				var sc: float = game.target_score(e, TDData.Target.FIRST)
				if sc > best_score:
					best_score = sc
					best = e
	var brute_us := (Time.get_ticks_usec() - t0) / float(sweeps)

	t0 = Time.get_ticks_usec()
	for pass_i in sweeps:
		# One rebuild per sweep, exactly as a frame of play would do.
		game.invalidate_targeting_grid()
		for origin: Vector2 in origins:
			game.find_target(origin, reach)
	var grid_us := (Time.get_ticks_usec() - t0) / float(sweeps)

	print("[PERF] %d creeps x %d firing spots: full scan %.2f ms/frame -> grid %.2f ms/frame (%.1fx)"
			% [game.enemies.size(), origins.size(), brute_us / 1000.0, grid_us / 1000.0,
			brute_us / maxf(1.0, grid_us)])

	# The mender pass was the quadratic one.
	for i in 8:
		var m: Enemy = game.enemies[i * (game.enemies.size() / 8 - 1)]
		m.heal = 12.0
		m.heal_range = 130.0
	for e: Enemy in game.enemies:
		e.hp = e.max_hp * 0.5
	t0 = Time.get_ticks_usec()
	for pass_i in sweeps:
		for medic: Enemy in game.enemies:
			if not is_instance_valid(medic) or medic.dead or medic.heal <= 0.0:
				continue
			for other: Enemy in game.enemies:
				if other == medic or not is_instance_valid(other) or other.dead:
					continue
				if other.hp >= other.max_hp:
					continue
				if medic.position.distance_to(other.position) <= medic.heal_range:
					pass
	var mend_brute_us := (Time.get_ticks_usec() - t0) / float(sweeps)
	t0 = Time.get_ticks_usec()
	for pass_i in sweeps:
		game.invalidate_targeting_grid()
		for medic: Enemy in game.enemies:
			if not is_instance_valid(medic) or medic.dead or medic.heal <= 0.0:
				continue
			for other: Enemy in game.enemies_near(medic.position, medic.heal_range):
				if other == medic or other.hp >= other.max_hp:
					continue
				if medic.position.distance_to(other.position) <= medic.heal_range:
					pass
	var mend_grid_us := (Time.get_ticks_usec() - t0) / float(sweeps)
	print("[PERF] mender pass (8 menders): %.2f ms/frame -> %.2f ms/frame (%.1fx)"
			% [mend_brute_us / 1000.0, mend_grid_us / 1000.0,
			mend_brute_us / maxf(1.0, mend_grid_us)])


func _process(delta: float) -> void:
	if game.game_over:
		print("[BALANCE] %s: reached wave %d | score %d | towers %d | leaks %d"
				% [game.level_def["name"], game.wave, game.score, game.occupied.size(),
				game.leaked_total])
		get_tree().quit()
		return
	if game.wave > 30:
		print("[BALANCE] %s: survived past wave 30 | gold %d | towers %d | lives %d"
				% [game.level_def["name"], game.gold, game.occupied.size(), game.lives])
		get_tree().quit()
		return
	if game.wave != last_wave:
		print("[WAVE] %d start | towers %d | gold %d | lives %d | leaks(+%d)"
				% [game.wave, game.occupied.size(), game.gold, game.lives,
				game.leaked_total - last_leaks])
		last_leaks = game.leaked_total
		last_wave = game.wave
	act_timer -= delta
	if act_timer > 0.0:
		return
	act_timer = 0.4
	player.act()
