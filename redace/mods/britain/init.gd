extends Node
## Mission-owned entry point. World only loads this path from the mission manifest.

var environment: Node3D
var camera_distance_scale := 0.65

func setup_map(world: World, sky: Environment, level: Node3D) -> void:
	environment = load("res://mods/britain/environment.gd").new()
	level.add_child(environment)
	environment.setup(sky, world.water_detail, world.cloud_detail)
	camera_distance_scale = environment.camera_distance_scale

func create_aircraft() -> Aircraft:
	return environment.create_aircraft()

func configure_aircraft(plane: Aircraft, section: Dictionary) -> void:
	environment.configure_aircraft(plane, section)

func is_sea(pos: Vector3) -> bool:
	return environment != null and environment.is_sea(pos)

func sea_crash(pos: Vector3) -> void:
	environment.sea_crash(pos)

func counts_as_lost(plane: Aircraft) -> bool:
	return plane.state == Aircraft.State.DEAD

func apply_graphics_quality(water: int, cloud: int) -> void:
	environment.set_quality(water, cloud)
