class_name Cheats
extends RefCounted

## Developer toggles the match consults.
##
## The on-screen cheat panel that used to drive these is gone: it was a
## developer tool sitting one keypress away from every player, and on a
## touch build there is no F1 to press anyway. What remains is the handful
## of flags the harnesses in `dev/` set directly to put the game into a
## state worth measuring — a full board, free building, an invulnerable
## base — plus the debug gate the balance editor still hangs off.
##
## A run that has had one of these set is flagged by `game.cheats_used`, and
## a flagged run sets no records and banks no XP or coins.

## No lives are ever lost.
static var god_mode: bool = false
## Towers cost nothing to build.
static var free_build: bool = false
## Every tower placed comes out of the box with every rank installed.
static var max_towers: bool = false


## True in a debug build, or with --cheats on an exported one. The balance
## editor (F2, `scripts/tuning_panel.gd`) uses this as its gate.
static func available() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_args().has("--cheats")


static func reset_toggles() -> void:
	god_mode = false
	free_build = false
	max_towers = false
