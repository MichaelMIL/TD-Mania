extends Control

## Main menu and level select. Draws a small preview of each map's path and
## terrain straight from the level data, so the cards never fall out of sync
## with the maps themselves.

const GAME_SCENE := "res://game.tscn"

var best: Dictionary = {}
var hovered: int = -1
## Which area sections are open; areas with nothing unlocked start closed.
var expanded: Dictionary = {}


func _ready() -> void:
	Progress.load_state()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	best = Progress.bests
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _sb(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
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
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0b1017")
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 40.0
	col.offset_right = -40.0
	col.offset_top = 26.0
	col.offset_bottom = -26.0
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var title := _label("TD MANIA", 44, Color("4fc3f7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Counted from the tables, so it cannot go stale again.
	var sub := _label("%d towers. %d battlegrounds across %d areas. %d kinds of enemy. Endless waves."
			% [TDData.TOWERS.size(), TDData.LEVELS.size(), TDData.AREAS.size(),
			TDData.ENEMIES.size()], 16,
			Color(1, 1, 1, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(_account_bar())

	var pad := Control.new()
	pad.custom_minimum_size.y = 10
	col.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var areas := VBoxContainer.new()
	areas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	areas.add_theme_constant_override("separation", 14)
	scroll.add_child(areas)

	# One collapsible section per area.
	for area: Dictionary in TDData.AREAS:
		var members: Array = TDData.levels_in_area(str(area["id"]))
		if members.is_empty():
			continue
		var area_id := str(area["id"])
		if not expanded.has(area_id):
			expanded[area_id] = _area_open(members)
		var grid := GridContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		grid.visible = bool(expanded[area_id])
		areas.add_child(_area_header(area, members, grid))
		areas.add_child(grid)
		members.sort_custom(_easier_first)
		for i: int in members:
			grid.add_child(_level_card(i))

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)

	foot.add_child(_label(
			"Drag towers from the palette  ·  Space starts a wave early  ·  A auto-start  ·  U upgrade  ·  T target  ·  X sell",
			13, Color(1, 1, 1, 0.4)))

	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(90.0, 34.0)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func(): get_tree().quit())
	foot.add_child(quit)


## Account strip. Two rows rather than one: progress on top, what the
## account owns and where it can go underneath. Eight things fought over
## one line before, and the XP bar always lost.
func _account_bar() -> Control:
	var info := Progress.level_progress()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color("101823"), Color("2c3a52"), 8))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	# ---- row one: level and the road to the next one
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	col.add_child(top)

	var level_label := _label("LEVEL %d" % int(info["level"]), 20, Color("4fc3f7"))
	level_label.custom_minimum_size.x = 110.0
	top.add_child(level_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 14.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = float(info["ratio"])
	bar.show_percentage = false
	# The default theme draws an empty bar as nothing at all, so a fresh
	# account looked like it had no XP bar rather than an empty one.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("1b2637")
	track.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("4fc3f7")
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	var span := int(info["to"]) - int(info["from"])
	var into := Progress.xp - int(info["from"])
	bar.tooltip_text = "Level %d is the cap; XP still counts towards records." \
			% Progress.MAX_LEVEL if bool(info.get("capped", false)) \
			else "%d / %d XP to level %d" % [into, span, int(info["level"]) + 1]
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(bar)

	var xp_label := _label("Level %d — the cap" % Progress.MAX_LEVEL
			if bool(info.get("capped", false)) else "%d / %d XP" % [into, span],
			12, Color(1, 1, 1, 0.55))
	xp_label.custom_minimum_size.x = 130.0
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(xp_label)

	var next: Dictionary = Progress.next_unlock()
	var unlock_text := "Everything unlocked"
	if not next.is_empty():
		unlock_text = "Next at Lv %d: %s" % [int(next["level"]), next["what"]]
	var unlock_label := _label(unlock_text, 13, Color("90a4ae"))
	unlock_label.custom_minimum_size.x = 250.0
	unlock_label.clip_text = true
	unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unlock_label.tooltip_text = unlock_text
	top.add_child(unlock_label)

	# ---- row two: what the account owns, and where it can go
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	col.add_child(bottom)

	bottom.add_child(_owned("◈ %d" % Progress.coins, Color("ffd54f"), 150.0,
			"Coins earned from runs. Spent in the tech tree."))
	bottom.add_child(_owned("★ %d / %d" % [Progress.total_stars(),
			TDData.LEVELS.size() * 3], Color("ffd54f"), 120.0,
			"Objective stars. Three on every map."))
	bottom.add_child(_owned("Cleared %d / %d" % [Progress.cleared_count(),
			TDData.LEVELS.size()], Color("9ccc65"), 150.0,
			"Maps whose last wave you have beaten."))

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)

	for entry: Array in [
		["Menu", "res://home.tscn", 84.0, "Back to the main menu (Escape)"],
		["Slot %d" % (Progress.slot + 1), "res://main.tscn", 88.0,
			"Switch save slot"],
		["Options", "res://options.tscn", 92.0, "Sound, window size and keys"],
		["Stats", "res://stats.tscn", 84.0, "Everything this save has done"],
		["Tech Tree", "res://tech.tscn", 112.0, "Spend coins on permanent upgrades"],
	]:
		var b := Button.new()
		b.text = str(entry[0])
		b.tooltip_text = str(entry[3])
		b.custom_minimum_size = Vector2(float(entry[2]), 36.0)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): get_tree().change_scene_to_file(str(entry[1])))
		bottom.add_child(b)
	return panel


## One thing the account owns, in a field wide enough for a big number.
func _owned(text: String, color: Color, width: float, hint: String) -> Label:
	var l := _label(text, 17, color)
	l.custom_minimum_size.x = width
	l.clip_text = true
	l.tooltip_text = hint
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Area banner: name, blurb, difficulty span and how many of its maps have
## been played on this save.
## An area opens by default once any of its maps is unlocked.
func _area_open(members: Array) -> bool:
	for i: int in members:
		if Progress.level_unlocked(TDData.LEVELS[i]):
			return true
	return false


func _area_header(area: Dictionary, members: Array, grid: Control) -> Control:
	var accent: Color = area["color"]
	var panel := PanelContainer.new()
	var box := _sb(Color(accent.r, accent.g, accent.b, 0.10), Color(accent.r, accent.g,
			accent.b, 0.45), 8)
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var area_id := str(area["id"])
	var toggle := Button.new()
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(30.0, 30.0)
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.text = "-" if bool(expanded[area_id]) else "+"
	toggle.tooltip_text = "Collapse or expand this area"
	toggle.pressed.connect(_toggle_area.bind(area_id, grid, toggle))
	row.add_child(toggle)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	titles.add_child(_label(str(area["name"]).to_upper(), 19, accent))
	titles.add_child(_label(str(area["blurb"]), 12, Color(1, 1, 1, 0.45)))

	var lowest := 99
	var highest := 0
	var played := 0
	var open_maps := 0
	var soonest := 99
	for i: int in members:
		var d: Dictionary = TDData.LEVELS[i]
		lowest = mini(lowest, int(d["tier"]))
		highest = maxi(highest, int(d["tier"]))
		if int(best.get(str(d["id"]), 0)) > 0:
			played += 1
		if Progress.level_unlocked(d):
			open_maps += 1
		else:
			soonest = mini(soonest, TDData.level_unlock(d))
	var span := str(TDData.TIERS[lowest]["name"])
	if highest != lowest:
		span += " - " + str(TDData.TIERS[highest]["name"])
	var status := "%s   ·   %d/%d played" % [span, played, members.size()]
	if open_maps == 0:
		status = "%s   ·   unlocks at level %d" % [span, soonest]
	elif open_maps < members.size():
		status = "%s   ·   %d/%d played   ·   %d locked" % [span, played, members.size(),
				members.size() - open_maps]
	row.add_child(_label(status, 13, Color(1, 1, 1, 0.55)))
	return panel


func _toggle_area(area_id: String, grid: Control, toggle: Button) -> void:
	expanded[area_id] = not bool(expanded[area_id])
	grid.visible = bool(expanded[area_id])
	toggle.text = "-" if bool(expanded[area_id]) else "+"


func _easier_first(a: int, b: int) -> bool:
	return int(TDData.LEVELS[a]["tier"]) < int(TDData.LEVELS[b]["tier"])


## The map's objectives, each marked with whether the account holds it.
func _objective_texts(level: Dictionary, earned: int) -> Array:
	var out: Array = []
	var goals: Array = TDData.objectives_for(level)
	for i in goals.size():
		out.append("%s  %s" % ["★" if earned & (1 << i) != 0 else "☆",
				str(goals[i]["text"])])
	return out


func _level_card(index: int) -> Control:
	var d: Dictionary = TDData.LEVELS[index]
	var tier: Dictionary = TDData.tier_of(d)
	var accent: Color = tier["color"]

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 162.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			_sb(Color("121a26"), Color(accent.r, accent.g, accent.b, 0.55)))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(_label(str(d["name"]), 21, Color("e3f2fd")))
	titles.add_child(_label(str(d.get("theme", "")).to_upper(), 11, Color(1, 1, 1, 0.4)))
	# Stars earned on this map, filled for the ones held.
	var earned := Progress.stars_for(str(d["id"]))
	var marks := ""
	for i in TDData.objectives_for(d).size():
		marks += "★" if earned & (1 << i) != 0 else "☆"
	var star_label := _label(marks, 17, Color("ffd54f"))
	star_label.tooltip_text = "\n".join(_objective_texts(d, earned))
	head.add_child(star_label)
	head.add_child(_difficulty_pill(d))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)

	var preview := LevelPreview.new()
	preview.level_index = index
	preview.custom_minimum_size = Vector2(162.0, 84.0)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(preview)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)

	var blurb := _label(str(d["blurb"]), 12, Color(1, 1, 1, 0.62))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(148.0, 34.0)
	text.add_child(blurb)

	var water_cells := 0
	for r: Array in d["water"]:
		water_cells += int(r[2]) * int(r[3])
	var stats := _label("Gold %d · Lives %d · Clear at wave %d\nHP x%.2f · Water %d" % [
		int(TDData.level_stat(d, "gold")), int(TDData.level_stat(d, "lives")),
		TDData.clear_wave(d), TDData.level_stat(d, "hp_scale"), water_cells],
		12, Color("90a4ae"))
	text.add_child(stats)

	var unlocked := Progress.level_unlocked(d)
	var record := int(best.get(str(d["id"]), 0))
	var parked: Dictionary = Progress.run_for(str(d["id"]))
	var status := "Best: wave %d" % record if record > 0 else "Not played yet"
	if Progress.is_cleared(str(d["id"])):
		# Once a map is beaten, how far past the finish line matters more
		# than the wave number on its own.
		var past := Progress.endless_best(str(d["id"]))
		status = "CLEARED · %s" % ("endless: %d past the finish" % past if past > 0
				else "no endless run yet")
	if not unlocked:
		status = "Locked"
	elif not parked.is_empty():
		status = "Run in progress — wave %d   ·   %s" % [int(parked.get("wave", 0)) + 1,
				status]
	text.add_child(_label(status, 13, Color("ffd54f") if unlocked else Color("90a4ae")))
	if unlocked:
		var goals := _label("  ·  ".join(_objective_texts(d, Progress.stars_for(str(d["id"])))),
				11, Color(1, 1, 1, 0.5))
		goals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(goals)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	col.add_child(buttons)

	if unlocked and not parked.is_empty():
		var resume := Button.new()
		resume.text = "Continue — wave %d" % (int(parked.get("wave", 0)) + 1)
		resume.custom_minimum_size = Vector2(0.0, 34.0)
		resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resume.add_theme_font_size_override("font_size", 14)
		resume.focus_mode = Control.FOCUS_NONE
		resume.pressed.connect(_play.bind(index, true))
		buttons.add_child(resume)

	var play := Button.new()
	play.text = "Play" if unlocked else "Unlocks at level %d" % TDData.level_unlock(d)
	if unlocked and not parked.is_empty():
		play.text = "New run"
		play.tooltip_text = "Starts over and discards the parked run"
	play.disabled = not unlocked
	play.custom_minimum_size = Vector2(0.0, 34.0)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.add_theme_font_size_override("font_size", 15)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(_play.bind(index, false))
	buttons.add_child(play)
	if not unlocked:
		card.modulate = Color(0.62, 0.66, 0.72, 0.85)
	return card


## Coloured difficulty chip: tier name plus its place in the ladder.
func _difficulty_pill(level: Dictionary) -> Control:
	var tier: Dictionary = TDData.tier_of(level)
	var accent: Color = tier["color"]
	var pill := PanelContainer.new()
	var box := _sb(Color(accent.r, accent.g, accent.b, 0.22), accent, 10)
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", box)
	var text := _label("%s %d/%d" % [str(tier["name"]).to_upper(),
			int(level["tier"]) + 1, TDData.TIERS.size()], 12, accent)
	pill.add_child(text)
	return pill


func _play(index: int, resume: bool = false) -> void:
	TDData.selected_level = index
	TDData.resume_run = resume
	if not resume:
		# A fresh run only discards this map's own parked save.
		Progress.clear_run(str(TDData.LEVELS[index]["id"]))
	get_tree().change_scene_to_file(GAME_SCENE)


## Escape goes back to the main menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://home.tscn")
