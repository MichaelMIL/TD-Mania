extends Node

## How fast an account actually levels.
##
##   godot --headless --fixed-fps 5 --quit-after 3000000 dev/dev_progress.tscn
##   ... -- --runs 40 --spread      (walk up the maps as they unlock)
##
## Plays runs with the crude player, banks each one into a real account the
## way the match does, and says which run each unlock landed on. The pace of
## the whole game hangs off this: towers, upgrade ranks and maps are all
## gated on account level, so a level curve that is too short hands the
## player everything before they have played enough to want it.

const MAX_FRAMES := 60000

var queue: Array = []
var game: Node = null
var player: ProxyPlayer = null
var frames: int = 0
var act_timer: float = 0.0
var run_index: int = 0
var rows: Array = []
var spread: bool = false
## run index -> what unlocked on it.
var unlocks: Dictionary = {}
var seen_level: int = 1
var before_xp: int = 0
var before_coins: int = 0
var before_level: int = 1


func _ready() -> void:
	Progress.use_clean_state()
	Progress.read_only = true
	Progress.unlock_all = false
	Progress.xp = 0
	Progress.coins = 0
	var args := OS.get_cmdline_user_args()
	var runs := 20
	spread = args.has("--spread")
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	for r in runs:
		queue.append(0)
	Engine.max_fps = 0
	print("[PROGRESS] %d runs, %s" % [runs,
			"walking up the maps as they unlock" if spread else "on Verdant Pass"])
	_next()


## The hardest map the account has unlocked, so a levelling account moves on
## rather than farming the first map forever.
func _pick_level() -> int:
	if not spread:
		return 0
	var best := 0
	for i in TDData.LEVELS.size():
		if Progress.level_unlocked(TDData.LEVELS[i]) \
				and int(TDData.LEVELS[i]["tier"]) >= int(TDData.LEVELS[best]["tier"]):
			best = i
	return best


func _next() -> void:
	if game != null and is_instance_valid(game):
		remove_child(game)
		game.queue_free()
		game = null
	if queue.is_empty():
		_report()
		return
	queue.pop_front()
	run_index += 1
	before_xp = Progress.xp
	before_coins = Progress.coins
	before_level = Progress.level()
	var level := _pick_level()
	seed(hash(str(TDData.LEVELS[level]["id"])) + run_index)
	TDData.active_challenge = {}
	TDData.selected_level = level
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
	if game.game_over or frames > MAX_FRAMES:
		_finish()


func _finish() -> void:
	if not game.game_over:
		game._trigger_game_over()
	var after := Progress.level()
	# What crossing those levels handed over.
	var gained: Array = []
	for l in range(seen_level + 1, after + 1):
		for type_id: String in TDData.TOWER_ORDER:
			if Progress.tower_unlock_level(type_id) == l:
				gained.append(str(TDData.TOWERS[type_id]["name"]))
		var maps := 0
		for m: Dictionary in TDData.LEVELS:
			if TDData.level_unlock(m) == l:
				maps += 1
		if maps > 0:
			gained.append("%d map%s" % [maps, "" if maps == 1 else "s"])
	if not gained.is_empty():
		unlocks[run_index] = gained
	seen_level = after
	rows.append({
		"run": run_index, "map": str(game.level_def["name"]),
		"waves": maxi(0, game.wave - 1), "score": game.score,
		"xp": Progress.xp - before_xp, "coins": Progress.coins - before_coins,
		"level_before": before_level, "level_after": after, "total_xp": Progress.xp,
	})
	_next()


func _report() -> void:
	for r: Dictionary in rows:
		var note: String = "  <- " + ", ".join(unlocks.get(int(r["run"]), [])) \
				if unlocks.has(int(r["run"])) else ""
		print("[PROGRESS] run %2d  %-20s wave %2d  score %6d  +%5d xp  +%4d coins  level %2d -> %2d%s"
				% [int(r["run"]), r["map"], int(r["waves"]), int(r["score"]), int(r["xp"]),
				int(r["coins"]), int(r["level_before"]), int(r["level_after"]), note])
	var runs := rows.size()
	if runs == 0:
		get_tree().quit()
		return
	var xp_total := 0
	var coin_total := 0
	for r: Dictionary in rows:
		xp_total += int(r["xp"])
		coin_total += int(r["coins"])
	var mean_xp: int = xp_total / runs
	var mean_coins: int = coin_total / runs
	print("[PROGRESS] mean %d xp and %d coins a run; level %d after %d runs"
			% [mean_xp, mean_coins, Progress.level(), runs])
	# Where the milestones land at that rate.
	var all_towers := 1
	for type_id: String in TDData.TOWERS:
		all_towers = maxi(all_towers, Progress.tower_unlock_level(type_id))
	var all_maps := 1
	for m: Dictionary in TDData.LEVELS:
		all_maps = maxi(all_maps, TDData.level_unlock(m))
	if mean_xp > 0:
		for pair: Array in [["every tower", all_towers], ["every map", all_maps],
				["the level cap", Progress.MAX_LEVEL]]:
			print("[PROGRESS] %-14s (level %2d) lands around run %d" % [pair[0], int(pair[1]),
					int(ceil(float(Progress.xp_for_level(int(pair[1]))) / float(mean_xp)))])
	if mean_coins > 0:
		var doctrine := 0
		for t: Dictionary in Progress.TECH:
			var c := float(t["cost"])
			for r in int(t["max"]):
				doctrine += int(c)
				c *= float(t["cost_mult"])
		var tower_ranks := 0
		for type_id: String in TDData.TOWERS:
			for i in TDData.tracks(type_id).size():
				for r in int(TDData.tracks(type_id)[i]["max"]):
					tower_ranks += TDData.track_cost(type_id, i, r)
		print("[PROGRESS] all doctrine (%d coins) around run %d; every rank in the tree (%d) around run %d"
				% [doctrine, int(ceil(float(doctrine) / float(mean_coins))),
				doctrine + tower_ranks,
				int(ceil(float(doctrine + tower_ranks) / float(mean_coins)))])
	get_tree().quit()
