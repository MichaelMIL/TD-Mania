extends Control

## Options: sound, window size and key bindings. Everything here is saved to
## the account slot the moment it changes, so there is no apply step.

const MENU_SCENE := "res://home.tscn"

var sfx_slider: HSlider
var music_slider: HSlider
var sfx_value: Label
var music_value: Label
var scale_row: HBoxContainer
var key_rows: Dictionary = {}
var status: Label
## The action waiting for a key press, or "" when nothing is being rebound.
var listening: String = ""


func _ready() -> void:
	Progress.load_state()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()


func _sb(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 32.0)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	return b


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
	head.add_child(_label("OPTIONS", 30, Color("4fc3f7")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var back := _button("Back", 90.0)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	head.add_child(back)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# ---- left: sound and window
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 420.0
	body.add_child(left)

	var sound_card := PanelContainer.new()
	sound_card.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))
	left.add_child(sound_card)
	var sound_col := VBoxContainer.new()
	sound_col.add_theme_constant_override("separation", 6)
	sound_card.add_child(sound_col)
	sound_col.add_child(_label("SOUND", 15, Color("90a4ae")))

	var sfx_pair := _slider_row("Effects", Progress.volume("sfx"))
	sfx_slider = sfx_pair["slider"]
	sfx_value = sfx_pair["value"]
	sfx_slider.value_changed.connect(_on_sfx)
	sound_col.add_child(sfx_pair["row"])

	var music_pair := _slider_row("Music", Progress.volume("music"))
	music_slider = music_pair["slider"]
	music_value = music_pair["value"]
	music_slider.value_changed.connect(_on_music)
	sound_col.add_child(music_pair["row"])

	var window_card := PanelContainer.new()
	window_card.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("2c3a52")))
	left.add_child(window_card)
	var window_col := VBoxContainer.new()
	window_col.add_theme_constant_override("separation", 6)
	window_card.add_child(window_col)
	window_col.add_child(_label("WINDOW", 15, Color("90a4ae")))
	scale_row = HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	window_col.add_child(scale_row)
	for value: float in Progress.WINDOW_SCALES:
		var b := _button("%d%%" % int(value * 100.0), 74.0)
		b.pressed.connect(_on_scale.bind(value))
		b.set_meta("scale", value)
		scale_row.add_child(b)
	var full := _button("Fullscreen", 110.0)
	full.pressed.connect(_on_fullscreen)
	scale_row.add_child(full)
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 6)
	window_col.add_child(cap_row)
	cap_row.add_child(_label("Frame cap", 13, Color("e3f2fd")))
	for value: int in App.CAPS:
		var b := _button("%d fps" % value if value > 0 else "Display", 84.0)
		b.pressed.connect(_on_cap.bind(value))
		b.set_meta("cap", value)
		cap_row.add_child(b)
	window_col.add_child(_label("A lower cap is cooler and quieter; 60 looks the same as 120 here.",
			11, Color(1, 1, 1, 0.45)))

	window_col.add_child(_label("The board is drawn at %d x %d; the window is a multiple of that."
			% [int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height"))],
			11, Color(1, 1, 1, 0.45)))

	status = _label("", 13, Color("ffd54f"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status)

	# ---- right: key bindings
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_label("KEYS — click a binding, then press the key you want",
			15, Color("90a4ae")))

	var keys_scroll := ScrollContainer.new()
	keys_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(keys_scroll)
	var keys_col := VBoxContainer.new()
	keys_col.add_theme_constant_override("separation", 3)
	keys_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_scroll.add_child(keys_col)
	for entry: Dictionary in Progress.DEFAULT_KEYS:
		var action := str(entry["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		keys_col.add_child(row)
		var name_label := _label(str(entry["name"]), 13, Color("e3f2fd"))
		name_label.custom_minimum_size.x = 260.0
		row.add_child(name_label)
		var bind := _button("", 130.0)
		bind.pressed.connect(_listen_for.bind(action))
		row.add_child(bind)
		key_rows[action] = bind

	var reset := _button("Reset keys to defaults", 200.0)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_on_reset_keys)
	right.add_child(reset)


func _slider_row(name: String, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _label(name, 13, Color("e3f2fd"))
	label.custom_minimum_size.x = 90.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(220.0, 24.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := _label("", 13, Color("ffd54f"))
	readout.custom_minimum_size.x = 54.0
	row.add_child(readout)
	return {"row": row, "slider": slider, "value": readout}


func _on_sfx(value: float) -> void:
	Progress.set_volume("sfx", value)
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	# A sample on every change, so the slider is audible rather than abstract.
	Audio.play("shot_light", -8.0, 0.0)
	_refresh()


func _on_music(value: float) -> void:
	Progress.set_volume("music", value)
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	_refresh()


func _on_scale(value: float) -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Progress.set_window_scale(value)
	_say("Window set to %d%%." % int(value * 100.0))
	_refresh()


func _on_cap(value: int) -> void:
	Progress.set_frame_cap(value)
	_say("Frame cap %s." % ("%d fps" % value if value > 0 else "off"))
	_refresh()


func _on_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if full:
		Progress.apply_window_scale()
	_say("Windowed." if full else "Fullscreen.")


func _listen_for(action: String) -> void:
	listening = action
	_refresh()
	_say("Press a key for \"%s\", or Escape to keep the current one." % _action_name(action))


func _action_name(action: String) -> String:
	for entry: Dictionary in Progress.DEFAULT_KEYS:
		if str(entry["id"]) == action:
			return str(entry["name"])
	return action


func _on_reset_keys() -> void:
	Progress.reset_keys()
	listening = ""
	_refresh()
	_say("Keys are back to the defaults.")


func _input(event: InputEvent) -> void:
	if listening == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var action := listening
	listening = ""
	if event.keycode == KEY_ESCAPE and action != "cancel":
		_say("Left \"%s\" on %s." % [_action_name(action), Progress.key_name(action)])
		_refresh()
		return
	var taken := Progress.action_for(event.keycode)
	Progress.bind_key(action, event.keycode)
	if taken != "" and taken != action:
		_say("%s is now %s; %s took the old key." % [_action_name(action),
				Progress.key_name(action), _action_name(taken)])
	else:
		_say("%s is now %s." % [_action_name(action), Progress.key_name(action)])
	_refresh()


func _say(text: String) -> void:
	if status != null:
		status.text = text


func _refresh() -> void:
	sfx_value.text = "%d%%" % int(round(Progress.volume("sfx") * 100.0))
	music_value.text = "%d%%" % int(round(Progress.volume("music") * 100.0))
	for child in scale_row.get_children():
		if child is Button and child.has_meta("scale"):
			var mine: bool = is_equal_approx(float(child.get_meta("scale")),
					Progress.window_scale())
			child.modulate = Color("9ce89c") if mine else Color.WHITE
	for row: Node in scale_row.get_parent().get_children():
		for child in row.get_children() if row is HBoxContainer else []:
			if child is Button and child.has_meta("cap"):
				child.modulate = Color("9ce89c") \
						if int(child.get_meta("cap")) == Progress.frame_cap() \
						else Color.WHITE
	for action: String in key_rows:
		var b: Button = key_rows[action]
		b.text = "press a key…" if listening == action else Progress.key_name(action)
		b.modulate = Color("ffd54f") if listening == action else Color.WHITE


## Escape backs out of a screen, wherever you are.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU_SCENE)
