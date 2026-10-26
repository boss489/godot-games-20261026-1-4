extends Control

const Game = preload("res://game_state.gd")
const Stages = preload("res://levels.gd")
const INK := Color("31483e")
const PAPER := Color("eee2c4")
const DARK := Color("193b40")
const WATER := Color("6596a2")
const GOLD := Color("c18b4e")
var levels: Array[Dictionary] = Stages.all_levels()
var state = Game.new()
var mode := "title"
var index := 0
var unlocked := 1
var hints := true
var cell := 56.0
var origin := Vector2.ZERO
var ui_font: Font
var audio: AudioStreamPlayer
var save_path := "user://island_progress.json"

func _ready() -> void:
	ui_font = load("res://fonts/NotoSansKR.ttf")
	var save := FileAccess.open(save_path, FileAccess.READ)
	if save:
		var parsed = JSON.parse_string(save.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			unlocked = clampi(int(parsed.get("unlocked", 1)), 1, levels.size())
	audio = AudioStreamPlayer.new()
	add_child(audio)
	queue_redraw()

func show_select() -> void:
	mode = "select"
	_sound(320)
	queue_redraw()

func start_level(n: int) -> void:
	if n < 0 or n >= unlocked or n >= levels.size():
		return
	index = n
	state.reset(levels[n])
	mode = "play"
	_sound(260)
	queue_redraw()

func complete_if_won() -> void:
	if state.won and mode == "play":
		mode = "win"
		unlocked = maxi(unlocked, mini(index + 2, levels.size()))
		var save := FileAccess.open(save_path, FileAccess.WRITE)
		if save:
			save.store_string(JSON.stringify({"unlocked": unlocked}))
		_sound(540)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if mode == "title":
			if k == KEY_ENTER or k == KEY_SPACE:
				show_select()
		elif mode == "select":
			if k == KEY_ESCAPE:
				mode = "title"
				queue_redraw()
			elif k == KEY_ENTER:
				start_level(unlocked - 1)
		elif mode == "win":
			if k == KEY_ENTER or k == KEY_SPACE:
				if index + 1 < levels.size():
					start_level(index + 1)
				else:
					show_select()
			elif k == KEY_ESCAPE:
				show_select()
		elif mode == "play":
			if k == KEY_ESCAPE:
				show_select()
			elif k == KEY_Z or k == KEY_BACKSPACE:
				if state.undo(): _sound(190)
			elif k == KEY_R:
				state.restart()
				_sound(210)
			elif k == KEY_H:
				hints = not hints
			elif k == KEY_SPACE or k == KEY_F:
				if state.cut(): _sound(115)
			else:
				var d := Vector2i.ZERO
				match k:
					KEY_UP, KEY_W: d = Vector2i.UP
					KEY_RIGHT, KEY_D: d = Vector2i.RIGHT
					KEY_DOWN, KEY_S: d = Vector2i.DOWN
					KEY_LEFT, KEY_A: d = Vector2i.LEFT
				if d != Vector2i.ZERO and state.move(d): _sound(270)
			complete_if_won()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if mode == "title":
			show_select()
		elif mode == "select":
			var col := int((pos.x - 147) / 144)
			var row := int((pos.y - 236) / 72)
			if col >= 0 and col < 6 and row >= 0 and row < 6:
				start_level(row * 6 + col)
		elif mode == "win":
			if index + 1 < levels.size(): start_level(index + 1)
			else: show_select()
		elif mode == "play":
			var p := Vector2i((pos - origin) / cell)
			var delta: Vector2i = p - state.player
			if abs(delta.x) + abs(delta.y) == 1:
				if state.move(delta): _sound(270)
				complete_if_won()

func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), PAPER)
	# Engraved map border and horizontal hatch strokes.
	for i in 14:
		var y := float(i) * 57.0 + 9.0
		draw_line(Vector2(0, y), Vector2(sz.x, y - 18), Color(0.64, 0.54, 0.38, 0.12), 1)
	for inset in [12.0, 18.0]:
		draw_rect(Rect2(Vector2(inset, inset), sz - Vector2.ONE * inset * 2), INK.darkened(0.05), false, 2)
	if mode == "title":
		_text("통나무 섬 배달", Vector2(226, 167), 72, DARK)
		_text("木版 海圖  /  LOG ISLAND DELIVERY", Vector2(342, 218), 20, GOLD)
		_draw_emblem(Vector2(sz.x / 2, 390))
		_text("한 그루의 길, 한 상자의 항해", Vector2(364, 555), 29, INK)
		_text("ENTER 또는 화면 클릭  ·  항해 시작", Vector2(372, 643), 24, DARK)
	elif mode == "select":
		_text("항로 지도", Vector2(83, 110), 52, DARK)
		_text("완료한 항로 다음부터 열립니다  ·  ENTER: 최근 항로  ·  ESC: 표지", Vector2(87, 156), 19, INK)
		for i in levels.size():
			var col := i % 6
			var row := i / 6
			var r := Rect2(147 + col * 144, 236 + row * 72, 126, 55)
			draw_rect(r, Color("decba5") if i < unlocked else Color("c9c4ad"))
			draw_rect(r, DARK if i < unlocked else Color("939990"), false, 2)
			_text("%02d" % (i + 1), r.position + Vector2(42, 37), 27, DARK if i < unlocked else Color("84877e"))
		_text("육지  ·  나무  ·  해협  ·  뗏목  ·  우편함", Vector2(300, 705), 19, INK)
	else:
		_draw_board()
		if mode == "win":
			var r := Rect2(304, 263, 544, 222)
			draw_rect(r, PAPER)
			draw_rect(r, DARK, false, 5)
			_text("배달 완료!", Vector2(398, 344), 54, DARK)
			_text("ENTER / 클릭: 다음 항로     ESC: 지도", Vector2(354, 428), 22, INK)

func _draw_board() -> void:
	var level: Dictionary = levels[index]
	var w: int = state.rows[0].length()
	var h: int = state.rows.size()
	cell = minf(65.0, minf(946.0 / w, 560.0 / h))
	origin = Vector2((size.x - w * cell) / 2.0, 142 + (560 - h * cell) / 2.0)
	_text(level.title, Vector2(85, 94), 43, DARK)
	_text("제 %d 장  /  %02d–36" % [level.chapter, index + 1], Vector2(820, 88), 21, GOLD)
	var reach: Array[Vector2i] = state.reachable() if hints else [] as Array[Vector2i]
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			var r := Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell)
			var terrain := state.tile(p)
			var color := Color("d9c797")
			match terrain:
				"~": color = WATER
				"#": color = Color("566d67")
				"D": color = Color("ad8457")
				"M": color = Color("e1c17f")
			draw_rect(r.grow(-1), color)
			if terrain == "~":
				for wave in 2:
					draw_arc(r.position + Vector2(cell * (0.3 + wave * 0.45), cell * 0.5), cell * 0.18, 0.1, PI - 0.1, 8, Color("aacbc3"), 1.5)
			elif terrain == "#":
				draw_line(r.position + Vector2(8, 8), r.end - Vector2(9, 9), Color("8d9c82"), 1)
			elif terrain == "D":
				for stripe in 3:
					draw_line(r.position + Vector2(6, 12 + stripe * cell / 4), r.position + Vector2(cell - 6, 12 + stripe * cell / 4), DARK, 2)
			elif terrain == "T":
				draw_circle(r.get_center(), cell * 0.32, INK)
				draw_circle(r.get_center(), cell * 0.2, Color("7e9b72"))
				draw_circle(r.get_center(), cell * 0.08, PAPER)
			elif terrain == "M":
				draw_rect(r.grow(-cell * 0.23), DARK)
				_text("✉", r.position + Vector2(cell * 0.29, cell * 0.7), int(cell * 0.35), PAPER)
			if hints and reach.has(p):
				draw_arc(r.get_center(), cell * 0.37, 0, TAU, 24, Color("fff0a0"), 2.5)
			if state.logs.has(p):
				var log_rect := r.grow(-cell * 0.18)
				draw_rect(log_rect, Color("8c5d3d"))
				draw_rect(log_rect, DARK, false, 2)
				for stripe in 3:
					draw_line(log_rect.position + Vector2(4 + stripe * 7, 3), log_rect.position + Vector2(4 + stripe * 7, log_rect.size.y - 3), Color("cba677"), 1)
			if p == state.parcel and not state.has_parcel:
				draw_rect(r.grow(-cell * 0.32), GOLD)
				draw_rect(r.grow(-cell * 0.32), DARK, false, 2)
	var center := origin + (Vector2(state.player) + Vector2(0.5, 0.5)) * cell
	draw_circle(center + Vector2(2, 3), cell * 0.25, DARK)
	draw_circle(center, cell * 0.21, Color("edcf9e"))
	draw_line(center, center + Vector2(state.facing) * cell * 0.25, DARK, 3)
	if state.has_parcel:
		draw_rect(Rect2(center + Vector2(-cell * 0.12, -cell * 0.35), Vector2.ONE * cell * 0.23), GOLD)
	_text("방향키 / WASD 이동 · SPACE 벌목 · Z 무제한 되돌리기 · R 재시작", Vector2(146, 714), 20, INK)
	_text("H 갈 수 있는 칸 표시 · ESC 항로 지도     소포: %s" % ("소지 중" if state.has_parcel else "아직 찾지 못함"), Vector2(188, 746), 17, INK)

func _draw_emblem(c: Vector2) -> void:
	for radius in [142.0, 128.0, 110.0]:
		draw_arc(c, radius, 0, TAU, 96, DARK, 3)
	draw_rect(Rect2(c + Vector2(-92, -19), Vector2(184, 38)), WATER)
	draw_rect(Rect2(c + Vector2(-69, -25), Vector2(138, 23)), Color("916444"))
	draw_circle(c + Vector2(0, -49), 32, INK)
	draw_circle(c + Vector2(0, -49), 19, PAPER)
	_text("航", c + Vector2(-22, 83), 43, DARK)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(ui_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _sound(pitch: float) -> void:
	# Short self-generated wooden/water tone: no downloaded assets.
	if not is_instance_valid(audio): return
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 22050
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	for i in 2205:
		var t := float(i) / 22050.0
		var env := pow(1.0 - float(i) / 2205.0, 2.0)
		var sample := int(2300.0 * env * (sin(TAU * pitch * t) + 0.23 * sin(TAU * pitch * 2.0 * t)))
		bytes.append(sample & 255)
		bytes.append((sample >> 8) & 255)
	wav.data = bytes
	audio.stream = wav
	audio.play()
