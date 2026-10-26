extends SceneTree

const Game = preload("res://game_state.gd")
const Levels = preload("res://levels.gd")
var checks := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL: ", message)
		quit(1)

func _initialize() -> void:
	var s = Game.new()
	s.reset({"rows": ["#######", "#.T~M.#", "#######"], "start": Vector2i(1, 1), "parcel": Vector2i(1, 1)})
	expect(s.has_parcel, "parcel starts collected")
	expect(not s.move(Vector2i.RIGHT), "tree blocks walking")
	expect(s.cut(), "tree fells in facing direction")
	expect(s.logs.has(Vector2i(3, 1)), "fallen log bridges water")
	expect(s.logs[Vector2i(3, 1)] == "afloat", "log becomes floating on water")
	expect(s.tile(Vector2i(2, 1)) == ".", "stump becomes ground")
	expect(s.move(Vector2i.RIGHT), "walk through stump")
	expect(s.move(Vector2i.RIGHT), "walk onto bridge")
	expect(s.move(Vector2i.RIGHT) and s.won, "delivery requires mailbox")
	expect(s.undo() and not s.won, "undo reverses delivery")
	s.restart()
	expect(s.player == Vector2i(1, 1) and s.logs.is_empty(), "restart resets level")

	s.reset({"rows": ["########", "#..O~~M#", "########"], "start": Vector2i(2, 1), "parcel": Vector2i(2, 1)})
	expect(s.move(Vector2i.RIGHT), "push log onto water")
	expect(s.logs.has(Vector2i(4, 1)), "pushed log position")
	expect(s.logs[Vector2i(4, 1)] == "afloat", "ground log transitions to floating")
	expect(s.move(Vector2i.RIGHT), "board raft")
	expect(s.move(Vector2i.RIGHT) and s.player == Vector2i(5, 1), "raft rolls with rider")
	expect(s.move(Vector2i.RIGHT) and s.won, "raft reaches island")
	expect(s.undo() and s.player == Vector2i(5, 1), "undo raft arrival")

	s.reset({"rows": ["########", "#..T~~M#", "#P.###.#", "########"], "start": Vector2i(2, 1), "parcel": Vector2i(1, 2)})
	expect(not s.has_parcel, "parcel can be separate")
	expect(not s.cut(), "tree cannot fall without facing it")
	expect(s.move(Vector2i.LEFT), "visit west")
	expect(s.move(Vector2i.DOWN) and s.has_parcel, "pickup parcel")
	expect(s.undo() and not s.has_parcel, "undo pickup")

	var levels = Levels.all_levels()
	expect(levels.size() == 36, "36 stages")
	s.reset(levels[12])
	s.move(Vector2i.LEFT)
	s.move(Vector2i.RIGHT)
	expect(s.cut() and s.logs[Vector2i(4, s.player.y)] == "ground", "late chapters fell tree onto land before water")
	var signatures := {}
	for i in levels.size():
		var level: Dictionary = levels[i]
		var signature: String = "|".join(level.rows)
		expect(not signatures.has(signature), "stage %d has unique layout" % (i + 1))
		signatures[signature] = true
		s.reset(level)
		for step in level.solution:
			if typeof(step) == TYPE_STRING:
				expect(s.cut(), "stage %d cut valid" % (i + 1))
			else:
				expect(s.move(step), "stage %d move valid: %s" % [i + 1, step])
		expect(s.won, "stage %d solvable replay" % (i + 1))
		for j in level.solution.size():
			expect(s.undo(), "stage %d undo history" % (i + 1))
		expect(not s.won and s.player == level.start, "stage %d exact rewind" % (i + 1))
	print("PASS: %d assertions, 36 distinct stages solved and rewound" % checks)
	quit()
