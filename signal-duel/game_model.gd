extends RefCounted
## Pure deterministic combat state; no rendering or wall-clock dependencies.

const KIND_NAMES := ["일반", "질주", "장갑", "차선 전환", "그림자", "연계"]
const COLORS := [Color("a8fa6b"), Color("f0c45a"), Color("f37e6e"), Color("75dcec"), Color("c8a3ff"), Color("ffad6d")]
const SAVE_PATH := "user://signal_duel_progress.cfg"
# Beats: entry side (-1 left, +1 right), enemy kind, gap from preceding beat.
const PATTERNS := [
	[[-1,0,0.0],[1,0,0.8],[-1,0,0.8],[1,0,0.8]],
	[[1,0,0.0],[1,0,0.85],[-1,0,0.75],[1,0,0.85]],
	[[-1,1,0.0],[1,0,0.8],[-1,1,0.85],[1,0,0.85]],
	[[1,1,0.0],[-1,0,0.9],[1,1,0.8],[-1,0,0.9]],
	[[-1,0,0.0],[-1,0,0.7],[1,0,0.9],[1,0,0.7]],
	[[1,2,0.0],[-1,0,1.15],[1,0,0.9],[-1,1,0.8]],
	[[-1,2,0.0],[1,0,1.2],[-1,0,0.8],[1,0,0.8]],
	[[1,3,0.0],[-1,0,1.0],[1,3,0.9],[-1,0,1.0]],
	[[-1,3,0.0],[1,1,0.95],[-1,0,0.95],[1,0,0.8]],
	[[1,4,0.0],[-1,0,1.0],[1,0,0.8],[-1,4,0.95]],
	[[-1,4,0.0],[1,2,1.05],[-1,0,1.05],[1,0,0.85]],
	[[1,0,0.0],[-1,1,0.7],[1,0,0.85],[-1,2,0.85]],
	[[-1,0,0.0],[1,3,0.8],[-1,1,0.95],[1,4,0.8]],
	[[1,1,0.0],[-1,4,0.85],[1,2,0.9],[-1,0,1.05]],
	[[-1,2,0.0],[1,3,1.0],[-1,4,0.9],[1,0,0.9]],
	[[1,4,0.0],[1,0,0.9],[-1,3,0.8],[-1,1,0.9]],
	[[-1,3,0.0],[-1,0,0.85],[1,2,0.85],[1,4,1.1]],
	[[1,2,0.0],[-1,4,1.15],[1,3,0.9],[-1,1,0.85]],
	[[-1,4,0.0],[1,4,0.95],[-1,2,0.9],[1,3,1.05]],
	[[1,3,0.0],[-1,3,0.9],[1,4,0.9],[-1,2,0.95],[1,1,1.0]]
]
var patterns: Array = PATTERNS
var state := "title"
var survival := false
var stage := 1
var unlocked := 1
var best_survival := 0
var health := 4
var max_health := 4
var combo := 0
var best_combo := 0
var score := 0
var elapsed := 0.0
var duration := 25.0
var enemies: Array = []
var pending: Array = []
var wave_index := 0
var next_wave := 0.8
var seed := 1
var last_event := ""

func stage_rules(number: int) -> Dictionary:
	var n := clampi(number, 1, 24)
	return {"duration": 22.0 + float(n - 1) * 0.65, "speed": 1.0 + float(n - 1) * 0.024, "window": maxf(0.16, 0.31 - float(n - 1) * 0.004)}

func difficulty_stage() -> int:
	return mini(24, 1 + int(elapsed / 4.0)) if survival else stage

func seeded_wave_index() -> int:
	return wave_index + posmod(seed, 20) if survival else wave_index

func pattern_for(number: int, wave: int) -> Array:
	var beats: Array = patterns[posmod(number - 1 + wave * 7, patterns.size())].duplicate(true)
	if number >= 8 and wave % 3 == 0:
		for beat in beats:
			if beat[1] == 0:
				beat[1] = 5
				break
	if number >= 15 and wave % 2 == 0 and not beats.is_empty():
		# Introduce a plain vertical enemy first; later waves alternate up/down.
		beats[0][0] = -2 if wave % 4 == 0 else 2
		beats[0][1] = 0
	return beats

func start(number: int = 1, endless: bool = false, run_seed: int = 1) -> void:
	stage = clampi(number, 1, 24)
	survival = endless
	seed = run_seed
	state = "playing"
	health = max_health
	combo = 0
	best_combo = 0
	score = 0
	elapsed = 0.0
	duration = 90.0 if survival else stage_rules(stage).duration
	enemies.clear()
	pending.clear()
	wave_index = 0
	next_wave = 0.8
	last_event = ""

func _enqueue_wave() -> void:
	var level := difficulty_stage()
	var beats = pattern_for(level, seeded_wave_index())
	var at := next_wave
	for beat in beats:
		at += float(beat[2]) / stage_rules(level).speed
		pending.append({"time": at, "side": beat[0], "kind": beat[1]})
	next_wave = at + maxf(0.9, 1.8 - float(level) * 0.025)
	wave_index += 1

func advance(delta: float) -> void:
	if state != "playing" or delta <= 0.0:
		return
	elapsed += delta
	if elapsed >= duration:
		elapsed = duration
		state = "victory"
		if survival:
			best_survival = maxi(best_survival, score)
		else:
			unlocked = maxi(unlocked, mini(24, stage + 1))
		last_event = "CLEAR"
		return
	while next_wave <= elapsed + 2.5:
		_enqueue_wave()
	while not pending.is_empty() and pending[0].time <= elapsed:
		var entry: Dictionary = pending.pop_front()
		var speed: float = stage_rules(difficulty_stage()).speed
		var travel := 1.2 / speed
		if entry.kind == 1:
			travel *= 0.72
		enemies.append({"side": entry.side, "kind": entry.kind, "remaining": travel, "switched": false, "armor": 0, "travel": travel})
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		enemy.remaining -= delta
		if enemy.kind == 3 and not enemy.switched and enemy.remaining <= 0.5:
			enemy.side *= -1
			enemy.switched = true
			last_event = "SWITCH!"
		if enemy.remaining < -0.16:
			enemies.remove_at(i)
			_damage("MISS")

func _damage(reason: String) -> void:
	health -= 1
	combo = 0
	last_event = reason
	if health <= 0:
		state = "defeat"

func attack(side: int) -> Dictionary:
	if state != "playing" or not side in [-2, -1, 1, 2]:
		return {"result": "ignored"}
	var closest := -1
	var remaining := INF
	for i in enemies.size():
		if enemies[i].remaining < remaining:
			remaining = enemies[i].remaining
			closest = i
	var window: float = stage_rules(difficulty_stage()).window
	if closest < 0 or remaining > window:
		_damage("TOO EARLY")
		return {"result": "early"}
	var enemy: Dictionary = enemies[closest]
	if enemy.side != side:
		_damage("WRONG SIDE")
		return {"result": "wrong"}
	if enemy.kind == 4 and absf(remaining) > window * 0.57:
		_damage("SHADOW WINDOW")
		return {"result": "early"}
	if enemy.kind == 2 and enemy.armor == 0:
		enemy.armor = 1
		enemy.remaining = 0.19
		last_event = "ARMOR BROKEN · AGAIN!"
		return {"result": "armor"}
	enemies.remove_at(closest)
	if enemy.kind == 5:
		# Follow-up is visibly outside the hit window, on the other lane.
		var lead := maxf(0.40, window + 0.16)
		enemies.append({"side": -side, "kind": 0, "remaining": lead, "switched": false, "armor": 0, "travel": 0.8})
	combo += 1
	best_combo = maxi(combo, best_combo)
	score += 100 + mini(combo, 30) * 15
	last_event = "PERFECT" if absf(remaining) < 0.09 else "COUNTER"
	return {"result": "hit"}

func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, 24)
		best_survival = maxi(0, int(cfg.get_value("progress", "best_survival", 0)))

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "best_survival", best_survival)
	cfg.save(SAVE_PATH)
