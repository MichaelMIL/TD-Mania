extends Control

## Main menu. The slot screen picks who is playing; this is where they
## decide what to do — carry on a parked run, pick a map, spend coins, look
## at the numbers, or change how the game behaves.
##
## Level select used to be the first thing after choosing a slot, which
## meant everything else on the account hid behind a strip at the top of a
## list of maps.

const LEVELS_SCENE := "res://menu.tscn"
const GAME_SCENE := "res://game.tscn"
const SLOTS_SCENE := "res://main.tscn"

var status: Label


func _ready() -> void:
	Progress.load_state()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	Audio.play_music(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _sb(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _menu_button(text: String, hint: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = hint
	b.custom_minimum_size = Vector2(360.0, 46.0)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0b1017")
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var title := _label("TD MANIA", 58, Color("4fc3f7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := _label("%d towers · %d maps across %d areas · %d kinds of enemy"
			% [TDData.TOWERS.size(), TDData.LEVELS.size(), TDData.AREAS.size(),
			TDData.ENEMIES.size()], 15, Color(1, 1, 1, 0.45))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(_spacer(18.0))
	col.add_child(_account_card())
	col.add_child(_spacer(10.0))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var centre := HBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(buttons)
	col.add_child(centre)

	# Carrying on where you left off is the most likely thing, so it leads.
	var parked := _parked_run()
	if not parked.is_empty():
		var level: Dictionary = TDData.LEVELS[int(parked["index"])]
		var resume := _menu_button("Continue — %s, wave %d" % [level["name"],
				int(parked["wave"]) + 1],
				"Pick the parked run back up where it stopped", 19)
		resume.add_theme_color_override("font_color", Color("9ce89c"))
		resume.pressed.connect(_continue.bind(int(parked["index"])))
		buttons.add_child(resume)

	var play := _menu_button("Play", "Choose a battleground")
	play.pressed.connect(_go.bind(LEVELS_SCENE))
	buttons.add_child(play)

	var tech := _menu_button("Tech Tree", "Spend coins on permanent upgrades")
	tech.pressed.connect(_go.bind("res://tech.tscn"))
	buttons.add_child(tech)

	var stats := _menu_button("Stats", "Everything this save has done")
	stats.pressed.connect(_go.bind("res://stats.tscn"))
	buttons.add_child(stats)

	var options := _menu_button("Options", "Sound, window size and keys")
	options.pressed.connect(_go.bind("res://options.tscn"))
	buttons.add_child(options)

	var slot := _menu_button("Save slot %d" % (Progress.slot + 1),
			"Switch to another save", 15)
	slot.pressed.connect(_go.bind(SLOTS_SCENE))
	buttons.add_child(slot)

	var quit := _menu_button("Quit", "Close the game", 15)
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)

	status = _label("Escape closes a screen. Everything here is saved as you go.",
			12, Color(1, 1, 1, 0.35))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_spacer(10.0))
	col.add_child(status)


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	return c


## What the account has, in one line each.
func _account_card() -> Control:
	var info := Progress.level_progress()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _sb(Color("101823"), Color("2c3a52")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	row.add_child(_label("LEVEL %d" % int(info["level"]), 20, Color("4fc3f7")))
	row.add_child(_label("◈ %d" % Progress.coins, 18, Color("ffd54f")))
	row.add_child(_label("★ %d / %d" % [Progress.total_stars(),
			TDData.LEVELS.size() * 3], 18, Color("ffd54f")))
	row.add_child(_label("Cleared %d / %d" % [Progress.cleared_count(),
			TDData.LEVELS.size()], 16, Color("9ccc65")))
	return panel


## The parked run to offer, if there is one: the deepest of them.
func _parked_run() -> Dictionary:
	var best: Dictionary = {}
	for i in TDData.LEVELS.size():
		var run: Dictionary = Progress.run_for(str(TDData.LEVELS[i]["id"]))
		if run.is_empty():
			continue
		if best.is_empty() or int(run.get("wave", 0)) > int(best.get("wave", 0)):
			best = {"index": i, "wave": int(run.get("wave", 0))}
	return best


func _continue(index: int) -> void:
	TDData.selected_level = index
	TDData.resume_run = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		# Escape from the main menu goes back to choosing who is playing.
		get_viewport().set_input_as_handled()
		_go(SLOTS_SCENE)
