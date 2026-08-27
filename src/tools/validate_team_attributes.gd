extends SceneTree

## Headless check that team .tres files match game.c def.teams and that
## apply_to scales WipeoutShip handling relative to AG Systems Venom.

const PATHS: Dictionary = {
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

const EXPECTED: Dictionary = {
	"AG SYSTEMS": {
		0: {"mass": 150.0, "thrust_max": 790.0, "resistance": 140.0, "turn_rate": 160.0, "turn_rate_max": 2560.0, "skid": 12.0},
		1: {"mass": 150.0, "thrust_max": 1200.0, "resistance": 140.0, "turn_rate": 160.0, "turn_rate_max": 2560.0, "skid": 10.0},
	},
	"AURICOM": {
		0: {"mass": 150.0, "thrust_max": 850.0, "resistance": 134.0, "turn_rate": 140.0, "turn_rate_max": 1920.0, "skid": 20.0},
		1: {"mass": 150.0, "thrust_max": 1400.0, "resistance": 140.0, "turn_rate": 120.0, "turn_rate_max": 1920.0, "skid": 14.0},
	},
	"QIREX": {
		0: {"mass": 150.0, "thrust_max": 850.0, "resistance": 140.0, "turn_rate": 120.0, "turn_rate_max": 1920.0, "skid": 24.0},
		1: {"mass": 150.0, "thrust_max": 1400.0, "resistance": 130.0, "turn_rate": 140.0, "turn_rate_max": 1920.0, "skid": 16.0},
	},
	"FEISAR": {
		0: {"mass": 150.0, "thrust_max": 790.0, "resistance": 134.0, "turn_rate": 180.0, "turn_rate_max": 2560.0, "skid": 12.0},
		1: {"mass": 150.0, "thrust_max": 1200.0, "resistance": 130.0, "turn_rate": 180.0, "turn_rate_max": 2560.0, "skid": 8.0},
	},
}


func _initialize() -> void:
	if not _check_resources():
		quit(1)
		return
	if not _check_apply():
		quit(1)
		return
	print("validate_team_attributes: OK")
	quit(0)


func _load_attrs(team: String, race_class: int) -> Resource:
	var paths: Array = PATHS[team]
	return load(str(paths[race_class]))


func _check_resources() -> bool:
	for team in EXPECTED:
		for race_class in EXPECTED[team]:
			var path := str(PATHS[team][int(race_class)])
			var attrs := load(path)
			if attrs == null:
				push_error("missing team attributes at %s" % path)
				return false
			var expected: Dictionary = EXPECTED[team][race_class]
			for key in expected:
				var got := float(attrs.get(key))
				var want := float(expected[key])
				if not is_equal_approx(got, want):
					push_error("%s class %s %s: got %s want %s" % [team, str(race_class), key, str(got), str(want)])
					return false
			print(team, " class=", race_class, " path=", path, " thrust_max=", attrs.thrust_max, " skid=", attrs.skid, " turn_rate=", attrs.turn_rate)
	return true


func _check_apply() -> bool:
	var scene := load("res://scenes/WipeoutShip.tscn") as PackedScene
	if scene == null:
		push_error("WipeoutShip.tscn failed to load")
		return false
	var ag: WipeoutShip = scene.instantiate()
	var feisar: WipeoutShip = scene.instantiate()
	var qirex: WipeoutShip = scene.instantiate()
	root.add_child(ag)
	root.add_child(feisar)
	root.add_child(qirex)

	ag.apply_team_attributes(_load_attrs("AG SYSTEMS", 0))
	feisar.apply_team_attributes(_load_attrs("FEISAR", 0))
	qirex.apply_team_attributes(_load_attrs("QIREX", 0))

	if not is_equal_approx(ag.thrust_max, feisar.thrust_max):
		push_error("Feisar Venom thrust_max should match AG Systems")
		return false
	if feisar.turn_accel <= ag.turn_accel:
		push_error("Feisar Venom should turn faster than AG Systems")
		return false
	if qirex.skid <= ag.skid:
		push_error("Qirex Venom should skid more than AG Systems")
		return false
	if qirex.turn_accel >= ag.turn_accel:
		push_error("Qirex Venom should turn slower than AG Systems")
		return false

	var feisar_venom_thrust := feisar.thrust_max
	var feisar_venom_turn := feisar.turn_accel
	feisar.apply_team_attributes(_load_attrs("FEISAR", 1))
	if feisar.thrust_max <= feisar_venom_thrust:
		push_error("Feisar Rapier should raise thrust_max over Venom")
		return false

	print("AG thrust_max=", snappedf(ag.thrust_max, 0.01), " turn_accel=", snappedf(ag.turn_accel, 0.01), " skid=", snappedf(ag.skid, 0.01))
	print("Feisar Venom turn_accel=", snappedf(feisar_venom_turn, 0.01), " Rapier thrust_max=", snappedf(feisar.thrust_max, 0.01))
	print("Qirex skid=", snappedf(qirex.skid, 0.01), " turn_accel=", snappedf(qirex.turn_accel, 0.01))
	return true
