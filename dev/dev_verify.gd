extends Node

## The verify suite's runner.
##
## The checks themselves live in `dev/suites/`, one script per area of the
## game, because a single file of three and a half thousand assertions is
## a file nobody can find anything in. This builds one match, hands it to
## each suite in turn, and reports.
##
##   godot --headless --quit-after 900 dev/dev_verify.tscn
##
## A suite is a `VerifySuite`: it gets `game` and a `check()` that funnels
## back here, so the count, the printing and the exit status stay in one
## place and a failure says which suite it came from.

const SUITES: Array = [
	"res://dev/suites/suite_basics.gd",
	"res://dev/suites/suite_towers.gd",
	"res://dev/suites/suite_combat.gd",
	"res://dev/suites/suite_maps.gd",
	"res://dev/suites/suite_waves.gd",
	"res://dev/suites/suite_account.gd",
]

var game: Node
var fails: int = 0
var current: String = ""
var counts: Dictionary = {}


func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	counts[current] = int(counts.get(current, 0)) + 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])


func _ready() -> void:
	# Isolated account: full unlocks, no tech, and nothing written to disk.
	Progress.use_clean_state()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	for path: String in SUITES:
		var suite: VerifySuite = load(path).new()
		suite.game = game
		suite.runner = self
		add_child(suite)
		current = suite.suite_name()
		var before := fails
		await suite.run()
		if fails > before:
			print("       ^ %d failure(s) in %s (%s)"
					% [fails - before, current, path.get_file()])

	var totals: Array = []
	for name: String in counts:
		totals.append("%s %d" % [name, int(counts[name])])
	print("[VERIFY] " + "  |  ".join(totals))
	print("[VERIFY] %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	get_tree().quit()
