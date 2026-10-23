extends Node

## Screenshot harness. Opens a real window (headless never fires
## `frame_post_draw`), plays for a moment, and saves one frame to $SHOT_PATH
## so a UI change can actually be looked at:
##
##   SHOT_PATH=/tmp/shot.png godot --quit-after 600 dev/dev_shot.tscn
##
## Optional user args: "-- --panel tuning|cheats" opens a panel first,
## "-- --fill" covers the board with maxed towers, "-- --wave" starts a wave,
## "-- --select [type]" selects a tower, "-- --place <type>" puts one down,
## "-- --challenge <id|daily>" plays under a challenge. Add "--phone" (and a phone-shaped
## "--resolution 1300x600") to see the handheld layout.

var game: Node


func _ready() -> void:
	Progress.use_clean_state()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			# "--scene res://home.tscn" shoots a menu instead of a match.
			Progress.unlock_all = true
			set_meta("scene_scale_path", args[i + 1])
			var screen: Node = load(args[i + 1]).instantiate()
			add_child(screen)
			if screen is Control:
				App.fit_safe(screen)
			await get_tree().create_timer(0.8).timeout
			RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)
			return
	for i in args.size():
		if args[i] == "--challenge" and i + 1 < args.size():
			# "--challenge gun_line", or "--challenge daily" for today's.
			var c: Dictionary = Challenges.daily() if args[i + 1] == "daily" \
					else Challenges.by_id(args[i + 1])
			TDData.active_challenge = c.duplicate(true)
			TDData.selected_level = Challenges.level_index(c)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	if args.has("--pause"):
		game._toggle_pause()
	if args.has("--skip-tutorial") and game.tutorial != null:
		game.tutorial._skip()
	if args.has("--fold") and game.hud.handheld:
		# Folds the handheld column away.
		game.hud.toggle_column()
	for i in args.size():
		if args[i] == "--resize" and i + 1 < args.size():
			# "--resize 1300x600" changes the window after the first frame,
			# the way a phone reports its screen late: the HUD must relayout.
			var parts := args[i + 1].split("x")
			get_window().size = Vector2i(int(parts[0]), int(parts[1]))
			await get_tree().process_frame
			await get_tree().process_frame
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
				# "--mode upgrades|enemies" opens the panel on that tab.
				for j in args.size():
					if args[j] == "--mode" and j + 1 < args.size():
						game.tuning_panel._select_mode(args[j + 1])
	for i in args.size():
		if args[i] == "--spawn" and i + 1 < args.size():
			# Drops one creep of that kind on the board straight away.
			for n in 4:
				game.spawn_kind(args[i + 1])
	if args.has("--unlock"):
		# Every tower and every rank unlocked on the account, so the upgrade
		# buttons show prices rather than tech-tree locks.
		Progress.unlock_all = true
		for type_id: String in TDData.TOWERS:
			var full: Array = []
			for t: Dictionary in TDData.tracks(type_id):
				full.append(int(t["max"]))
			Progress.tower_ranks[type_id] = full
	var place_at := args.find("--place")
	if place_at >= 0 and place_at + 1 < args.size():
		# "--place cannon" or "--place tide,torpedo,wavegun": one plain tower
		# of each, on the first cell it fits.
		for want: String in args[place_at + 1].split(","):
			if not TDData.TOWERS.has(want):
				continue
			for key: Vector2i in game.terrain:
				if game.can_place(key, want):
					game._place_tower(want, key)
					break
	if args.has("--select") and not game.occupied.is_empty():
		# Selects the first tower on the board so the info panel is filled;
		# "--select airfield" picks the first of that kind.
		var pick: Tower = game.occupied.values()[0]
		var at := args.find("--select")
		if at + 1 < args.size() and TDData.TOWERS.has(args[at + 1]):
			for t: Tower in game.occupied.values():
				if t.type_id == args[at + 1]:
					pick = t
					break
		if args.has("--unlock"):
			# Partway up the first track, one rank short of its ability.
			pick.ranks[0] = maxi(0, int(TDData.tracks(pick.type_id)[0]["max"]) - 1)
		game._select(pick)
		if args.has("--moved"):
			# As after a move this wave: the Move button's longest label.
			game.move_used_wave = game.wave
		game.hud.refresh_info()
	var delay := 0.8
	for i in args.size():
		if args[i] == "--delay" and i + 1 < args.size():
			delay = float(args[i + 1])
	await get_tree().create_timer(delay, true, false, true).timeout
	if args.has("--hover") and not game.enemies.is_empty():
		# Park the pointer on a creep so its card is in the frame.
		var creep: Enemy = game.enemies[0]
		Input.warp_mouse(creep.position - Vector2(0.0, creep.radius * 1.15
				if creep.flying else 0.0))
		await get_tree().process_frame
		game.hud.refresh_creep_tip()
		await get_tree().process_frame
	RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)


func _grab() -> void:
	print("[SHOT] window %s viewport %s safe %s" % [get_window().size,
			get_viewport().get_visible_rect().size, App.safe_margins()])
	var path := OS.get_environment("SHOT_PATH")
	if path == "":
		path = "user://shot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] saved %s" % path)
	get_tree().quit()
