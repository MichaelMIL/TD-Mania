class_name Projectile
extends Node2D

## Homing shot. Keeps chasing its target's live position, but remembers the
## last known point so splash weapons still detonate if the target dies.

var game: Node = null
var source: Node = null
## Whether the tower that fired this can reach flyers; its splash inherits
## the same limit, so a mortar's blast cannot swat something overhead.
var hits_air: bool = true
var target: Enemy = null
var dest: Vector2 = Vector2.ZERO
var damage: float = 10.0
var speed: float = 500.0
var splash: float = 0.0
var slow: float = 0.0
var slow_dur: float = 0.0
var pierce_armor: bool = false
var shatter: float = 1.0
var cluster: int = 0
var pierce_count: int = 0
var burn: float = 0.0
var knockback: float = 0.0
var max_travel: float = 900.0
var travelled: float = 0.0
var hit: Array = []
var color: Color = Color.WHITE
var radius: float = 4.0
var life: float = 3.0
var trail: PackedVector2Array = PackedVector2Array()


func _process(delta: float) -> void:
	# A sold tower must not take its shots' credit — or crash them. Freed
	# objects compare equal to null, so check validity rather than nullity.
	if not is_instance_valid(source):
		source = null
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if pierce_count > 0:
		_process_piercing(delta)
		return
	if is_instance_valid(target) and not target.dead:
		dest = target.position
	var to_dest := dest - position
	var step := speed * delta
	trail.append(position)
	if trail.size() > 6:
		trail.remove_at(0)
	if to_dest.length() <= step or to_dest.length() < 1.0:
		position = dest
		_impact()
		return
	position += to_dest.normalized() * step
	rotation = to_dest.angle()
	queue_redraw()


## Piercing shots fly a straight line, damaging each enemy they pass through
## once, and stop after `pierce_count` hits or when they run out of range.
func _process_piercing(delta: float) -> void:
	if travelled <= 0.0:
		rotation = (dest - position).angle() if dest != position else rotation
	var step := speed * delta
	var motion := Vector2.RIGHT.rotated(rotation) * step
	trail.append(position)
	if trail.size() > 6:
		trail.remove_at(0)
	position += motion
	travelled += step
	queue_redraw()

	# Only creeps near the segment just flown can be struck by it.
	for e: Enemy in game.enemies_near(position - motion * 0.5, motion.length() * 0.5 + radius):
		if hit.has(e) or (e.flying and not hits_air):
			continue
		# Segment/circle test so fast shots cannot tunnel past a creep.
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				e.position, position - motion, position)
		if closest.distance_to(e.position) > e.radius + radius:
			continue
		hit.append(e)
		var dmg := damage
		if shatter > 1.0 and e.slow_timer > 0.0:
			dmg *= shatter
		e.take_damage(dmg, pierce_armor, source)
		if slow > 0.0 and is_instance_valid(e) and not e.dead:
			e.apply_slow(slow, slow_dur)
		if burn > 0.0 and is_instance_valid(e) and not e.dead:
			e.apply_burn(burn, 2.5, source)
		game.fx_spark(closest, color)
		if hit.size() >= pierce_count:
			queue_free()
			return
	if travelled >= max_travel:
		queue_free()


func _impact() -> void:
	if splash > 0.0:
		game.explode(position, splash, damage, color, slow, slow_dur, pierce_armor, shatter,
				source, knockback, hits_air)
		# Cluster munitions scatter smaller secondary blasts around the impact.
		for i in cluster:
			var offset := Vector2.RIGHT.rotated(TAU * float(i) / float(cluster)) \
					* splash * 0.75
			game.explode(position + offset, splash * 0.55, damage * 0.4, color,
					slow, slow_dur, pierce_armor, shatter, source, 0.0, hits_air)
	elif is_instance_valid(target) and not target.dead:
		var dmg := damage
		if shatter > 1.0 and target.slow_timer > 0.0:
			dmg *= shatter
		target.take_damage(dmg, pierce_armor, source)
		if slow > 0.0:
			target.apply_slow(slow, slow_dur)
		if burn > 0.0 and is_instance_valid(target) and not target.dead:
			target.apply_burn(burn, 2.5, source)
		game.fx_spark(position, color)
	else:
		game.fx_spark(position, color)
	queue_free()


func _draw() -> void:
	for i in trail.size():
		var alpha := float(i + 1) / float(trail.size()) * 0.35
		draw_circle(to_local(trail[i]), radius * 0.7, Color(color.r, color.g, color.b, alpha))
	if not Art.draw_centered(self, "shot", Vector2.ZERO, radius * 3.0):
		draw_circle(Vector2.ZERO, radius + 1.5, Color(color.r, color.g, color.b, 0.35))
		draw_circle(Vector2.ZERO, radius, color.lightened(0.25))
