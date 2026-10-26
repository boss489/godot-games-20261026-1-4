extends SceneTree
const Model = preload("res://game_model.gd")
var failures := 0
func _initialize() -> void:
	for level in [1, 8, 16, 24]:
		simulate(level, false)
	simulate(1, true)
	print("FULL RUNS: 5 simulated completions; %d failures" % failures)
	quit(1 if failures else 0)

func simulate(level: int, survival: bool) -> void:
	var m = Model.new()
	m.start(level, survival, 42)
	var max_steps := 12000
	for step in max_steps:
		if m.state != "playing": break
		m.advance(0.01)
		if m.state != "playing": break
		var imminent: Dictionary = {}
		for foe in m.enemies:
			if foe.remaining <= 0.05 and (imminent.is_empty() or foe.remaining < imminent.remaining):
				imminent = foe
		if not imminent.is_empty():
			var result: Dictionary = m.attack(imminent.side)
			if result.result not in ["hit", "armor"]:
				printerr("UNEXPECTED ATTACK level=%d survival=%s time=%.2f result=%s" % [level, survival, m.elapsed, result.result])
				failures += 1
				break
	if m.state != "victory":
		failures += 1
		printerr("FAILED RUN level=%d survival=%s time=%.2f hp=%d state=%s" % [level, survival, m.elapsed, m.health, m.state])
	else:
		print("RUN level=%d survival=%s score=%d combo=%d hp=%d waves=%d" % [level, survival, m.score, m.best_combo, m.health, m.wave_index])
