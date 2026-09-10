class_name Aircraft
extends Node2D

## A bomber or gunship launched by an air tower.
##
## Bombers fly to the leading creep, release their payload as splash blasts,
## then turn for home. Gunships fly out, hover over the fight and strafe until
## the ammo runs out. Either way the aircraft returns to its pad and frees
## itself, which releases the tower's squadron slot.

enum State { OUTBOUND, ATTACK, RETURN }

## Seconds before an aircraft gives up and lands regardless of what it is doing.
const MAX_SORTIE := 30.0

var game: Node = null
var tower: Node = null
var kind: String = "plane"
var color: Color = Color.WHITE
var speed: float = 260.0
var damage: float = 40.0
var splash: float = 60.0
var shots: int = 1
var pierce_armor: bool = false
var op_range: float = 320.0
var target_mode: int = 0
var pad: Vector2 = Vector2.ZERO
var target: Enemy = null

var state: int = State.OUTBOUND
var heading: float = 0.0
var rotor: float = 0.0
var shots_left: int = 1
var fire_timer: float = 0.0
var bombs_left: int = 0
var bomb_timer: float = 0.0
var hover_timer: float = 0.0
var sortie_time: float = 0.0


func _ready() -> void:
	shots_left = shots
	bombs_left = shots
	heading = (pad.direction_to(target.position) if is_instance_valid(target)
			else Vector2.RIGHT).angle()
	rotation = heading


func _process(delta: float) -> void:
	if not is_instance_valid(tower):
		# Pad sold mid-sortie: finish the flight, credit nobody.
		tower = null
	rotor += delta * 34.0
	sortie_time += delta
	# A sortie can never outstay its welcome: an aircraft that somehow cannot
	# reach its target or its pad still lands, freeing the squadron slot.
	if sortie_time > MAX_SORTIE:
		_land()
		return
	match state:
		State.OUTBOUND:
			_outbound(delta)
		State.ATTACK:
			_attack(delta)
		State.RETURN:
			_return(delta)
	queue_redraw()


func _reacquire() -> void:
	# Drop dead prey, and prey that has walked out of the tower's radius, so
	# aircraft never chase a creep across the whole map.
	if is_instance_valid(target) and not target.dead \
			and pad.distance_to(target.position) > op_range * 1.25:
		target = null
	if not is_instance_valid(target) or target.dead:
		target = game.find_target(pad, op_range, 0.0, target_mode)


## A crosswind on some maps: aircraft are pushed sideways as they fly, so
## a bombing run drifts off the road unless the pad sits close to it.
func _drift(delta: float) -> Vector2:
	if game == null or not is_instance_valid(game):
		return Vector2.ZERO
	var push := float(game.hazard.get("air_drift", 0.0))
	if is_zero_approx(push):
		return Vector2.ZERO
	return Vector2(0.0, push) * delta


func _fly_to(point: Vector2, delta: float) -> float:
	var to_point := point - position
	var dist := to_point.length()
	var want := to_point.angle()
	# Aircraft bank into wide turns for looks, but a wide turn radius must
	# never stop them reaching a fixed point: closer than `direct_range` they
	# steer straight at it. Without this an aircraft whose turn circle is
	# bigger than the arrival threshold orbits its target forever.
	var turn := 3.2 if dist > speed * 0.5 else 14.0
	heading = lerp_angle(heading, want, minf(1.0, delta * turn))
	position += Vector2.RIGHT.rotated(heading) * speed * delta + _drift(delta)
	rotation = heading
	return dist


## Arrival slack has to cover one frame of travel, which grows with the game
## speed multiplier, or fast aircraft step straight over the threshold.
func _arrive_slack(delta: float) -> float:
	return maxf(20.0, speed * delta * 1.4)


func _outbound(delta: float) -> void:
	_reacquire()
	if target == null:
		state = State.RETURN
		return
	var dist := _fly_to(target.position, delta)
	if dist < _arrive_slack(delta) + 8.0:
		state = State.ATTACK
		hover_timer = 0.0
		bomb_timer = 0.0


func _attack(delta: float) -> void:
	if kind == "plane":
		_bomb_run(delta)
	else:
		_gun_run(delta)


## The bomber keeps flying straight and lays its bombs in a line beneath it.
func _bomb_run(delta: float) -> void:
	position += Vector2.RIGHT.rotated(heading) * speed * delta
	rotation = heading
	bomb_timer -= delta
	if bomb_timer <= 0.0 and bombs_left > 0:
		bombs_left -= 1
		bomb_timer = 0.16
		game.explode(position, splash, damage, color, 0.0, 0.0, pierce_armor, 1.0,
				tower if is_instance_valid(tower) else null)
	if bombs_left <= 0:
		state = State.RETURN


func _gun_run(delta: float) -> void:
	_reacquire()
	hover_timer += delta
	if target != null:
		# Hold station a little short of the target and keep the nose on it.
		var stand_off: Vector2 = target.position - Vector2.RIGHT.rotated(heading) * 46.0
		var to_point := stand_off - position
		heading = lerp_angle(heading, (target.position - position).angle(),
				minf(1.0, delta * 4.0))
		position += to_point.limit_length(speed * delta)
		rotation = heading
	fire_timer -= delta
	if fire_timer <= 0.0 and shots_left > 0 and target != null:
		shots_left -= 1
		fire_timer = 0.28
		var p := Projectile.new()
		p.game = game
		p.target = target
		p.dest = target.position
		p.damage = damage
		p.speed = 620.0
		p.pierce_armor = pierce_armor
		p.color = color
		p.source = tower if is_instance_valid(tower) else null
		p.radius = 2.6
		p.position = position + Vector2.RIGHT.rotated(heading) * 14.0
		game.layer_proj.add_child(p)
		game.fx_spark(p.position, color)
	if shots_left <= 0 or (target == null and hover_timer > 1.5):
		state = State.RETURN


func _return(delta: float) -> void:
	var dist := _fly_to(pad, delta)
	if dist < _arrive_slack(delta):
		_land()


func _land() -> void:
	if is_instance_valid(tower):
		tower.units.erase(self)
		tower.sorties_landed += 1
	queue_free()


func _draw() -> void:
	# Drawn in local space with the node already rotated to `heading`, so the
	# nose points along +X. The offset dark copy fakes altitude.
	var shadow := Vector2(9.0, 13.0).rotated(-rotation)
	if kind == "plane":
		if not Art.draw_centered(self, "unit_plane", Vector2.ZERO, 46.0):
			_plane_shape(shadow, Color(0, 0, 0, 0.28))
			_plane_shape(Vector2.ZERO, color)
	else:
		if not Art.draw_centered(self, "unit_heli", Vector2.ZERO, 44.0):
			_heli_shape(shadow, Color(0, 0, 0, 0.28), false)
			_heli_shape(Vector2.ZERO, color, true)


func _plane_shape(offset: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		offset + Vector2(19.0, 0.0), offset + Vector2(-6.0, 5.0),
		offset + Vector2(-13.0, 4.0), offset + Vector2(-13.0, -4.0),
		offset + Vector2(-6.0, -5.0)]), col)
	draw_colored_polygon(PackedVector2Array([
		offset + Vector2(4.0, 0.0), offset + Vector2(-6.0, 17.0),
		offset + Vector2(-11.0, 17.0), offset + Vector2(-3.0, 0.0)]), col.darkened(0.22))
	draw_colored_polygon(PackedVector2Array([
		offset + Vector2(4.0, 0.0), offset + Vector2(-6.0, -17.0),
		offset + Vector2(-11.0, -17.0), offset + Vector2(-3.0, 0.0)]), col.darkened(0.22))
	draw_line(offset + Vector2(-13.0, -7.0), offset + Vector2(-13.0, 7.0),
			col.darkened(0.35), 2.5)
	if col.a > 0.5:
		draw_circle(offset + Vector2(6.0, 0.0), 3.0, Color(0.85, 0.95, 1.0, 0.9))


func _heli_shape(offset: Vector2, col: Color, blades: bool) -> void:
	draw_colored_polygon(PackedVector2Array([
		offset + Vector2(15.0, 0.0), offset + Vector2(4.0, 6.0),
		offset + Vector2(-8.0, 4.0), offset + Vector2(-8.0, -4.0),
		offset + Vector2(4.0, -6.0)]), col)
	draw_rect(Rect2(offset + Vector2(-19.0, -1.5), Vector2(12.0, 3.0)), col.darkened(0.25))
	draw_line(offset + Vector2(-19.0, -5.0), offset + Vector2(-19.0, 5.0),
			col.darkened(0.35), 2.0)
	if col.a > 0.5:
		draw_circle(offset + Vector2(9.0, 0.0), 3.2, Color(0.85, 0.95, 1.0, 0.9))
	if blades:
		for i in 2:
			var ang := rotor + PI * float(i)
			draw_line(Vector2.RIGHT.rotated(ang) * -18.0, Vector2.RIGHT.rotated(ang) * 18.0,
					Color(1, 1, 1, 0.45), 2.0, true)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(1, 1, 1, 0.08), 1.0, true)
