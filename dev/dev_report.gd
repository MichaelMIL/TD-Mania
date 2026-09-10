extends Node

## The balance report: plays every map several times with the crude proxy
## player and says whether the difficulty ladder actually holds.
##
##   godot --headless --fixed-fps 5 --quit-after 900000 dev/dev_report.tscn
##   ... dev/dev_report.tscn -- --runs 5          # more samples per map
##   ... dev/dev_report.tscn -- --area wastes     # one area only
##
## `--fixed-fps 5` is what makes it quick and repeatable: every frame
## advances exactly 0.2 s of game time regardless of how fast the machine
## runs, so a run takes a predictable number of frames and the same seed
## always plays out the same way. (Note that `--fixed-fps` overrides
## `Engine.time_scale` rather than compounding with it.) The coarse step is
## the same one `dev_balance.tscn` has always simulated at; it is not how
## the game feels at 1x, which is what `dev_smoke.tscn` is for.
##
## What it checks, rather than just prints:
##   * every tier is harder than the one before it, on average
##   * no map is a wild outlier inside its own tier
##   * no map is unplayable (the proxy dies in the first few waves) and none
##     is free (the proxy clears it without losing a life)
##
## The proxy is not a good player — it never counters Menders or Wardens —
## so treat the absolute numbers as a floor. What it measures well is maps
## *against each other*, which is exactly what a difficulty ladder is.

## Game time is the budget; a run that reaches this is called a survival.
const MAX_WAVE := 40
## Frames one run may take before it is written off as stuck. At 0.2 s a
## frame this is well over an hour of game time.
const FRAME_BUDGET := 20000

var runs_per_map := 3
var only_area := ""
var levels: Array = []
var queue: Array = []
var results: Array = []
var fails: int = 0

var game: Node = null
var player: ProxyPlayer = null
var current: Dictionary = {}
var frames := 0
var act_timer := 0.0


func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])


func _ready() -> void:
	Progress.use_clean_state()
	Progress.unlock_all = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs_per_map = int(args[i + 1])
		if args[i] == "--area" and i + 1 < args.size():
			only_area = args[i + 1]
	for i in TDData.LEVELS.size():
		if only_area == "" or str(TDData.LEVELS[i].get("area", "")) == only_area:
			levels.append(i)
			for run in runs_per_map:
				queue.append({"level": i, "seed": run})
	# The App autoload caps the frame rate for the player's benefit; a batch
	# of simulations wants none of that.
	Engine.max_fps = 0
	print("[REPORT] %d maps x %d runs" % [levels.size(), runs_per_map])
	_next()


## Starts the next queued run, or reports once the queue is empty.
func _next() -> void:
	if game != null and is_instance_valid(game):
		remove_child(game)
		game.queue_free()
		game = null
	if queue.is_empty():
		_report()
		return
	current = queue.pop_front()
	# Same seed, same run: the report is reproducible.
	seed(hash(str(TDData.LEVELS[int(current["level"])]["id"])) + int(current["seed"]))
	TDData.selected_level = int(current["level"])
	TDData.resume_run = false
	game = load("res://game.tscn").instantiate()
	add_child(game)
	frames = 0
	act_timer = 0.0
	player = ProxyPlayer.new(game)


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	frames += 1
	act_timer -= delta
	if act_timer <= 0.0:
		act_timer = 0.4
		player.act()
	if OS.get_cmdline_user_args().has("--trace") and frames % 2000 == 0:
		print("[TRACE] frame %d wave %d towers %d creeps %d lives %d gold %d in_wave %s"
				% [frames, game.wave, game.occupied.size(), game.enemies.size(),
				game.lives, game.gold, game.in_wave])
	var over: bool = game.game_over
	if over or game.wave > MAX_WAVE or frames > FRAME_BUDGET:
		_finish(over)


func _finish(died: bool) -> void:
	var level: Dictionary = TDData.LEVELS[int(current["level"])]
	results.append({
		"id": str(level["id"]),
		"name": str(level["name"]),
		"tier": int(level.get("tier", 0)),
		"waves": maxi(0, game.wave - (1 if died else 0)),
		"cleared": game.map_cleared,
		"lives": game.lives,
		"leaks": game.leaked_total,
		"towers": game.occupied.size(),
		"died": died,
		"frames": frames,
	})
	_next()


func _mean(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var total := 0.0
	for v in list:
		total += float(v)
	return total / float(list.size())


func _report() -> void:
	# ---- per map
	var by_map: Dictionary = {}
	for r: Dictionary in results:
		if not by_map.has(r["id"]):
			by_map[r["id"]] = []
		(by_map[r["id"]] as Array).append(r)
	var by_tier: Dictionary = {}
	print("[REPORT] map                tier   waves (mean)   cleared   lives left   leaks")
	for id: String in by_map:
		var runs: Array = by_map[id]
		var waves: Array = []
		var lives: Array = []
		var leaks: Array = []
		var cleared := 0
		for r: Dictionary in runs:
			waves.append(r["waves"])
			lives.append(r["lives"])
			leaks.append(r["leaks"])
			if bool(r["cleared"]):
				cleared += 1
		var tier := int(runs[0]["tier"])
		if not by_tier.has(tier):
			by_tier[tier] = []
		(by_tier[tier] as Array).append(_mean(waves))
		print("[REPORT] %-22s %-4s %6.1f        %d/%d       %5.1f      %5.1f"
				% [runs[0]["name"], TDData.TIERS[tier]["name"], _mean(waves),
				cleared, runs.size(), _mean(lives), _mean(leaks)])

	# ---- per tier, and the ladder itself
	var tier_means: Array = []
	for tier in TDData.TIERS.size():
		if not by_tier.has(tier):
			tier_means.append(-1.0)
			continue
		var mean := _mean(by_tier[tier])
		tier_means.append(mean)
		print("[REPORT] %-8s mean %.1f waves over %d maps"
				% [TDData.TIERS[tier]["name"], mean, (by_tier[tier] as Array).size()])

	var inversions: Array = []
	var previous := 999.0
	for tier in tier_means.size():
		var mean: float = tier_means[tier]
		if mean < 0.0:
			continue
		if mean > previous + 0.5:
			inversions.append("%s beats %s" % [TDData.TIERS[tier]["name"],
					TDData.TIERS[tier - 1]["name"]])
		previous = mean
	check("each tier is harder than the one before (%s)" % ", ".join(inversions),
			inversions.is_empty())

	# ---- outliers inside a tier
	var odd: Array = []
	for id: String in by_map:
		var runs: Array = by_map[id]
		var tier := int(runs[0]["tier"])
		var waves: Array = []
		for r: Dictionary in runs:
			waves.append(r["waves"])
		var mine := _mean(waves)
		var tier_mean: float = tier_means[tier]
		if tier_mean <= 0.0:
			continue
		if mine > tier_mean * 1.6 or mine < tier_mean * 0.55:
			odd.append("%s %.1f vs %.1f" % [runs[0]["name"], mine, tier_mean])
	check("no map is a wild outlier in its tier (%s)" % ", ".join(odd), odd.is_empty())

	# ---- unplayable or free
	var brutal: Array = []
	var trivial: Array = []
	for id: String in by_map:
		var runs: Array = by_map[id]
		var waves: Array = []
		var untouched := true
		for r: Dictionary in runs:
			waves.append(r["waves"])
			if int(r["leaks"]) > 0:
				untouched = false
		if _mean(waves) < 5.0:
			brutal.append(str(runs[0]["name"]))
		if untouched and _mean(waves) >= float(MAX_WAVE):
			trivial.append(str(runs[0]["name"]))
	check("no map is unplayable (%s)" % ", ".join(brutal), brutal.is_empty())
	check("no map is free (%s)" % ", ".join(trivial), trivial.is_empty())

	var stuck: Array = []
	for r: Dictionary in results:
		if not bool(r["died"]) and int(r["frames"]) > FRAME_BUDGET:
			stuck.append("%s at wave %d" % [r["name"], int(r["waves"])])
	check("every run finished rather than running out of frames (%s)"
			% ", ".join(stuck), stuck.is_empty())
	print("[REPORT] %d runs, %d failures" % [results.size(), fails])
	get_tree().quit()
