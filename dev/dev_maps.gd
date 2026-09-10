extends Node

## Measures every map: how much road it has, how many cells can shoot at
## that road, and how its lanes compare. Used when adding maps, because the
## difficulty ladder is defined by these two numbers.
##
##   godot --headless --quit-after 400 dev/dev_maps.tscn


func _ready() -> void:
	Progress.use_clean_state()
	await get_tree().process_frame
	var by_tier: Dictionary = {}
	print("[MAPS] %-14s %-11s %-7s %5s %6s  %s" % ["id", "area", "tier",
			"road", "spots", "lanes"])
	for i in TDData.LEVELS.size():
		TDData.selected_level = i
		var probe: Node = load("res://game.tscn").instantiate()
		add_child(probe)
		var road := 0
		var spots := 0
		for key: Vector2i in probe.terrain:
			if probe.terrain_at(key) == TDData.Terrain.PATH:
				road += 1
				continue
			if probe.terrain_at(key) != TDData.Terrain.GROUND:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
					Vector2i(0, -1)]:
				if probe.is_path(key + o):
					spots += 1
					break
		var level: Dictionary = TDData.LEVELS[i]
		var tier := int(level["tier"])
		var lanes: int = probe.routes.size()
		print("[MAPS] %-14s %-11s %-7s %5d %6d  %d" % [level["id"], level["area"],
				TDData.TIERS[tier]["name"], road, spots, lanes])
		if lanes == 1:
			if not by_tier.has(tier):
				by_tier[tier] = {"road": [], "spots": []}
			by_tier[tier]["road"].append(road)
			by_tier[tier]["spots"].append(spots)
		remove_child(probe)
		probe.queue_free()
	TDData.selected_level = 0
	for tier in TDData.TIERS.size():
		if not by_tier.has(tier):
			continue
		print("[BAND] %-7s road %d-%d  spots %d-%d  (%d maps)"
				% [TDData.TIERS[tier]["name"], by_tier[tier]["road"].min(),
				by_tier[tier]["road"].max(), by_tier[tier]["spots"].min(),
				by_tier[tier]["spots"].max(), by_tier[tier]["road"].size()])
	get_tree().quit()
