extends Node

## Drag-to-scroll for touch screens, for every ScrollContainer in the game.
##
## Godot's own touch scrolling only hears a drag that starts on a list's
## background. A drag that starts on a button, a palette card or a level
## card goes to that control instead, and nearly every pixel of a list is
## one of those, so on a phone the lists barely moved.
##
## So a finger that lands inside a list that can scroll is held back from
## the controls for a moment, the way a phone's own lists do it:
##
## - it moves along the list: the list scrolls, follows the finger, and
##   keeps going for a moment when flung; the control never hears of it;
## - it lifts without moving: the held events are replayed and the control
##   gets a normal tap;
## - it moves across the list: the held events are replayed and everything
##   after flows straight through, so a palette card dragged sideways
##   carries its tower out onto the map and a slider slides.
##
## A tap on a list that is still coasting just stops it.
##
## Only touch is handled: mouse events the engine emulated from a touch,
## which carry device -1. A mouse keeps its wheel and its scrollbars.

const EMULATED_DEVICE := -1
## How far a finger travels before its intent is read.
const SLOP_MM := 2.0
## The same, clamped in viewport units so a tiny or huge screen still works.
const SLOP_MIN := 6.0
const SLOP_MAX := 24.0
## A flung list loses this fraction of its speed per second, roughly.
const FRICTION := 4.0
## Slower than this (viewport units a second) and a fling just stops.
const FLING_MIN := 40.0

enum State { IDLE, HOLDING, SCROLLING, PASSING }

var state: int = State.IDLE
var target: ScrollContainer = null
var start_pos: Vector2 = Vector2.ZERO
var start_scroll: float = 0.0
## Events held back while the gesture is undecided.
var held: Array = []
## Events waiting to be replayed into the viewport, in order.
var replay: Array = []
var replay_queued: bool = false
var replaying: bool = false
## Whether this touch landed on a coasting list (and so only stops it).
var caught_fling: bool = false

var velocity: float = 0.0
var last_y: float = 0.0
var last_usec: int = 0
var fling: ScrollContainer = null
var fling_pos: float = 0.0
var fling_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if replaying or not (event is InputEventMouse) or event.device != EMULATED_DEVICE:
		return
	match state:
		State.IDLE:
			if _is_left(event) and event.pressed:
				_begin(event)
		State.HOLDING:
			_hold(event)
		State.SCROLLING:
			_scroll(event)
		State.PASSING:
			# Anything that arrives before the replay has run must queue
			# behind it, or the control would see it out of order.
			if not replay.is_empty():
				replay.append(event)
				get_viewport().set_input_as_handled()
			if _is_left(event) and not event.pressed:
				state = State.IDLE


func _is_left(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT


func _begin(event: InputEventMouseButton) -> void:
	var sc := scroller_at(event.position)
	caught_fling = fling != null and is_instance_valid(fling) and fling == sc
	fling = null
	if sc == null:
		return
	target = sc
	start_pos = event.position
	start_scroll = float(sc.scroll_vertical)
	last_y = start_pos.y
	last_usec = Time.get_ticks_usec()
	velocity = 0.0
	held = [event]
	state = State.HOLDING
	get_viewport().set_input_as_handled()


func _hold(event: InputEvent) -> void:
	held.append(event)
	get_viewport().set_input_as_handled()
	if _is_left(event) and not event.pressed:
		# A tap. Give the control the whole thing, unless all it did was
		# stop a list that was coasting.
		if caught_fling:
			held.clear()
		else:
			_replay_held()
		state = State.IDLE
		return
	if not (event is InputEventMouseMotion):
		return
	var d: Vector2 = event.position - start_pos
	if d.length() < slop():
		return
	if absf(d.y) >= absf(d.x) and is_instance_valid(target):
		# Along the list: scroll, starting from here so it does not jump.
		held.clear()
		state = State.SCROLLING
		start_pos = event.position
		start_scroll = float(target.scroll_vertical)
		last_y = start_pos.y
		last_usec = Time.get_ticks_usec()
	else:
		state = State.PASSING
		_replay_held()


func _scroll(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not is_instance_valid(target):
		state = State.IDLE
		return
	var k := _scale_of(target)
	if event is InputEventMouseMotion:
		target.scroll_vertical = int(round(start_scroll - (event.position.y - start_pos.y) / k))
		var now := Time.get_ticks_usec()
		var dt := float(now - last_usec) / 1000000.0
		if dt > 0.0:
			var instant: float = -(event.position.y - last_y) / k / dt
			velocity = lerpf(velocity, instant, 0.6)
		last_y = event.position.y
		last_usec = now
	elif _is_left(event) and not event.pressed:
		state = State.IDLE
		# A finger that stopped before lifting does not fling.
		var still := float(Time.get_ticks_usec() - last_usec) / 1000000.0
		if still < 0.08 and absf(velocity) > FLING_MIN:
			fling = target
			fling_pos = float(target.scroll_vertical)
			fling_usec = Time.get_ticks_usec()
		target = null


func _process(_delta: float) -> void:
	if fling == null:
		return
	if not is_instance_valid(fling) or not fling.is_visible_in_tree():
		fling = null
		return
	# Wall-clock time: a paused or fast-forwarded match must not change how
	# a list coasts.
	var now := Time.get_ticks_usec()
	var dt := float(now - fling_usec) / 1000000.0
	fling_usec = now
	fling_pos += velocity * dt
	velocity *= exp(-FRICTION * dt)
	# Ends of the list stop it; a frame that moves less than a unit does not.
	var bar := fling.get_v_scroll_bar()
	var end := maxf(0.0, bar.max_value - bar.page)
	var at_end := fling_pos <= 0.0 or fling_pos >= end
	fling_pos = clampf(fling_pos, 0.0, end)
	fling.scroll_vertical = int(round(fling_pos))
	if absf(velocity) < FLING_MIN or at_end:
		fling = null


func _replay_held() -> void:
	replay.append_array(held)
	held.clear()
	if not replay_queued:
		replay_queued = true
		_flush.call_deferred()


## Puts the held events back into the viewport, in viewport coordinates,
## after the current event has finished its trip.
func _flush() -> void:
	replay_queued = false
	replaying = true
	var vp := get_viewport()
	while not replay.is_empty():
		vp.push_input(replay.pop_front(), true)
	replaying = false


## The innermost visible list under a point that has something to scroll.
func scroller_at(pos: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_depth := -1
	for node: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var sc := node as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			continue
		var bar := sc.get_v_scroll_bar()
		if bar.max_value - bar.page <= 0.5:
			continue
		var rect: Rect2 = sc.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, sc.size)
		if not rect.has_point(pos):
			continue
		var depth := 0
		var up := sc.get_parent()
		while up != null:
			depth += 1
			up = up.get_parent()
		if depth > best_depth:
			best_depth = depth
			best = sc
	return best


## How far a finger moves before it counts as a drag, in viewport units.
func slop() -> float:
	var px_per_unit := get_viewport().get_final_transform().get_scale().x
	var px := float(DisplayServer.screen_get_dpi()) * SLOP_MM / 25.4
	return clampf(px / maxf(0.001, px_per_unit), SLOP_MIN, SLOP_MAX)


func _scale_of(sc: Control) -> float:
	return maxf(0.001, sc.get_global_transform_with_canvas().get_scale().y)
