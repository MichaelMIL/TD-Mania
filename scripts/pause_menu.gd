class_name PauseMenu
extends Control

## The pause menu. Stops the match and puts the things you might want
## mid-run in one place: the volume sliders, and the ways out.
##
## It is deliberately not the options screen — leaving a match to change a
## setting would park the run. Anything that belongs to the account rather
## than to this run stays in Options, reachable from the main menu.

var game: Node = null
var panel: PanelContainer
var sfx_slider: HSlider
var music_slider: HSlider
var sfx_value: Label
var music_value: Label
var lbl_state: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _sb(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, height)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	add_child(shade)

	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220.0
	panel.offset_right = 220.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	panel.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("4fc3f7")))
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := _label("Paused", 28, Color("4fc3f7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	lbl_state = _label("", 13, Color(1, 1, 1, 0.6))
	lbl_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lbl_state)

	col.add_child(_label("SOUND", 12, Color("90a4ae")))
	var sfx_pair := _slider_row("Effects", Progress.volume("sfx"))
	sfx_slider = sfx_pair["slider"]
	sfx_value = sfx_pair["value"]
	sfx_slider.value_changed.connect(_on_sfx)
	col.add_child(sfx_pair["row"])
	var music_pair := _slider_row("Music", Progress.volume("music"))
	music_slider = music_pair["slider"]
	music_value = music_pair["value"]
	music_slider.value_changed.connect(_on_music)
	col.add_child(music_pair["row"])

	col.add_child(_label("THIS RUN", 12, Color("90a4ae")))
	var resume := _button("Resume", 17, 42.0)
	resume.pressed.connect(_resume)
	col.add_child(resume)

	var restart := _button("Restart this map", 14, 36.0)
	restart.pressed.connect(_restart)
	col.add_child(restart)

	var give_up := _button("End run and collect", 14, 36.0)
	give_up.tooltip_text = "Ends the run now; you keep the XP and coins it earned"
	give_up.pressed.connect(_end_run)
	col.add_child(give_up)

	var to_menu := _button("Level select", 14, 36.0)
	to_menu.tooltip_text = "Parks this run so you can come back to it"
	to_menu.pressed.connect(_to_menu)
	col.add_child(to_menu)

	var hint := _label("", 11, Color(1, 1, 1, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "%s or Escape closes this. Window size and keys live in Options." \
			% Progress.key_name("pause")
	col.add_child(hint)


func _slider_row(name: String, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _label(name, 13, Color("e3f2fd"))
	label.custom_minimum_size.x = 74.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(230.0, 24.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := _label("", 13, Color("ffd54f"))
	readout.custom_minimum_size.x = 48.0
	row.add_child(readout)
	return {"row": row, "slider": slider, "value": readout}


func _on_sfx(value: float) -> void:
	Progress.set_volume("sfx", value)
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	# Audible feedback, or the slider is just a number.
	Audio.play("shot_light", -8.0, 0.0)
	_refresh()


func _on_music(value: float) -> void:
	Progress.set_volume("music", value)
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	_refresh()


## Every way out unpauses first, or the next screen inherits a frozen
## clock. The game owns `paused`; this menu only shows it.
func _resume() -> void:
	if game.paused:
		game._toggle_pause()


func _restart() -> void:
	_resume()
	game._restart()


func _end_run() -> void:
	_resume()
	game._surrender()


func _to_menu() -> void:
	_resume()
	game._to_menu()


func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh() -> void:
	sfx_value.text = "%d%%" % int(round(Progress.volume("sfx") * 100.0))
	music_value.text = "%d%%" % int(round(Progress.volume("music") * 100.0))
	if game == null or not is_instance_valid(game):
		return
	lbl_state.text = "%s — wave %d of %d, %d lives, $%d in hand." % [
		game.level_def["name"], maxi(1, game.wave),
		TDData.clear_wave(game.level_def), game.lives, game.gold]
