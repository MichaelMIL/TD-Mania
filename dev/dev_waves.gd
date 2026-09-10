extends Node

## Prints the wave curve so the tables in `data.gd` can be read as numbers
## rather than guessed at:
##
##   godot --headless --quit-after 300 dev/dev_waves.tscn
##   godot --headless --quit-after 300 dev/dev_waves.tscn -- --area wastes
##
## With no area it prints the totals for every area side by side.

var game: Node


func _ready() -> void:
	Progress.use_clean_state()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only := ""
	for i in args.size():
		if args[i] == "--area" and i + 1 < args.size():
			only = args[i + 1]
	if only != "":
		_dump_area(only)
	else:
		_compare_areas()
	get_tree().quit()


func _use(area_id: String) -> bool:
	var maps: Array = TDData.levels_in_area(area_id)
	if maps.is_empty():
		return false
	game.level_def = TDData.LEVELS[int(maps[0])]
	return true


func _dump_area(area_id: String) -> void:
	if not _use(area_id):
		print("[WAVES] no maps in area '%s'" % area_id)
		return
	for n in range(1, 31):
		var parts: PackedStringArray = []
		var comp: Dictionary = game.wave_composition(n)
		var total := 0
		for kind: String in comp:
			parts.append("%s:%d" % [kind, int(comp[kind])])
			total += int(comp[kind])
		var span := 0.0
		for e: Dictionary in game._build_wave(n):
			span = maxf(span, float(e["t"]))
		print("[WAVE %d] %s | %d creeps over %.1fs" % [n, ",".join(parts), total, span])


func _compare_areas() -> void:
	for area: Dictionary in TDData.AREAS:
		if not _use(str(area["id"])):
			continue
		var line := ""
		for n in [5, 10, 15, 20, 25, 30]:
			var total := 0
			var comp: Dictionary = game.wave_composition(n)
			for kind: String in comp:
				total += int(comp[kind])
			line += "  w%d:%d(%d kinds)" % [n, total, comp.size()]
		print("[AREA] %-12s%s" % [area["id"], line])
