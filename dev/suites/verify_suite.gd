class_name VerifySuite
extends Node

## One area of the verify suite. The runner builds the match, hands it to
## each suite in turn and collects the results, so a suite only has to say
## what it checks — and a failure names the file it came from.

var game: Node = null
var runner: Node = null


## Records one assertion. Everything funnels through the runner so the
## count, the printing and the exit status stay in one place.
func check(name: String, cond: bool) -> void:
	runner.check(name, cond)


## What this suite is called in the output.
func suite_name() -> String:
	return "suite"


## Runs every check in this suite.
func run() -> void:
	pass
