extends Node

## Keeps the game from working harder than it needs to, and fits it to the
## screen it is on.
##
## It caps how often the frame is rebuilt, and drops that to a trickle while
## the window is in the background — a tower defence left open on a laptop
## should not keep a core busy and the fan spinning. On a phone it also
## scales each screen for the glass and keeps it clear of the notch and the
## rounded corners, and it sets the look every button in the game shares.

## Frame rates the options screen offers. 0 means "as fast as the display
## allows", which is what the game used to do unasked.
const CAPS: Array = [30, 60, 120, 0]
const DEFAULT_CAP := 60
## What the game runs at with the window in the background. Low enough to
## idle the CPU, high enough that music and timers stay smooth.
const BACKGROUND_FPS := 10

var focused: bool = true
## Text scale asked for on the command line ("-- --phone" or "--phone=2.2"),
## so the handheld layout can be looked at in a desktop window. Negative
## means it was not asked for.
var phone_arg: float = -1.0
## The scene whose scale was applied last, and the path it was scaled as.
var scaled_scene: Node = null
var scaled_path: String = ""
## The menu screen kept clear of the notch, refitted when the window changes.
var fitted: Control = null
## A safe area asked for on the command line ("-- --safe=66,0,66,29", in
## window pixels: left, top, right, bottom), so the notch can be looked at
## in a desktop window. Negative means it was not asked for.
var safe_arg: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)


## Whether the player is most likely using a finger. Decides wording and
## which options are offered; the game itself handles touch and mouse alike.
func touchscreen() -> bool:
	return DisplayServer.is_touchscreen_available()


## The Android back button (and a swipe back) arrives as a window request,
## not a key. It is replayed as the "cancel" key so every screen's Escape
## handling — close the panel, put the tower away, pause, go back — serves
## it without knowing. Nothing on desktop sends this.
func _go_back() -> void:
	var keycode := Progress.key_for("cancel")
	if keycode == KEY_NONE:
		return
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--phone":
			phone_arg = 2.0
		elif arg.begins_with("--phone="):
			phone_arg = float(arg.get_slice("=", 1))
		elif arg.begins_with("--safe="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 4:
				safe_arg = Vector4(float(parts[0]), float(parts[1]), float(parts[2]),
						float(parts[3]))
	_style_buttons()
	# A scene is scaled the moment it enters the tree, before its _ready
	# lays anything out, so nothing is ever measured at the wrong scale.
	get_tree().node_added.connect(_on_node_added)
	get_window().size_changed.connect(_refit)
	apply_cap()


## The part of the screen nothing covers — no notch, no rounded corner, no
## home bar — as insets from each edge in window pixels: left, top, right,
## bottom. Zero on a desktop.
func safe_inset_px() -> Vector4:
	if safe_arg.x >= 0.0:
		return safe_arg
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := get_window()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	return Vector4(maxf(0.0, safe.position.x), maxf(0.0, safe.position.y),
			maxf(0.0, win.size.x - safe.end.x), maxf(0.0, win.size.y - safe.end.y))


## The same insets in the units the current screen is laid out in.
func safe_margins() -> Vector4:
	var px_per_unit := get_window().get_final_transform().get_scale().x
	return safe_inset_px() / maxf(0.001, px_per_unit)


## Phones and tablets: the HUD uses the handheld layout, where the map is
## scaled to fit and the palette and tower info share a column beside it.
## Try it on a desktop with: godot --resolution 1952x902 -- --phone
func handheld() -> bool:
	return OS.has_feature("mobile") or phone_arg >= 0.0


## How much bigger than the desktop design the handheld text is drawn.
## Picked from the glass: a 12 px label should come out about 2.2 mm tall,
## which is a comfortable body size on a phone and barely changes a tablet.
func ui_scale() -> float:
	if phone_arg > 0.0:
		return phone_arg
	if not handheld():
		return 1.0
	var win := get_window()
	var base := Vector2(win.content_scale_size)
	# Physical pixels per design pixel, as the stretch mode will scale it.
	var scale := minf(win.size.x / base.x, win.size.y / base.y)
	var dpi := float(DisplayServer.screen_get_dpi())
	return clampf(dpi * 0.085 / (12.0 * scale), 1.0, 2.6)


## How much a whole scene is blown up on a handheld. The match lays itself
## out (see hud.gd) and gets 1.0; the menus were drawn for a desktop window
## and are simply scaled, as far as their widest screen still fits.
func scene_scale(scene_path: String) -> float:
	# The harnesses in dev/ host a match too.
	if not handheld() or scene_path == "res://game.tscn" or scene_path.begins_with("res://dev/"):
		return 1.0
	var k := clampf(ui_scale() * 0.6, 1.0, 1.4)
	if scene_path == "res://menu.tscn" or scene_path == "res://challenges.tscn":
		# The level select is as wide as the design; blow it up only as far
		# as the safe part of the screen's width allows.
		var win := get_window()
		var base := Vector2(win.content_scale_size)
		var stretch := minf(win.size.x / base.x, win.size.y / base.y)
		var inset := safe_inset_px()
		var usable_w := (win.size.x - inset.x - inset.z) / stretch
		k = minf(k, usable_w / base.x)
	return maxf(1.0, k)


func _on_node_added(node: Node) -> void:
	# Only a scene's own root: autoloads are scripts, everything else is
	# deeper in the tree.
	if node.get_parent() != get_tree().root or not node.scene_file_path.ends_with(".tscn"):
		return
	frame(node, node.get_meta("scene_scale_path", node.scene_file_path))


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# A harness that shows a menu says which one with this meta, which it
	# can only set once it is already in the tree.
	var path: String = scene.get_meta("scene_scale_path", scene.scene_file_path)
	if scene != scaled_scene or path != scaled_path:
		frame(scene, path)


## Scales a screen for this device and, if it is a Control filling the
## window, keeps it inside the safe area.
func frame(scene: Node, path: String) -> void:
	scaled_scene = scene
	scaled_path = path
	get_window().content_scale_factor = scene_scale(path)
	fitted = scene as Control
	_refit()


## Insets a full-window Control by the safe area. A harness that hosts a
## menu inside itself calls this on the menu.
func fit_safe(c: Control) -> void:
	fitted = c
	_refit()


func _refit() -> void:
	if fitted == null or not is_instance_valid(fitted) or not fitted.is_inside_tree():
		return
	var m := safe_margins()
	fitted.offset_left = m.x
	fitted.offset_top = m.y
	fitted.offset_right = -m.z
	fitted.offset_bottom = -m.w


## One look for every button in the game, set on the engine's default theme
## so it reaches controls under a CanvasLayer too (a theme on the window
## stops at the first node that is not a Control). The engine's own buttons
## are dark grey on dark grey with a half-transparent label when disabled,
## which on a phone in daylight reads as nothing at all.
func _style_buttons() -> void:
	var theme := ThemeDB.get_default_theme()
	var box := func(bg: Color, border: Color, width: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		return sb
	theme.set_stylebox("normal", "Button", box.call(Color("1f2c3d"), Color("44607f"), 1))
	theme.set_stylebox("hover", "Button", box.call(Color("283a51"), Color("6a8db3"), 1))
	theme.set_stylebox("pressed", "Button", box.call(Color("173a55"), Color("4fc3f7"), 2))
	theme.set_stylebox("hover_pressed", "Button", box.call(Color("1b4262"), Color("4fc3f7"), 2))
	theme.set_stylebox("disabled", "Button", box.call(Color("141c27"), Color("2a394d"), 1))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color("e8f1fb"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color("e8f1fb"))
	theme.set_color("font_disabled_color", "Button", Color(0.68, 0.74, 0.81, 0.8))


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
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_go_back()
