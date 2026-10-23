extends Node

## Touch harness. Feeds a match the events a phone produces — mouse events
## with device -1, which is how the engine marks mouse emulated from touch
## — and checks the few places where a finger must behave differently from
## a mouse: the lift on a dragged tower, tapping an armed card to put it
## away, the Android back button, the app going to the background, and
## scrolling a list with a finger that lands on a card or a button.
##
##   godot --headless --quit-after 600 dev/dev_touch.tscn
##
## Positions are given in board coordinates and converted to window pixels
## through the stretch transform, because the headless window is 64x64.
var game: Node
var fails := 0
func check(name: String, cond: bool) -> void:
	if not cond: fails += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])
func win(pos: Vector2) -> Vector2:
	# Content coordinates -> window pixels (the headless window is 64x64).
	return get_window().get_screen_transform() * pos
func mouse(pos: Vector2, pressed: bool, device: int) -> void:
	pos = win(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.device = device
	Input.parse_input_event(ev)
func motion(pos: Vector2, device: int) -> void:
	pos = win(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.device = device
	Input.parse_input_event(ev)
func _ready() -> void:
	Progress.use_clean_state()
	Progress.unlock_all = true
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.gold = 4000
	var card: Control = game.hud.palette_cards["gun"]
	var cpos: Vector2 = card.get_global_rect().get_center()
	var target := Vector2i(-1, -1)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun") and key.y >= 2:
			target = key; break
	check("found a cell", target.x >= 0)
	var tpos: Vector2 = game.cell_center(target)
	# 1. touch drag: press card, drag to (cell below target), release -> lands on target
	mouse(cpos, true, -1); await get_tree().process_frame
	check("touch press on card arms gun", game.placing == "gun" and game.dragging and game.touch_input)
	var finger: Vector2 = tpos - game.TOUCH_LIFT
	motion(finger, -1); await get_tree().process_frame
	check("hover cell is lifted above finger", game.hover_cell == target)
	mouse(finger, false, -1); await get_tree().process_frame
	check("tower landed on lifted cell", game.occupied.has(target) and not game.dragging)
	# 2. mouse drag has no lift
	var target2 := Vector2i(-1, -1)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun") and key != target:
			target2 = key; break
	var t2: Vector2 = game.cell_center(target2)
	mouse(cpos, true, 0); await get_tree().process_frame
	check("mouse press clears touch flag", not game.touch_input)
	motion(t2, 0); await get_tree().process_frame
	check("mouse hover is exact", game.hover_cell == target2)
	mouse(t2, false, 0); await get_tree().process_frame
	check("mouse drag placed exact", game.occupied.has(target2))
	# 3. tap card -> armed; tap again -> disarmed (a drag leaves the card
	# armed for the next one, so clear it first as Escape would)
	game.placing = ""
	mouse(cpos, true, -1); await get_tree().process_frame
	mouse(cpos, false, -1); await get_tree().process_frame
	check("tap arms", game.placing == "gun" and not game.dragging)
	mouse(cpos, true, -1); await get_tree().process_frame
	mouse(cpos, false, -1); await get_tree().process_frame
	check("second tap disarms", game.placing == "" and not game.dragging)
	# 4. back button replays cancel: arm, then GO_BACK -> disarmed
	mouse(cpos, true, -1); mouse(cpos, false, -1); await get_tree().process_frame
	check("armed again", game.placing == "gun")
	App.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame; await get_tree().process_frame
	check("back request put tower away", game.placing == "")
	# 5. background: save run + pause
	game.wave = 3
	var paused_before: bool = game.paused
	game.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	check("background pauses", game.paused and not paused_before)
	check("background parked the run", Progress.has_run(str(game.level_def["id"])))
	game._toggle_pause()
	await _palette_scrolling()
	await _level_select_scrolling()
	print("[TOUCH] %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A finger on a palette card: up and down scrolls the palette, sideways
## carries the tower out, a tap arms it. The headless window is square, so
## the palette is cut short here to give it something to scroll.
func _palette_scrolling() -> void:
	game.placing = ""
	var card: Control = game.hud.palette_cards["gun"]
	var panel: Control = card.get_parent().get_parent().get_parent().get_parent()
	panel.offset_bottom = -panel.get_global_rect().size.y + 330.0
	await frames(2)
	var scroll: ScrollContainer = TouchScroll.scroller_at(card.get_global_rect().get_center())
	check("short palette scrolls by touch", scroll != null)
	if scroll == null:
		return
	scroll.scroll_vertical = 0
	await frames(1)
	var cpos: Vector2 = card.get_global_rect().get_center()

	mouse(cpos, true, -1)
	await frames(1)
	check("a touch on a card waits before arming", game.placing == "" and not game.dragging)
	for step in 6:
		motion(cpos - Vector2(0.0, 25.0 * (step + 1)), -1)
		await frames(1)
	check("dragging up scrolls the palette", scroll.scroll_vertical > 60)
	mouse(cpos - Vector2(0.0, 150.0), false, -1)
	await frames(1)
	check("a scroll arms nothing", game.placing == "" and not game.dragging)
	TouchScroll.fling = null
	scroll.scroll_vertical = 0
	await frames(1)

	# Sideways: the held press is replayed and the drag goes to the map.
	var target := Vector2i(-1, -1)
	for key: Vector2i in game.terrain:
		if game.can_place(key, "gun") and key.y >= 2:
			target = key
			break
	var finger: Vector2 = game.cell_center(target) - game.TOUCH_LIFT
	mouse(cpos, true, -1)
	await frames(1)
	motion(cpos - Vector2(60.0, 0.0), -1)
	await frames(2)
	check("dragging sideways picks the tower up", game.placing == "gun" and game.dragging)
	motion(finger, -1)
	await frames(1)
	mouse(finger, false, -1)
	await frames(2)
	check("and puts it on the map", game.occupied.has(target) and not game.dragging)

	mouse(cpos, true, -1)
	await frames(1)
	mouse(cpos, false, -1)
	await frames(2)
	check("a tap on a held card still arms it", game.placing == "gun")
	mouse(cpos, true, -1)
	await frames(1)
	mouse(cpos, false, -1)
	await frames(2)
	check("and a second tap puts it away", game.placing == "")


## The level select: drags on a card's buttons scroll the list without
## pressing them, a tap presses them, a fling coasts, and a tap on a
## coasting list only stops it.
func _level_select_scrolling() -> void:
	game.queue_free()
	await frames(2)
	var menu: Control = load("res://menu.tscn").instantiate()
	add_child(menu)
	await frames(3)
	var scroll := _biggest_scroll(menu)
	check("level select scrolls by touch", scroll != null
			and TouchScroll.scroller_at(scroll.get_global_rect().get_center()) == scroll)
	if scroll == null:
		return
	var toggle := _first_handicap(scroll)
	check("found a handicap button", toggle != null)
	if toggle == null:
		return
	var before: int = TDData.selected_modifiers.size()
	var p: Vector2 = toggle.get_global_rect().get_center()
	mouse(p, true, -1)
	await frames(1)
	for step in 6:
		motion(p - Vector2(0.0, 30.0 * (step + 1)), -1)
		await frames(1)
	var scrolled := scroll.scroll_vertical
	check("dragging on a button scrolls the list", scrolled > 80)
	await frames(1)
	mouse(p - Vector2(0.0, 180.0), false, -1)
	await frames(2)
	check("and does not press it", TDData.selected_modifiers.size() == before)

	# The fling from that drag carries on for a moment after the lift.
	var after_lift := scroll.scroll_vertical
	check("a quick lift flings the list", TouchScroll.fling == scroll)
	await frames(3)
	check("a flung list coasts", scroll.scroll_vertical > after_lift)
	# A tap while it coasts only stops it, and presses nothing.
	var centre := scroll.get_global_rect().get_center()
	mouse(centre, true, -1)
	await frames(1)
	mouse(centre, false, -1)
	await frames(2)
	var stopped_at := scroll.scroll_vertical
	await frames(3)
	check("a tap on a coasting list stops it", TouchScroll.fling == null
			and scroll.scroll_vertical == stopped_at
			and TDData.selected_modifiers.size() == before)
	TouchScroll.fling = null

	scroll.scroll_vertical = 0
	await frames(2)
	toggle = _first_handicap(scroll)
	p = toggle.get_global_rect().get_center()
	mouse(p, true, -1)
	await frames(1)
	mouse(p, false, -1)
	await frames(3)
	check("a tap on a button presses it", TDData.selected_modifiers.size() == before + 1)
	TDData.selected_modifiers.clear()


func _biggest_scroll(root: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for n: Node in root.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if sc.is_visible_in_tree() and (best == null or sc.size.y > best.size.y):
			best = sc
	return best


## A handicap toggle on the first level card: a small button deep inside a
## card, the kind a finger lands on when it means to scroll.
func _first_handicap(scroll: ScrollContainer) -> Button:
	for n: Node in scroll.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text.contains("%") and b.text.contains("+"):
			return b
	return null
