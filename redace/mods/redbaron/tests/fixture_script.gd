extends "res://mods/redbaron/mission_script.gd"
## Mission script of the test fixture (game_data/missions/199): records its calls; the test drives the API.

var start_calls := 0
var steps := 0
var throttle_cap := -1.0  # >= 0: the player's throttle is held at most this (the wound effect's mechanism)
var guns_off := false


func start() -> void:
	start_calls += 1
	owns_win = true


func step(_dt: float) -> void:
	steps += 1
	var p := world.player
	if throttle_cap >= 0.0:
		p.throttle = minf(p.throttle, throttle_cap)
	if guns_off:
		p.fire_input = false
