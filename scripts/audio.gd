extends Node

## Procedurally synthesised audio.
##
## Every sound is baked once at startup into an AudioStreamWAV, so playback is
## cheap and the game still needs no asset files. Drop a real .wav into
## assets/audio/<name>.wav and it is used instead of the generated one.
##
## Autoloaded as `Audio`, so any script can call `Audio.play("shot_gun")`.

const RATE := 22050
const VOICES := 20
const ASSET_DIR := "res://assets/audio/"

var bank: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var recent: Dictionary = {}
var beam_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var beam_voices: int = 0
var sfx_volume: float = 0.8
var music_volume: float = 0.35
## Which pad is loaded, so switching areas is a change and staying is not.
var music_track: String = "music"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_bank()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	beam_player = AudioStreamPlayer.new()
	beam_player.stream = bank.get("beam")
	beam_player.volume_db = -60.0
	add_child(beam_player)
	music_player = AudioStreamPlayer.new()
	music_player.stream = bank.get("music")
	music_track = "music"
	add_child(music_player)
	_apply_volumes()


# ------------------------------------------------------------------ playback

## Plays a one-shot. `pitch_jitter` spreads repeated shots so a row of towers
## does not sound like one machine.
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if sfx_volume <= 0.001 or not bank.has(name):
		return
	# Rate limit: identical sounds within a few milliseconds just add mush.
	var now := Time.get_ticks_msec()
	if int(recent.get(name, -999)) + 35 > now:
		return
	recent[name] = now
	var p: AudioStreamPlayer = players[next_voice]
	next_voice = (next_voice + 1) % players.size()
	p.stream = bank[name]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db + linear_to_db(sfx_volume)
	p.play()


## Beams are continuous: towers report in each frame and the hum follows.
func beam_active(count: int) -> void:
	beam_voices = count


func _process(_delta: float) -> void:
	if beam_player == null:
		return
	var want: bool = beam_voices > 0 and sfx_volume > 0.001
	if want and not beam_player.playing:
		beam_player.play()
	elif not want and beam_player.playing:
		beam_player.stop()
	if want:
		var loudness: float = clampf(0.35 + 0.12 * float(beam_voices - 1), 0.0, 0.9)
		beam_player.volume_db = linear_to_db(loudness * sfx_volume) - 6.0
	beam_voices = 0


## `area` picks the pad; an unknown or empty one keeps the generic loop.
## Switching areas restarts the track, staying put does not.
func play_music(on: bool, area: String = "") -> void:
	if music_player == null:
		return
	var wanted: String = "music_" + area if bank.has("music_" + area) else "music"
	if wanted != music_track:
		music_track = wanted
		music_player.stream = bank.get(wanted)
		if music_player.playing:
			music_player.stop()
	if on and music_volume > 0.001:
		if not music_player.playing:
			music_player.play()
	elif music_player.playing:
		music_player.stop()


func set_volumes(sfx: float, music: float) -> void:
	sfx_volume = clampf(sfx, 0.0, 1.0)
	music_volume = clampf(music, 0.0, 1.0)
	_apply_volumes()
	play_music(music_volume > 0.001, music_track.trim_prefix("music_")
			if music_track != "music" else "")


func _apply_volumes() -> void:
	if music_player != null:
		music_player.volume_db = linear_to_db(maxf(0.0001, music_volume)) - 4.0


# ----------------------------------------------------------------- synthesis

func _build_bank() -> void:
	bank["shot_gun"] = _wav(_shot_gun())
	bank["shot_cannon"] = _wav(_shot_cannon())
	bank["shot_light"] = _wav(_shot_light())
	bank["explosion"] = _wav(_explosion())
	bank["death"] = _wav(_death())
	bank["leak"] = _wav(_leak())
	bank["build"] = _wav(_build())
	bank["upgrade"] = _wav(_upgrade())
	bank["sell"] = _wav(_sell())
	bank["wave_start"] = _wav(_wave_start())
	bank["wave_clear"] = _wav(_wave_clear())
	bank["game_over"] = _wav(_game_over())
	bank["boss"] = _wav(_boss())
	bank["click"] = _wav(_click())
	bank["beam"] = _wav(_beam(), true)
	bank["music"] = _wav(_music(), true)
	for area_id: String in AREA_MUSIC:
		bank["music_" + area_id] = _wav(_music(AREA_MUSIC[area_id]), true)
	# A real file always wins over the generated version.
	for name: String in bank.keys():
		var path := ASSET_DIR + name + ".wav"
		if FileAccess.file_exists(path):
			var loaded := ResourceLoader.load(path)
			if loaded is AudioStream:
				bank[name] = loaded


## Packs floating point samples (-1..1) into a 16-bit mono stream.
func _wav(samples: PackedFloat32Array, looping: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _len(seconds: float) -> int:
	return int(seconds * float(RATE))


## Attack/decay envelope, 0..1 across the sample.
func _env(i: int, count: int, attack: float, curve: float = 2.0) -> float:
	var t := float(i) / float(maxi(1, count - 1))
	if t < attack and attack > 0.0:
		return t / attack
	var fall := (t - attack) / maxf(0.0001, 1.0 - attack)
	return pow(1.0 - fall, curve)


func _sine(freq: float, i: int) -> float:
	return sin(TAU * freq * float(i) / float(RATE))


func _saw(freq: float, i: int) -> float:
	return fposmod(float(i) * freq / float(RATE), 1.0) * 2.0 - 1.0


func _square(freq: float, i: int) -> float:
	return 1.0 if fposmod(float(i) * freq / float(RATE), 1.0) < 0.5 else -1.0


## Sharp click plus a downward blip: a small calibre shot.
func _shot_gun() -> PackedFloat32Array:
	var n := _len(0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / float(n)
		var noise := randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.55)
		var body := _square(760.0 - 420.0 * t, i) * 0.35
		out[i] = (low * 0.5 + body) * _env(i, n, 0.005, 3.5) * 0.55
	return out


## Deep thump with a noise transient: artillery.
func _shot_cannon() -> PackedFloat32Array:
	var n := _len(0.34)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / float(n)
		low = lerpf(low, randf_range(-1.0, 1.0), 0.12)
		var boom := _sine(150.0 - 95.0 * t, i) * 0.8
		out[i] = (boom + low * 0.45 * (1.0 - t)) * _env(i, n, 0.004, 2.2) * 0.75
	return out


## Thin zap for light and energy weapons.
func _shot_light() -> PackedFloat32Array:
	var n := _len(0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		out[i] = _sine(1400.0 - 900.0 * t, i) * _env(i, n, 0.002, 4.0) * 0.45
	return out


## Filtered noise burst over a low thump.
func _explosion() -> PackedFloat32Array:
	var n := _len(0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / float(n)
		low = lerpf(low, randf_range(-1.0, 1.0), 0.22 - 0.16 * t)
		var thump := _sine(110.0 - 70.0 * t, i) * 0.7 * (1.0 - t)
		out[i] = (low * 0.85 + thump) * _env(i, n, 0.006, 2.4) * 0.7
	return out


## Short wet pop when a creep dies.
func _death() -> PackedFloat32Array:
	var n := _len(0.13)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var blip := _sine(520.0 - 340.0 * t, i) * 0.6
		out[i] = (blip + randf_range(-1.0, 1.0) * 0.25 * (1.0 - t)) \
				* _env(i, n, 0.004, 3.0) * 0.5
	return out


## Two-tone descending alarm: something reached the base.
func _leak() -> PackedFloat32Array:
	var n := _len(0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var freq := 400.0 if t < 0.5 else 300.0
		out[i] = (_square(freq, i) * 0.35 + _sine(freq * 0.5, i) * 0.3) \
				* _env(i, n, 0.01, 1.4) * 0.6
	return out


## Solid, satisfying chunk when a tower goes down.
func _build() -> PackedFloat32Array:
	var n := _len(0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var thunk := _sine(180.0 + 60.0 * t, i) * 0.7
		var grit := randf_range(-1.0, 1.0) * 0.3 * (1.0 - t) * (1.0 - t)
		out[i] = (thunk + grit) * _env(i, n, 0.008, 2.6) * 0.6
	return out


## Rising three-note figure for an installed rank.
func _upgrade() -> PackedFloat32Array:
	var n := _len(0.36)
	var out := PackedFloat32Array()
	out.resize(n)
	var steps: Array = [523.25, 659.25, 783.99]
	for i in n:
		var t := float(i) / float(n)
		var step: int = mini(int(t * 3.0), 2)
		var local := fposmod(t * 3.0, 1.0)
		out[i] = _sine(float(steps[step]), i) * pow(1.0 - local, 1.6) * 0.4
	return out


## Bright metallic ping for selling.
func _sell() -> PackedFloat32Array:
	var n := _len(0.28)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (_sine(1174.0, i) * 0.5 + _sine(1760.0, i) * 0.3) \
				* _env(i, n, 0.003, 3.2) * 0.4
	return out


## Two stacked horns announcing a wave.
func _wave_start() -> PackedFloat32Array:
	var n := _len(0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var wobble := 1.0 + 0.004 * sin(TAU * 5.0 * t)
		var horn := _saw(146.83 * wobble, i) * 0.35 + _saw(220.0 * wobble, i) * 0.28
		out[i] = horn * _env(i, n, 0.12, 1.6) * 0.55
	return out


## Major arpeggio for a cleared wave.
func _wave_clear() -> PackedFloat32Array:
	var n := _len(0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array = [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / float(n)
		var step: int = mini(int(t * 4.0), 3)
		var local := fposmod(t * 4.0, 1.0)
		out[i] = _sine(float(notes[step]), i) * pow(1.0 - local, 1.4) * 0.35
	return out


## Long descending tone for defeat.
func _game_over() -> PackedFloat32Array:
	var n := _len(1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var freq := 330.0 * pow(0.35, t)
		out[i] = (_sine(freq, i) * 0.5 + _saw(freq * 0.5, i) * 0.2) \
				* _env(i, n, 0.02, 1.1) * 0.55
	return out


## Low growl when a boss walks on.
func _boss() -> PackedFloat32Array:
	var n := _len(1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / float(n)
		low = lerpf(low, randf_range(-1.0, 1.0), 0.08)
		var growl := _saw(55.0 + 8.0 * sin(TAU * 3.0 * t), i) * 0.5
		out[i] = (growl + low * 0.4) * _env(i, n, 0.15, 1.3) * 0.7
	return out


## Tiny UI tick.
func _click() -> PackedFloat32Array:
	var n := _len(0.035)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _sine(1500.0, i) * _env(i, n, 0.002, 5.0) * 0.25
	return out


## Seamless hum for continuous beams.
func _beam() -> PackedFloat32Array:
	var cycles := 24.0
	var base := 180.0
	var n := int(round(float(RATE) * cycles / base))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var am := 0.85 + 0.15 * sin(TAU * 6.0 * float(i) / float(n))
		out[i] = (_saw(base, i) * 0.25 + _saw(base * 1.5, i) * 0.15
				+ _sine(base * 4.0, i) * 0.08) * am * 0.5
	return out


## Slow four-chord pad that loops cleanly: the ambient bed.
## Each area gets its own pad: the same shape of loop, tuned differently.
## Cheap variety - a set of frequencies and a tempo, not new content.
const AREA_MUSIC: Dictionary = {
	"greenlands": {"bar": 2.4, "shift": 1.0, "bright": 1.0},
	"riverlands": {"bar": 2.8, "shift": 1.06, "bright": 1.15},
	"wastes": {"bar": 2.2, "shift": 0.94, "bright": 0.8},
	"frozen": {"bar": 3.1, "shift": 1.19, "bright": 1.3},
	"delta": {"bar": 2.0, "shift": 0.84, "bright": 0.7},
}


func _music(shape: Dictionary = {}) -> PackedFloat32Array:
	var bar := float(shape.get("bar", 2.4))
	var shift := float(shape.get("shift", 1.0))
	var bright := float(shape.get("bright", 1.0))
	var chords: Array = [
		[220.0 * shift, 261.63 * shift, 329.63 * shift],   # Am
		[174.61 * shift, 220.0 * shift, 261.63 * shift],   # F
		[196.0 * shift, 246.94 * shift, 293.66 * shift],   # G
		[164.81 * shift, 207.65 * shift, 246.94 * shift],  # E minor-ish resolve
	]
	var n := _len(bar * float(chords.size()))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var pos := float(i) / float(RATE) / bar
		var index: int = int(pos) % chords.size()
		var local := fposmod(pos, 1.0)
		# Cross-fade neighbouring chords so the loop has no seams.
		var swell := sin(PI * local)
		var value := 0.0
		for freq: float in chords[index]:
			value += _sine(freq, i) * 0.16 + _sine(freq * 2.0, i) * 0.05 * bright
		value += _sine(float(chords[index][0]) * 0.5, i) * 0.12
		out[i] = value * (0.35 + 0.65 * swell) * 0.5
	return out
