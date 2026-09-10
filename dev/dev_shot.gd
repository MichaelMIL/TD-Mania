extends Node

## Screenshot harness. Opens a real window (headless never fires
## `frame_post_draw`), plays for a moment, and saves one frame to $SHOT_PATH
## so a UI change can actually be looked at:
##
##   SHOT_PATH=/tmp/shot.png godot --quit-after 600 dev/dev_shot.tscn
##
## Optional user args: "-- --panel tuning|cheats" opens a panel first,
## "-- --fill" covers the board with maxed towers, "-- --wave" starts a wave.

var game: Node


func _ready() -> void:
	Progress.use_clean_state()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--fill"):
		game.gold = 999999
		game.fill_with_random_towers()
	for i in args.size():
		if args[i] == "--wave":
			# "--wave 11" jumps to just before that wave and starts it.
			if i + 1 < args.size() and args[i + 1].is_valid_int():
				game.wave = int(args[i + 1]) - 1
			game._start_wave()
	for i in args.size():
		if args[i] == "--panel" and i + 1 < args.size():
			if args[i + 1] == "tuning" and game.tuning_panel != null:
				game.tuning_panel.toggle()
			elif args[i + 1] == "cheats" and game.cheats != null:
				game.cheats.toggle()
	for i in args.size():
		if args[i] == "--spawn" and i + 1 < args.size():
			# Drops one creep of that kind on the board straight away.
			for n in 4:
				game.spawn_kind(args[i + 1])
	var delay := 0.8
	for i in args.size():
		if args[i] == "--delay" and i + 1 < args.size():
			delay = float(args[i + 1])
	await get_tree().create_timer(delay).timeout
	RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)


func _grab() -> void:
	var path := OS.get_environment("SHOT_PATH")
	if path == "":
		path = "user://shot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] saved %s" % path)
	get_tree().quit()
