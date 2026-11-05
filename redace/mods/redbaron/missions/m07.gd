extends "res://mods/redbaron/mission_script.gd"
## Mission 7, The Other Side: escort the Halberstadt photo plane over the British lines and home. Three
## Camels appear (0x120) when it is deep over their side. The win is the photo plane back at the
## aerodrome after its photo run (its waypoint over the far side), not the Camels destroyed. Losing it
## fails (Group3 = 100; failed_defence.html).

const AERODROME := Vector3(8400, 0, 7750)
const FAR_POINT := Vector3(10300, 0, 12000)  # end of the photo run
const HOME_RANGE := 400.0

var photo: Aircraft
var photographed := false


func start() -> void:
	owns_win = true
	photo = plane(3002)
	mark_on_map(AERODROME)
	message("Escort the Halberstadt over the lines and bring it home.", 6.0)


func step(_dt: float) -> void:
	if photo == null or not alive(photo):
		return
	if not photographed and near(photo, FAR_POINT, 400.0, true):
		photographed = true
		message("Photographs taken. Bring them home!", 6.0)
	if photographed and near(photo, AERODROME, HOME_RANGE, true):
		win()
