class_name Cheats
extends Control

## Developer cheat panel. Toggled with F1 during a match (or from any screen
## that adds it). Off by default, and a run that uses one is flagged so it
## cannot quietly set a personal best.

## Live toggles the game consults.
static var god_mode: bool = false
static var free_build: bool = false
## Every tower placed comes out of the box with every rank installed.
static var max_towers: bool = false
static var enabled: bool = false

var game: Node = null
var panel: PanelContainer
var log_label: Label


## Cheats are available from a debug build, or with --cheats on the command
## line for an exported one.
static func available() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_args().has("--cheats")


static func reset_toggles() -> void:
	god_mode = false
	free_build = false
	max_towers = false


func _ready() -> void:
	# Offsets too, or the panel anchors to a zero-size rect in the corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _sb() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.12, 0.96)
	sb.border_color = Color("ce93d8")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	col.add_child(_label("DEVELOPER CHEATS", 20, Color("ce93d8")))
	col.add_child(_label("F1 closes this. Using any cheat marks the run and blocks new records.",
			11, Color(1, 1, 1, 0.5)))

	col.add_child(_label("THIS RUN", 12, Color("90a4ae")))
	var run_grid := GridContainer.new()
	run_grid.columns = 3
	run_grid.add_theme_constant_override("h_separation", 6)
	run_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(run_grid)
	for entry: Array in [
		["+ $1000", "gold"], ["+ 10 lives", "lives"], ["Kill all creeps", "kill"],
		["Finish wave", "wave"], ["Jump 5 waves", "jump5"], ["Spawn boss", "boss"],
		["God mode", "god"], ["Free building", "free"], ["Speed 10x", "fast"],
		["Maxed buildings", "maxed"], ["Fill map with towers", "fill"],
	]:
		run_grid.add_child(_action(str(entry[0]), str(entry[1])))

	col.add_child(_label("ACCOUNT", 12, Color("90a4ae")))
	var acct := GridContainer.new()
	acct.columns = 3
	acct.add_theme_constant_override("h_separation", 6)
	acct.add_theme_constant_override("v_separation", 6)
	col.add_child(acct)
	for entry: Array in [
		["+ 1000 coins", "coins"], ["+ 5000 XP", "xp"], ["Max level", "maxlevel"],
		["Unlock all (session)", "unlock"], ["Buy every upgrade", "buyall"],
		["Wipe this slot", "wipe"],
	]:
		acct.add_child(_action(str(entry[0]), str(entry[1])))

	log_label = _label("Ready.", 12, Color("ffd54f"))
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(log_label)


func _action(text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180.0, 34.0)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_run.bind(id, b))
	return b


func toggle() -> void:
	visible = not visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if visible:
		_say("Cheats open. Toggles: god %s, free build %s, maxed builds %s."
				% ["on" if god_mode else "off", "on" if free_build else "off",
				"on" if max_towers else "off"])


func _say(text: String) -> void:
	if log_label != null:
		log_label.text = text


## Runs one cheat. Everything funnels through here so each one can mark the
## run as cheated in the same place.
func _run(id: String, button: Button) -> void:
	var live: bool = game != null and is_instance_valid(game)
	if live:
		game.cheats_used = true
	match id:
		"gold":
			if live:
				game.gold += 1000
				_say("Granted $1000.")
		"lives":
			if live:
				game.lives += 10
				_say("Granted 10 lives.")
		"kill":
			if live:
				var killed := 0
				for e in game.enemies.duplicate():
					if is_instance_valid(e) and not e.dead:
						e.take_damage(1000000.0, true)
						killed += 1
				_say("Killed %d creeps." % killed)
		"wave":
			if live:
				game.finish_wave_now()
				_say("Wave %d closed out." % game.wave)
		"jump5":
			if live:
				game.skip_waves(5)
				_say("Jumped to wave %d." % game.wave)
		"boss":
			if live:
				game.spawn_kind("boss")
				_say("Behemoth incoming.")
		"god":
			god_mode = not god_mode
			button.modulate = Color("9ce89c") if god_mode else Color.WHITE
			_say("God mode %s." % ("on" if god_mode else "off"))
		"free":
			free_build = not free_build
			button.modulate = Color("9ce89c") if free_build else Color.WHITE
			_say("Free building %s." % ("on" if free_build else "off"))
		"maxed":
			max_towers = not max_towers
			button.modulate = Color("9ce89c") if max_towers else Color.WHITE
			var upgraded := 0
			if max_towers and live:
				# Bring everything already on the board up to full as well.
				for t in game.occupied.values():
					if is_instance_valid(t):
						upgraded += t.max_out()
			_say("Maxed buildings %s.%s" % ["on" if max_towers else "off",
					"  Upgraded %d standing towers." % upgraded if upgraded > 0 else ""])
		"fill":
			if live:
				var placed: int = game.fill_with_random_towers()
				_say("Filled every free cell: %d maxed towers placed." % placed)
		"fast":
			var fast: bool = not is_equal_approx(Engine.time_scale, 10.0)
			Engine.time_scale = 10.0 if fast else 1.0
			button.modulate = Color("9ce89c") if fast else Color.WHITE
			_say("Time scale %.0fx." % Engine.time_scale)
		"coins":
			Progress.coins += 1000
			Progress.save_state()
			_say("Coins: %d." % Progress.coins)
		"xp":
			Progress.xp += 5000
			Progress.save_state()
			_say("Level %d (%d XP)." % [Progress.level(), Progress.xp])
		"maxlevel":
			Progress.xp = Progress.xp_for_level(25)
			Progress.save_state()
			_say("Level %d." % Progress.level())
		"unlock":
			Progress.unlock_all = not Progress.unlock_all
			button.modulate = Color("9ce89c") if Progress.unlock_all else Color.WHITE
			_say("Everything unlocked: %s (this session)."
					% ("yes" if Progress.unlock_all else "no"))
		"buyall":
			var bought := 0
			for type_id: String in TDData.TOWER_ORDER:
				var list: Array = Progress.ranks_for(type_id)
				for i in list.size():
					var top: int = int(TDData.tracks(type_id)[i]["max"])
					if int(list[i]) < top:
						bought += top - int(list[i])
					list[i] = top
				Progress.tower_ranks[type_id] = list
			for t: Dictionary in Progress.TECH:
				Progress.ranks[str(t["id"])] = int(t["max"])
			Progress.save_state()
			_say("Unlocked %d tower ranks and every doctrine node." % bought)
		"wipe":
			Progress.reset()
			_say("Slot %d wiped." % (Progress.slot + 1))
	if live:
		game.hud.refresh_info()
