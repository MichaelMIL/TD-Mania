extends Control

## Every upgrade's picture on one screen: the drawn symbol, or the PNG from
## assets/ once it exists. For checking a batch of generated icons at a
## glance, or the symbols when one is added.
##
##   SHOT_PATH=/tmp/icons.png godot --resolution 1520x902 --quit-after 600 dev/dev_icons.tscn
##   godot --resolution 1520x902 dev/dev_icons.tscn     # to look at it live


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("0b1119")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(12.0, 12.0)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	for type_id: String in TDData.TOWER_ORDER:
		var list: Array = TDData.tracks(type_id)
		for i in list.size():
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(140.0, 0.0)
			var icon := UpgradeIcon.new()
			icon.custom_minimum_size = Vector2(64.0, 64.0)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.show_track(type_id, i)
			cell.add_child(icon)
			var name := Label.new()
			name.text = "%s\n%s" % [TDData.TOWERS[type_id]["short"], list[i]["name"]]
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name.add_theme_font_size_override("font_size", 11)
			cell.add_child(name)
			grid.add_child(cell)
	var path := OS.get_environment("SHOT_PATH")
	if path != "":
		await get_tree().create_timer(0.5).timeout
		RenderingServer.frame_post_draw.connect(func():
			get_viewport().get_texture().get_image().save_png(path)
			print("[ICONS] saved %s" % path)
			get_tree().quit(), CONNECT_ONE_SHOT)
