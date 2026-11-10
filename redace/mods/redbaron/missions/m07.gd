extends "res://mods/redbaron/mission_script.gd"
## Mission 7, The Other Side: escort the Halberstadt photo plane over the British lines and home. The win is the
## photo plane back at the aerodrome after its photo run (its waypoint over the far side), not the Camels destroyed.
## Losing it fails (Group3 = 100; failed_defence.html).
## Enemy pressure is spread over the flight in three small, separate attacks the player can see coming: a pair of
## Camels each (one goes for the photo plane, one for the Baron), announced and highlighted, appearing well out:
##   1. outward    when the photo plane crosses into no man's land (z > OUTWARD_Z): ahead of it, from the south-east
##   2. photo run  when it reaches the start of the run (RUN_START): ahead of it, from the south
##   3. withdrawal once the photographs are taken and it has turned for home: behind it, from the east
## A pair waits until the one before is down or WAVE_GAP has passed.
## The photo plane carries the protect marks (green ring, bracket with distance, arrow when off screen); the
## aerodrome blinks on the minimap once the return begins.

const AERODROME := Vector3(8400, 0, 7750)
const FAR_POINT := Vector3(10300, 0, 12000)  # end of the photo run
const RUN_START := Vector3(9200, 0, 11600)
const OUTWARD_Z := 9300.0
const HOME_RANGE := 400.0
const WAVES := [[3010, 3011], [3012, 3013], [3014, 3015]]
const WAVE_GAP := 20.0

var photo: Aircraft
var photographed := false
var home_marker: Dictionary
var _wave := 0
var _turned_home := 0.0
var _wave_time := -100.0


func start() -> void:
	owns_win = true
	photo = plane(3002)
	home_marker = mark_destination(AERODROME)
	mark_protect(photo, "Halberstadt")
	objective("Escort the Halberstadt over the lines and bring it home.", "Escort the Halberstadt (green) on its photo run")


func step(_dt: float) -> void:
	if photo == null or not alive(photo):
		return
	if _wave == 0 and photo.global_position.z > OUTWARD_Z:
		_attack(0, Vector3(700.0, 120.0, 950.0), "Two Camels from the south-east, ahead of the Halberstadt!")
	elif _wave == 1 and _ready_for_next() and not photographed and (near(photo, RUN_START, 500.0, true)
			or photo.global_position.z > RUN_START.z):
		_attack(1, Vector3(250.0, 150.0, 1100.0), "Camels coming up from the south! Keep them off the photo run.")
	if not photographed and near(photo, FAR_POINT, 400.0, true):
		photographed = true
		_turned_home = now()
		home_marker.pulse = true
		objective("Photographs taken! The Halberstadt is turning for home. Stay with it.",
			"Bring the Halberstadt home to the aerodrome (blinking)")
	if _wave == 2 and photographed and now() >= _turned_home + 12.0 and _ready_for_next():
		var f := Vector3(photo.flight_basis.z.x, 0.0, photo.flight_basis.z.z).normalized()
		var side := f.cross(Vector3.UP)
		_attack(2, -f * 1100.0 + side * 350.0 + Vector3.UP * 150.0, "Camels chasing from behind! Cover the withdrawal.", true)
	if photographed and near(photo, AERODROME, HOME_RANGE, true):
		win()


## The next pair waits until the last one is down or WAVE_GAP has passed: small attacks, one at a time.
func _ready_for_next() -> bool:
	if now() >= _wave_time + WAVE_GAP:
		return true
	return WAVES[_wave - 1].all(func(id: int) -> bool: return not alive(plane(id)))


## Brings in wave i at the photo plane's position + offset (world axes, or already turned when relative) facing it.
func _attack(i: int, offset: Vector3, text: String, relative := false) -> void:
	_wave = i + 1
	_wave_time = now()
	var pair: Array[Aircraft] = []
	for k in WAVES[i].size():
		var c := plane(WAVES[i][k])
		if c == null:
			continue
		var spread: Vector3 = Vector3(90.0 * (k * 2 - 1), 30.0 * k, 0.0) if not relative else Vector3.UP * 30.0 * k
		var at: Vector3 = photo.global_position + offset + spread
		if relative and k == 1:
			at += (photo.global_position + offset - photo.global_position).cross(Vector3.UP).normalized() * 160.0
		var target: Aircraft = photo if k == 0 else world.player
		reveal(c, at, [goal(Aircraft.G_ATTACK, target.object_id)], target.global_position - at)
		pair.append(c)
	warn(text, 6.0)
	highlight(pair, 8.0)
