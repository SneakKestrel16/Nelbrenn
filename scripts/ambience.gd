extends AudioStreamPlayer
## Endless gusty wind made from filtered noise, so there's no sound file.
## It gets louder the higher up you are.

const MIX_RATE := 22050.0

var listener: Node3D  # Usually the player.

var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _gusts := FastNoiseLite.new()
var _time := 0.0
var _brown := [0.0, 0.0]  # One per ear, so it sounds wide.
var _volume := 0.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25
	stream = generator
	bus = "Ambience"
	_gusts.frequency = 0.2
	play()
	_playback = get_stream_playback()


func _process(delta: float) -> void:
	_time += delta
	var height := listener.global_position.y if listener else 0.0
	var altitude := clampf(0.35 + height / 100.0, 0.35, 1.2)
	var gust := 0.55 + 0.45 * _gusts.get_noise_1d(_time * 10.0)
	var target := altitude * gust

	var frames := _playback.get_frames_available()
	if frames == 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i in frames:
		# Glide the volume so gusts swell smoothly instead of clicking.
		_volume += (target - _volume) * 0.0005
		for ear in 2:
			_brown[ear] = (_brown[ear] + _rng.randf_range(-1.0, 1.0) * 0.02) / 1.02
		buffer[i] = Vector2(_brown[0], _brown[1]) * 3.0 * _volume
	_playback.push_buffer(buffer)
