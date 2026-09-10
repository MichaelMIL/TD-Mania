extends Control

## Career page for the active save: lifetime totals, a per-tower table and a
## per-map table.

const MENU_SCENE := "res://home.tscn"


func _ready() -> void:
	Progress.load_state()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
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
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## 12345 -> "12.3k" so long totals stay readable in a column.
static func short(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fm" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%.0f" % value


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0b1017")
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 44.0
	col.offset_right = -44.0
	col.offset_top = 24.0
	col.offset_bottom = -24.0
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	head.add_child(_label("CAREER", 30, Color("4fc3f7")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_label("Slot %d" % (Progress.slot + 1), 15, Color("90a4ae")))
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(90.0, 34.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	head.add_child(back)

	col.add_child(_summary_row())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_tower_table())
	body.add_child(_enemy_table())
	body.add_child(_map_table())


## The headline numbers, as a row of tiles.
func _summary_row() -> Control:
	var info := Progress.level_progress()
	var tiles: Array = [
		["Level", str(int(info["level"])), Color("4fc3f7")],
		["XP", short(float(Progress.xp)), Color("b0bec5")],
		["Coins", str(Progress.coins), Color("ffd54f")],
		["Runs", str(Progress.stat_int("runs")), Color("b0bec5")],
		["Waves cleared", str(Progress.stat_int("waves")), Color("b0bec5")],
		["Best wave", str(Progress.stat_int("best_wave")), Color("81c784")],
		["Kills", short(float(Progress.stat_int("kills"))), Color("ef9a9a")],
		["Damage", short(float(Progress.stat_int("damage"))), Color("ef9a9a")],
		["Leaks", str(Progress.stat_int("leaks")), Color("ef5350")],
		["Towers built", str(Progress.stat_int("towers_built")), Color("b0bec5")],
		["Gold earned", short(float(Progress.stat_int("gold_earned"))), Color("ffd54f")],
		["Coins earned", short(float(Progress.stat_int("coins_earned"))), Color("ffd54f")],
	]
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for tile: Array in tiles:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0.0, 56.0)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		panel.add_child(box)
		box.add_child(_label(str(tile[0]), 11, Color(1, 1, 1, 0.45)))
		box.add_child(_label(str(tile[1]), 22, tile[2]))
		grid.add_child(panel)
	return grid


func _panel(title: String) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _sb(Color("101823"), Color("2c3a52")))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(_label(title, 16, Color("90a4ae")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)
	return [panel, rows]


func _row(rows: VBoxContainer, cells: Array, size: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows.add_child(row)
	for i in cells.size():
		var l := _label(str(cells[i]), size, color)
		if i == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = 92
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)


func _tower_table() -> Control:
	var parts := _panel("TOWERS")
	var rows: VBoxContainer = parts[1]
	_row(rows, ["Tower", "Kills", "Built", "Ranks"], 12, Color(1, 1, 1, 0.45))
	var kills: Dictionary = Progress.stat("tower_kills", {})
	var built: Dictionary = Progress.stat("tower_built", {})
	var order: Array = TDData.TOWER_ORDER.duplicate()
	order.sort_custom(func(a, b): return int(kills.get(a, 0)) > int(kills.get(b, 0)))
	for type_id: String in order:
		var top := 0
		for track: Dictionary in TDData.tracks(type_id):
			top += int(track["max"])
		_row(rows, [TDData.TOWERS[type_id]["name"], short(float(int(kills.get(type_id, 0)))),
				str(int(built.get(type_id, 0))),
				"%d/%d" % [Progress.tower_rank_total(type_id), top]], 13,
				Color("e3f2fd") if int(kills.get(type_id, 0)) > 0 else Color(1, 1, 1, 0.4))
	return parts[0]


## Bestiary: how many of each kind you have killed, and how many got past.
func _enemy_table() -> Control:
	var parts := _panel("BESTIARY")
	var rows: VBoxContainer = parts[1]
	_row(rows, ["Enemy", "Killed", "Through"], 12, Color(1, 1, 1, 0.45))
	var kills: Dictionary = Progress.stat("enemy_kills", {})
	var leaks: Dictionary = Progress.stat("enemy_leaks", {})
	var order: Array = TDData.ENEMIES.keys()
	order.sort_custom(func(a, b): return int(kills.get(a, 0)) > int(kills.get(b, 0)))
	var total := 0
	for kind: String in order:
		total += int(kills.get(kind, 0))
	for kind: String in order:
		var killed := int(kills.get(kind, 0))
		var through := int(leaks.get(kind, 0))
		_row(rows, [TDData.ENEMIES[kind]["name"], short(float(killed)),
				str(through) if through > 0 else "-"], 13,
				Color("e3f2fd") if killed > 0 else Color(1, 1, 1, 0.4))
	_row(rows, ["Total", short(float(total)), str(Progress.stat_int("leaks"))], 13,
			Color("ffd54f"))
	return parts[0]


func _map_table() -> Control:
	var parts := _panel("BATTLEGROUNDS")
	var rows: VBoxContainer = parts[1]
	_row(rows, ["Map", "Best wave", "Tier"], 12, Color(1, 1, 1, 0.45))
	for area: Dictionary in TDData.AREAS:
		var members: Array = TDData.levels_in_area(str(area["id"]))
		if members.is_empty():
			continue
		_row(rows, [str(area["name"]).to_upper(), "", ""], 11, area["color"])
		for i: int in members:
			var d: Dictionary = TDData.LEVELS[i]
			var best := Progress.best_wave(str(d["id"]))
			var locked := not Progress.level_unlocked(d)
			var mark := "locked" if locked else ("wave %d" % best if best > 0 else "-")
			_row(rows, ["   " + str(d["name"]), mark, str(TDData.tier_of(d)["name"])], 13,
					Color(1, 1, 1, 0.35) if locked else Color("e3f2fd"))
	return parts[0]


## Escape backs out of a screen, wherever you are.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU_SCENE)
