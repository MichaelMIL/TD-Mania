class_name TuningPanel
extends Control

## Live balance editor. F2 during a match opens it: pick a subject on the
## left, nudge its numbers on the right, and watch the change take effect in
## the running game — towers and creeps re-read their numbers every frame.
##
## Three kinds of subject, chosen with the row of buttons at the top:
## **Towers** (damage, rate, range, cost and the rest), **Upgrades** (each
## tower's tracks: how many ranks, what a rank costs, and what a rank
## actually does) and **Enemies** (health, speed, armour, bounty and the
## traits that decide how a kind has to be answered).
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
var blurb: Label
var status: Label
var scope_button: Button

## "towers", "upgrades" or "enemies".
var mode: String = "towers"
var mode_buttons: Dictionary = {}
var current: String = "gun"
## -1 edits the global layer; otherwise the id of the level being played.
var scope_level: int = -1
var tower_buttons: Dictionary = {}
var value_fields: Dictionary = {}
var file_dialog: FileDialog
## Which way the open file browser is going.
var exporting: bool = false
var delta_labels: Dictionary = {}


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
	# Somewhere you can find, keep and share a set of numbers.
	var export_button := _small_button("Export", 84.0)
	export_button.tooltip_text = "Write these numbers to a file you can keep or send"
	export_button.pressed.connect(_export)
	scope_row.add_child(export_button)
	var import_button := _small_button("Import", 84.0)
	import_button.tooltip_text = "Replace these numbers with a file you exported before"
	import_button.pressed.connect(_import)
	scope_row.add_child(import_button)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	col.add_child(mode_row)
	for pair: Array in [["towers", "Towers"], ["upgrades", "Upgrades"],
			["enemies", "Enemies"]]:
		var b := _small_button(str(pair[1]), 120.0)
		b.pressed.connect(_select_mode.bind(str(pair[0])))
		mode_row.add_child(b)
		mode_buttons[str(pair[0])] = b

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

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	title = _label("", 15, Color("e0f7fa"))
	right.add_child(title)
	# What the thing being edited actually is, in words.
	blurb = _label("", 11, Color(1, 1, 1, 0.55))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(0.0, 30.0)
	right.add_child(blurb)
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

	_select_mode(mode)


## Every subject the current mode can edit, in table order.
func subjects() -> Array:
	var out: Array = []
	match mode:
		"enemies":
			for kind: String in TDData.ENEMIES:
				out.append(Tuning.enemy_subject(kind))
		"upgrades":
			for type_id: String in TDData.TOWERS:
				for i in TDData.TOWERS[type_id]["tracks"].size():
					out.append(Tuning.track_subject(type_id, i))
		_:
			for type_id: String in TDData.TOWERS:
				out.append(type_id)
	return out


func _select_mode(next_mode: String) -> void:
	mode = next_mode
	for child in list_col.get_children():
		list_col.remove_child(child)
		child.queue_free()
	tower_buttons = {}
	var first := ""
	for subject: String in subjects():
		if first == "":
			first = subject
		var b := _small_button(_short_label(subject), 138.0)
		b.pressed.connect(_select_tower.bind(subject))
		list_col.add_child(b)
		tower_buttons[subject] = b
	_select_tower(first)


## Fits a subject's name in the narrow list: towers by their short name,
## upgrade tracks by the track alone (the tower is in the title).
func _short_label(subject: String) -> String:
	if Tuning.is_track(subject):
		var body := subject.trim_prefix(Tuning.TRACK_PREFIX).split("#")
		var track: Dictionary = TDData.TOWERS[body[0]]["tracks"][int(body[1])]
		return "%s · %s" % [TDData.TOWERS[body[0]]["short"], track["name"]]
	if Tuning.is_enemy(subject):
		return str(TDData.ENEMIES[subject.trim_prefix(Tuning.ENEMY_PREFIX)]["name"])
	return str(TDData.TOWERS[subject].get("short", TDData.TOWERS[subject]["name"]))


## One stat per line: what it is, an "i" that explains it, minus, a field
## you can type into, plus, how far it has drifted, and a reset. Rows are
## grouped — the track as a whole first, then a block per rank.
func _build_rows() -> void:
	for child in rows_col.get_children():
		rows_col.remove_child(child)
		child.queue_free()
	value_fields = {}
	delta_labels = {}
	var group := ""
	for row: Dictionary in Tuning.rows_for(current):
		var key := str(row["key"])
		if str(row.get("group", "")) != group:
			group = str(row.get("group", ""))
			if group != "":
				var header := _label(group, 11, Color("4dd0e1"))
				header.custom_minimum_size = Vector2(0.0, 20.0)
				rows_col.add_child(header)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		rows_col.add_child(line)

		var name_label := _label(str(row["name"]), 13, Color(1, 1, 1, 0.75))
		name_label.custom_minimum_size = Vector2(96.0, 0.0)
		line.add_child(name_label)

		# An "i" that explains the stat on hover, so tuning does not require
		# knowing the codebase.
		var info := Button.new()
		info.text = "i"
		info.flat = true
		info.custom_minimum_size = Vector2(20.0, 26.0)
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color("4dd0e1"))
		info.focus_mode = Control.FOCUS_NONE
		info.mouse_filter = Control.MOUSE_FILTER_STOP
		info.tooltip_text = str(row.get("info", str(row["name"])))
		line.add_child(info)

		var minus := _small_button("−", 30.0)
		minus.pressed.connect(_nudge.bind(key, -1.0))
		line.add_child(minus)

		# Typed straight in when you know the number you want.
		var field := LineEdit.new()
		field.custom_minimum_size = Vector2(86.0, 26.0)
		field.alignment = HORIZONTAL_ALIGNMENT_CENTER
		field.add_theme_font_size_override("font_size", 13)
		field.select_all_on_focus = true
		field.text_submitted.connect(_typed.bind(key))
		field.focus_exited.connect(_commit.bind(key))
		line.add_child(field)
		value_fields[key] = field

		var plus := _small_button("+", 30.0)
		plus.pressed.connect(_nudge.bind(key, 1.0))
		line.add_child(plus)

		var drift := _label("", 12, Color("ff8a65"))
		drift.custom_minimum_size = Vector2(56.0, 0.0)
		line.add_child(drift)
		delta_labels[key] = drift

		var reset := _small_button("reset", 58.0)
		reset.pressed.connect(_reset_stat.bind(key))
		line.add_child(reset)
	_refresh_values()


## Reads a typed number. Anything unparseable is simply ignored and the
## field snaps back to what the value really is.
func _typed(text: String, key: String) -> void:
	var cleaned := text.strip_edges().replace(",", ".")
	if cleaned == "" or not cleaned.is_valid_float():
		_refresh_values()
		return
	var row := _row_for(key)
	var value: float = clampf(cleaned.to_float(), float(row.get("min", -99999.0)),
			float(row.get("max", 99999.0)))
	Tuning.set_value(current, key, value, scope_level)
	_after_change()
	_say("%s %s = %s (%s)" % [Tuning.label_of(current), row.get("name", key),
			_format(value, row), "all levels" if scope_level < 0 else level_name()])


func _commit(key: String) -> void:
	if value_fields.has(key):
		_typed(str((value_fields[key] as LineEdit).text), key)


## Some changes add or remove rows — giving a track more ranks gives it
## more rank blocks — so the list is rebuilt when its shape moves.
func _after_change() -> void:
	if value_fields.size() != Tuning.rows_for(current).size():
		_build_rows()
	else:
		_refresh_values()


func _row_for(key: String) -> Dictionary:
	for row: Dictionary in Tuning.rows_for(current):
		if str(row["key"]) == key:
			return row
	return {}


## Whole-numbered stats print whole: "Ranks 4", not "Ranks 4.00".
func _format(value: float, row: Dictionary) -> String:
	return "%.0f" % value if float(row.get("step", 1.0)) >= 1.0 else "%.2f" % value


func _refresh_values() -> void:
	var scope := scope_level
	var base_table := Tuning.base_of(current)
	for row: Dictionary in Tuning.rows_for(current):
		var key := str(row["key"])
		if not value_fields.has(key):
			continue
		var field: LineEdit = value_fields[key]
		var base := float(base_table.get(key, 0.0))
		var now := Tuning.value_of(current, key, level_id() if scope >= 0 else -1)
		# Never fight the player for the field they are typing in.
		if not field.has_focus():
			field.text = _format(now, row)
		var overridden := Tuning.is_overridden(current, key,
				level_id() if scope >= 0 else -1)
		field.add_theme_color_override("font_color",
				Color("ff8a65") if overridden else Color("ffd54f"))
		var drift: Label = delta_labels[key]
		if is_equal_approx(now, base) or is_zero_approx(base):
			drift.text = ""
		else:
			drift.text = "%+d%%" % int(round((now / base - 1.0) * 100.0))
	scope_button.text = "Scope: %s" % ("all levels" if scope_level < 0
			else "%s only" % level_name())
	for subject: String in tower_buttons:
		var button: Button = tower_buttons[subject]
		var tuned := not Tuning.effective(subject, level_id()).is_empty()
		button.modulate = Color("ff8a65") if tuned else Color.WHITE
		if subject == current:
			button.modulate = button.modulate.lightened(0.3)
	for id: String in mode_buttons:
		(mode_buttons[id] as Button).modulate = Color("9ce89c") if id == mode \
				else Color.WHITE
	title.text = "%s — %s" % [Tuning.label_of(current),
			"tuned" if not Tuning.effective(current, level_id()).is_empty() else "stock"]
	blurb.text = Tuning.describe(current)


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
	var row := _row_for(key)
	if row.is_empty():
		return
	var scope := scope_level if scope_level >= 0 else -1
	var now := Tuning.value_of(current, key, level_id() if scope >= 0 else -1)
	var next: float = clampf(now + direction * float(row["step"]),
			float(row["min"]), float(row["max"]))
	Tuning.set_value(current, key, next, scope)
	_after_change()
	_say("%s %s = %s (%s)" % [Tuning.label_of(current), row["name"],
			_format(next, row), "all levels" if scope < 0 else level_name()])


func _reset_stat(key: String) -> void:
	Tuning.clear_value(current, key, scope_level)
	_after_change()
	_say("%s back to the table value." % key)


## Export and import both go through a file browser, so a set of numbers
## can live outside the game's own data directory.
func _browse(save_mode: bool) -> void:
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.json ; tuning files"])
		file_dialog.size = Vector2i(720, 480)
		file_dialog.file_selected.connect(_on_file_chosen)
		add_child(file_dialog)
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save_mode \
			else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Export tuning" if save_mode else "Import tuning"
	exporting = save_mode
	var suggested := Tuning.suggested_export_path()
	file_dialog.current_dir = ProjectSettings.globalize_path(Tuning.EXPORT_DIR)
	if save_mode:
		file_dialog.current_file = suggested.get_file()
	file_dialog.popup_centered()


func _on_file_chosen(path: String) -> void:
	if exporting:
		_say("Exported to %s" % path if Tuning.export_to(path)
				else "Could not write %s" % path)
		return
	if Tuning.import_from(path):
		_build_rows()
		_refresh_values()
		_say("Imported %s. Nothing is saved until you press Save." % path.get_file())
	else:
		_say("%s is not a tuning export." % path.get_file())


func _export() -> void:
	_browse(true)


func _import() -> void:
	_browse(false)


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
