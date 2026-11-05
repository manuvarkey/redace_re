extends Node
## Red Baron campaign ("Der Rote Kampfflieger"): mission-owned entry point, declared by each mission as
## [mod] init = res://mods/redbaron/init.gd. Optional mission keys read here (not by the engine):
##   [mod] script = res://mods/redbaron/missions/mNN.gd   mission script (default: stock rules only)
##   [environment] fogcolour = r g b                      fog and horizon colour, 0..255
##   [environment] sky = res://mods/redbaron/skies/<name>/  folder with sky_front/back/left/right/up.png
##   [environment] ambient = r g b                        ambient light, 0..255
##   [airN] gunners = 0 / 1                               defensive gunners off / on (aircraft.gd)
##   [airN] gunnerrate = N                                gunners' rounds per second (default 5)
##   [airN] firerate / fireon / fireoff                   the plane's own guns (plane.ini [armaments])

const MissionScript := preload("res://mods/redbaron/mission_script.gd")
const RedBaronAircraft := preload("res://mods/redbaron/aircraft.gd")

var camera_distance_scale := 1.0
var world: World
var environment: Environment
var mission := {}  # the mission.ini sections
var mission_script: MissionScript
var overlay: CanvasLayer  # overlay.gd, made by the mission script on first use


func setup_map(world_: World, env: Environment, _level: Node3D) -> void:
	world = world_
	environment = env
	mission = Ini.load_file(Ini.data_path("missions/%d/mission.ini" % world.mission_id))
	var envs: Dictionary = mission.get("environment", {})
	if envs.has("fogcolour"):
		set_fog(_colour(str(envs.fogcolour)))
	if envs.has("sky"):
		set_sky(str(envs.sky))
	if envs.has("ambient"):
		environment.ambient_light_color = _colour(str(envs.ambient))
	var path := str(mission.get("mod", {}).get("script", ""))
	if path.begins_with("res://mods/") and ResourceLoader.exists(path):
		mission_script = load(path).new()
	else:
		mission_script = MissionScript.new()
	mission_script.world = world
	mission_script.mod = self


static func _colour(text: String) -> Color:
	var parts := text.split(" ", false)
	if parts.size() < 3:
		return Color.WHITE
	return Color8(int(parts[0]), int(parts[1]), int(parts[2]))


## Fog and horizon colour: the map environment, the sky shader's lower half and the lit shader's fog.
func set_fog(colour: Color) -> void:
	environment.fog_light_color = colour
	var sky_mat := environment.sky.sky_material as ShaderMaterial if environment.sky else null
	if sky_mat:
		sky_mat.set_shader_parameter("fog_color", colour)
	RenderingServer.global_shader_parameter_set("ra_fog_colour", Vector3(colour.r, colour.g, colour.b))


## Sky box from a folder of sky_front/back/left/right/up.png (the maps' own layout).
func set_sky(dir: String) -> void:
	var sky_mat := environment.sky.sky_material as ShaderMaterial if environment.sky else null
	if sky_mat == null:
		return
	for f in ["front", "back", "left", "right", "up"]:
		var p := dir.path_join("sky_%s.png" % f)
		if ResourceLoader.exists(p):
			sky_mat.set_shader_parameter("sky_" + f, load(p))


func create_aircraft() -> Aircraft:
	return RedBaronAircraft.new()


func configure_aircraft(plane: Aircraft, section: Dictionary) -> void:
	if section.has("gunners"):
		plane.set("gunners_enabled", int(Ini.num(section, "gunners", 0)) != 0)
	# the plane's own guns, as plane.ini [armaments] (the engine reads only endurance and highspeed here)
	if section.has("firerate"):
		plane.fire_rate = Ini.num(section, "firerate", plane.fire_rate)
	if section.has("fireon"):
		plane.fire_on = Ini.num(section, "fireon", plane.fire_on)
	if section.has("fireoff"):
		plane.fire_off = Ini.num(section, "fireoff", plane.fire_off)
	if section.has("gunnerrate"):
		plane.call("set_gunner_rate", Ini.num(section, "gunnerrate", 5.0))


## A plane is lost when destroyed, or when it is an enemy (group 9) that flew off the map (stock 0x439046).
## Hidden planes waiting to appear are not lost, and a friendly plane that leaves the map has escaped.
func counts_as_lost(plane: Aircraft) -> bool:
	return plane.state == Aircraft.State.DEAD or (plane.left_map and plane.groups & (1 << 9) != 0)


func is_sea(_pos: Vector3) -> bool:
	return false


func sea_crash(_pos: Vector3) -> void:
	pass


func mission_step(_world: World, dt: float) -> void:
	if mission_script:
		mission_script.run_step(dt)


func mission_outcome(_world: World, stock: String) -> String:
	return mission_script.outcome(stock) if mission_script else stock


func end_message(_world: World, result: String) -> Variant:
	return mission_script.end_messages.get(result) if mission_script else null


func result_page(_world: World, result: String, campaign: bool) -> String:
	return mission_script.page_for(result, campaign) if mission_script else ""
