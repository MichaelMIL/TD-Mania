class_name Art
extends RefCounted

## Optional sprite layer.
##
## Everything in TD Mania draws itself with vector primitives, but if a PNG
## with the matching name exists in res://assets/ it is used instead. Images
## are loaded straight off disk (not through the import pipeline) so dropping
## new files in the folder works without reopening the editor.

const DIR := "res://assets/"

static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var result: Texture2D = null
	for ext: String in [".png", ".webp", ".jpg"]:
		var path := DIR + name + ext
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				result = ImageTexture.create_from_image(img)
				break
	_cache[name] = result
	return result


## Draw a sprite centred on `pos`, scaled so its longest side is `size`
## pixels. Returns false when no such sprite exists, so callers can fall
## back to their vector drawing.
static func draw_centered(ci: CanvasItem, name: String, pos: Vector2, size: float,
		angle: float = 0.0, modulate: Color = Color.WHITE) -> bool:
	var t := tex(name)
	if t == null:
		return false
	var src := Vector2(t.get_width(), t.get_height())
	var scale := size / maxf(src.x, src.y)
	var dest := src * scale
	if is_zero_approx(angle):
		ci.draw_texture_rect(t, Rect2(pos - dest * 0.5, dest), false, modulate)
	else:
		ci.draw_set_transform(pos, angle, Vector2.ONE)
		ci.draw_texture_rect(t, Rect2(-dest * 0.5, dest), false, modulate)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
