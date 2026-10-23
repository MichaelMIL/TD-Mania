class_name TrackButton
extends Button

## One upgrade track as a button: the upgrade's picture on the left, its
## name over its rank and price on the right.
##
## The words live in labels of their own rather than in the button's text,
## for two reasons. A long name ("Second Bomber *") is trimmed with an
## ellipsis instead of widening the panel it sits in, which on a phone used
## to push the whole column off the edge of the screen. And the two lines
## can be coloured apart: the name stays readable while the price line says
## whether you can buy (green), cannot afford it (red), have maxed it (gold)
## or have not unlocked it (grey).

var picture: UpgradeIcon
var title: Label
var detail: Label


func _init(font_size: int, picture_size: float) -> void:
	text = ""
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = maxf(picture_size + 10.0, float(font_size) * 2.6 + 10.0)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = minf(8.0, picture_size * 0.2)
	row.offset_right = -4.0
	row.add_theme_constant_override("separation", int(clampf(picture_size * 0.18, 4.0, 14.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	picture = UpgradeIcon.new()
	picture.custom_minimum_size = Vector2(picture_size, picture_size)
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)

	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	title = _line(font_size)
	lines.add_child(title)
	detail = _line(int(round(float(font_size) * 0.92)))
	lines.add_child(detail)


func _line(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## What this button offers: which track (for the picture) and the two lines.
func show_track(type_id: String, track: int, name_line: String, detail_line: String) -> void:
	picture.show_track(type_id, track)
	if title.text != name_line:
		title.text = name_line
	if detail.text != detail_line:
		detail.text = detail_line


## Colours for a state; see GameHUD._style_track.
func paint(name_color: Color, detail_color: Color, picture_alpha: float) -> void:
	title.add_theme_color_override("font_color", name_color)
	detail.add_theme_color_override("font_color", detail_color)
	picture.modulate = Color(1, 1, 1, picture_alpha)
