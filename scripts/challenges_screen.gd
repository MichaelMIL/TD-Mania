extends Control

## The challenges screen: today's daily challenge across the top, the fixed
## set underneath. Each card says the map, the rules, the goal, the reward
## and how far you have got, and offers Play (or Continue, when a run of it
## is parked). See scripts/challenges.gd for what a challenge is.

const HOME_SCENE := "res://home.tscn"

var countdown: Label
var coins_label: Label


func _ready() -> void:
	Progress.load_state()
	Audio.set_volumes(Progress.volume("sfx"), Progress.volume("music"))
	Audio.play_music(true)
	# Back from a challenge run: whatever is picked next decides the rules.
	TDData.active_challenge = {}
	_drop_stale_dailies()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


## A daily that was parked and never finished belongs to a day that is
## over; its slot in the save would otherwise sit there forever.
func _drop_stale_dailies() -> void:
	var today := "daily:%s" % Challenges.today()
	for key: String in Progress.runs.keys():
		if key.begins_with("daily:") and key != today:
			Progress.clear_run(key)


func _sb(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
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
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Audio.play("click", -12.0, 0.0))
	return b


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0b1017")
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if side != "top" else 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	# ---- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	page.add_child(head)
	head.add_child(_label("CHALLENGES", 30, Color("4fc3f7")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_label("%d / %d beaten" % [Progress.challenges_done(), Challenges.LIST.size()],
			16, Color("9ccc65")))
	coins_label = _label("◈ %d" % Progress.coins, 18, Color("ffd54f"))
	head.add_child(coins_label)
	var back := _button("Back", 16, 40.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.custom_minimum_size.x = 100.0
	back.pressed.connect(func(): get_tree().change_scene_to_file(HOME_SCENE))
	head.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)

	body.add_child(_daily_card())
	body.add_child(_label("THE SET  ·  easy to brutal  ·  each pays its coins the first time it is beaten",
			14, Color("90a4ae")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for c: Dictionary in Challenges.LIST:
		grid.add_child(_challenge_card(c))


## The map in miniature, as on the level select.
func _preview(c: Dictionary, size: Vector2) -> Control:
	var p := LevelPreview.new()
	p.level_index = Challenges.level_index(c)
	p.custom_minimum_size = size
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _rules_box(c: Dictionary, size: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	var lines: Array = Challenges.rule_lines(c)
	for i in lines.size():
		# The goal first, in white; the rules after it.
		var line := _label(("◎ " if i == 0 else "• ") + str(lines[i]), size,
				Color("e3f2fd") if i == 0 else Color(1, 1, 1, 0.72))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)
	return col


func _daily_card() -> Control:
	var c := Challenges.daily()
	var key := str(c["daily"])
	var done := Progress.daily_done(key)
	var level := Challenges.level_of(c)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(Color("1a1428"),
			Color("9ccc65") if done else Color("ce93d8"), 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)
	row.add_child(_preview(c, Vector2(260.0, 143.0)))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	info.add_child(_label("DAILY CHALLENGE  ·  %s" % Challenges.pretty_date(key).to_upper(),
			14, Color("ce93d8")))
	var tier: Dictionary = TDData.tier_of(level)
	info.add_child(_label("%s  —  %s, %s twist" % [level["name"], str(tier["name"]),
			str(c["twist"]).to_lower()], 22, Color("e3f2fd")))
	info.add_child(_rules_box(c, 14))

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 250.0
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var streak := Progress.daily_streak(key)
	var reward := int(c["reward"]) + Challenges.streak_bonus(streak + (0 if done else 1))
	side.add_child(_label("✓ Done today" if done else "◈ %d coins" % reward, 20,
			Color("9ce89c") if done else Color("ffd54f")))
	var streak_text := "No streak yet" if streak == 0 else "Streak: %d day%s" % [streak,
			"" if streak == 1 else "s"]
	if not done and streak > 0:
		streak_text += " — keep it today"
	side.add_child(_label(streak_text, 14, Color(1, 1, 1, 0.7)))
	var best := Progress.daily_best(key)
	if best > 0:
		side.add_child(_label("Best today: wave %d" % best, 14, Color(1, 1, 1, 0.7)))
	countdown = _label("", 13, Color(1, 1, 1, 0.45))
	side.add_child(countdown)
	_tick_countdown()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	_add_play_buttons(side, c, "Play again" if done else "Play the daily")
	return card


func _challenge_card(c: Dictionary) -> Control:
	var rec := Progress.challenge_record(str(c["id"]))
	var done := Progress.challenge_done(str(c["id"]))
	var level := Challenges.level_of(c)
	var tier: Dictionary = TDData.tier_of(level)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Unbeaten cards carry their grade's colour faintly in the border.
	var edge: Color = Challenges.grade_of(c)["color"]
	card.add_theme_stylebox_override("panel", _sb(Color("121a26"),
			Color("9ccc65") if done else Color(edge.r, edge.g, edge.b, 0.45)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(str(c["name"]), 20, Color("e3f2fd"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label("✓ Beaten" if done else "◈ %d" % int(c["reward"]), 15,
			Color("9ce89c") if done else Color("ffd54f")))
	var grade := Challenges.grade_of(c)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 10)
	col.add_child(sub)
	sub.add_child(_label(str(grade["name"]).to_upper(), 12, grade["color"]))
	sub.add_child(_label("%s  ·  %s map" % [level["name"], str(tier["name"]).to_lower()], 12,
			Color(1, 1, 1, 0.55)))

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	col.add_child(mid)
	mid.add_child(_preview(c, Vector2(120.0, 66.0)))
	var rules := _rules_box(c, 12)
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(rules)

	var blurb := _label(str(c["blurb"]), 12, Color(1, 1, 1, 0.55))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 200.0
	col.add_child(blurb)
	if int(rec.get("best", 0)) > 0:
		col.add_child(_label("Best: wave %d of %d" % [int(rec["best"]), int(c["waves"])], 12,
				Color(1, 1, 1, 0.7)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_add_play_buttons(col, c, "Play again" if done else "Play")
	return card


## Play, plus Continue when a run of this challenge is parked.
func _add_play_buttons(parent: Control, c: Dictionary, play_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var parked := Progress.run_for(Challenges.run_key(c))
	if not parked.is_empty():
		var resume := _button("Continue — wave %d" % (int(parked.get("wave", 0)) + 1), 14, 36.0)
		resume.add_theme_color_override("font_color", Color("9ce89c"))
		resume.pressed.connect(func(): Challenges.play(get_tree(), c, true))
		row.add_child(resume)
		play_text = "Restart"
	var play := _button(play_text, 14, 36.0)
	play.pressed.connect(func(): Challenges.play(get_tree(), c, false))
	row.add_child(play)


func _process(_delta: float) -> void:
	_tick_countdown()


func _tick_countdown() -> void:
	if countdown == null:
		return
	var left := Challenges.seconds_to_next_daily()
	countdown.text = "Next daily in %dh %02dm" % [left / 3600, (left % 3600) / 60]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and Progress.action_for(event.keycode) == "cancel":
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(HOME_SCENE)
