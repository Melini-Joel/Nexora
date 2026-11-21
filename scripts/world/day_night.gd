class_name DayNight
extends Node
## Ciclo de día y noche: mueve el sol y la luna y cambia el cielo, la luz y la niebla.
## La hora la manda el servidor a todos los jugadores, así que todos ven lo mismo.

const DAY_SECONDS := 1800.0  ## Duración de un día completo (30 minutos: ~20 de día y ~10 de noche).
const NIGHT_START := 0.79
const NIGHT_END := 0.21

const DAY_TOP := Color(0.3, 0.5, 0.82)
const DAY_HORIZON := Color(0.72, 0.8, 0.88)
const SUNSET_HORIZON := Color(0.98, 0.58, 0.32)
const SUNSET_TOP := Color(0.32, 0.33, 0.6)
const NIGHT_TOP := Color(0.015, 0.02, 0.06)
const NIGHT_HORIZON := Color(0.08, 0.11, 0.22)

var time := 0.3  ## 0 = medianoche, 0.25 = amanecer, 0.5 = mediodía, 0.75 = atardecer.
var day := 1
## Solo para cinemáticas (local): fuerza una hora sin cambiar la real (-1 = sin forzar).
var override_time := -1.0
## Tormenta (0..1): cielo más oscuro, niebla densa y menos luz. Solo para cinemáticas.
var storm := 0.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky: ShaderMaterial


func setup(p_sun: DirectionalLight3D, p_moon: DirectionalLight3D, p_environment: Environment, p_sky: ShaderMaterial) -> void:
	sun = p_sun
	moon = p_moon
	environment = p_environment
	sky = p_sky
	_apply()


func is_night() -> bool:
	return time > NIGHT_START or time < NIGHT_END


func clock_text() -> String:
	var hours := time * 24.0
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)]


func period_name() -> String:
	if is_night():
		return "Noche"
	if time < 0.3:
		return "Amanecer"
	if time < 0.45:
		return "Mañana"
	if time < 0.62:
		return "Mediodía"
	if time < 0.72:
		return "Tarde"
	return "Atardecer"


func set_time(new_time: float, new_day: int) -> void:
	# Corrige suave si la diferencia es chica (evita saltos de luz).
	if absf(new_time - time) < 0.01 and new_day == day:
		time = lerpf(time, new_time, 0.5)
	else:
		time = new_time
	day = new_day
	_apply()


func _process(delta: float) -> void:
	if sun == null:
		return
	time += delta / DAY_SECONDS
	if time >= 1.0:
		time -= 1.0
		day += 1
	_apply()


func _apply() -> void:
	var shown_time := override_time if override_time >= 0.0 else time
	var angle := (shown_time - 0.25) * TAU  # 0 = amanecer, PI/2 = mediodía, PI = atardecer
	var elevation := sin(angle)
	var day_factor := clampf(elevation * 3.5 + 0.15, 0.0, 1.0)
	var sunset := clampf(1.0 - absf(elevation) * 3.0, 0.0, 1.0) * clampf(elevation * 5.0 + 1.0, 0.0, 1.0)
	var night_factor := 1.0 - day_factor

	sun.rotation = Vector3(-angle, deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.15 * day_factor
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), sunset)
	sun.visible = day_factor > 0.01
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if sun.visible else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.rotation = Vector3(-(angle - PI), deg_to_rad(-35.0), 0.0)
	moon.light_energy = 0.6 * night_factor
	moon.visible = night_factor > 0.01

	var top := NIGHT_TOP.lerp(DAY_TOP, day_factor).lerp(SUNSET_TOP, sunset * 0.6)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day_factor).lerp(SUNSET_HORIZON, sunset * 0.8)
	sky.set_shader_parameter("ground_horizon_color", horizon.darkened(0.2))
	sky.set_shader_parameter("ground_bottom_color", Color(0.04, 0.08, 0.12).lerp(Color(0.12, 0.3, 0.42), day_factor))
	sky.set_shader_parameter("star_intensity", clampf((0.2 - day_factor) * 5.0, 0.0, 1.0) * (1.0 - storm))
	var clouds := Color(0.14, 0.15, 0.2).lerp(Color(1.0, 1.0, 1.0), day_factor).lerp(Color(1.0, 0.72, 0.55), sunset * 0.7)
	sky.set_shader_parameter("cloud_color", clouds.lerp(Color(0.25, 0.27, 0.3), storm))
	sky.set_shader_parameter("cloud_coverage", lerpf(0.42, 0.85, storm))
	environment.ambient_light_energy = lerpf(0.85, 1.45, day_factor) * (1.0 - storm * 0.4)
	environment.fog_light_color = horizon.lerp(Color(0.12, 0.14, 0.18), storm)
	environment.fog_density = lerpf(0.0035, 0.0012, day_factor) + storm * 0.012
	sky.set_shader_parameter("sky_top_color", top.lerp(Color(0.04, 0.05, 0.07), storm))
	sky.set_shader_parameter("sky_horizon_color", horizon.lerp(Color(0.1, 0.12, 0.15), storm))
