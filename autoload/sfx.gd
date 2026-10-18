extends Node
## Sound effects (GDD §6). One player per sound, all on the SFX bus, which
## Settings.sfx_muted mutes. Every button in the app gets the click automatically
## (opt out with the "no_click_sound" metadata). Dice sounds are driven by the roll
## screen and synced to the die's simulated bounces.

enum Sound { CLICK, UNLOCK, IMPACT, REVEAL }

const BUS := &"SFX"
const RATTLE_FADE_TIME := 0.25  # Seconds.
const MIN_IMPACT_STRENGTH := 0.05  # Quieter bounces are skipped.

const CLICK_STREAM := preload("res://assets/audio/sfx/click.ogg")
const UNLOCK_STREAM := preload("res://assets/audio/sfx/unlock.ogg")
const IMPACT_STREAM := preload("res://assets/audio/sfx/impact.ogg")
const REVEAL_STREAM := preload("res://assets/audio/sfx/reveal.ogg")
const RATTLE_STREAM := preload("res://assets/audio/sfx/rattle.ogg")

var _players: Array[AudioStreamPlayer] = []  # Indexed by Sound.
var _rattle: AudioStreamPlayer
var _rattle_tween: Tween


func _ready() -> void:
	_players.resize(Sound.size())
	_players[Sound.CLICK] = _make_player(CLICK_STREAM, 1.05, 3)
	_players[Sound.UNLOCK] = _make_player(UNLOCK_STREAM, 1.0, 1)
	_players[Sound.IMPACT] = _make_player(IMPACT_STREAM, 1.1, 4)
	_players[Sound.REVEAL] = _make_player(REVEAL_STREAM, 1.0, 1)
	_rattle = _make_player(RATTLE_STREAM, 1.0, 1)
	Settings.changed.connect(_apply_mute)
	_apply_mute()
	get_tree().node_added.connect(_on_node_added)


func play(sound: Sound, volume_db: float = 0.0) -> void:
	var player := _players[sound]
	player.volume_db = volume_db
	player.play()


## strength 0..1 from Die.impact: harder bounces are louder.
func play_impact(strength: float) -> void:
	if strength >= MIN_IMPACT_STRENGTH:
		play(Sound.IMPACT, lerpf(-18.0, 0.0, strength))


## intensity 0..1 from the roll: stronger rolls rattle louder and slightly higher.
func start_rattle(intensity: float) -> void:
	if _rattle_tween != null:
		_rattle_tween.kill()
	_rattle.volume_db = lerpf(-14.0, -2.0, intensity)
	_rattle.pitch_scale = lerpf(0.95, 1.1, intensity)
	_rattle.play()


func stop_rattle() -> void:
	if not _rattle.playing:
		return
	if _rattle_tween != null:
		_rattle_tween.kill()
	_rattle_tween = create_tween()
	_rattle_tween.tween_property(_rattle, "volume_db", -40.0, RATTLE_FADE_TIME)
	_rattle_tween.tween_callback(_rattle.stop)


func _make_player(stream: AudioStream, random_pitch: float, polyphony: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	if random_pitch > 1.0:
		# Slight random pitch per play, so repeated sounds don't feel mechanical.
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(-1, stream)
		randomizer.random_pitch = random_pitch
		player.stream = randomizer
	else:
		player.stream = stream
	player.bus = BUS
	player.max_polyphony = polyphony
	add_child(player)
	return player


func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS), Settings.sfx_muted)


## Gives every button that enters the tree its click sound.
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.has_meta("no_click_sound"):
		return
	var click := play.bind(Sound.CLICK, 0.0)
	if not button.pressed.is_connected(click):
		button.pressed.connect(click)
