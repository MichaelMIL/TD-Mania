extends Node

## Screenshots any full-screen scene, for looking at menus and panels:
##
##   SCREEN_SCENE=res://options.tscn SHOT_PATH=/tmp/o.png \
##       godot --quit-after 600 dev/dev_screen_shot.tscn


func _ready() -> void:
	Progress.use_clean_state()
	var path := OS.get_environment("SCREEN_SCENE")
	if path == "":
		path = "res://menu.tscn"
	add_child(load(path).instantiate())
	await get_tree().create_timer(0.6).timeout
	RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)


func _grab() -> void:
	var out := OS.get_environment("SHOT_PATH")
	if out == "":
		out = "user://screen.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("[SHOT] saved %s" % out)
	get_tree().quit()
