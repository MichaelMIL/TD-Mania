class_name TuningPanel
extends Control

## Live balance editor. F2 during a match opens it: pick a tower on the left,
## nudge its numbers on the right, and watch the change take effect in the
## running game — towers re-read their stats every frame.
##
## Each stat can be set for this level alone or for every level, so a tower
## that is fine on Easy and absurd on Brutal is fixed only where it is wrong.
## Save writes `user://td_mania_tuning.cfg`; Revert throws away everything
## unsaved. Nothing here touches a save slot.

var game: Node = null
var panel: PanelContainer
var list_col: VBoxContainer
var rows_col: VBoxContainer
var title: Label
var status: Label
var scope_button: Button

var current: String = "gun"
## -1 edits the global layer; otherwise the id of the level being played.
var scope_level: int = -1
var tower_buttons: Dictionary = {}
var value_labels: Dictionary = {}


static func available() -> bool:
	return Cheats.available()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Tuning.ensure_loaded()
	_build()
	visible = false


func level_id() -> int:
	if game != null and is_instance_valid(game) and game.level_def != null:
		return int(game.level_def["id"])
	return TDData.selected_level


func level_name() -> String:
	if game != null and is_instance_valid(game) and game.level_def != null:
		return str(game.level_def["name"])
	return "this level"


func _sb(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
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


func _small_button(text: String, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 26.0)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -370.0
	panel.offset_right = 370.0
	panel.offset_top = -290.0
	panel.offset_bottom = 290.0
	panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.09, 0.11, 0.97),
			Color("4dd0e1")))
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	col.add_child(_label("BALANCE TUNING", 20, Color("4dd0e1")))
	col.add_child(_label("F2 closes this. Changes apply live; Save keeps them between runs.",
			11, Color(1, 1, 1, 0.5)))

	var scope_row := HBoxContainer.new()
	scope_row.add_theme_constant_override("separation", 6)
	col.add_child(scope_row)
	scope_button = _small_button("", 250.0)
	scope_button.pressed.connect(_toggle_scope)
	scope_row.add_child(scope_button)
	var save := _small_button("Save", 90.0)
	save.pressed.connect(_save)
	scope_row.add_child(save)
	var revert := _small_button("Revert", 90.0)
	revert.pressed.connect(_revert)
	scope_row.add_child(revert)
	var wipe := _small_button("Reset all", 100.0)
	wipe.pressed.connect(_reset_all)
	scope_row.add_child(wipe)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(150.0, 0.0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(list_scroll)
	list_col = VBoxContainer.new()
	list_col.add_theme_constant_override("separation", 2)
	list_scroll.add_child(list_col)
	for type_id: String in TDData.TOWERS:
		var b := _small_button(str(TDData.TOWERS[type_id].get("short",
				TDData.TOWERS[type_id]["name"])), 138.0)
		b.pressed.connect(_select_tower.bind(type_id))
		list_col.add_child(b)
		tower_buttons[type_id] = b

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	title = _label("", 15, Color("e0f7fa"))
	right.add_child(title)
	var rows_scroll := ScrollContainer.new()
	rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rows_scroll)
	rows_col = VBoxContainer.new()
	rows_col.add_theme_constant_override("separation", 3)
	rows_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll.add_child(rows_col)

	status = _label("Ready.", 12, Color("ffd54f"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)

	_select_tower(current)


## One stat: name, minus, value, plus, and a reset that drops the override.
func _build_rows() -> void:
	for child in rows_col.get_children():
		rows_col.remove_child(child)
		child.queue_free()
	value_labels = {}
	for row: Dictionary in Tuning.rows_for(current):
		var key := str(row["key"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		rows_col.add_child(line)
		var name_label := _label(str(row["name"]), 13, Color(1, 1, 1, 0.75))
		name_label.custom_minimum_size = Vector2(96.0, 0.0)
		line.add_child(name_label)
		var minus := _small_button("−", 30.0)
		minus.pressed.connect(_nudge.bind(key, -1.0))
		line.add_child(minus)
		var value := _label("", 13, Color("ffd54f"))
		value.custom_minimum_size = Vector2(120.0, 0.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(value)
		value_labels[key] = value
		var plus := _small_button("+", 30.0)
		plus.pressed.connect(_nudge.bind(key, 1.0))
		line.add_child(plus)
		var reset := _small_button("reset", 58.0)
		reset.pressed.connect(_reset_stat.bind(key))
		line.add_child(reset)
	_refresh_values()


func _refresh_values() -> void:
	var scope := scope_level
	for key: String in value_labels:
		var base := float(TDData.TOWERS[current].get(key, 0.0))
		var now := Tuning.value_of(current, key, level_id() if scope >= 0 else -1)
		var label: Label = value_labels[key]
		var text := "%.2f" % now if absf(now) < 10.0 else "%.0f" % now
		if not is_equal_approx(now, base):
			var delta := (now / base - 1.0) * 100.0 if not is_zero_approx(base) else 0.0
			text += "  (%+d%%)" % int(round(delta))
			label.add_theme_color_override("font_color", Color("ff8a65"))
		else:
			label.add_theme_color_override("font_color", Color("ffd54f"))
		label.text = text
	scope_button.text = "Scope: %s" % ("all levels" if scope_level < 0
			else "%s only" % level_name())
	for type_id: String in tower_buttons:
		var button: Button = tower_buttons[type_id]
		var tuned := not Tuning.effective(type_id, level_id()).is_empty()
		button.modulate = Color("ff8a65") if tuned else Color.WHITE
		if type_id == current:
			button.modulate = button.modulate.lightened(0.3)
	title.text = "%s — %s" % [TDData.TOWERS[current]["name"],
			"tuned" if not Tuning.effective(current, level_id()).is_empty() else "stock"]


func _select_tower(type_id: String) -> void:
	current = type_id
	_build_rows()


func _toggle_scope() -> void:
	scope_level = level_id() if scope_level < 0 else -1
	_refresh_values()
	_say("Editing %s." % ("every level" if scope_level < 0 else level_name()))


## A click moves the stat by its step; the value is clamped to something the
## game can still run with.
func _nudge(key: String, direction: float) -> void:
	var row: Dictionary = {}
	for candidate: Dictionary in Tuning.TUNABLE:
		if str(candidate["key"]) == key:
			row = candidate
	if row.is_empty():
		return
	var scope := scope_level if scope_level >= 0 else -1
	var now := Tuning.value_of(current, key, level_id() if scope >= 0 else -1)
	var next: float = clampf(now + direction * float(row["step"]),
			float(row["min"]), float(row["max"]))
	Tuning.set_value(current, key, next, scope)
	_refresh_values()
	_say("%s %s = %.2f (%s)" % [TDData.TOWERS[current]["name"], row["name"], next,
			"all levels" if scope < 0 else level_name()])


func _reset_stat(key: String) -> void:
	Tuning.clear_value(current, key, scope_level)
	_refresh_values()
	_say("%s back to the table value." % key)


func _save() -> void:
	if Tuning.save_file():
		_say("Saved to %s." % Tuning.FILE_PATH)
	else:
		_say("Nothing written — this session is read-only.")


func _revert() -> void:
	Tuning.load_file()
	_refresh_values()
	_say("Reloaded the saved numbers; unsaved changes are gone.")


func _reset_all() -> void:
	Tuning.clear_all()
	Tuning.save_file()
	_refresh_values()
	_say("Every tower is back to the numbers in data.gd.")


func _say(text: String) -> void:
	if status != null:
		status.text = text


func toggle() -> void:
	visible = not visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if visible:
		_refresh_values()
		_say("Tuning %s. Changes are live; Save keeps them." % level_name())
