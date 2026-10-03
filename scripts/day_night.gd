extends Node
## Moves the sun across the sky and shifts the sky colours over a day.

@export var day_length_seconds := 480.0
@export_range(0.0, 1.0) var time_of_day := 0.38## 0 = midnight, 0.25 = sunrise, 0.5 = noon.

var sun: DirectionalLight3D
var world_environment: WorldEnvironment

var _sky_material := ProceduralSkyMaterial.new()
var _environment := Environment.new()

const DAY_TOP := Color(0.30, 0.55, 0.90)
const DAY_HORIZON := Color(0.70, 0.82, 0.95)
const DUSK_HORIZON := Color(0.95, 0.55, 0.35)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HORIZON := Color(0.06, 0.08, 0.15)


func _ready() -> void:
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.fog_enabled = true
	_environment.fog_density = 0.002
	_environment.ambient_light_sky_contribution = 0.6
	_environment.ambient_light_color = Color(0.9, 0.9, 0.85)
	_environment.fog_aerial_perspective = 0.6
	_environment.fog_sky_affect = 0.2
	world_environment.environment = _environment
	_update()


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
	_update()


func _update() -> void:
	# Sun angle: below the horizon at night, overhead at noon.
	var angle := (time_of_day - 0.25) * TAU
	sun.rotation = Vector3(-sin(angle) * PI * 0.5 - 0.0001, deg_to_rad(30.0), 0)
	var height := sin(angle)                      # -1 midnight .. 1 noon
	var daylight := smoothstep(-0.1, 0.25, height)
	var dusk := 1.0 - smoothstep(0.0, 0.35, absf(height))

	sun.light_energy = daylight * 1.3
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), dusk)
	sun.visible = height > -0.05

	var top := NIGHT_TOP.lerp(DAY_TOP, daylight)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_HORIZON, dusk * 0.7)
	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	_sky_material.ground_bottom_color = top.darkened(0.5)
	_environment.fog_light_color = horizon
	_environment.ambient_light_energy = lerpf(0.15, 0.7, daylight)
