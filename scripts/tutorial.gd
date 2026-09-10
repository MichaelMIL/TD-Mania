class_name Tutorial
extends Control

## The first run, taught rather than assumed.
##
## The game has towers, ranks, coins, tech, objectives, targeting modes,
## flyers, water, aircraft and auras, and none of it is obvious to someone
## who did not build it. This runs once, on a new account: a line at a time,
## each waiting for the player to actually do the thing rather than for a
## timer to run out, so it cannot get ahead of them.
##
## Every step is a condition on the match itself, which means the tutorial
## has no state of its own to disagree with the game about.

signal finished

var game: Node = null
var steps: Array = []
var index: int = 0
## Steps that are simply read wait this long before the next one arrives.
var dwell: float = 0.0

var panel: PanelContainer
var label: Label
var counter: Label


## Whether this account has yet to be shown the ropes.
static func wanted() -> bool:
	return Progress.stat_int("runs") == 0 \
			and not bool(Progress.options.get("tutorial_done", false))


static func mark_seen() -> void:
	Progress.load_state()
	Progress.options["tutorial_done"] = true
	Progress.save_state()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_build_steps()
	_show_step()


func _sb() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.09, 0.14, 0.95)
	sb.border_color = Color("4fc3f7")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.offset_top = float(TDData.HUD_H) + 26.0
	panel.add_theme_stylebox_override("panel", _sb())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	counter = Label.new()
	counter.add_theme_font_size_override("font_size", 12)
	counter.add_theme_color_override("font_color", Color("4fc3f7"))
	counter.custom_minimum_size.x = 34.0
	row.add_child(counter)

	label = Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e3f2fd"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520.0
	row.add_child(label)

	var skip := Button.new()
	skip.text = "Skip"
	skip.tooltip_text = "Stop the walkthrough. It will not come back."
	skip.custom_minimum_size = Vector2(58.0, 26.0)
	skip.add_theme_font_size_override("font_size", 12)
	skip.focus_mode = Control.FOCUS_NONE
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	skip.pressed.connect(_skip)
	row.add_child(skip)


## Each step is a line and the thing that has to happen before the next
## one. `wait` steps ask nothing and move on by themselves.
func _build_steps() -> void:
	steps = [
		{"text": "That road is the whole game: everything walks it, from the portal to your base. Lose too many and the run ends.",
			"wait": 4.5},
		{"text": "Drag the Gunner from the palette onto a cell beside the road — towers only reach what passes them.",
			"until": func(): return game.occupied.size() >= 1},
		{"text": "Good. Towers fire by themselves. Press Start Wave to call the wave in early — the earlier you call it, the bigger the gold bonus.",
			"until": func(): return game.in_wave or game.wave > 1},
		{"text": "Watch it work. Kills pay gold, and gold is the only thing that buys anything during a run.",
			"until": func(): return int(game.run_stats.get("kills", 0)) >= 1},
		{"text": "Spend it: put a second tower down. Two towers covering the same stretch of road beat one tower covering twice as much.",
			"until": func(): return game.occupied.size() >= 2},
		{"text": "Click a tower you own. The bar underneath shows its upgrade tracks — a rank costs gold and takes effect the moment you buy it.",
			"until": func(): return game.selected != null},
		{"text": "Hover any creep on the board to see what it is: armour, speed, and whether it ignores fire, ignores slows, heals the others or flies.",
			"wait": 6.0},
		{"text": "That is all of it. Clear the map's last wave to beat it; the three objectives under the map name are worth a star each. Good luck.",
			"wait": 6.0},
	]


func _show_step() -> void:
	if index >= steps.size():
		_finish()
		return
	var step: Dictionary = steps[index]
	label.text = str(step["text"])
	counter.text = "%d/%d" % [index + 1, steps.size()]
	dwell = float(step.get("wait", 0.0))


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game) or index >= steps.size():
		return
	if game.game_over:
		_finish()
		return
	var step: Dictionary = steps[index]
	if step.has("until"):
		if (step["until"] as Callable).call():
			advance()
		return
	dwell -= delta
	if dwell <= 0.0:
		advance()


func advance() -> void:
	index += 1
	_show_step()


func _skip() -> void:
	index = steps.size()
	_finish()


func _finish() -> void:
	if not visible:
		return
	visible = false
	mark_seen()
	finished.emit()
