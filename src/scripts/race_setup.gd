extends Node

## Autoload: central race configuration mirroring src/wipeout/main_menu.c's
## menu flow (race class -> race type -> team -> pilot -> circuit) and
## src/wipeout/game.c's def.teams/def.pilots data. Drives MainMenu.tscn's
## chain of selection screens; the final picks are handed off to
## ShipSelection/TrackSelection so main.tscn doesn't need to change.

const RACE_CLASS_VENOM := 0
const RACE_CLASS_RAPIER := 1
const RACE_CLASSES: Array[String] = ["VENOM CLASS", "RAPIER CLASS"]

const RACE_TYPE_CHAMPIONSHIP := 0
const RACE_TYPE_SINGLE := 1
const RACE_TYPE_TIME_TRIAL := 2
const RACE_TYPES: Array[String] = ["CHAMPIONSHIP RACE", "SINGLE RACE", "TIME TRIAL"]

## Team order matches src/wipeout/game.c's def.teams.
const TEAM_ORDER: Array[String] = ["AG SYSTEMS", "AURICOM", "QIREX", "FEISAR"]

## Team name -> ordered pilot names, matching def.teams[*].pilots.
const TEAM_PILOTS: Dictionary = {
	"AG SYSTEMS": ["John Dekka", "Daniel Chang"],
	"AURICOM": ["Arial Tetsuo", "Anastasia Cherovoski"],
	"QIREX": ["Kel Solaar", "Arian Tetsuo"],
	"FEISAR": ["Sofia De La Rente", "Paul Jackson"],
}

## Per-team PSX attributes from def.teams, indexed [Venom, Rapier].
const TEAM_ATTRIBUTE_PATHS: Dictionary = {
	"AG SYSTEMS": [
		"res://resources/teams/ag_systems_venom.tres",
		"res://resources/teams/ag_systems_rapier.tres",
	],
	"AURICOM": [
		"res://resources/teams/auricom_venom.tres",
		"res://resources/teams/auricom_rapier.tres",
	],
	"QIREX": [
		"res://resources/teams/qirex_venom.tres",
		"res://resources/teams/qirex_rapier.tres",
	],
	"FEISAR": [
		"res://resources/teams/feisar_venom.tres",
		"res://resources/teams/feisar_rapier.tres",
	],
}

var race_class: int = RACE_CLASS_VENOM
var race_type: int = RACE_TYPE_CHAMPIONSHIP
var team_name: String = ""
var pilot_name: String = ""


func select_race_class(value: int) -> void:
	race_class = value


func select_race_type(value: int) -> void:
	race_type = value


func select_team(value: String) -> void:
	team_name = value


## Returns ShipSelection.SHIPS entries for `team`, in def.teams pilot order.
func pilots_for_team(team: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wanted_pilot in TEAM_PILOTS.get(team, []):
		for ship in ShipSelection.SHIPS:
			if ship["pilot"] == wanted_pilot:
				result.append(ship)
				break
	return result


func select_pilot(ship: Dictionary) -> void:
	pilot_name = ship["pilot"]
	ShipSelection.select_ship(ship["mesh"])


func normalize_team_name(team: String) -> String:
	return team.strip_edges().to_upper()


func team_for_pilot(pilot: String) -> String:
	for team in TEAM_PILOTS:
		for name in TEAM_PILOTS[team]:
			if name == pilot:
				return team
	for ship in ShipSelection.SHIPS:
		if str(ship.get("pilot", "")) == pilot:
			var from_ship := normalize_team_name(str(ship.get("team", "")))
			if TEAM_ATTRIBUTE_PATHS.has(from_ship):
				return from_ship
	if TEAM_ATTRIBUTE_PATHS.has(normalize_team_name(team_name)):
		return normalize_team_name(team_name)
	return TEAM_ORDER[0]


func attributes_path_for(team: String, race_class_value: int = -1) -> String:
	if race_class_value < 0:
		race_class_value = race_class
	var key := normalize_team_name(team)
	if not TEAM_ATTRIBUTE_PATHS.has(key):
		key = TEAM_ORDER[0]
	var paths: Array = TEAM_ATTRIBUTE_PATHS[key]
	var index := clampi(race_class_value, 0, paths.size() - 1)
	return str(paths[index])


func attributes_for(team: String, race_class_value: int = -1) -> Resource:
	return load(attributes_path_for(team, race_class_value))


func attributes_for_pilot(pilot: String, race_class_value: int = -1) -> Resource:
	return attributes_for(team_for_pilot(pilot), race_class_value)
