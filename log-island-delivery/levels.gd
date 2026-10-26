extends RefCounted

# Six terrain glyphs: earth ., sea ~, cliff #, tree T, dock D, postbox M.
# O and P are overlays parsed into log / parcel state by game_state.gd.
static func all_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for number in 36:
		var chapter := number / 6
		var variation := number % 6
		var gap := 1 + mini(chapter / 2, 2)
		var approach := 0 if chapter < 2 else 1 + chapter / 4
		var height := 7 + (number % 3) * 2
		var width := 10 + gap + approach + (variation % 3)
		var lane := height / 2
		var shore := 4 + approach + gap
		var grid: Array[String] = []
		for y in height:
			var line := ""
			for x in width:
				var glyph := "."
				if x == 0 or y == 0 or x == width - 1 or y == height - 1:
					glyph = "#"
				elif x >= 4 + approach and x < shore:
					glyph = "~"
				elif y != lane and abs(y - lane) > 1 and ((x * 13 + y * 7 + number * 11) % 9) < 3:
					glyph = "#"
				line += glyph
			grid.append(line)
		_put_tile(grid, Vector2i(3, lane), "T")
		_put_tile(grid, Vector2i(shore, lane), "M")
		# A side pier and stranded logs create alternate planning options.
		var side := lane + (1 if number % 2 == 0 else -1)
		_put_tile(grid, Vector2i(2, side), "D")
		if number >= 6:
			_put_tile(grid, Vector2i(1, side), "O")
		if number >= 12:
			_put_tile(grid, Vector2i(shore + 2, lane + (1 if variation % 2 == 0 else -1)), "T")
		var start := Vector2i(2, lane)
		var parcel := start
		var solution: Array = []
		if number >= 6:
			parcel = Vector2i(2, side)
			solution.append(Vector2i.DOWN if side > lane else Vector2i.UP)
			solution.append(Vector2i.UP if side > lane else Vector2i.DOWN)
			solution.append(Vector2i.LEFT)
			solution.append(Vector2i.RIGHT)
		else:
			solution.append(Vector2i.LEFT)
			solution.append(Vector2i.RIGHT)
		solution.append("cut")
		for unused in gap + approach + 1:
			solution.append(Vector2i.RIGHT)
		solution.append(Vector2i.RIGHT) # disembark into the postbox
		result.append({"rows": grid, "start": start, "parcel": parcel, "solution": solution,
			"title": _title(number), "chapter": chapter + 1})
	return result

static func _put_tile(rows: Array[String], p: Vector2i, glyph: String) -> void:
	var line := rows[p.y]
	rows[p.y] = line.substr(0, p.x) + glyph + line.substr(p.x + 1)

static func _title(number: int) -> String:
	var names := ["첫 물길", "갈대 선착장", "숲의 물결", "바람 부는 해협", "긴 뗏목", "마지막 항로"]
	return "%s · %02d" % [names[number / 6], number + 1]
