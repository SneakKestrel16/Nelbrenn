extends Node
## Moves the sun across the sky and shifts the sky colours over a day.
## In horror worlds the colours are washed out, the fog is thick, and
## nights are close to pitch black.

@export var day_length_seconds := 480.0
@export_range(0.0, 1.0) var time_of_day := 0.38## 0 = midnight, 0.25 = sunrise, 0.5 = noon.
## Set before adding to the tree.
var horror := false

var sun: DirectionalLight3D
var world_environment: WorldEnvironment

var _sky_material := ProceduralSkyMaterial.new()
var _environment := Environment.new()

const DAY_TOP := Color(0.30, 0.55, 0.90)
const DAY_HORIZON := Color(0.70, 0.82, 0.95)
const DUSK_HORIZON := Color(0.95, 0.55, 0.35)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HORIZON := Color(0.06, 0.08, 0.15)

const HORROR_DAY_TOP := Color(0.42, 0.45, 0.48)
const HORROR_DAY_HORIZON := Color(0.58, 0.59, 0.58)
const HORROR_DUSK_HORIZON := Color(0.55, 0.16, 0.10)  # A blood-red sunset.
const HORROR_NIGHT_TOP := Color(0.004, 0.005, 0.01)
const HORROR_NIGHT_HORIZON := Color(0.01, 0.012, 0.018)


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
	if horror:
		_environment.fog_aerial_perspective = 0.0
		_environment.fog_sky_affect = 0.7
		_environment.adjustment_enabled = true
		_environment.adjustment_saturation = 0.5  # Drained, sickly colours.
		_environment.adjustment_contrast = 1.1
		_sky_material.sun_angle_max = 5.0
	world_environment.environment = _environment
	_update()


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
	_update()


## 1 in full daylight, 0 at night.
func get_daylight() -> float:
	return smoothstep(-0.1, 0.25, sin((time_of_day - 0.25) * TAU))


func _update() -> void:
	# Sun angle: below the horizon at night, overhead at noon.
	var angle := (time_of_day - 0.25) * TAU
	sun.rotation = Vector3(-sin(angle) * PI * 0.5 - 0.0001, deg_to_rad(30.0), 0)
	var height := sin(angle)                      # -1 midnight .. 1 noon
	var daylight := smoothstep(-0.1, 0.25, height)
	var dusk := 1.0 - smoothstep(0.0, 0.35, absf(height))

	sun.light_energy = daylight * (0.8 if horror else 1.3)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), dusk)
	sun.visible = height > -0.05

	var top: Color
	var horizon: Color
	if horror:
		top = HORROR_NIGHT_TOP.lerp(HORROR_DAY_TOP, daylight)
		horizon = HORROR_NIGHT_HORIZON.lerp(HORROR_DAY_HORIZON, daylight).lerp(HORROR_DUSK_HORIZON, dusk * 0.8)
	else:
		top = NIGHT_TOP.lerp(DAY_TOP, daylight)
		horizon = NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_HORIZON, dusk * 0.7)
	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	_sky_material.ground_bottom_color = top.darkened(0.5)
	_environment.fog_light_color = horizon
	if horror:
		# Thick fog by day, a wall of black at night: you can see ~40 m.
		_environment.fog_density = lerpf(0.03, 0.014, daylight)
		_environment.ambient_light_energy = lerpf(0.035, 0.5, daylight)
	else:
		_environment.ambient_light_energy = lerpf(0.15, 0.7, daylight)
