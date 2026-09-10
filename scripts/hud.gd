class_name GameHUD
extends Node

## Everything the player looks at during a match: the top bar, the build
## palette, the wave readout, the info bar, the creep card and the defeat
## panel. Split out of `game.gd`, which was 2,200 lines of state and screen
## in one file.
##
## The HUD owns no game state. It reads the match through `game` and calls
## back into it for anything that changes the world, so the rule when
## reading this file is: a bare name is a widget, a `game.` name is the
## match.

var game: Node = null
## Set by the perf harness to price what the HUD costs per frame.
var frozen: bool = false

var info_hover: Label
var track_buttons: Array = []
var palette_cards: Dictionary = {}
var palette_costs: Dictionary = {}
var creep_tip: PanelContainer
var creep_tip_label: Label
var lbl_level: Label
var lbl_lives: Label
var lbl_gold: Label
var lbl_wave: Label
var lbl_status: Label
var preview_row: HBoxContainer
var lbl_wave_note: Label
var preview_wave: int = -1
var btn_start: Button
var btn_speed: Button
var btn_pause: Button
var btn_auto: Button
var lbl_coins: Label
var tower_buttons: Dictionary = {}
var info_title: Label
var info_body: Label
var info_perk: Label
var btn_upgrade: Button
var btn_sell: Button
var btn_move: Button
var btn_target: Button
var over_root: Control
var lbl_over_title: Label
var btn_continue: Button
var over_panel: PanelContainer
var btn_surrender: Button
var lbl_over: Label


func _sb(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Audio.play("click", -12.0, 0.0))
	return b


func build() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_topbar(root)
	_build_palette(root)
	_build_info_bar(root)
	_build_status_label(root)
	_build_creep_tip(root)
	_build_game_over(root)


## A card that follows the cursor over a creep. Reading the roster off the
## board beats keeping a wiki open.
func _build_creep_tip(root: Control) -> void:
	creep_tip = PanelContainer.new()
	creep_tip.add_theme_stylebox_override("panel",
			_sb(Color(0.04, 0.06, 0.09, 0.94), Color("546e7a"), 6))
	creep_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creep_tip.visible = false
	creep_tip_label = _label("", 12, Color("e3f2fd"))
	creep_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creep_tip.add_child(creep_tip_label)
	root.add_child(creep_tip)


## What a creep is, in one card: health, what it shrugs off, and the note
## that says how to answer it.
static func describe_enemy(e: Enemy) -> String:
	var d: Dictionary = TDData.ENEMIES.get(e.kind, {})
	var text := "%s   %d / %d hp" % [e.display_name, int(ceil(e.hp)), int(round(e.max_hp))]
	var traits: Array = []
	if e.armor > 0.0:
		traits.append("armour %d" % int(round(e.armor)))
	traits.append("%d px/s" % int(round(e.base_speed)))
	if e.flying:
		traits.append("flying")
	if e.slow_immune:
		traits.append("ignores slows")
	if e.burn_immune:
		traits.append("ignores fire")
	if e.heal > 0.0:
		traits.append("heals nearby")
	if e.steal_gold > 0:
		traits.append("steals $%d" % e.steal_gold)
	if e.split_count > 0:
		traits.append("splits into %d" % e.split_count)
	if e.charge_period > 0.0:
		traits.append("sprints in bursts")
	if e.leak_damage > 1:
		traits.append("costs %d lives" % e.leak_damage)
	text += "\n" + "  ·  ".join(traits)
	var note := str(d.get("note", ""))
	if note != "":
		text += "\n" + note
	return text


func refresh_creep_tip() -> void:
	if creep_tip == null:
		return
	var pos: Vector2 = game.get_global_mouse_position()
	var over: Enemy = null if not game.map_rect().has_point(pos) else game.enemy_at(pos)
	if over == null:
		creep_tip.visible = false
		return
	creep_tip_label.text = describe_enemy(over)
	creep_tip.visible = true
	# Keep the card on screen, and out from under the cursor.
	var wanted := pos + Vector2(18.0, 18.0)
	var card := creep_tip.get_combined_minimum_size()
	wanted.x = minf(wanted.x, float(TDData.MAP_W) - card.x - 8.0)
	wanted.y = minf(wanted.y, float(TDData.MAP_H) - card.y - 8.0)
	creep_tip.position = wanted


## The map is finished. Same panel as defeat, dressed as a win, plus the way
## back into the run.
func show_victory(text: String) -> void:
	over_panel.add_theme_stylebox_override("panel",
			_sb(Color("121a26"), Color("ffd54f"), 10))
	lbl_over_title.text = "Map cleared"
	lbl_over_title.add_theme_color_override("font_color", Color("ffd54f"))
	lbl_over.text = text
	btn_continue.visible = true
	over_root.visible = true


func hide_victory() -> void:
	over_root.visible = false
	btn_continue.visible = false
	over_panel.add_theme_stylebox_override("panel",
			_sb(Color("121a26"), Color("ef5350"), 10))
	lbl_over_title.text = "The base has fallen"
	lbl_over_title.add_theme_color_override("font_color", Color("ef5350"))


## The top bar carries the run's state on the left and its controls on the
## right. Everything in it has a fixed width: with 987654 gold, 128 lives
## and a long map name, the old layout pushed the buttons off the edge of
## the screen. Numbers now clip inside their own field instead of shoving
## their neighbours, and the gap between the two halves is the only thing
## that flexes.
func _build_topbar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.offset_right = float(TDData.MAP_W)
	bar.offset_bottom = float(TDData.HUD_H)
	bar.add_theme_stylebox_override("panel", _sb(Color("111823"), Color("2c3a52"), 0))
	root.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	# ---- who and where
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 0)
	identity.custom_minimum_size.x = 168.0
	row.add_child(identity)
	lbl_level = _label(str(game.level_def["name"]), 16, Color("e3f2fd"))
	lbl_level.clip_text = true
	lbl_level.custom_minimum_size.x = 168.0
	lbl_level.tooltip_text = str(game.level_def["name"])
	identity.add_child(lbl_level)
	var tier: Dictionary = TDData.tier_of(game.level_def)
	var badge := _label("%s  ·  %d/4" % [str(tier["name"]).to_upper(),
			int(game.level_def["tier"]) + 1], 11, tier["color"])
	identity.add_child(badge)

	# ---- how the run is going
	lbl_lives = _stat_field(112.0, 18, Color("ef5350"),
			"Lives left. A creep that reaches the base costs one, or more.")
	lbl_gold = _stat_field(150.0, 18, Color("ffd54f"),
			"Gold in hand. Spent on towers and on installing upgrade ranks.")
	lbl_wave = _stat_field(150.0, 18, Color("e3f2fd"),
			"The wave you are on, and the one that clears the map.")
	lbl_coins = _stat_field(130.0, 15, Color("ffca28"),
			"Coins banked on this save, plus what this run has earned so far.")
	for l: Label in [lbl_lives, lbl_gold, lbl_wave, lbl_coins]:
		row.add_child(l)

	# Only this gives, so the controls stay put however big the numbers get.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.x = 8.0
	row.add_child(spacer)

	# ---- controls, compact enough to survive the widest numbers
	btn_start = _button("Start Wave", 14, Vector2(112.0, 44.0))
	btn_start.tooltip_text = "Call the next wave in early for bonus gold (%s)" \
			% Progress.key_name("start_wave")
	btn_start.pressed.connect(game._on_start_pressed)
	row.add_child(btn_start)

	btn_speed = _button("1x", 15, Vector2(46.0, 44.0))
	btn_speed.tooltip_text = "Game speed (%s)" % Progress.key_name("speed") \
			if game.speeds.size() > 1 \
			else "Faster speeds unlock with Field Tempo in the tech tree"
	btn_speed.modulate = Color.WHITE if game.speeds.size() > 1 \
			else Color(0.55, 0.58, 0.64)
	btn_speed.pressed.connect(game._cycle_speed)
	row.add_child(btn_speed)

	btn_pause = _button("II", 15, Vector2(44.0, 44.0))
	btn_pause.tooltip_text = "Pause (%s)" % Progress.key_name("pause")
	btn_pause.pressed.connect(game._toggle_pause)
	row.add_child(btn_pause)

	btn_auto = _button("Auto", 12, Vector2(54.0, 44.0))
	btn_auto.tooltip_text = "Automatically call each wave in early and collect the bonus gold (%s)" \
			% Progress.key_name("auto")
	btn_auto.pressed.connect(game._toggle_auto)
	row.add_child(btn_auto)

	btn_surrender = _button("End run", 12, Vector2(64.0, 44.0))
	btn_surrender.tooltip_text = "End this run now and collect what it earned"
	btn_surrender.pressed.connect(game._surrender)
	row.add_child(btn_surrender)

	var menu := _button("Menu", 13, Vector2(58.0, 44.0))
	menu.tooltip_text = "Park this run and come back to it later (%s)" \
			% Progress.key_name("menu")
	menu.pressed.connect(game._to_menu)
	row.add_child(menu)


## A number that owns its space: fixed width, clipped rather than pushy.
func _stat_field(width: float, size: int, color: Color, hint: String) -> Label:
	var l := _label("", size, color)
	l.custom_minimum_size.x = width
	l.clip_text = true
	l.tooltip_text = hint
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Right-hand build palette: one card per tower, dragged onto the map.
func _build_palette(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -float(TDData.PALETTE_W)
	panel.add_theme_stylebox_override("panel", _sb(Color("0e141d"), Color("2c3a52"), 0))
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	col.add_child(_label("BUILD", 15, Color("90a4ae")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for i in TDData.TOWER_ORDER.size():
		grid.add_child(_palette_card(TDData.TOWER_ORDER[i], i))

	var hint := _label("Drag a card onto the map,\nor click it then click a cell.", 12,
			Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)


func _palette_card(type_id: String, index: int) -> Control:
	var d: Dictionary = TDData.tower_def(type_id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(102.0, 88.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s  $%d\n%s" % [d["name"], int(d["cost"]), d["desc"]]
	card.add_theme_stylebox_override("panel", _sb(Color("16202e"), Color("32425c"), 6))
	card.gui_input.connect(_palette_input.bind(type_id))
	card.mouse_entered.connect(_hover_card.bind(type_id))
	card.mouse_exited.connect(_hover_card.bind(""))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	card.add_child(col)

	var icon := TowerIcon.new()
	icon.type_id = type_id
	icon.custom_minimum_size = Vector2(0.0, 38.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)

	var name_row := _label(str(d.get("short", d["name"])), 12, Color("e3f2fd"))
	name_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)

	var locked := not Progress.tower_unlocked(type_id)
	var cost := _label("Lv %d" % Progress.tower_unlock_level(type_id) if locked
			else "$%d" % game.tower_cost(type_id), 12,
			Color("90a4ae") if locked else Color("ffd54f"))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cost)
	# Kept so a price retuned with F2 shows up without rebuilding the palette.
	palette_costs[type_id] = cost
	if locked:
		card.tooltip_text = "%s — unlocks at account level %d\n%s" % [d["name"],
				Progress.tower_unlock_level(type_id), d["desc"]]

	palette_cards[type_id] = card
	return card


## Hovering a card previews the tower on the board — where it may stand and
## how far it reaches — before any gold is spent.
func _hover_card(type_id: String) -> void:
	game.preview_tower = type_id
	if game.cursor != null:
		game.cursor.queue_redraw()
	refresh_info(type_id)


func _palette_input(event: InputEvent, type_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			game.begin_drag(type_id)
		elif game.dragging:
			# Released back over the palette: keep the tower selected for
			# click-to-place instead of building anything.
			game.dragging = false
			game.cursor.queue_redraw()


## Strip along the top of the bottom bar naming what the next wave brings,
## with a note for any kind that needs a specific answer.
func _build_wave_preview(parent: Control) -> void:
	preview_row = HBoxContainer.new()
	preview_row.custom_minimum_size.y = 24
	preview_row.add_theme_constant_override("separation", 6)
	preview_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview_row)


## The advice line is rebuilt with the chips rather than kept: it lives inside
## `preview_row`, which is emptied and freed on every refresh.
func _wave_note_label(text: String) -> Label:
	var note := _label(text, 12, Color("ffca28"))
	note.clip_text = true
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return note


func _enemy_chip(kind: String, count: int) -> Control:
	var d: Dictionary = TDData.ENEMIES[kind]
	var chip := PanelContainer.new()
	var box := _sb(Color(0.05, 0.07, 0.1, 0.72), Color(d["color"]).darkened(0.2), 9)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	var dot := EnemyDot.new()
	dot.tint = d["color"]
	dot.winged = bool(d.get("flying", false))
	dot.custom_minimum_size = Vector2(12.0, 12.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var label := _label("%d %s" % [count, d["name"]], 12, Color("e3f2fd"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return chip


## Rebuilds the chips when the upcoming wave changes. During a wave the strip
## keeps its height but just states what is running, so the bar never jumps.
func refresh_wave_preview() -> void:
	if preview_row == null:
		return
	var upcoming: int = game.wave + 1
	var key: int = -1 if game.game_over else (0 if game.in_wave else upcoming)
	if preview_wave == key:
		return
	preview_wave = key
	for child in preview_row.get_children():
		preview_row.remove_child(child)
		child.queue_free()
	lbl_wave_note = null
	if game.game_over:
		return
	if game.in_wave:
		var running := _label("Wave %d in progress" % game.wave, 13, Color(1, 1, 1, 0.4))
		running.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_row.add_child(running)
		return

	var composition: Dictionary = game.wave_composition(upcoming)
	var boss: bool = composition.has("boss") or composition.has("titan")
	var heading := _label("BOSS WAVE %d" % upcoming if boss else "Wave %d incoming" % upcoming,
			13, Color("ef5350") if boss else Color(1, 1, 1, 0.65))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(heading)
	for kind: String in composition:
		preview_row.add_child(_enemy_chip(kind, int(composition[kind])))

	# One line of advice, drawn from the roster's own notes, right-aligned in
	# whatever space the chips leave.
	var notes: Array = []
	for kind: String in composition:
		var note := str(TDData.ENEMIES[kind].get("note", ""))
		if note != "":
			notes.append("%s: %s" % [TDData.ENEMIES[kind]["name"], note])
	lbl_wave_note = _wave_note_label(str(notes[0]) if not notes.is_empty() else "")
	preview_row.add_child(lbl_wave_note)


func _build_status_label(root: Control) -> void:
	lbl_status = _label("", 15, Color(1, 1, 1, 0.75))
	lbl_status.offset_right = float(TDData.MAP_W)
	lbl_status.offset_top = float(TDData.HUD_H) + 6.0
	lbl_status.offset_bottom = float(TDData.HUD_H) + 30.0
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_status)


## Bottom bar: selected tower stats on the left, one button per upgrade track
## in the middle, sell on the right.
func _build_info_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -float(TDData.BAR_H)
	bar.offset_right = float(TDData.MAP_W)
	bar.add_theme_stylebox_override("panel", _sb(Color("0b1119"), Color("2c3a52"), 0))
	root.add_child(bar)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	bar.add_child(stack)
	_build_wave_preview(stack)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 432
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	info_title = _label("", 16, Color("e3f2fd"))
	left.add_child(info_title)

	info_body = _label("", 12, Color(1, 1, 1, 0.78))
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	left.add_child(info_body)

	info_hover = _label("", 12, Color("ffd54f"))
	info_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_hover.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info_hover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(info_hover)

	var tracks_row := HBoxContainer.new()
	tracks_row.add_theme_constant_override("separation", 6)
	tracks_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tracks_row)

	for i in 4:
		var b := _button("", 12, Vector2(0.0, 74.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(game._upgrade_selected.bind(i))
		b.mouse_entered.connect(_hover_track.bind(i))
		b.mouse_exited.connect(_hover_track.bind(-1))
		b.visible = false
		tracks_row.add_child(b)
		track_buttons.append(b)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 124
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)

	btn_target = _button("Target: First", 12, Vector2(118.0, 34.0))
	btn_target.pressed.connect(game._cycle_target_mode)
	right.add_child(btn_target)

	btn_move = _button("Move", 13, Vector2(118.0, 30.0))
	btn_move.tooltip_text = "Pick this tower up and put it somewhere else. Free, once a wave, between waves."
	btn_move.pressed.connect(game.begin_move)
	right.add_child(btn_move)

	btn_sell = _button("Sell", 13, Vector2(118.0, 34.0))
	btn_sell.pressed.connect(game._sell_selected)
	right.add_child(btn_sell)


func _build_game_over(root: Control) -> void:
	over_root = Control.new()
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.mouse_filter = Control.MOUSE_FILTER_STOP
	over_root.visible = false
	root.add_child(over_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	over_root.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	over_panel = panel
	panel.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("ef5350"), 10))
	over_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	lbl_over_title = _label("The base has fallen", 28, Color("ef5350"))
	var title := lbl_over_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	lbl_over = _label("", 15, Color(1, 1, 1, 0.85))
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_over.custom_minimum_size = Vector2(560.0, 0.0)
	col.add_child(lbl_over)

	btn_continue = _button("Keep playing — endless", 15, Vector2(0.0, 38.0))
	btn_continue.pressed.connect(game.continue_endless)
	btn_continue.visible = false
	col.add_child(btn_continue)

	var again := _button("Play again  (%s)" % Progress.key_name("restart"), 16,
			Vector2(0.0, 42.0))
	again.pressed.connect(game._restart)
	col.add_child(again)

	var menu := _button("Level select  (%s)" % Progress.key_name("menu"), 15,
			Vector2(0.0, 38.0))
	menu.pressed.connect(game._to_menu)
	col.add_child(menu)


func update() -> void:
	if frozen:
		return
	lbl_lives.text = "♥ %d" % game.lives
	lbl_gold.text = "$ %d" % game.gold
	# The finish line, so a run has a shape rather than going on forever.
	var target := TDData.clear_wave(game.level_def)
	lbl_wave.text = "Wave %d / %d" % [maxi(1, game.wave), target] \
			if not game.map_cleared else "Wave %d ✓" % maxi(1, game.wave)
	# Banked coins plus what the run would pay out if it ended now.
	var pending := 0
	if not game.rewarded and game.wave > 1:
		pending = int(Progress.run_reward(game.wave - 1, game.score, int(game.level_def["tier"]))["coins"])
	lbl_coins.text = "◈ %d" % Progress.coins if pending <= 0 \
			else "◈ %d +%d" % [Progress.coins, pending]
	if game.game_over:
		lbl_status.text = "Base destroyed on wave %d" % game.wave
		btn_start.disabled = true
		btn_start.text = "Game over"
		return
	if game.in_wave:
		var left: int = game.spawn_queue.size() - game.spawn_index + game.enemies.size()
		lbl_status.text = "Wave %d in progress — %d enemies left" % [game.wave, left]
		btn_start.disabled = true
		btn_start.text = "Fighting..."
	else:
		var bonus := int(maxf(0.0, game.break_timer) * 3.0
				* Progress.bonus_mult("early_bonus_mult"))
		var lanes: Array = game.next_wave_lanes()
		var from := ""
		if game.routes.size() > 1:
			if lanes.size() == 1:
				from = "  ·  from Spawn %d only" % (int(lanes[0]) + 1)
			else:
				from = "  ·  from all %d spawns" % lanes.size()
		if game.wave + 1 <= game.early_claimed:
			lbl_status.text = "Next wave in %.1fs — bonus for this wave already collected%s" \
					% [maxf(0.0, game.break_timer), from]
		elif game.auto_start:
			lbl_status.text = "Auto-start armed — wave %d rolls in with a +$%d bonus%s" \
					% [game.wave + 1, bonus, from]
		else:
			lbl_status.text = "Next wave in %.1fs — Start now for +$%d bonus (%s)%s" \
					% [maxf(0.0, game.break_timer), bonus, Progress.key_name("start_wave"), from]
		# For the first seconds of the break, what just happened matters more
		# than the countdown to what is next.
		if game.wave_report_timer > 0.0 and game.wave_report != "":
			lbl_status.text = game.wave_report
		btn_start.disabled = false
		btn_start.text = "Start Wave"
	refresh_wave_preview()
	for type_id: String in palette_cards:
		var card: Control = palette_cards[type_id]
		if not Progress.tower_unlocked(type_id):
			card.modulate = Color(0.45, 0.5, 0.58, 0.75)
		elif game.placing == type_id:
			card.modulate = Color("9ce89c")
		elif game.gold < game.tower_cost(type_id):
			card.modulate = Color(1, 1, 1, 0.42)
		else:
			card.modulate = Color.WHITE
		if Progress.tower_unlocked(type_id) and palette_costs.has(type_id):
			var price := "$%d" % game.tower_cost(type_id)
			if palette_costs[type_id].text != price:
				palette_costs[type_id].text = price
	if game.selected != null and is_instance_valid(game.selected):
		sync_track_buttons()


## Shows the selected tower's live stats and upgrade tracks, a hovered tower
## type's blurb, or the default hint text.
func refresh_info(hovered_type: String = "") -> void:
	if game.selected != null and is_instance_valid(game.selected):
		show_selected_info()
		return

	for b: Button in track_buttons:
		b.visible = false
	btn_sell.visible = false
	btn_move.visible = false
	btn_target.visible = false
	info_hover.text = ""

	var type_id: String = hovered_type if hovered_type != "" else game.placing
	if type_id != "":
		var d: Dictionary = TDData.tower_def(type_id)
		var where := "water only" if int(d["terrain"]) == TDData.Terrain.WATER else "dry ground"
		if not Progress.tower_unlocked(type_id):
			where = "locked until level %d" % Progress.tower_unlock_level(type_id)
		if not bool(d.get("hits_air", false)) and not bool(d.get("air", false)):
			where += ", ground only"
		info_title.text = "%s  —  $%d  (%s)" % [d["name"], game.tower_cost(type_id), where]
		var stats := "%s\n" % d["desc"]
		if bool(d.get("support", false)):
			stats += "Aura +%d%% damage, +%d%% fire rate   Radius %.0f" % [
				int(float(d["aura_damage"]) * 100.0), int(float(d["aura_rate"]) * 100.0),
				float(d["range"])]
		else:
			stats += "Damage %.0f   Range %.0f   Rate %.2f/s" % [
				float(d["damage"]), float(d["range"]), float(d["rate"])]
			if float(d.get("min_range", 0.0)) > 0.0:
				stats += "   Dead zone %.0f" % float(d["min_range"])
		info_body.text = stats
		preview_track_buttons(type_id)
		return

	info_title.text = str(game.level_def["name"])
	info_body.text = "%s\n%s\nDrag a tower onto the map. %s upgrades, %s sells, %s starts a wave early. %s auto, %s target, %s pause, %s speed, %s menu." \
			% [game.level_def["blurb"], "    ".join(game.objective_lines(true)),
			Progress.key_name("upgrade"), Progress.key_name("sell"),
			Progress.key_name("start_wave"), Progress.key_name("auto"),
			Progress.key_name("target"), Progress.key_name("pause"),
			Progress.key_name("speed"), Progress.key_name("menu")]


func show_selected_info() -> void:
	var d: Dictionary = game.selected.def()
	info_title.text = "%s  ·  %d upgrades" % [d["name"], game.selected.level()]

	var lines := ""
	if game.selected.income() > 0.0:
		lines = "Pays $%.0f at the end of every wave. Build early, profit later." \
				% game.selected.income()
	elif game.selected.is_field():
		lines = "Slows everything within %.0f by %d%% while they stand in it." % [
			game.selected.stat("range"), int(game.selected.slow_factor() * 100.0)]
	elif game.selected.is_pulse():
		lines = "Slams every %.1fs for %.0f damage in a %.0f radius." % [
			1.0 / maxf(0.05, game.selected.stat("rate")), game.selected.stat("damage"),
			game.selected.splash()]
	elif game.selected.is_support():
		lines = "Support aura: +%d%% damage, +%d%% fire rate to towers within %.0f.\nAuras do not stack — the strongest post wins." % [
			int(game.selected.aura_damage() * 100.0), int(game.selected.aura_rate() * 100.0),
			game.selected.stat("range")]
	elif game.selected.is_air():
		lines = "Sortie every %.1fs   Radius %.0f\n%s x%d   Payload %.0f x%d   Blast %.0f" % [
			1.0 / maxf(0.01, game.selected.stat("rate")), game.selected.stat("range"),
			str(d["unit"]).capitalize(), game.selected.unit_count(),
			game.selected.stat("damage"), game.selected.unit_shots(), game.selected.splash()]
	else:
		lines = "Damage %.0f   Range %.0f   %s" % [game.selected.stat("damage"),
			game.selected.stat("range"),
			"beam" if bool(d["beam"]) else "%.2f/s" % game.selected.stat("rate")]
		var extras: Array = []
		if game.selected.shots() > 1:
			extras.append("x%d shots" % game.selected.shots())
		if game.selected.chain() > 1:
			extras.append("hits %d" % game.selected.chain())
		if game.selected.pierce_count() > 0:
			extras.append("bores through %d" % game.selected.pierce_count())
		if game.selected.splash() > 0.0:
			extras.append("splash %.0f" % game.selected.splash())
		if game.selected.slow_factor() > 0.0:
			extras.append("slow %d%% / %.1fs" % [int(game.selected.slow_factor() * 100.0),
					game.selected.slow_duration()])
		if game.selected.burn() > 0.0:
			extras.append("burn %.0f/s" % game.selected.burn())
		if game.selected.min_range() > 0.0:
			extras.append("dead zone %.0f" % game.selected.min_range())
		if game.selected.pierces():
			extras.append("ignores armor")
		if game.selected.knockback() > 0.0:
			extras.append("knocks back %.0f" % game.selected.knockback())
		if game.selected.focus_peak() > 1.0:
			extras.append("focuses to x%.1f" % game.selected.focus_peak())
		if game.selected.volley() > 1:
			extras.append("%d bolts" % game.selected.volley())
		extras.append("targets %s" % game.selected.target_mode_name().to_lower())
		if game.selected.shatter() > 1.0:
			extras.append("+%d%% vs chilled" % int((game.selected.shatter() - 1.0) * 100.0))
		if game.selected.buff_damage > 0.0 or game.selected.buff_rate > 0.0:
			extras.append("buffed +%d%%/+%d%%" % [int(game.selected.buff_damage * 100.0),
					int(game.selected.buff_rate * 100.0)])
		lines += "\n" + "   ".join(extras)
	lines += "\nKills %d   ·   damage dealt %s" % [game.selected.kills,
			_short_number(game.selected.damage_dealt)]
	info_body.text = lines

	btn_sell.visible = true
	btn_sell.text = "Sell  +$%d" % game.selected.sell_value()
	btn_move.visible = true
	btn_move.disabled = not game.can_move_selected()
	btn_move.text = "Move" if game.can_move_selected() \
			else ("Moving…" if game.moving != null else "Move (next wave)")
	btn_target.visible = true
	btn_target.disabled = game.selected.is_support()
	btn_target.text = "Target: %s" % game.selected.target_mode_name()
	btn_target.tooltip_text = "Shoot %s. Click or press T to change." \
			% TDData.TARGET_HINTS[game.selected.target_mode]
	sync_track_buttons()


## Greyed-out preview of what a tower type can be upgraded into, shown while
## hovering its palette card.
func preview_track_buttons(type_id: String) -> void:
	var list: Array = TDData.tracks(type_id)
	for i in track_buttons.size():
		var b: Button = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		var t: Dictionary = list[i]
		var cap: Dictionary = TDData.capstone(type_id, i)
		b.visible = true
		b.disabled = true
		var unlocked := Progress.track_rank_for(type_id, i)
		b.text = "%s%s\nunlocked %d/%d   $%d" % [t["name"],
				"  *" if not cap.is_empty() else "", unlocked, int(t["max"]),
				TDData.track_gold_cost(type_id, i, 0)]
		b.tooltip_text = _track_explanation(type_id, i, null)
	var caps: Array = []
	for i in list.size():
		var cap: Dictionary = TDData.capstone(type_id, i)
		if not cap.is_empty():
			caps.append(str(cap["name"]))
	if game.hovered_track < 0:
		info_hover.text = ("* unlocks " + ", ".join(caps)) if not caps.is_empty() else ""


## Called when the pointer enters or leaves an upgrade button (-1 = left).
func _hover_track(track: int) -> void:
	game.hovered_track = track
	if track < 0:
		refresh_info()
		return
	var type_id := ""
	var tower: Tower = null
	if game.selected != null and is_instance_valid(game.selected):
		type_id = game.selected.type_id
		tower = game.selected
	elif game.placing != "":
		type_id = game.placing
	if type_id == "" or track >= TDData.tracks(type_id).size():
		return
	info_hover.text = _track_explanation(type_id, track, tower)


## What one more rank of this track actually does, in words and — when the
## tower already exists — in before/after numbers.
func _track_explanation(type_id: String, track: int, tower: Tower) -> String:
	var t: Dictionary = TDData.tracks(type_id)[track]
	var rank: int = tower.track_rank(track) if tower != null else 0
	var unlocked: int = Progress.track_rank_for(type_id, track)
	var top := int(t["max"])
	var lines: Array = []
	lines.append("%s  %d/%d — %s per rank" % [t["name"], rank, top,
			TDData.describe_mods(t["mods"])])
	if tower != null:
		var block: Dictionary = tower.track_block(track)
		if not block.is_empty():
			lines.append("Locked: needs %s at rank %d (you have %d)."
					% [block["name"], int(block["rank"]), int(block["have"])])
	else:
		var need: Dictionary = TDData.track_requirement(type_id, track)
		if not need.is_empty():
			var parent := TDData.track_index(type_id, str(need["track"]))
			lines.append("Opens after %s reaches rank %d."
					% [TDData.tracks(type_id)[parent]["name"], int(need["rank"])])
	if rank < top:
		var deltas := _rank_deltas(type_id, track, tower)
		if deltas != "":
			lines.append("This rank: " + deltas)
		if rank < mini(top, unlocked):
			lines.append("Install for $%d" % TDData.track_gold_cost(type_id, track, rank))
		else:
			lines.append("Unlock rank %d for %d coins in the Tech Tree, then install for $%d"
					% [rank + 1, TDData.track_cost(type_id, track, unlocked),
					TDData.track_gold_cost(type_id, track, rank)])
	var cap: Dictionary = TDData.capstone(type_id, track)
	if cap.is_empty():
		if rank >= top:
			lines.append("Fully upgraded.")
	elif rank >= top:
		lines.append("%s active — %s" % [cap["name"], cap["desc"]])
	elif rank + 1 >= top:
		lines.append("This rank unlocks %s — %s" % [cap["name"], cap["desc"]])
	else:
		lines.append("At %d/%d unlocks %s — %s" % [top, top, cap["name"], cap["desc"]])
	return "\n".join(lines)


## Concrete stat changes from buying one rank, measured by comparing a scratch
## copy of the tower rather than restating the data table.
func _rank_deltas(type_id: String, track: int, tower: Tower) -> String:
	var before := Tower.new()
	before.game = self
	before.setup(type_id, Vector2i.ZERO)
	var after := Tower.new()
	after.game = self
	after.setup(type_id, Vector2i.ZERO)
	if tower != null:
		before.ranks = tower.ranks.duplicate()
		after.ranks = tower.ranks.duplicate()
	after.ranks[track] = int(after.ranks[track]) + 1

	var parts: Array = []
	for spec: Array in [["Damage", "damage", 0], ["Rate", "rate", 2], ["Range", "range", 0]]:
		var a := before.stat(str(spec[1]))
		var b := after.stat(str(spec[1]))
		if not is_equal_approx(a, b):
			parts.append("%s %.*f -> %.*f" % [spec[0], int(spec[2]), a, int(spec[2]), b])
	if not is_equal_approx(before.splash(), after.splash()):
		parts.append("Blast %.0f -> %.0f" % [before.splash(), after.splash()])
	if not is_equal_approx(before.slow_factor(), after.slow_factor()):
		parts.append("Slow %d%% -> %d%%" % [int(before.slow_factor() * 100.0),
				int(after.slow_factor() * 100.0)])
	if not is_equal_approx(before.slow_duration(), after.slow_duration()):
		parts.append("Slow lasts %.1fs -> %.1fs" % [before.slow_duration(),
				after.slow_duration()])
	if not is_equal_approx(before.burn(), after.burn()):
		parts.append("Burn %.0f -> %.0f/s" % [before.burn(), after.burn()])
	if not is_equal_approx(before.min_range(), after.min_range()):
		parts.append("Dead zone %.0f -> %.0f" % [before.min_range(), after.min_range()])
	if before.shots() != after.shots():
		parts.append("Shots %d -> %d" % [before.shots(), after.shots()])
	if before.chain() != after.chain():
		parts.append("Targets %d -> %d" % [before.chain(), after.chain()])
	if before.pierce_count() != after.pierce_count():
		parts.append("Pierces %d -> %d" % [before.pierce_count(), after.pierce_count()])
	if before.unit_count() != after.unit_count():
		parts.append("Aircraft %d -> %d" % [before.unit_count(), after.unit_count()])
	if before.unit_shots() != after.unit_shots():
		parts.append("Rounds %d -> %d" % [before.unit_shots(), after.unit_shots()])
	if not is_equal_approx(before.aura_damage(), after.aura_damage()):
		parts.append("Damage aura +%d%% -> +%d%%" % [int(before.aura_damage() * 100.0),
				int(after.aura_damage() * 100.0)])
	if not is_equal_approx(before.aura_rate(), after.aura_rate()):
		parts.append("Rate aura +%d%% -> +%d%%" % [int(before.aura_rate() * 100.0),
				int(after.aura_rate() * 100.0)])
	if not is_equal_approx(before.income(), after.income()):
		parts.append("Gold per wave %.0f -> %.0f" % [before.income(), after.income()])
	if not is_equal_approx(before.knockback(), after.knockback()):
		parts.append("Knockback %.0f -> %.0f" % [before.knockback(), after.knockback()])
	if not is_equal_approx(before.focus_peak(), after.focus_peak()):
		parts.append("Focused damage x%.1f -> x%.1f" % [before.focus_peak(),
				after.focus_peak()])
	if before.volley() != after.volley():
		parts.append("Bolts %d -> %d" % [before.volley(), after.volley()])
	if not before.pierces() and after.pierces():
		parts.append("starts ignoring armor")
	before.free()
	after.free()
	return ", ".join(parts)


## 1234 -> "1.2k", for stat lines that must stay short.
func _short_number(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fm" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%.0f" % value


func sync_track_buttons() -> void:
	var list: Array = TDData.tracks(game.selected.type_id)
	var hint := ""
	for i in track_buttons.size():
		var b: Button = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		b.visible = true
		var t: Dictionary = list[i]
		var rank: int = game.selected.track_rank(i)
		var top: int = game.selected.track_max(i)
		var cap_rank: int = game.selected.track_cap(i)
		var capstone: Dictionary = TDData.capstone(game.selected.type_id, i)
		var star := "  *" if not capstone.is_empty() else ""
		var blocked: Dictionary = game.selected.track_block(i)
		if rank >= top:
			b.disabled = true
			b.text = "%s%s\n%d/%d  MAX" % [t["name"], star, rank, top]
		elif not blocked.is_empty():
			b.disabled = true
			b.text = "%s\n%d/%d  needs %s %d" % [t["name"], rank, top, blocked["name"],
					int(blocked["rank"])]
		elif rank >= cap_rank:
			# Installed everything the account has unlocked; the next rank is
			# a coin purchase in the tech tree.
			b.disabled = true
			var state: Dictionary = Progress.track_buy_state(game.selected.type_id, i)
			if not bool(state["level_ok"]):
				b.text = "%s\n%d/%d  Lv %d" % [t["name"], rank, top,
						Progress.track_unlock_level(game.selected.type_id, i)]
			else:
				b.text = "%s\n%d/%d  unlock %d c" % [t["name"], rank, top,
						int(state["cost"])]
				hint = "Unlock more ranks with coins in the Tech Tree."
		else:
			var cost: int = game.selected.track_cost(i)
			b.disabled = game.gold < cost
			b.text = "%s%s\n%d/%d   $%d" % [t["name"], star, rank, top, cost]
			if rank + 1 >= top and not capstone.is_empty():
				hint = "* Next rank of %s unlocks %s: %s" % [t["name"], capstone["name"],
						capstone["desc"]]
		b.tooltip_text = _track_explanation(game.selected.type_id, i, game.selected)
	if game.hovered_track < 0:
		info_hover.text = hint
