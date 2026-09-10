extends Node

## Keeps the game from working harder than it needs to.
##
## Nothing here changes what is on screen. It caps how often the frame is
## rebuilt, and drops that to a trickle while the window is in the
## background — a tower defence left open on a laptop should not keep a core
## busy and the fan spinning.

## Frame rates the options screen offers. 0 means "as fast as the display
## allows", which is what the game used to do unasked.
const CAPS: Array = [30, 60, 120, 0]
const DEFAULT_CAP := 60
## What the game runs at with the window in the background. Low enough to
## idle the CPU, high enough that music and timers stay smooth.
const BACKGROUND_FPS := 10

var focused: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_cap()


## The player's chosen cap, or the default before an account is loaded.
func cap() -> int:
	if Progress.loaded or not Progress.read_only:
		return int(Progress.frame_cap())
	return DEFAULT_CAP


func apply_cap() -> void:
	Engine.max_fps = BACKGROUND_FPS if not focused else cap()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			focused = false
			apply_cap()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			focused = true
			apply_cap()
