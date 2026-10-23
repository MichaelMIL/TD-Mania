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
var palette_icons: Dictionary = {}
## The state each card was last drawn in ("ready", "armed", "poor",
## "locked"), so its look is only touched when the state changes.
var palette_state: Dictionary = {}
## Card and upgrade-button looks, made once. A card says what it is by its
## border and price colour rather than by fading: a faded card on a phone in
## daylight reads as missing, not as "not yet".
var card_boxes: Dictionary = {}
var track_box_buy: StyleBoxFlat
var track_box_buy_hover: StyleBoxFlat
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
## Whether the card under the pointer was already the armed tower when it
## was pressed. A second tap on an armed card disarms it, which is the only
## way to cancel a placement on a touch screen (there is no right button).
var card_was_armed: bool = false

## Layout. The desktop layout is the design: a 64 px top bar over a 1280 px
## map, the palette down the right, a 134 px info bar underneath. The
## handheld layout (phones, tablets, or "-- --phone" on a desktop) keeps
## every widget but arranges them for a wide short screen with big text:
## the top bar spans the width, the map is scaled to fit under it, the
## palette and the tower info share a column beside it, and the wave strip
## runs under the map. `f` scales text in that column, `ft` in the top bar
## (which is squeezed to fit the width), `fo` the overlays.
var handheld: bool = false
var f: float = 1.0
var ft: float = 1.0
var fo: float = 1.0
## Top bar height, and where the map lands on screen.
var top_h: float = float(TDData.HUD_H)
var map_screen: Rect2 = Rect2(0.0, float(TDData.HUD_H), float(TDData.MAP_W), float(TDData.MAP_H))
## Marks a track whose last rank unlocks a special ability.
const STAR := " ★"

## Handheld only: the column shows one of these at a time — the palette
## until a tower is selected, then that tower's panel.
var palette_box: Control
var info_box: Control
## Handheld only: the column can be folded away to clear the side of the
## screen; a tab at the edge brings it back, and selecting a tower opens it
## for as long as the selection lasts.
var column: Control
var column_open: bool = true
var column_tab: Button
var strip: Control
var strip_h: float = 0.0
var tab_w: float = 0.0
## Handheld only: how far in from each screen edge (left, top, right,
## bottom) the notch, the rounded corners and the home bar reach.
var safe: Vector4 = Vector4.ZERO
## Handheld only: covers beside the board. The world is drawn by a camera,
## so whatever lies past the board's edges (the road's way in, the range of
## a tower in the corner) would otherwise show in the notch's strip.
var mask_left: ColorRect
var mask_right: ColorRect
## Handheld only: "Start now" sits beside the countdown, where the desktop
## line names a key instead.
var btn_start_now: Button
## Everything on screen hangs off this, so a relayout is one free().
var layer: CanvasLayer
## The screen the current layout was measured for.
var laid_out_for: Vector2 = Vector2.ZERO


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
	laid_out_for = screen_size()
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	handheld = App.handheld()
	if handheld:
		_layout_handheld(root, laid_out_for)
		if not get_window().size_changed.is_connected(_on_window_resized):
			get_window().size_changed.connect(_on_window_resized)
	else:
		_build_topbar(root)
		_build_palette(root)
		_build_info_bar(root)
	_build_status_label(root)
	_build_creep_tip(root)
	_build_game_over(root)
	if handheld:
		place_map(column.visible)


## The screen in design units, as the stretch mode will present it. Taken
## from the window rather than the viewport, which on a phone can still be
## reporting the design size during the first frame.
func screen_size() -> Vector2:
	var win := get_window()
	var base := Vector2(win.content_scale_size)
	var size := Vector2(win.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return base
	return size / minf(size.x / base.x, size.y / base.y)


## A phone reports its real size a frame or two in, and a tablet can be
## turned over: either way the handheld layout is measured again. Every
## widget is rebuilt, then told what the match is up to.
func _on_window_resized() -> void:
	if not handheld or frozen or screen_size().is_equal_approx(laid_out_for):
		return
	# The window signal fires mid-frame; the tree is edited on the next one.
	rebuild.call_deferred()


func rebuild() -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.free()
	layer = null
	track_buttons.clear()
	palette_cards.clear()
	palette_costs.clear()
	palette_icons.clear()
	palette_state.clear()
	preview_row = null
	lbl_wave_note = null
	preview_wave = -1
	build()
	# Widget state the game writes directly, restored from the match.
	btn_pause.text = "▶" if game.paused else "II"
	btn_auto.text = "Auto ●" if game.auto_start else "Auto ○"
	btn_auto.modulate = Color("9ce89c") if game.auto_start else Color.WHITE
	btn_speed.text = "%dx" % int(game.speeds[game.speed_index])
	over_root.visible = game.game_over
	refresh_info()
	update()


## Measures the screen and places the handheld pieces. Heights come from the
## text they hold; the map takes what is left vertically, or what the column
## leaves horizontally, whichever is tighter. Everything that carries
## information stays inside the safe area (no notch, no rounded corner, no
## home bar); backgrounds run on to the screen's edge so the inset does not
## read as a black frame.
func _layout_handheld(root: Control, size: Vector2) -> void:
	f = App.ui_scale()
	fo = clampf(f * 0.7, 1.0, 1.6)
	safe = App.safe_margins()
	var usable_w := size.x - safe.x - safe.z
	# The top bar is one row of fixed-width fields; shrink its text until
	# the row fits, so a narrow phone never pushes the buttons off screen.
	const TOP_ROW_W := 1032.0
	ft = minf(f, (usable_w - 120.0) / TOP_ROW_W)
	top_h = ceilf(44.0 * ft + 12.0 + safe.y)
	strip_h = ceilf(22.0 * f + 10.0)
	tab_w = ceilf(28.0 * f)
	var col_min := ceilf(2.0 * 102.0 * f * 0.8 + 40.0)
	var s := minf((size.y - top_h - strip_h - safe.w) / float(TDData.MAP_H),
			(usable_w - col_min) / float(TDData.MAP_W))
	var column_left := safe.x + float(TDData.MAP_W) * s

	for i in 2:
		var mask := ColorRect.new()
		mask.color = Color("0b1119")
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(mask)
		if i == 0:
			mask_left = mask
		else:
			mask_right = mask
	_build_topbar(root)
	_build_column(root, column_left, top_h)
	_build_wave_strip(root)
	_build_column_tab(root)
	# The pause menu is drawn at design size on its own layer; scaling the
	# layer about the screen's centre blows it up without touching its code.
	game.pause_layer.scale = Vector2(fo, fo)
	game.pause_layer.offset = size * 0.5 * (1.0 - fo)


## Puts the board where the column's state leaves room for it. With the
## column open the board sits at the left of the safe area; folded, it is
## centred in the width that remains beside the tab. The board is usually
## bound by the screen's height rather than its width, so folding the
## column clears the side of the screen more than it grows the board.
func place_map(column_shown: bool) -> void:
	var size := laid_out_for
	var fit_h := (size.y - top_h - strip_h - safe.w) / float(TDData.MAP_H)
	var left := safe.x
	var right: float = column.offset_left if column_shown else size.x - safe.z - tab_w
	var room := right - left
	var s := minf(fit_h, room / float(TDData.MAP_W))
	var w := float(TDData.MAP_W) * s
	var x := left if column_shown else left + (room - w) * 0.5
	map_screen = Rect2(x, top_h, w, float(TDData.MAP_H) * s)
	game.set_world_view(s, Vector2(x, top_h - float(TDData.HUD_H) * s))
	# The strip runs to the screen's bottom edge; its text stays above the
	# home bar through its bottom margin.
	strip.position = Vector2(x, map_screen.end.y)
	strip.size = Vector2(w, size.y - map_screen.end.y)
	lbl_status.get_parent().offset_left = x
	lbl_status.get_parent().offset_right = map_screen.end.x
	column_tab.position = Vector2(size.x - safe.z - tab_w, top_h)
	column_tab.size = Vector2(tab_w, size.y - top_h - safe.w)
	var right_edge: float = column.offset_left if column_shown else size.x
	mask_left.position = Vector2(0.0, top_h)
	mask_left.size = Vector2(x, size.y - top_h)
	mask_right.position = Vector2(map_screen.end.x, top_h)
	mask_right.size = Vector2(maxf(0.0, right_edge - map_screen.end.x), size.y - top_h)
	if game.tutorial_layer != null:
		# The walkthrough is centred over the board, clear of the column.
		game.tutorial_layer.scale = Vector2(fo, fo)
		game.tutorial_layer.offset = Vector2(map_screen.get_center().x - size.x * 0.5 * fo,
				top_h + 10.0 - (float(TDData.HUD_H) + 26.0) * fo)
	game.cursor.queue_redraw()


## Folds the column or opens it, then shows whichever the match needs.
func toggle_column() -> void:
	column_open = not column_open
	refresh_info()


func _build_column_tab(root: Control) -> void:
	column_tab = _button("◂", int(20 * f), Vector2(tab_w, 0.0))
	column_tab.tooltip_text = "Open the build palette"
	column_tab.add_theme_stylebox_override("normal", _sb(Color("0e141d"), Color("2c3a52"), 0))
	column_tab.add_theme_stylebox_override("hover", _sb(Color("16202e"), Color("32425c"), 0))
	column_tab.add_theme_stylebox_override("pressed", _sb(Color("1b2838"), Color("4fc3f7"), 0))
	column_tab.visible = false
	column_tab.pressed.connect(toggle_column)
	root.add_child(column_tab)


## A card that follows the cursor over a creep. Reading the roster off the
## board beats keeping a wiki open.
func _build_creep_tip(root: Control) -> void:
	creep_tip = PanelContainer.new()
	creep_tip.add_theme_stylebox_override("panel",
			_sb(Color(0.04, 0.06, 0.09, 0.94), Color("546e7a"), 6))
	creep_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creep_tip.visible = false
	creep_tip_label = _label("", int(12 * f), Color("e3f2fd"))
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
	var wanted: Vector2 = game.world_to_screen(pos) + Vector2(18.0, 18.0)
	var card := creep_tip.get_combined_minimum_size()
	wanted.x = minf(wanted.x, map_screen.end.x - card.x - 8.0)
	wanted.y = minf(wanted.y, map_screen.end.y - card.y - 8.0)
	creep_tip.position = wanted


## The map is finished. Same panel as defeat, dressed as a win, plus the way
## back into the run.
func show_victory(text: String, title: String = "Map cleared",
		offer_endless: bool = true) -> void:
	over_panel.add_theme_stylebox_override("panel",
			_sb(Color("121a26"), Color("ffd54f"), 10))
	lbl_over_title.text = title
	lbl_over_title.add_theme_color_override("font_color", Color("ffd54f"))
	lbl_over.text = text
	btn_continue.visible = offer_endless
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
	var bar_box := _sb(Color("111823"), Color("2c3a52"), 0)
	if handheld:
		bar.anchor_right = 1.0
		bar_box.content_margin_left += safe.x
		bar_box.content_margin_right += safe.z
		bar_box.content_margin_top += safe.y
	else:
		bar.offset_right = float(TDData.MAP_W)
	bar.offset_bottom = top_h
	bar.add_theme_stylebox_override("panel", bar_box)
	root.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	# ---- who and where
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 0)
	identity.custom_minimum_size.x = 168.0 * ft
	row.add_child(identity)
	lbl_level = _label(game.title_name(), int(16 * ft), Color("e3f2fd"))
	lbl_level.clip_text = true
	lbl_level.custom_minimum_size.x = 168.0 * ft
	lbl_level.tooltip_text = game.title_name()
	identity.add_child(lbl_level)
	var tier: Dictionary = TDData.tier_of(game.level_def)
	var badge := _label("%s  ·  %d/4" % [str(tier["name"]).to_upper(),
			int(game.level_def["tier"]) + 1], int(11 * ft), tier["color"])
	if not game.challenge.is_empty():
		# A challenge names itself on top and its map underneath.
		badge.text = "%s  ·  %s" % ["DAILY" if game.challenge.has("daily") else "CHALLENGE",
				str(game.level_def["name"]).to_upper()]
		badge.add_theme_color_override("font_color", Color("ce93d8"))
		badge.clip_text = true
		badge.custom_minimum_size.x = 168.0 * ft
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
	btn_start = _top_button("Start Wave", 14, 112.0)
	btn_start.tooltip_text = "Call the next wave in early for bonus gold, even while one is still running (%s)" \
			% Progress.key_name("start_wave")
	btn_start.pressed.connect(game._on_start_pressed)
	row.add_child(btn_start)

	btn_speed = _top_button("1x", 15, 46.0)
	btn_speed.tooltip_text = "Game speed (%s)" % Progress.key_name("speed") \
			if game.speeds.size() > 1 \
			else "Faster speeds unlock with Field Tempo in the tech tree"
	btn_speed.modulate = Color.WHITE if game.speeds.size() > 1 \
			else Color(0.55, 0.58, 0.64)
	btn_speed.pressed.connect(game._cycle_speed)
	row.add_child(btn_speed)

	btn_pause = _top_button("II", 15, 44.0)
	btn_pause.tooltip_text = "Pause (%s)" % Progress.key_name("pause")
	btn_pause.pressed.connect(game._toggle_pause)
	row.add_child(btn_pause)

	btn_auto = _top_button("Auto", 12, 54.0)
	btn_auto.tooltip_text = "Automatically call each wave in early and collect the bonus gold (%s)" \
			% Progress.key_name("auto")
	btn_auto.pressed.connect(game._toggle_auto)
	row.add_child(btn_auto)

	btn_surrender = _top_button("End run", 12, 64.0)
	btn_surrender.tooltip_text = "End this run now and collect what it earned"
	btn_surrender.pressed.connect(game._surrender)
	# The pause menu has the same button; a phone's bar has no room for two.
	btn_surrender.visible = not handheld
	row.add_child(btn_surrender)

	var menu := _top_button("Menu", 13, 58.0)
	menu.tooltip_text = "Park this run and come back to it later (%s)" \
			% Progress.key_name("menu")
	menu.pressed.connect(game._to_menu)
	row.add_child(menu)


func _top_button(text: String, size: int, width: float) -> Button:
	return _button(text, int(size * ft), Vector2(width * ft, 44.0 * ft))


## A number that owns its space: fixed width, clipped rather than pushy.
func _stat_field(width: float, size: int, color: Color, hint: String) -> Label:
	var l := _label("", int(size * ft), color)
	l.custom_minimum_size.x = width * ft
	l.clip_text = true
	l.tooltip_text = hint
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Right-hand build palette: one card per tower, dragged onto the map. It
## runs from the map's edge to the screen's, so a wide window gives the
## cards the room rather than leaving a bar.
func _build_palette(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = float(TDData.MAP_W)
	panel.add_theme_stylebox_override("panel", _sb(Color("0e141d"), Color("2c3a52"), 0))
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_build_palette_grid(col)


## The BUILD heading, the scrolling grid of cards and the hint under it,
## into whatever column holds them.
func _build_palette_grid(col: Control, width: float = float(TDData.PALETTE_W)) -> void:
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("BUILD", int(15 * f), Color("90a4ae"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if handheld:
		var fold := _button("▸", int(16 * f), Vector2(30.0 * f, 24.0 * f))
		fold.tooltip_text = "Fold the palette away"
		fold.pressed.connect(toggle_column)
		head.add_child(fold)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var grid := GridContainer.new()
	# As many cards across as fit; two on the desktop palette.
	var card_w := 102.0 * (f * 0.8 if handheld else 1.0)
	grid.columns = maxi(2, int(floorf((width - 20.0 + 6.0) / (card_w + 6.0))))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for i in TDData.TOWER_ORDER.size():
		var type_id: String = TDData.TOWER_ORDER[i]
		# A challenge that names its towers shows only those; a locked card
		# for a tower nobody can build here would only be noise.
		if not game.challenge.is_empty() and not game.tower_available(type_id):
			continue
		grid.add_child(_palette_card(type_id, i))

	if handheld:
		# The walkthrough says it, and the column's height is better spent
		# on cards.
		return
	var hint := _label("Drag a card onto the map, or tap it then tap a cell.\nTap it again to put it away."
			if App.touchscreen() else "Drag a card onto the map,\nor click it then click a cell.",
			int(12 * f), Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)


## Handheld: one column beside the map with the palette above and the
## selected tower's stats, upgrade tracks and actions below. Everything the
## desktop bottom bar held except the wave strip, which goes under the map.
func _build_column(root: Control, left: float, top: float) -> void:
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = left
	panel.offset_top = top
	var box := _sb(Color("0e141d"), Color("2c3a52"), 0)
	box.content_margin_right += safe.z
	box.content_margin_bottom += safe.w
	panel.add_theme_stylebox_override("panel", box)
	root.add_child(panel)
	column = panel

	# The two faces of the column, stacked; refresh_info() shows one.
	var width: float = laid_out_for.x - safe.z - left
	palette_box = VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", int(6 * f))
	palette_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(palette_box)
	_build_palette_grid(palette_box, width)

	# The tower panel scrolls rather than spills: a tower with four tracks
	# and a long stat line is taller than a phone's column. The actions stay
	# pinned under it, always in reach. Nothing may widen the panel; every
	# line wraps or is trimmed.
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_FULL_RECT)
	info.add_theme_constant_override("separation", int(5 * f))
	panel.add_child(info)
	info_box = info
	info_box.visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(5 * f))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	info_title = _label("", int(16 * f), Color("e3f2fd"))
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(info_title)

	info_body = _label("", int(12 * f), Color(1, 1, 1, 0.78))
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(info_body)

	# One track per row, full width: the picture, the name and rank, the
	# price and what it buys.
	for i in 4:
		var b := _track_button(i, int(12 * f), 30.0 * f)
		col.add_child(b)

	# A footnote under the list rather than a banner over it: text that
	# changes length above the buttons moved them under the finger.
	info_hover = _label("", int(11 * f), Color(0.86, 0.79, 0.58, 0.9))
	info_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_hover.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(info_hover)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(6 * f))
	btn_target = _action_button("Target: First", int(12 * f), 30.0 * f)
	btn_target.pressed.connect(game._cycle_target_mode)
	info.add_child(btn_target)
	info.add_child(actions)
	btn_move = _action_button("Move", int(12 * f), 30.0 * f)
	btn_move.tooltip_text = "Pick this tower up and put it somewhere else. Free, once a wave, between waves."
	btn_move.pressed.connect(game.begin_move)
	actions.add_child(btn_move)
	btn_sell = _action_button("Sell", int(12 * f), 30.0 * f)
	btn_sell.pressed.connect(game._sell_selected)
	actions.add_child(btn_sell)


## An upgrade track's button, wired to buy that track and explain it.
func _track_button(i: int, font_size: int, picture: float) -> TrackButton:
	var b := TrackButton.new(font_size, picture)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): Audio.play("click", -12.0, 0.0))
	b.pressed.connect(game._upgrade_selected.bind(i))
	b.mouse_entered.connect(_hover_track.bind(i))
	b.mouse_exited.connect(_hover_track.bind(-1))
	b.visible = false
	track_buttons.append(b)
	return b


## A button that shares its row: its label is trimmed, never allowed to
## push its neighbours or the panel wider.
func _action_button(text: String, font_size: int, height: float) -> Button:
	var b := _button(text, font_size, Vector2(0.0, height))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


## Handheld: the next-wave readout in a strip between the map and the
## bottom of the screen.
func _build_wave_strip(root: Control) -> void:
	var bar := PanelContainer.new()
	var box := _sb(Color("0b1119"), Color("2c3a52"), 0)
	box.content_margin_bottom += safe.w
	bar.add_theme_stylebox_override("panel", box)
	root.add_child(bar)
	strip = bar
	_build_wave_preview(bar)


func _palette_card(type_id: String, index: int) -> Control:
	var d: Dictionary = TDData.tower_def(type_id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(102.0, 88.0) * (f * 0.8 if handheld else 1.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s  $%d\n%s" % [d["name"], int(d["cost"]), d["desc"]]
	card.add_theme_stylebox_override("panel", _sb(Color("16202e"), Color("32425c"), 6))
	card.gui_input.connect(_palette_input.bind(type_id))
	card.mouse_entered.connect(_hover_card.bind(type_id))
	card.mouse_exited.connect(_hover_card.bind(""))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	card.add_child(col)

	var fcard := f * 0.8 if handheld else 1.0
	var icon := TowerIcon.new()
	icon.type_id = type_id
	icon.custom_minimum_size = Vector2(0.0, 38.0 * fcard)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	palette_icons[type_id] = icon

	var name_row := _label(str(d.get("short", d["name"])), int(12 * fcard), Color("e3f2fd"))
	name_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)

	var locked: bool = not game.tower_available(type_id)
	var cost := _label("Lv %d" % Progress.tower_unlock_level(type_id) if locked
			else "$%d" % game.tower_cost(type_id), int(12 * fcard),
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


## Draws a palette card for its state: ready to buy, armed for placing, too
## dear for the gold in hand, or still locked.
func _style_card(type_id: String, state: String) -> void:
	if card_boxes.is_empty():
		card_boxes["ready"] = _sb(Color("18243a"), Color("4a6585"), 6)
		var armed := _sb(Color("16301f"), Color("66bb6a"), 6)
		armed.set_border_width_all(3)
		card_boxes["armed"] = armed
		card_boxes["poor"] = _sb(Color("141b26"), Color("3a3240"), 6)
		card_boxes["locked"] = _sb(Color("10151d"), Color("232d3b"), 6)
	var card: Control = palette_cards[type_id]
	card.add_theme_stylebox_override("panel", card_boxes[state])
	card.modulate = Color(0.62, 0.66, 0.72) if state == "locked" else Color.WHITE
	if palette_icons.has(type_id):
		palette_icons[type_id].modulate = Color(1, 1, 1, 0.45) if state == "poor" else Color.WHITE
	if palette_costs.has(type_id):
		var color := Color("ffd54f")
		if state == "poor":
			color = Color("ef5350")
		elif state == "locked":
			color = Color("90a4ae")
		elif state == "armed":
			color = Color("9ce89c")
		palette_costs[type_id].add_theme_color_override("font_color", color)


## Draws an upgrade button for what it offers: "buy" (affordable, outlined
## in green), "poor" (red text), "max" (gold text), "locked" or "preview"
## (grey). Only touched when the state changes; this runs every frame.
func _style_track(b: Button, state: String) -> void:
	if b.get_meta("state", "") == state:
		return
	b.set_meta("state", state)
	if track_box_buy == null:
		track_box_buy = _sb(Color("1a3324"), Color("66bb6a"), 6)
		track_box_buy.set_border_width_all(2)
		track_box_buy_hover = _sb(Color("214230"), Color("8ed68f"), 6)
		track_box_buy_hover.set_border_width_all(2)
	if state == "buy":
		b.add_theme_stylebox_override("normal", track_box_buy)
		b.add_theme_stylebox_override("hover", track_box_buy_hover)
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_stylebox_override("hover")
	var colors := {"poor": Color("ef9a9a"), "max": Color("ffd54f"),
		"locked": Color(0.62, 0.68, 0.76), "preview": Color(0.75, 0.8, 0.86)}
	if colors.has(state):
		b.add_theme_color_override("font_disabled_color", colors[state])
	else:
		b.remove_theme_color_override("font_disabled_color")
	if b is TrackButton:
		var name_color := Color("e8f1fb")
		var detail_color := Color("9ce89c")
		var picture_alpha := 1.0
		match state:
			"poor":
				detail_color = Color("ef9a9a")
			"max":
				name_color = Color(0.85, 0.88, 0.92)
				detail_color = Color("ffd54f")
			"locked":
				name_color = Color(0.7, 0.75, 0.82)
				detail_color = Color(0.6, 0.66, 0.74)
				picture_alpha = 0.5
			"preview":
				name_color = Color(0.82, 0.86, 0.9)
				detail_color = Color(0.68, 0.74, 0.8)
				picture_alpha = 0.8
		(b as TrackButton).paint(name_color, detail_color, picture_alpha)


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
			card_was_armed = game.placing == type_id and game.moving == null
			game.begin_drag(type_id)
			return
		# The card keeps mouse focus until the button goes up, so it also
		# sees the release that ends a drag onto the map; by then the game's
		# own `_input` has placed the tower and ended the drag. What is left
		# to handle is a release back over the card: a click, not a drag.
		# That keeps the tower selected for click-to-place — unless it was
		# already selected, in which case this click puts it away.
		game.dragging = false
		var card: Control = palette_cards[type_id]
		var over_card := Rect2(Vector2.ZERO, card.size).has_point(event.position)
		if over_card and card_was_armed:
			game.placing = ""
			refresh_info()
		card_was_armed = false
		game.cursor.queue_redraw()


## Strip along the top of the bottom bar naming what the next wave brings,
## with a note for any kind that needs a specific answer.
func _build_wave_preview(parent: Control) -> void:
	preview_row = HBoxContainer.new()
	preview_row.custom_minimum_size.y = 24 * f
	preview_row.add_theme_constant_override("separation", 6)
	preview_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview_row)


## The advice line is rebuilt with the chips rather than kept: it lives inside
## `preview_row`, which is emptied and freed on every refresh.
func _wave_note_label(text: String) -> Label:
	var note := _label(text, int(12 * f), Color("ffca28"))
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
	dot.custom_minimum_size = Vector2(12.0, 12.0) * f
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var label := _label("%d %s" % [count, d["name"]], int(12 * f), Color("e3f2fd"))
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
		var running := _label("Wave %d in progress" % game.wave, int(13 * f), Color(1, 1, 1, 0.4))
		running.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_row.add_child(running)
		return

	var composition: Dictionary = game.wave_composition(upcoming)
	var boss: bool = composition.has("boss") or composition.has("titan")
	var affix: Dictionary = TDData.affix_for(upcoming)
	var heading_text := "BOSS WAVE %d" % upcoming if boss else "Wave %d incoming" % upcoming
	if not affix.is_empty():
		heading_text += "  ·  %s" % str(affix["name"]).to_upper()
	var heading := _label(heading_text, int(13 * f),
			Color("ef5350") if boss else (Color("ffca28") if not affix.is_empty()
			else Color(1, 1, 1, 0.65)))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(heading)
	for kind: String in composition:
		preview_row.add_child(_enemy_chip(kind, int(composition[kind])))

	# One line of advice, drawn from the roster's own notes, right-aligned in
	# whatever space the chips leave.
	var notes: Array = []
	# A modifier changes the whole wave, so it outranks any one creep's note.
	if not affix.is_empty():
		notes.append("%s: %s" % [affix["name"], affix["note"]])
	for kind: String in composition:
		var note := str(TDData.ENEMIES[kind].get("note", ""))
		if note != "":
			notes.append("%s: %s" % [TDData.ENEMIES[kind]["name"], note])
	lbl_wave_note = _wave_note_label(str(notes[0]) if not notes.is_empty() else "")
	preview_row.add_child(lbl_wave_note)


func _build_status_label(root: Control) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(10 * f))
	row.offset_left = map_screen.position.x
	row.offset_right = map_screen.end.x
	row.offset_top = top_h + 6.0
	row.offset_bottom = top_h + 6.0 + 30.0 * f
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	lbl_status = _label("", int(15 * f), Color(1, 1, 1, 0.75))
	# Clipped on the desktop, where it spans the map; on a phone it sits in
	# a centred row with the button and must keep the width of its text.
	lbl_status.clip_text = not handheld
	lbl_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lbl_status)
	if handheld:
		btn_start_now = _button("Start now", int(14 * f), Vector2(0.0, 30.0 * f))
		btn_start_now.add_theme_color_override("font_color", Color("9ce89c"))
		btn_start_now.pressed.connect(game._on_start_pressed)
		btn_start_now.visible = false
		row.add_child(btn_start_now)


## Bottom bar: selected tower stats on the left, one button per upgrade track
## in the middle, sell on the right.
func _build_info_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_bottom = 1.0
	bar.offset_top = float(TDData.HUD_H + TDData.MAP_H)
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
		var b := _track_button(i, 12, 30.0)
		b.custom_minimum_size.y = 74.0
		tracks_row.add_child(b)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 124
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	# Three buttons in the bar's height: at 34 px each they ran off the
	# bottom of the screen and Sell was half hidden.
	right.add_theme_constant_override("separation", 3)
	row.add_child(right)

	btn_target = _button("Target: First", 12, Vector2(118.0, 29.0))
	btn_target.pressed.connect(game._cycle_target_mode)
	right.add_child(btn_target)

	btn_move = _button("Move", 13, Vector2(118.0, 29.0))
	btn_move.tooltip_text = "Pick this tower up and put it somewhere else. Free, once a wave, between waves."
	btn_move.pressed.connect(game.begin_move)
	right.add_child(btn_move)

	btn_sell = _button("Sell", 13, Vector2(118.0, 29.0))
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
	panel.offset_left = -300.0 * fo
	panel.offset_right = 300.0 * fo
	panel.offset_top = -150.0 * fo
	panel.offset_bottom = 150.0 * fo
	over_panel = panel
	panel.add_theme_stylebox_override("panel", _sb(Color("121a26"), Color("ef5350"), 10))
	over_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	lbl_over_title = _label("The base has fallen", int(28 * fo), Color("ef5350"))
	var title := lbl_over_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	lbl_over = _label("", int(15 * fo), Color(1, 1, 1, 0.85))
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_over.custom_minimum_size = Vector2(560.0 * fo, 0.0)
	col.add_child(lbl_over)

	btn_continue = _button("Keep playing — endless", int(15 * fo), Vector2(0.0, 38.0 * fo))
	btn_continue.pressed.connect(game.continue_endless)
	btn_continue.visible = false
	col.add_child(btn_continue)

	var again := _button("Play again  (%s)" % Progress.key_name("restart"), int(16 * fo),
			Vector2(0.0, 42.0 * fo))
	again.pressed.connect(game._restart)
	col.add_child(again)

	var menu := _button("%s  (%s)" % ["Level select" if game.challenge.is_empty() else "Challenges",
			Progress.key_name("menu")], int(15 * fo),
			Vector2(0.0, 38.0 * fo))
	menu.pressed.connect(game._to_menu)
	col.add_child(menu)


func update() -> void:
	if frozen:
		return
	lbl_lives.text = "♥ %d" % game.lives
	lbl_gold.text = "$ %d" % game.gold
	# The finish line, so a run has a shape rather than going on forever.
	var target: int = game.goal_wave()
	lbl_wave.text = "Wave %d / %d" % [maxi(1, game.wave), target] \
			if not game.map_cleared else "Wave %d ✓" % maxi(1, game.wave)
	# Banked coins plus what the run would pay out if it ended now.
	var pending := 0
	if not game.rewarded and game.wave > 1:
		pending = int(Progress.run_reward(game.wave - 1, game.score, int(game.level_def["tier"]))["coins"])
	lbl_coins.text = "◈ %d" % Progress.coins if pending <= 0 \
			else "◈ %d +%d" % [Progress.coins, pending]
	if btn_start_now != null:
		# Over the board it is only ever an offer: when there is nothing to
		# call in it goes away rather than sitting there greyed out.
		btn_start_now.visible = not game.game_over \
				and (not game.in_wave or game.can_rush())
		if game.in_wave:
			var ready: int = game.rush_bonus()
			btn_start_now.text = "Rush  +$%d" % ready if ready > 0 else "Rush wave"
			btn_start_now.disabled = false
	if game.game_over:
		lbl_status.text = "Base destroyed on wave %d" % game.wave
		btn_start.disabled = true
		btn_start.text = "Game over"
		return
	if game.in_wave:
		var left: int = game.spawn_queue.size() - game.spawn_index + game.enemies.size()
		var merged: int = game.waves_merged
		lbl_status.text = ("Waves %d-%d in progress — %d enemies left"
				% [game.wave - merged + 1, game.wave, left]) if merged > 1 \
				else ("Wave %d in progress — %d enemies left" % [game.wave, left])
		# The same button, still offering the same thing: the next wave,
		# now, for gold. It just costs more nerve while one is running.
		var rush: int = game.rush_bonus()
		btn_start.disabled = not game.can_rush()
		if game.can_rush():
			btn_start.text = "Rush  +$%d" % rush if rush > 0 else "Rush wave"
		elif game.wave >= game.goal_wave() and not game.map_cleared:
			btn_start.text = "Final wave"
		else:
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
		elif btn_start_now != null:
			# The button beside the line carries the offer on a phone.
			btn_start_now.disabled = false
			lbl_status.text = "Next wave in %.1fs%s" % [maxf(0.0, game.break_timer), from]
		else:
			lbl_status.text = "Next wave in %.1fs — Start now for +$%d bonus (%s)%s" \
					% [maxf(0.0, game.break_timer), bonus, Progress.key_name("start_wave"), from]
		if btn_start_now != null:
			btn_start_now.text = "Start now" if bonus <= 0 or game.wave + 1 <= game.early_claimed \
					else "Start now  +$%d" % bonus
		# For the first seconds of the break, what just happened matters more
		# than the countdown to what is next.
		if game.wave_report_timer > 0.0 and game.wave_report != "":
			lbl_status.text = game.wave_report
		btn_start.disabled = false
		btn_start.text = "Start Wave"
	refresh_wave_preview()
	for type_id: String in palette_cards:
		var state := "ready"
		if not game.tower_available(type_id):
			state = "locked"
		elif game.placing == type_id:
			state = "armed"
		elif game.gold < game.tower_cost(type_id):
			state = "poor"
		if palette_state.get(type_id, "") != state:
			palette_state[type_id] = state
			_style_card(type_id, state)
		if game.tower_available(type_id) and palette_costs.has(type_id):
			var price := "$%d" % game.tower_cost(type_id)
			if palette_costs[type_id].text != price:
				palette_costs[type_id].text = price
	if game.selected != null and is_instance_valid(game.selected):
		sync_track_buttons()


## Shows the selected tower's live stats and upgrade tracks, a hovered tower
## type's blurb, or the default hint text.
func refresh_info(hovered_type: String = "") -> void:
	var has_selection: bool = game.selected != null and is_instance_valid(game.selected)
	if handheld:
		palette_box.visible = not has_selection
		info_box.visible = has_selection
		var show := column_open or has_selection
		if column.visible != show:
			column.visible = show
			column_tab.visible = not show
			place_map(show)
	if has_selection:
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
		if not game.tower_available(type_id):
			where = "not in this challenge" if not game.challenge.is_empty() \
					else "locked until level %d" % Progress.tower_unlock_level(type_id)
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

	info_title.text = game.title_name()
	var weather: Dictionary = TDData.hazard_of(game.level_def)
	var blurb_text: String = str(game.challenge.get("blurb", game.level_def["blurb"]))
	if not weather.is_empty():
		blurb_text += "   ⚠ %s: %s" % [weather["name"], weather["note"]]
	if not game.modifiers.is_empty():
		var chosen: Array = []
		for id: String in game.modifiers:
			chosen.append(str(TDData.modifier(id).get("name", id)))
		blurb_text += "   ⚑ %s (+%d%% reward)" % [", ".join(chosen),
				int(round((TDData.modifier_bonus(game.modifiers) - 1.0) * 100.0))]
	if App.touchscreen():
		# Every key below has a button on screen; listing keys to a thumb
		# is noise.
		info_body.text = "%s\n%s\nDrag a tower onto the map, or tap a card then a cell. Tap a tower to see its upgrades." \
				% [blurb_text, "    ".join(game.objective_lines(true))]
		return
	info_body.text = "%s\n%s\nDrag a tower onto the map. %s upgrades, %s sells, %s starts a wave early. %s auto, %s target, %s pause, %s speed, %s menu." \
			% [blurb_text, "    ".join(game.objective_lines(true)),
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
			else ("Moving…" if game.moving != null
			else ("Move later" if handheld else "Move (next wave)"))
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
		var b: TrackButton = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		var t: Dictionary = list[i]
		var cap: Dictionary = TDData.capstone(type_id, i)
		b.visible = true
		b.disabled = true
		_style_track(b, "preview")
		var unlocked := Progress.track_rank_for(type_id, i)
		b.show_track(type_id, i, "%s %d/%d unlocked%s" % [t["name"], unlocked, int(t["max"]),
				STAR if not cap.is_empty() else ""],
				"$%d · %s" % [TDData.track_gold_cost(type_id, i, 0), _track_effect(t)])
		b.tooltip_text = _track_explanation(type_id, i, null)
	var caps: Array = []
	for i in list.size():
		var cap: Dictionary = TDData.capstone(type_id, i)
		if not cap.is_empty():
			caps.append(str(cap["name"]))
	if game.hovered_track < 0:
		info_hover.text = ("★ unlocks " + ", ".join(caps)) if not caps.is_empty() else ""


## What one rank of a track does, in a few words: its first effect. The
## full list, with before and after numbers, is in the hover text.
func _track_effect(t: Dictionary) -> String:
	return TDData.describe_mods(t["mods"]).get_slice(", ", 0)


## Called when the pointer enters or leaves an upgrade button (-1 = left).
func _hover_track(track: int) -> void:
	# A finger has no hover: the "hover" a tap sends would swap a paragraph
	# into the panel as the tap lands. Each button carries its own price
	# and effect instead.
	if handheld:
		return
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
	# Scratch copies belong to the match, not to the HUD: they have to see
	# the same auras, tech and map hazard the real tower would.
	var before := Tower.new()
	before.game = game
	before.setup(type_id, Vector2i.ZERO)
	var after := Tower.new()
	after.game = game
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


## Each upgrade button says everything needed to decide: the name and rank
## on top (with a star when a special ability waits at the last rank), and
## underneath either the price and what it buys, or why it cannot be bought
## yet. The only note left over is which rank unlocks an ability.
func sync_track_buttons() -> void:
	var type_id: String = game.selected.type_id
	var list: Array = TDData.tracks(type_id)
	var hint := ""
	for i in track_buttons.size():
		var b: TrackButton = track_buttons[i]
		if i >= list.size():
			b.visible = false
			continue
		b.visible = true
		var t: Dictionary = list[i]
		var rank: int = game.selected.track_rank(i)
		var top: int = game.selected.track_max(i)
		var cap_rank: int = game.selected.track_cap(i)
		var capstone: Dictionary = TDData.capstone(type_id, i)
		var blocked: Dictionary = game.selected.track_block(i)
		var title := "%s %d/%d%s" % [t["name"], rank, top,
				STAR if not capstone.is_empty() else ""]
		var detail := ""
		var state := "locked"
		if bool(game.rule("no_upgrades", false)):
			detail = "no upgrades in this challenge"
		elif rank >= top:
			state = "max"
			detail = "MAX · %s" % capstone["name"] if not capstone.is_empty() else "MAX"
		elif not blocked.is_empty():
			detail = "needs %s %d" % [blocked["name"], int(blocked["rank"])]
		elif rank >= cap_rank:
			# Installed everything the account has unlocked; the next rank is
			# bought with coins in the tech tree.
			var buy: Dictionary = Progress.track_buy_state(type_id, i)
			if not bool(buy["level_ok"]):
				detail = "account level %d" % Progress.track_unlock_level(type_id, i)
			else:
				detail = "Tech Tree · %d coins" % int(buy["cost"])
				if not handheld:
					hint = "Unlock more ranks with coins in the Tech Tree."
		else:
			var cost: int = game.selected.track_cost(i)
			state = "poor" if game.gold < cost else "buy"
			detail = "$%d · %s" % [cost, _track_effect(t)]
			if rank + 1 >= top and not capstone.is_empty():
				hint = "★ The next %s rank unlocks %s: %s" % [t["name"], capstone["name"],
						str(capstone["desc"]).trim_suffix(".").to_lower()]
		b.disabled = state != "buy"
		_style_track(b, state)
		b.show_track(type_id, i, title, detail)
		b.tooltip_text = _track_explanation(type_id, i, game.selected)
	if game.hovered_track < 0:
		info_hover.text = hint
