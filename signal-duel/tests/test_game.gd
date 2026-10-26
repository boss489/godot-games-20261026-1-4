extends SceneTree

const Model = preload("res://game_model.gd")
var failures := 0
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var m = Model.new()
	check(m.patterns.size() == 20, "twenty distinct patterns")
	var signatures := {}
	for p in m.patterns:
		check(p.size() >= 3, "pattern has at least three beats")
		var signature := str(p)
		check(not signatures.has(signature), "patterns unique")
		signatures[signature] = true
		for beat in p:
			check(beat[1] >= 0 and beat[1] < 5, "enemy type valid")
	check(signatures.size() == 20, "twenty unique patterns")
	check(m.stage_rules(1).duration < m.stage_rules(24).duration, "stage length ramps")
	check(m.stage_rules(24).speed > m.stage_rules(1).speed, "stage speed ramps")
	check(m.stage_rules(1).duration > 0, "stage duration positive")
	m.start(1, false, 73)
	check(m.state == "playing", "stage starts")
	check(m.stage == 1, "stage selected")
	m.enemies.clear()
	m.enemies.append({"side": -1, "kind": 0, "remaining": 0.01, "switched": false, "armor": 0})
	var hit: Dictionary = m.attack(-1)
	check(hit.result == "hit", "correct timed defense hits")
	check(m.combo == 1, "hit builds combo")
	m.enemies.append({"side": 1, "kind": 0, "remaining": 0.01, "switched": false, "armor": 0})
	check(m.attack(-1).result == "wrong", "wrong side punished")
	check(m.combo == 0, "wrong side breaks combo")
	check(m.health == m.max_health - 1, "wrong side damages")
	m.enemies.clear()
	m.enemies.append({"side": 1, "kind": 0, "remaining": 0.9, "switched": false, "armor": 0})
	check(m.attack(1).result == "early", "button mashing punished")
	m.enemies.clear()
	m.enemies.append({"side": -1, "kind": 2, "remaining": 0.01, "switched": false, "armor": 0})
	check(m.attack(-1).result == "armor", "armored foe needs two blows")
	check(m.enemies.size() == 1, "armor survives first blow")
	check(m.attack(-1).result == "hit", "second blow defeats armor")
	m.enemies.clear()
	m.enemies.append({"side": -1, "kind": 3, "remaining": 0.5, "switched": false, "armor": 0})
	m.advance(0.01)
	check(m.enemies[0].side == 1 and m.enemies[0].switched, "switcher telegraphs then changes lane")
	var a = Model.new()
	var b = Model.new()
	a.start(7, false, 999)
	b.start(7, false, 999)
	for i in 80:
		a.advance(0.05)
		b.advance(0.05)
	check(a.enemies == b.enemies and a.wave_index == b.wave_index, "same seed yields deterministic waves")
	var seen := {}
	for stage in range(1, 25):
		var wave = m.pattern_for(stage, stage - 1)
		seen[(stage - 1) % 20] = true
		check(wave.size() >= 3, "each stage maps to pattern")
	check(seen.size() == 20, "all patterns used in campaign")
	var early := m.pattern_for(1, 0)
	var later := m.pattern_for(8, 0)
	check(early.all(func(beat): return beat[1] != 5), "relay character stays out of first stage")
	check(later.any(func(beat): return beat[1] == 5), "relay character joins later stages")
	for level in range(1, 15):
		check(m.pattern_for(level, 0).all(func(beat): return abs(beat[0]) == 1), "vertical enemies locked before stage 15")
	var vertical := m.pattern_for(15, 0)
	check(vertical.any(func(beat): return abs(beat[0]) == 2), "vertical enemy appears at stage 15")
	m.start(15, false, 12)
	m.enemies.append({"side": -2, "kind": 0, "remaining": 0.01, "switched": false, "armor": 0})
	check(m.attack(-2).result == "hit", "up button defeats up enemy")
	m.enemies.append({"side": 2, "kind": 0, "remaining": 0.01, "switched": false, "armor": 0})
	check(m.attack(-2).result == "wrong", "up button cannot defeat down enemy")
	check(m.attack(2).result == "hit", "down button defeats down enemy")
	m.start(8, false, 1)
	m.enemies.append({"side": -1, "kind": 5, "remaining": 0.01, "switched": false, "armor": 0, "travel": 1.0})
	check(m.attack(-1).result == "hit", "relay first character is hittable")
	check(m.enemies.size() == 1 and m.enemies[0].side == 1 and m.enemies[0].kind == 0, "relay creates a visible opposite-side follow-up")
	if not m.enemies.is_empty():
		check(m.enemies[0].remaining > m.stage_rules(8).window, "relay follow-up gives reaction time")
	m.start(24, false, 1)
	m.advance(m.duration + 1.0)
	check(m.state == "victory" and m.unlocked == 24, "final stage ends in campaign victory")
	m.start(1, true, 1)
	check(m.duration == 90.0, "survival lasts ninety seconds")
	m.elapsed = 65.0
	check(m.difficulty_stage() > 1, "survival difficulty climbs over time")
	m.start(1, true, 2)
	var wave_two: int = m.seeded_wave_index()
	m.start(1, true, 3)
	check(wave_two != m.seeded_wave_index(), "survival seed changes wave order")
	m.advance(90.01)
	check(m.state == "victory", "survival completes at ninety seconds")
	m.start(1, false, 1)
	for i in m.max_health:
		m.enemies.clear()
		m.attack(1)
	check(m.state == "defeat", "health exhaustion ends run")
	print("GAME TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
