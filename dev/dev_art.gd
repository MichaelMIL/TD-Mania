extends Node

## Which sprites are in and which are still drawn by hand.
##
##   godot --headless --quit-after 100 dev/dev_art.tscn
##
## `scripts/art.gd` uses a PNG whenever one exists and falls back to the
## vector drawing when it does not, so the game works at any point along
## the way. This says where along the way it is, which is the thing you
## want to know while feeding prompts through an image model.


func _ready() -> void:
	var wanted: Array = []
	for tile: String in ["tile_grass", "tile_path", "tile_water", "tile_rock"]:
		wanted.append(tile)
	for type_id: String in TDData.TOWERS:
		wanted.append("tower_%s_base" % type_id)
		wanted.append("tower_%s_gun" % type_id)
	for kind: String in TDData.ENEMIES:
		wanted.append("enemy_%s" % kind)
	for unit: String in ["unit_plane", "unit_heli", "shot"]:
		wanted.append(unit)

	var have: Array = []
	var missing: Array = []
	for name: String in wanted:
		if Art.tex(name) != null:
			have.append(name)
		else:
			missing.append(name)

	# Per-level tile variants are optional extras on top.
	var variants: Array = []
	for level: Dictionary in TDData.LEVELS:
		for tile: String in ["tile_grass", "tile_path", "tile_water", "tile_rock"]:
			var name := "%s_%s" % [tile, level["id"]]
			if Art.tex(name) != null:
				variants.append(name)

	print("[ART] %d of %d sprites in place (%.0f%%), plus %d per-level variants"
			% [have.size(), wanted.size(),
			100.0 * float(have.size()) / float(maxi(1, wanted.size())),
			variants.size()])
	if missing.is_empty():
		print("[ART] every sprite the game looks for exists. Nothing is drawn by hand any more.")
	else:
		print("[ART] still drawn by hand (prompts for these are in assets/PROMPTS.md):")
		var line: PackedStringArray = PackedStringArray()
		for name: String in missing:
			line.append(name)
			if line.size() == 4:
				print("        " + "  ".join(line))
				line = PackedStringArray()
		if line.size() > 0:
			print("        " + "  ".join(line))
	get_tree().quit()
