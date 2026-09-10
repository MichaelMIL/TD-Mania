class_name ProxyPlayer
extends RefCounted

## The crude player the balance harnesses use. It is deliberately not
## clever: it walks a wish list and builds the first thing it can afford on
## a cell next to the road, drops Command Posts where they cover the most
## towers, spends spare gold deepening whatever it already owns, and never
## adapts to what a wave is actually made of.
##
## That makes its results a floor rather than a verdict — a real player who
## counters Menders and Wardens will always go deeper. It is still the only
## way to compare twenty maps against each other on equal terms.

## Towers it will try to build, in order, cycling.
const WISH: Array = ["gun", "gun", "cannon", "flame", "gun", "frost", "cannon",
		"tide", "gun", "tesla", "flame", "cannon", "marksman", "command", "tide",
		"cannon", "airfield", "torpedo", "flame", "mortar", "helipad", "cannon"]

## Gold to keep in hand before spending on upgrades rather than towers.
const UPGRADE_FLOOR := 350

var game: Node
var mix_index: int = 0


func _init(match_node: Node) -> void:
	game = match_node


## One decision. Called a few times a second of game time.
func act() -> void:
	if game.game_over:
		return
	# A player who never upgrades is not a fair proxy for a competent one:
	# with gold to spare, deepen what is already built before adding more.
	if game.gold > UPGRADE_FLOOR and not game.occupied.is_empty() and randf() < 0.5:
		if _upgrade_something():
			return
	_act()


## Installs the cheapest available rank on some tower that can take one.
func _upgrade_something() -> bool:
	var towers: Array = game.occupied.values()
	for attempt in 6:
		var t: Tower = towers[randi() % towers.size()]
		if not is_instance_valid(t):
			continue
		var best := -1
		var best_cost := 1 << 30
		for i in t.ranks.size():
			if t.track_rank(i) >= t.track_cap(i) or not t.track_open(i):
				continue
			var cost: int = t.track_cost(i)
			if cost <= game.gold and cost < best_cost:
				best_cost = cost
				best = i
		if best >= 0:
			game._select(t)
			game._upgrade_selected(best)
			game._select(null)
			return true
	return false


func _act() -> void:
	# Upgrade ranks are account purchases now, so a run is only about placing
	# towers: walk the wish list and build the first affordable choice.
	for offset in WISH.size():
		var want: String = WISH[(mix_index + offset) % WISH.size()]
		if game.gold < game.tower_cost(want):
			continue
		var spot: Vector2i = _support_spot() if want == "command" else _find_spot(want)
		if spot.x < 0 or spot.x == -99:
			continue
		game.placing = want
		game._try_place(spot)
		game.placing = ""
		mix_index += offset + 1
		return


## Support towers are worth nothing on their own, so drop them where they
## cover the most existing towers.
func _support_spot() -> Vector2i:
	var best := Vector2i(-99, -99)
	var best_score := 0
	var radius: float = float(TDData.TOWERS["command"]["range"])
	for y in TDData.ROWS:
		for x in TDData.COLS:
			var c := Vector2i(x, y)
			if not game.can_place(c, "command"):
				continue
			var here: Vector2 = game.cell_center(c)
			var score := 0
			for t in game.occupied.values():
				if not t.is_support() and here.distance_to(t.position) <= radius:
					score += 1
			if score > best_score:
				best_score = score
				best = c
	return best if best_score >= 3 else Vector2i(-99, -99)


## Prefers empty cells that touch the path, like a human would.
func _find_spot(type_id: String) -> Vector2i:
	var best := Vector2i(-99, -99)
	var candidates: Array = []
	for y in TDData.ROWS:
		for x in TDData.COLS:
			var c := Vector2i(x, y)
			if not game.can_place(c, type_id):
				continue
			var touches := false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if game.is_path(c + o):
					touches = true
					break
			if touches:
				candidates.append(c)
	if candidates.is_empty():
		# Water and air towers may have no path-adjacent cell free; take any.
		for y in TDData.ROWS:
			for x in TDData.COLS:
				if game.can_place(Vector2i(x, y), type_id):
					candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return best
	return candidates[randi() % candidates.size()]
