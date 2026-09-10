extends Control

## Tech tree: permanent purchases made with coins earned in matches.
##
## The left rail picks a category — the global doctrine nodes, or one tower —
## and the right pane shows what that category can buy. Tower upgrade ranks
## live here rather than inside a match, so they are bought once and apply to
## every tower of that type from the moment it is built.

const MENU_SCENE := "res://home.tscn"

var lbl_coins: Label
var lbl_level: Label
var rail_buttons: Dictionary = {}
var pane: VBoxContainer
var selected: String = "global"
var reset_armed: bool = false
var btn_reset: Button
var btn_respec: Button
var respec_armed: bool = false


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
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
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
	col.offset_top = 22.0
	col.offset_bottom = -22.0
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	head.add_child(_label("TECH TREE", 30, Color("4fc3f7")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	lbl_level = _label("", 16, Color("b0bec5"))
	head.add_child(lbl_level)
	lbl_coins = _label("", 20, Color("ffd54f"))
	head.add_child(lbl_coins)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(90.0, 34.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	head.add_child(back)

	col.add_child(_label("Coins are permanent. Doctrine applies straight away; tower ranks unlock what you may install with gold during a match.",
			12, Color(1, 1, 1, 0.45)))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var rail_scroll := ScrollContainer.new()
	rail_scroll.custom_minimum_size.x = 210
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(rail_scroll)
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	rail.custom_minimum_size.x = 196
	rail_scroll.add_child(rail)

	rail.add_child(_rail_button("global", "Doctrine"))
	rail.add_child(_label("TOWERS", 12, Color("607d8b")))
	for type_id: String in TDData.TOWER_ORDER:
		rail.add_child(_rail_button(type_id, str(TDData.TOWERS[type_id]["name"])))

	var pane_scroll := ScrollContainer.new()
	pane_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(pane_scroll)
	pane = VBoxContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_theme_constant_override("separation", 10)
	pane_scroll.add_child(pane)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	# Respec first: it is the one people actually want, and it sits well
	# clear of the button that erases the account.
	btn_respec = Button.new()
	btn_respec.custom_minimum_size = Vector2(300.0, 30.0)
	btn_respec.add_theme_font_size_override("font_size", 12)
	btn_respec.focus_mode = Control.FOCUS_NONE
	btn_respec.pressed.connect(_on_respec)
	foot.add_child(btn_respec)

	btn_reset = Button.new()
	btn_reset.text = "Reset all progress"
	btn_reset.custom_minimum_size = Vector2(190.0, 30.0)
	btn_reset.add_theme_font_size_override("font_size", 12)
	btn_reset.focus_mode = Control.FOCUS_NONE
	btn_reset.pressed.connect(_on_reset)
	foot.add_child(btn_reset)

	_show(selected)


func _rail_button(id: String, title: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0.0, 34.0)
	b.add_theme_font_size_override("font_size", 13)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.text = title
	b.pressed.connect(_show.bind(id))
	rail_buttons[id] = {"button": b, "title": title}
	return b


## Swaps the right-hand pane to a category and rebuilds it.
func _show(id: String) -> void:
	selected = id
	for child in pane.get_children():
		child.queue_free()
	if id == "global":
		_build_global()
	else:
		_build_tower(id)
	_refresh()


func _build_global() -> void:
	pane.add_child(_label("DOCTRINE — applies to every tower you build", 15, Color("90a4ae")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(grid)
	for t: Dictionary in Progress.TECH:
		grid.add_child(_global_card(t))


func _global_card(t: Dictionary) -> Control:
	var id := str(t["id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 124.0)
	card.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var name_label := _label(str(t["name"]), 16, Color("e3f2fd"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var rank_label := _label("", 13, Color("ffd54f"))
	head.add_child(rank_label)

	# Most nodes change numbers; a few just unlock something, and saying
	# "per rank" about those reads as a bug.
	var effect: String = Progress.describe(t["mods"])
	var unlocks: Array = t.get("unlocks", [])
	var detail := "%s per rank" % effect if effect != "" \
			else "Rank %d: %s" % [1, unlocks[0]] if unlocks.size() > 0 else ""
	if effect == "" and unlocks.size() > 1:
		var lines: Array = []
		for i in unlocks.size():
			lines.append("Rank %d: %s" % [i + 1, unlocks[i]])
		detail = "\n".join(lines)
	var desc := _label("%s\n%s" % [t["desc"], detail], 12, Color(1, 1, 1, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0.0, 28.0)
	buy.add_theme_font_size_override("font_size", 12)
	buy.focus_mode = Control.FOCUS_NONE
	buy.pressed.connect(_on_buy_global.bind(id))
	col.add_child(buy)

	card.set_meta("node_id", id)
	card.set_meta("rank_label", rank_label)
	card.set_meta("buy", buy)
	return card


func _build_tower(type_id: String) -> void:
	var d: Dictionary = TDData.TOWERS[type_id]
	pane.add_child(_label("%s — %s" % [str(d["name"]).to_upper(), d["desc"]], 15,
			Color("90a4ae")))
	if not Progress.tower_unlocked(type_id):
		pane.add_child(_label("This tower unlocks at account level %d."
				% Progress.tower_unlock_level(type_id), 13, Color("ef5350")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(grid)
	for i in TDData.tracks(type_id).size():
		grid.add_child(_track_card(type_id, i))


func _track_card(type_id: String, track: int) -> Control:
	var t: Dictionary = TDData.tracks(type_id)[track]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 150.0)
	card.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var cap: Dictionary = TDData.capstone(type_id, track)
	var title := str(t["name"]) + ("  *" if not cap.is_empty() else "")
	var name_label := _label(title, 16, Color("e3f2fd"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var rank_label := _label("", 13, Color("ffd54f"))
	head.add_child(rank_label)

	var effect := _label("%s per rank" % TDData.describe_mods(t["mods"]), 12,
			Color(1, 1, 1, 0.68))
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(effect)

	if not cap.is_empty():
		var capstone := _label("At %d/%d: %s — %s" % [int(t["max"]), int(t["max"]),
				cap["name"], cap["desc"]], 11, Color("ffd54f"))
		capstone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(capstone)

	var gate := _label("", 11, Color("90a4ae"))
	gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gate)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0.0, 28.0)
	buy.add_theme_font_size_override("font_size", 12)
	buy.focus_mode = Control.FOCUS_NONE
	buy.pressed.connect(_on_buy_track.bind(type_id, track))
	col.add_child(buy)

	card.set_meta("tower", type_id)
	card.set_meta("track", track)
	card.set_meta("rank_label", rank_label)
	card.set_meta("gate", gate)
	card.set_meta("buy", buy)
	return card


func _on_buy_global(id: String) -> void:
	if Progress.buy(id):
		_refresh()


func _on_buy_track(type_id: String, track: int) -> void:
	if Progress.buy_track(type_id, track):
		_refresh()


## Hands back most of what was spent and clears every rank, so a build can
## be undone. Two presses, like the reset button beside it.
func _on_respec() -> void:
	if not Progress.has_anything_to_respec():
		return
	if not respec_armed:
		respec_armed = true
		btn_respec.text = "Press again — clears every rank for %d coins back" \
				% Progress.respec_refund()
		return
	var refund := Progress.respec()
	respec_armed = false
	_show(selected)
	_refresh()
	btn_respec.text = "Refunded %d coins" % refund


func _on_reset() -> void:
	if not reset_armed:
		reset_armed = true
		btn_reset.text = "Press again to erase everything"
		return
	Progress.reset()
	reset_armed = false
	btn_reset.text = "Reset all progress"
	_show(selected)


func _refresh() -> void:
	var info := Progress.level_progress()
	lbl_level.text = "Level %d (the cap)   ·   %d XP" % [int(info["level"]), Progress.xp] \
			if bool(info.get("capped", false)) \
			else "Level %d   ·   %d / %d XP" % [int(info["level"]), Progress.xp,
			int(info["to"])]
	lbl_coins.text = "%d coins" % Progress.coins
	if btn_respec != null and not respec_armed:
		var spent := Progress.spent_on_tech()
		btn_respec.disabled = spent <= 0
		btn_respec.text = "Respec — refund %d of %d coins (%d%%)" % [
				Progress.respec_refund(), spent, int(Progress.RESPEC_REFUND * 100.0)] \
				if spent > 0 else "Respec — nothing bought yet"

	for id: String in rail_buttons:
		var parts: Dictionary = rail_buttons[id]
		var b: Button = parts["button"]
		var title: String = parts["title"]
		b.modulate = Color.WHITE
		if id == "global":
			var bought := 0
			for t: Dictionary in Progress.TECH:
				bought += Progress.rank(str(t["id"]))
			b.text = "%s   %d" % [title, bought]
		else:
			var owned := Progress.tower_rank_total(id)
			var top := 0
			for track: Dictionary in TDData.tracks(id):
				top += int(track["max"])
			b.text = "%s   %d/%d" % [title, owned, top]
			b.modulate = Color.WHITE if Progress.tower_unlocked(id) else Color(0.6, 0.64, 0.7)
		if id == selected:
			b.modulate = Color("9ce89c")

	for card in _all_cards(pane):
		if card.has_meta("node_id"):
			_refresh_global(card)
		else:
			_refresh_track(card)


func _all_cards(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is PanelContainer and (child.has_meta("node_id") or child.has_meta("track")):
			out.append(child)
		out.append_array(_all_cards(child))
	return out


func _refresh_global(card: PanelContainer) -> void:
	var id: String = card.get_meta("node_id")
	var t: Dictionary = Progress.node(id)
	var rank := Progress.rank(id)
	var top := int(t["max"])
	(card.get_meta("rank_label") as Label).text = "%d/%d" % [rank, top]
	var buy: Button = card.get_meta("buy")
	if rank >= top:
		buy.disabled = true
		buy.text = "Maxed"
		card.modulate = Color(1, 1, 1, 0.92)
	elif not Progress.node_available(id):
		buy.disabled = true
		buy.text = "Needs %s maxed" % Progress.node(str(t["requires"]))["name"]
		card.modulate = Color(0.62, 0.66, 0.72, 0.8)
	else:
		buy.disabled = Progress.coins < Progress.node_cost(id)
		buy.text = "Buy — %d coins" % Progress.node_cost(id)
		card.modulate = Color.WHITE


func _refresh_track(card: PanelContainer) -> void:
	var type_id: String = card.get_meta("tower")
	var track: int = card.get_meta("track")
	var t: Dictionary = TDData.tracks(type_id)[track]
	var rank := Progress.track_rank_for(type_id, track)
	var top := int(t["max"])
	var state := Progress.track_buy_state(type_id, track)
	(card.get_meta("rank_label") as Label).text = "%d/%d" % [rank, top]
	var gate: Label = card.get_meta("gate")
	var buy: Button = card.get_meta("buy")

	if bool(state["maxed"]):
		gate.text = "Every rank unlocked."
		buy.disabled = true
		buy.text = "Maxed"
		card.modulate = Color(1, 1, 1, 0.92)
		return
	if not bool(state["level_ok"]):
		gate.text = "Unlocks at account level %d." % Progress.track_unlock_level(type_id, track)
		buy.disabled = true
		buy.text = "Locked — level %d" % Progress.track_unlock_level(type_id, track)
		card.modulate = Color(0.62, 0.66, 0.72, 0.8)
		return
	if not bool(state["prereq_ok"]):
		var need: Dictionary = TDData.track_requirement(type_id, track)
		var parent := TDData.track_index(type_id, str(need["track"]))
		gate.text = "Opens once %s reaches rank %d." % [
				TDData.tracks(type_id)[parent]["name"], int(need["rank"])]
		buy.disabled = true
		buy.text = "Needs %s %d" % [TDData.tracks(type_id)[parent]["name"], int(need["rank"])]
		card.modulate = Color(0.62, 0.66, 0.72, 0.8)
		return
	gate.text = "Unlocks rank %d for install — $%d in a match." % [rank + 1,
			TDData.track_gold_cost(type_id, track, rank)]
	buy.disabled = not bool(state["affordable"])
	buy.text = "Unlock rank %d — %d coins" % [rank + 1, int(state["cost"])]
	card.modulate = Color.WHITE


## Escape backs out of a screen, wherever you are.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU_SCENE)
