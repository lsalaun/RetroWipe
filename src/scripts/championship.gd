extends Node

## Autoload: campaign progression, ported from src/wipeout/game.c's
## championship_ranks/lives/circuit fields and race.c's race_end()'s
## championship scoring and race_next()'s circuit chaining / class-and-bonus
## unlocks / congratulations text.
##
## Reset once per campaign by PilotMenu.tscn (button_pilot_select's g.circuit =
## 0; game_reset_championship()). The state below is intentionally not saved
## to disk, same as `g` in the C original -- only the unlock flags in Settings
## persist across campaigns.

const NUM_LIVES := 3 # game.h NUM_LIVES
const NUM_NON_BONUS_CIRCUITS := 6 # game.h NUM_NON_BONUS_CIRCUITS
const NUM_WIPEOUT_CIRCUITS := 7 # game.h NUM_WIPEOUT_CIRCUITS (CIRCUIT_TALONS_REACH)

## def.race_points_for_rank, indexed by finishing position (0 = 1st).
const POINTS_FOR_RANK: Array[int] = [9, 7, 5, 3, 2, 1, 0, 0]

## def.congratulations.* (game.c). "#" prefixes a bigger accent-coloured
## heading line with extra leading/trailing spacing, per
## ingame_menus.c's text_scroll_menu_draw().
const CONGRATULATIONS_VENOM: Array[String] = [
	"#WELL DONE", "", "VENOM CLASS", "", "COMPETENCE ACHIEVED", "",
	"YOU HAVE NOW QUALIFIED", "", "FOR THE ULTRA FAST", "", "RAPIER CLASS", "",
	"WE RECOMMEND YOU", "", "SAVE YOUR CURRENT GAME",
]
const CONGRATULATIONS_VENOM_ALL_CIRCUITS: Array[String] = [
	"#AMAZING", "", "YOU HAVE COMPLETED THE FULL", "", "VENOM CLASS CHAMPIONSHIP", "",
	"", "WELL DONE", "", "YOU ARE A GREAT PILOT", "", "", "",
	"NOW TAKE ON THE FULL", "", "RAPIER CLASS CHAMPIONSHIP", "", "", "#KEEP GOING",
]
const CONGRATULATIONS_RAPIER: Array[String] = [
	"#CONGRATULATIONS", "", "RAPIER CLASS", "", "COMPETENCE ACHIEVED", "",
	"YOU NOW HAVE ACCESS TO THE", "", "FULL VENOM AND RAPIER", "",
	"CHAMPIONSHIPS WITH THE ", "", "NEWLY CONSTRUCTED CIRCUIT", "", "FIRESTAR", "",
	"", "", "WE RECOMMEND YOU", "", "SAVE", "", "YOUR CURRENT GAME", "", "", "#GOOD LUCK",
]
const CONGRATULATIONS_RAPIER_ALL_CIRCUITS: Array[String] = [
	"#AWESOME", "", "YOU HAVE BEATEN", "#WIPEOUT", "", "YOU ARE A TRULY", "",
	"AMAZING PILOT", "", "", "", "#CONGRATULATIONS", "", "", "", "",
	"#A BIG THANKS", "", "FROM ALL OF US ON THE TEAM", "", "LOOK OUT FOR",
	"#WIPEOUT II", "", "COMING SOON",
]

## g.circuit, as an index into TrackSelection.CIRCUIT_ORDER.
var circuit_index: int = 0
var lives: int = NUM_LIVES
## pilot name -> accumulated points, one entry per ShipSelection.SHIPS pilot.
var standings: Dictionary = {}
## The last record_race_result()'s per-race points, same keys as `standings`.
var last_race_points: Dictionary = {}


## game_reset_championship() + button_pilot_select()'s `g.circuit = 0`.
func reset() -> void:
	circuit_index = 0
	lives = NUM_LIVES
	standings.clear()
	last_race_points.clear()
	for ship in ShipSelection.SHIPS:
		standings[str(ship["pilot"])] = 0


## The circuit name (a TrackSelection.CIRCUIT_ORDER entry) for the current
## championship position.
func current_circuit() -> String:
	var order := TrackSelection.CIRCUIT_ORDER
	return order[clampi(circuit_index, 0, order.size() - 1)]


## race.c race_end()'s championship block: awards POINTS_FOR_RANK to every
## pilot by finish order (index 0 = 1st place) and accumulates into
## `standings`. Runs every time a championship race ends, qualified or not --
## matching the original, which scores the race before the player even learns
## whether they personally qualified.
func record_race_result(finish_order: Array[String]) -> void:
	last_race_points.clear()
	for i in finish_order.size():
		var pilot: String = finish_order[i]
		var points: int = POINTS_FOR_RANK[clampi(i, 0, POINTS_FOR_RANK.size() - 1)]
		last_race_points[pilot] = points
		standings[pilot] = int(standings.get(pilot, 0)) + points


## Cumulative standings, leader first, as page_championship_points_draw()
## shows them: [{"pilot": String, "points": int}, ...].
func standings_sorted() -> Array[Dictionary]:
	return _sorted(standings)


## This race's points alone, same sort/shape as standings_sorted().
func last_race_points_sorted() -> Array[Dictionary]:
	return _sorted(last_race_points)


func _sorted(points_by_pilot: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for pilot in points_by_pilot:
		rows.append({"pilot": pilot, "points": int(points_by_pilot[pilot])})
	rows.sort_custom(func(a, b): return int(a["points"]) > int(b["points"]))
	return rows


## race_restart(): a failed qualification costs a life. Returns true once
## that was the last one (game_over_menu_init() territory).
func lose_life() -> bool:
	lives -= 1
	return lives <= 0


## race_next(): true once `circuit_index` has run every circuit the current
## unlock state allows. Checked (like the C) before complete_championship()
## updates either unlock flag for this run.
func is_championship_complete() -> bool:
	var next_circuit := circuit_index + 1
	var gate := NUM_WIPEOUT_CIRCUITS if Settings.has_bonus_circuits else NUM_NON_BONUS_CIRCUITS
	return next_circuit >= gate


## race_next()'s "next track" branch.
func advance_circuit() -> void:
	circuit_index += 1


## race_next()'s "championship complete" branch: flips the unlock flag(s) this
## `race_class` finish grants and returns the congratulations text to show.
## Finishing VENOM always unlocks RAPIER CLASS; finishing RAPIER unlocks the
## bonus circuit (FIRESTAR) the first time, and re-running either class after
## bonus circuits are unlocked plays the "_all_circuits" ending instead.
func complete_championship(race_class: int) -> Array[String]:
	if race_class == RaceSetup.RACE_CLASS_RAPIER:
		if Settings.has_bonus_circuits:
			return CONGRATULATIONS_RAPIER_ALL_CIRCUITS
		Settings.set_has_bonus_circuits(true)
		return CONGRATULATIONS_RAPIER
	Settings.set_has_rapier_class(true)
	if Settings.has_bonus_circuits:
		return CONGRATULATIONS_VENOM_ALL_CIRCUITS
	return CONGRATULATIONS_VENOM
