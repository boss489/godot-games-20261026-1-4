extends RefCounted

const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var rows: Array[String] = []
var logs: Dictionary = {}
var player := Vector2i.ZERO
var facing := Vector2i.DOWN
var parcel := Vector2i.ZERO
var has_parcel := false
var won := false
var history: Array[Dictionary] = []
var initial: Dictionary = {}

func reset(level: Dictionary) -> void:
	rows.clear()
	logs.clear()
	for y in level.rows.size():
		var line: String = level.rows[y]
		for x in line.length():
			if line[x] == "O":
				logs[Vector2i(x, y)] = "ground"
				line = line.substr(0, x) + "." + line.substr(x + 1)
			elif line[x] == "P":
				line = line.substr(0, x) + "." + line.substr(x + 1)
		rows.append(line)
	player = level.start
	parcel = level.parcel
	facing = Vector2i.DOWN
	has_parcel = player == parcel
	won = false
	history.clear()
	initial = snapshot()

func tile(p: Vector2i) -> String:
	if p.y < 0 or p.y >= rows.size() or p.x < 0 or p.x >= rows[p.y].length():
		return "#"
	return rows[p.y][p.x]

func snapshot() -> Dictionary:
	return {"rows": rows.duplicate(), "logs": logs.duplicate(), "player": player, "facing": facing, "parcel": parcel, "has_parcel": has_parcel, "won": won}

func restore(data: Dictionary) -> void:
	rows = data.rows.duplicate()
	logs = data.logs.duplicate()
	player = data.player
	facing = data.facing
	parcel = data.parcel
	has_parcel = data.has_parcel
	won = data.won

func undo() -> bool:
	if history.is_empty():
		return false
	restore(history.pop_back())
	return true

func restart() -> void:
	restore(initial)
	history.clear()

func _walkable(p: Vector2i) -> bool:
	var t := tile(p)
	return t == "." or t == "D" or t == "M" or (t == "~" and logs.has(p))

func move(direction: Vector2i) -> bool:
	if not DIRECTIONS.has(direction) or won:
		return false
	var before := snapshot()
	facing = direction
	var next := player + direction
	# A rider can pole a raft across water; landing does not move the raft.
	if logs.has(player) and tile(player) == "~" and tile(next) == "~" and not logs.has(next):
		history.append(before)
		logs.erase(player)
		logs[next] = "afloat"
		player = next
		return true
	if logs.has(next):
		if tile(next) == "~":
			history.append(before)
			player = next
			return true
		var beyond := next + direction
		if tile(beyond) == "#" or tile(beyond) == "T" or logs.has(beyond) or tile(beyond) == "M":
			return false
		if tile(beyond) != "~" and tile(beyond) != "." and tile(beyond) != "D":
			return false
		history.append(before)
		logs.erase(next)
		logs[beyond] = "afloat" if tile(beyond) == "~" else "ground"
		player = next if tile(next) != "~" else beyond
	elif _walkable(next):
		history.append(before)
		player = next
	else:
		return false
	if player == parcel:
		has_parcel = true
	if tile(player) == "M" and has_parcel:
		won = true
	return true

func cut() -> bool:
	if won:
		return false
	var tree := player + facing
	var landing := tree + facing
	if tile(tree) != "T" or not [".", "~", "D"].has(tile(landing)) or logs.has(landing):
		return false
	history.append(snapshot())
	var line := rows[tree.y]
	rows[tree.y] = line.substr(0, tree.x) + "." + line.substr(tree.x + 1)
	logs[landing] = "afloat" if tile(landing) == "~" else "ground"
	return true

func reachable() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		var n: Vector2i = player + d
		if logs.has(player) and tile(player) == "~" and tile(n) == "~" and not logs.has(n):
			result.append(n)
		elif logs.has(n):
			if tile(n) == "~":
				result.append(n)
				continue
			var b: Vector2i = n + d
			if [".", "~", "D"].has(tile(b)) and not logs.has(b):
				result.append(b if tile(n) == "~" else n)
		elif _walkable(n):
			result.append(n)
	return result
