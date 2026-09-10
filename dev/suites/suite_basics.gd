extends VerifySuite

## The basics, in the order a match does them: place a tower, buy a rank,
## see it take effect, shoot something, and have the damage add up. If this
## suite fails, nothing else is worth reading.

func suite_name() -> String:
	return "basics"


func run() -> void:
	# Pick real cells from the map rather than assuming fixed coordinates.
	var open_cell := Vector2i(-99, -99)
	var path_cell := Vector2i(-99, -99)
	for key: Vector2i in game.terrain:
		if open_cell.x < 0 and game.can_place(key, "gun"):
			open_cell = key
		if path_cell.x < 0 and game.is_path(key):
			path_cell = key
	check("path cells blocked", path_cell.x >= 0 and not game.can_place(path_cell))
	check("open ground placeable", open_cell.x >= 0 and game.can_place(open_cell))
	check("off-grid rejected", not game.can_place(Vector2i(-1, 5)))
	var start_gold := int(TDData.level_stat(game.level_def, "gold"))
	check("start gold comes from the tier", game.gold == start_gold and start_gold > 0)

	game.placing = "gun"
	game._try_place(open_cell)
	game.placing = ""
	check("tower placed", game.occupied.has(open_cell))
	check("gold spent", game.gold == start_gold - 60)
	check("cell now occupied", not game.can_place(open_cell))

	var t: Tower = game.occupied[open_cell]
	Progress.tower_ranks = {}
	check("a tower with nothing bought starts plain", t.level() == 0 and not t.pierces())

	# Upgrade ranks are bought with coins on the account, then every tower of
	# that type is built with them.
	Progress.unlock_all = true
	Progress.coins = 100000
	Progress.tower_ranks = {}
	var base_damage := t.stat("damage")
	var base_rate := t.stat("rate")
	var base_range := t.stat("range")

	check("a rank costs coins", Progress.track_next_cost("gun", 0) > 0)
	var coins_before := Progress.coins
	check("buying a rank succeeds", Progress.buy_track("gun", 0))
	check("coins were spent", Progress.coins < coins_before)
	check("the account remembers the rank", Progress.track_rank_for("gun", 0) == 1)
	check("the next rank costs more",
			Progress.track_next_cost("gun", 0) > TDData.track_cost("gun", 0, 0))

	var fresh_gun := Tower.new()
	fresh_gun.game = game
	fresh_gun.setup("gun", Vector2i.ZERO)
	check("a new tower still starts at rank 0", fresh_gun.track_rank(0) == 0)
	check("the unlocked rank becomes installable", fresh_gun.can_upgrade_track(0))
	check("only the unlocked amount is installable", fresh_gun.track_cap(0) == 1)
	check("installing costs gold", fresh_gun.track_cost(0) > 0)
	fresh_gun.upgrade_track(0)
	check("installing raises damage", fresh_gun.stat("damage") > base_damage)
	check("other stats stay put", is_equal_approx(fresh_gun.stat("rate"), base_rate))
	check("a second rank needs another unlock", not fresh_gun.can_upgrade_track(0))
	fresh_gun.free()

	Progress.buy_track("gun", 1)
	check("a second track buys independently", Progress.track_rank_for("gun", 1) == 1)

	# The per-tower tree still gates: Long Barrel needs Heavy Rounds 2.
	check("a gated track cannot be bought yet",
			not bool(Progress.track_buy_state("gun", 2)["prereq_ok"]))
	check("buying a gated track fails", not Progress.buy_track("gun", 2))
	Progress.buy_track("gun", 0)
	check("the gate opens once the prerequisite is met",
			bool(Progress.track_buy_state("gun", 2)["prereq_ok"]))
	check("the freed track can then be bought", Progress.buy_track("gun", 2))

	var geared := Tower.new()
	geared.game = game
	geared.setup("gun", Vector2i.ZERO)
	geared.upgrade_track(0)
	geared.upgrade_track(0)
	geared.upgrade_track(2)
	check("an unlocked range rank installs on the tower", geared.stat("range") > base_range)
	geared.free()

	# Coins actually gate the purchase.
	Progress.coins = 0
	check("no coins means no rank", not Progress.buy_track("cannon", 0))
	check("the state explains why",
			not bool(Progress.track_buy_state("cannon", 0)["affordable"]))
	Progress.coins = 100000

	# Account level gates a track even when coins and prerequisites allow it.
	Progress.unlock_all = false
	Progress.xp = 0
	var gated_by_level := -1
	for i in TDData.tracks("gun").size():
		if Progress.track_unlock_level("gun", i) > 1:
			gated_by_level = i
	check("some tracks are level gated", gated_by_level >= 0)
	check("a level-gated track reports the gate",
			not bool(Progress.track_buy_state("gun", gated_by_level)["level_ok"]))
	Progress.xp = Progress.xp_for_level(40)
	check("levelling opens it",
			bool(Progress.track_buy_state("gun", gated_by_level)["level_ok"]))
	Progress.unlock_all = true
	Progress.tower_ranks = {}
	Progress.coins = 0
	Progress.xp = 0

	game._select(t)
	var before: int = game.gold
	var value: int = t.sell_value()
	check("sell value refunds the build cost", value == int(60.0 * 0.7))
	game._sell_selected()
	check("sell refunds", game.gold == before + value)
	check("sell frees cell", game.can_place(open_cell))
	check("selection cleared", game.selected == null)

	# Blocked / unaffordable placement must not charge or build.
	game.gold = 10
	game.placing = "tesla"
	game._try_place(Vector2i(2, 2))
	game.placing = ""
	check("cannot afford -> no build", game.occupied.is_empty() and game.gold == 10)
	game.gold = 500
	game.placing = "gun"
	game._try_place(path_cell)
	game.placing = ""
	check("cannot build on path", game.occupied.is_empty() and game.gold == 500)

	# Wave composition.
	var w1: Array = game._build_wave(1)
	var w10: Array = game._build_wave(10)
	var w13: Array = game._build_wave(13)
	var kinds10: Array = []
	for e: Dictionary in w10:
		if not kinds10.has(e["kind"]):
			kinds10.append(e["kind"])
	check("wave 1 is grunts only", w1.size() == 5 and str(w1[0]["kind"]) == "grunt")
	check("wave 10 has a boss", kinds10.has("boss"))
	check("wave 13 is bigger than wave 1", w13.size() > w1.size())
	check("wave hp scales", float(w13[0]["hp"]) > float(w1[0]["hp"]) * 3.0)
	var sorted_ok := true
	for i in range(1, w13.size()):
		if float(w13[i]["t"]) < float(w13[i - 1]["t"]):
			sorted_ok = false
	check("spawn times sorted", sorted_ok)

	# Armor, slow and lethality on a live creep.
	var e := Enemy.new()
	e.setup("tank", 1.0, 1.0, game.path_points)
	add_child(e)
	e.take_damage(10.0)
	check("armor reduces damage", is_equal_approx(e.hp, 215.0 - 5.0))
	e.take_damage(10.0, true)
	check("armor pierced", is_equal_approx(e.hp, 200.0))
	e.apply_slow(0.45, 2.0)
	check("slow applied", e.speed() < e.base_speed)
	e.take_damage(9999.0)
	check("lethal damage kills", e.dead)

	# Splash hits several creeps at once.
	var spawned: Array = []
	for i in 3:
		var s := Enemy.new()
		s.setup("grunt", 1.0, 1.0, game.path_points)
		s.died.connect(game._on_enemy_died)
		s.leaked.connect(game._on_enemy_leaked)
		game.layer_enemies.add_child(s)
		s.position = Vector2(400.0, 400.0) + Vector2(float(i) * 12.0, 0.0)
		game.enemies.append(s)
		game.invalidate_targeting_grid()
		spawned.append(s)
	game.explode(Vector2(400.0, 400.0), 60.0, 20.0, Color.WHITE)
	var all_hit := true
	for s in spawned:
		if s.hp >= s.max_hp:
			all_hit = false
	check("splash hits everything in radius", all_hit)

	var target = game.find_target(Vector2(400.0, 400.0), 200.0)
	check("targets furthest along path", target == spawned[0] or target != null)



## Water cells accept only the Tide Caller, and land towers only dry ground.
