extends Node

## Plays every challenge, and a run of daily challenges, with the balance
## harness's crude player, and says how far it got against each goal.
##
##   godot --headless --fixed-fps 5 --quit-after 900000 dev/dev_challenges.tscn
##   godot --headless --fixed-fps 5 --quit-after 900000 dev/dev_challenges.tscn -- --days 14 --runs 2
##   ... -- --only shoestring,last_stand --days 0      (some of the set)
##   ... -- --only-daily --days 21                      (dailies only)
##   ... -- --tech                                      (with a finished account)
##   ... -- --depth                                     (play past the goal until lost)
##
## The player builds only what the challenge allows (cycling through its
## towers, cheapest weighted most), plays without account upgrades, and
## never counters anything. So its result is a floor: a goal it reaches is
## comfortably fair, one it misses by a few waves is a real challenge, and
## one it misses by many is probably out of reach and worth a second look.

const MAX_FRAMES := 60000

var queue: Array = []
var results: Array = []
var game: Node = null
var player: ProxyPlayer = null
var current: Dictionary = {}
var frames: int = 0
var act_timer: float = 0.0


func _ready() -> void:
	Progress.use_clean_state()
	var args := OS.get_cmdline_user_args()
	if args.has("--tech"):
		# A finished account: every tech rank and every tower rank bought, so
		# the player upgrades as it goes. The crude player alone is a floor
		# a beginner clears; this is the ceiling a veteran brings.
		for t: Dictionary in Progress.TECH:
			Progress.ranks[str(t["id"])] = int(t["max"])
		for type_id: String in TDData.TOWERS:
			var full: Array = []
			for tr: Dictionary in TDData.tracks(type_id):
				full.append(int(tr["max"]))
			Progress.tower_ranks[type_id] = full
	var days := 7
	var runs := 1
	for i in args.size():
		if args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	var only: Array = []
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = Array(args[i + 1].split(","))
	for c: Dictionary in Challenges.LIST:
		if args.has("--only-daily"):
			break
		if not only.is_empty() and not only.has(str(c["id"])):
			continue
		for r in runs:
			queue.append({"challenge": c, "seed": r})
	var noon := Time.get_unix_time_from_system()
	for d in days:
		var key := Challenges.date_key(Time.get_date_dict_from_unix_time(int(noon) + d * 86400))
		for r in runs:
			queue.append({"challenge": Challenges.daily_for(key), "seed": r})
	Engine.max_fps = 0
	print("[CHALLENGES] %d runs" % queue.size())
	_next()


func _wish_for(c: Dictionary) -> Array:
	var rules: Dictionary = c.get("rules", {})
	var allowed: Array = []
	if rules.has("towers"):
		allowed = (rules["towers"] as Array).duplicate()
	else:
		for t: String in ProxyPlayer.WISH:
			if Challenges.allows(c, t):
				allowed.append(t)
		return allowed
	# Cheap towers twice, so it builds a line before it buys the big ones —
	# but damage first: a Tar Pit slows and kills nothing, so it goes last.
	allowed.sort_custom(func(a, b):
		var sa := int(TDData.TOWERS[a]["cost"]) + (10000 if a == "tarpit" else 0)
		var sb := int(TDData.TOWERS[b]["cost"]) + (10000 if b == "tarpit" else 0)
		return sa < sb)
	var out: Array = []
	for i in allowed.size():
		out.append(allowed[i])
		if i < 2:
			out.append(allowed[i])
	return out


func _next() -> void:
	if game != null and is_instance_valid(game):
		remove_child(game)
		game.queue_free()
		game = null
	if queue.is_empty():
		_report()
		return
	current = queue.pop_front()
	var c: Dictionary = current["challenge"]
	seed(Challenges.stable_hash(Challenges.run_key(c)) + int(current["seed"]))
	TDData.active_challenge = c.duplicate(true)
	if OS.get_cmdline_user_args().has("--depth"):
		# Play on past the goal until the run is lost, to see the headroom.
		TDData.active_challenge["waves"] = 60
	TDData.selected_level = Challenges.level_index(c)
	TDData.resume_run = false
	game = load("res://game.tscn").instantiate()
	add_child(game)
	frames = 0
	act_timer = 0.0
	player = ProxyPlayer.new(game)
	player.wish = _wish_for(c)


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	frames += 1
	act_timer -= delta
	if act_timer <= 0.0:
		act_timer = 0.4
		player.act()
	if game.game_over or game.map_cleared or frames > MAX_FRAMES * (3 if OS.get_cmdline_user_args().has("--depth") else 1):
		_finish()


func _finish() -> void:
	var c: Dictionary = current["challenge"]
	results.append({
		"name": str(c["name"]) if not c.has("daily") else "Daily %s (%s, %s)" % [c["daily"],
				Challenges.level_of(c)["name"], c["twist"]],
		"goal": int(c["waves"]),
		"reached": maxi(0, game.wave - (1 if game.game_over else 0)),
		"won": game.map_cleared,
		"towers": game.occupied.size(),
	})
	_next()


func _report() -> void:
	var won := 0
	for r: Dictionary in results:
		if bool(r["won"]):
			won += 1
		print("[CHALLENGES] %-52s goal %2d  reached %2d  %s  (%d towers)" % [r["name"],
				int(r["goal"]), int(r["reached"]), "WON " if bool(r["won"]) else "lost",
				int(r["towers"])])
	print("[CHALLENGES] the crude player beat %d of %d" % [won, results.size()])
	TDData.active_challenge = {}
	get_tree().quit()
