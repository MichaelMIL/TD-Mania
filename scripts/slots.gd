extends Control

## Title screen: pick one of three save slots. Each slot keeps its own level,
## coins, tech and per-map records.

const MENU_SCENE := "res://menu.tscn"

var cards: Dictionary = {}
var armed_erase: int = -1


func _ready() -> void:
	Progress.migrate_legacy()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	# The window size the player chose in Options, applied once at startup.
	Progress.apply_window_scale()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _sb(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
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
	col.offset_left = 120.0
	col.offset_right = -120.0
	col.offset_top = 90.0
	col.offset_bottom = -90.0
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title := _label("TD MANIA", 60, Color("4fc3f7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := _label("Choose a save slot", 18, Color(1, 1, 1, 0.55))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var pad := Control.new()
	pad.custom_minimum_size.y = 12
	col.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	for i in Progress.SLOTS:
		row.add_child(_slot_card(i))

	var foot := _label("Each slot keeps its own account level, coins, tech tree and map records.",
			13, Color(1, 1, 1, 0.4))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)

	var quit_row := HBoxContainer.new()
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(quit_row)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(100.0, 34.0)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func(): get_tree().quit())
	quit_row.add_child(quit)

	_refresh()


func _slot_card(index: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 300.0)
	card.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	col.add_child(_label("SLOT %d" % (index + 1), 24, Color("e3f2fd")))

	var body := _label("", 14, Color(1, 1, 1, 0.7))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var play := Button.new()
	play.custom_minimum_size = Vector2(0.0, 42.0)
	play.add_theme_font_size_override("font_size", 16)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(_on_play.bind(index))
	col.add_child(play)

	var erase := Button.new()
	erase.custom_minimum_size = Vector2(0.0, 30.0)
	erase.add_theme_font_size_override("font_size", 12)
	erase.focus_mode = Control.FOCUS_NONE
	erase.pressed.connect(_on_erase.bind(index))
	col.add_child(erase)

	cards[index] = {"card": card, "body": body, "play": play, "erase": erase}
	return card


func _on_play(index: int) -> void:
	Progress.use_slot(index)
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_erase(index: int) -> void:
	if armed_erase != index:
		armed_erase = index
		_refresh()
		return
	Progress.erase_slot(index)
	armed_erase = -1
	_refresh()


func _refresh() -> void:
	for index: int in cards:
		var parts: Dictionary = cards[index]
		var info := Progress.slot_summary(index)
		var used := bool(info["used"])
		if used:
			parts["body"].text = "Level %d\n%d XP\n%d coins\n\n%d maps played\nBest wave %d\n%d tech ranks" \
					% [int(info["level"]), int(info["xp"]), int(info["coins"]),
					int(info["maps"]), int(info["best"]), int(info["tech"])]
			parts["play"].text = "Continue"
			parts["erase"].visible = true
			parts["erase"].text = "Erase this slot?" if armed_erase == index else "Erase"
			parts["card"].modulate = Color.WHITE
		else:
			parts["body"].text = "Empty slot\n\nStart a fresh account:\nlevel 1, no coins,\nno tech."
			parts["play"].text = "New game"
			parts["erase"].visible = false
			parts["card"].modulate = Color(0.85, 0.88, 0.94)
