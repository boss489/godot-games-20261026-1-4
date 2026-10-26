extends Control

const Model = preload("res://game_model.gd")
const DARK := Color("07121b")
const ROAD := Color("15232c")
const LIME := Color("c6ff69")
const CYAN := Color("76e4ed")
const RED := Color("ff6e7a")
var model = Model.new()
var font: Font
var audio: AudioStreamPlayer
var sounds := {}
var screen := "title"
var selected_stage := 1
var flash := 0.0
var flash_color := LIME
var feedback := ""
var feedback_time := 0.0
var camera_shake := 0.0
var sparks: Array = []
var saved_state := ""
var blink := 0.0
var last_touch_position := Vector2.INF
var last_touch_msec := -10000

func _ready() -> void:
	model.load_progress()
	selected_stage = model.unlocked
	font = load("res://fonts/NotoSansKR.ttf")
	audio = AudioStreamPlayer.new()
	add_child(audio)
	for key in ["hit", "perfect", "wrong", "armor", "clear", "menu"]:
		sounds[key] = _tone(key)
	set_process(true)
	queue_redraw()

func _tone(key: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var duration := 0.19 if key != "clear" else 0.42
	var count := int(22050 * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var pitch := 490.0
	match key:
		"perfect": pitch = 760.0
		"wrong": pitch = 132.0
		"armor": pitch = 235.0
		"clear": pitch = 660.0
		"menu": pitch = 390.0
	for i in count:
		var t := float(i) / 22050.0
		var envelope := pow(1.0 - float(i) / float(count), 2.0)
		var frequency := pitch * (1.0 + 0.15 * sin(t * 32.0))
		var wave := sin(TAU * frequency * t)
		if key == "wrong" or key == "armor":
			wave += 0.32 * sin(TAU * frequency * 0.43 * t)
		if key == "clear":
			wave += 0.32 * sin(TAU * frequency * 1.5 * t)
		var sample := int(clampf(wave * envelope * 6500.0, -32000.0, 32000.0))
		data.encode_s16(i * 2, sample)
	stream.data = data
	return stream

func _sound(key: String) -> void:
	audio.stream = sounds[key]
	audio.play()

func _process(delta: float) -> void:
	blink += delta
	if screen == "play":
		var previous: String = model.state
		model.advance(minf(delta, 0.08))
		if model.last_event == "SWITCH!":
			_feedback("차선 변경! / SWITCH", CYAN, 0.45)
			model.last_event = ""
		if model.last_event == "MISS":
			_feedback("놓쳤습니다 / MISSED", RED, 0.65)
			_sound("wrong")
			model.last_event = ""
		if previous != model.state:
			_on_finished()
	flash = maxf(0.0, flash - delta * 2.3)
	feedback_time = maxf(0.0, feedback_time - delta)
	camera_shake = maxf(0.0, camera_shake - delta * 12.0)
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i].life -= delta
		sparks[i].pos += sparks[i].velocity * delta
		if sparks[i].life <= 0.0:
			sparks.remove_at(i)
	queue_redraw()

func _feedback(text: String, color: Color, length: float = 0.55) -> void:
	feedback = text
	feedback_time = length
	flash = 0.32
	flash_color = color

func _on_finished() -> void:
	if model.state == "victory":
		model.save_progress()
		_sound("clear")
		_feedback("신호 확보 / CLEAR", LIME, 2.0)
	else:
		_sound("wrong")
		_feedback("신호 상실 / GAME OVER", RED, 2.0)
	screen = "result"

func _begin(stage: int, survival: bool = false) -> void:
	model.start(stage, survival, randi())
	screen = "play"
	_sound("menu")

func _strike(side: int) -> void:
	var previous: String = model.state
	var result: Dictionary = model.attack(side)
	match result.result:
		"hit":
			var perfect: bool = model.last_event == "PERFECT"
			_feedback("완벽! / PERFECT" if perfect else "반격! / COUNTER", LIME)
			_sound("perfect" if perfect else "hit")
			camera_shake = 4.0
			for j in 12:
				var angle := float(j) * TAU / 12.0
				sparks.append({"pos": Vector2(480 + side * 96, 306), "velocity": Vector2(cos(angle), sin(angle)) * randf_range(50, 160), "life": 0.3})
		"armor":
			_feedback("장갑 파손! 다시! / AGAIN", CYAN, 0.65)
			_sound("armor")
		"early":
			_feedback("너무 빨라요 / TOO EARLY", RED)
			_sound("wrong")
		"wrong":
			_feedback("반대 방향! / WRONG SIDE", RED)
			_sound("wrong")
	if previous != model.state:
		_on_finished()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT:
				if screen == "play": _strike(-1)
			KEY_D, KEY_RIGHT:
				if screen == "play": _strike(1)
			KEY_ESCAPE, KEY_P:
				if screen == "play":
					screen = "pause"
					_sound("menu")
				elif screen == "pause": screen = "play"
				else: screen = "title"
			KEY_R:
				if screen in ["play", "pause", "result"]: _begin(model.stage, model.survival)
			KEY_ENTER, KEY_SPACE:
				if screen == "title": _begin(selected_stage)
				elif screen == "result":
					if model.state == "victory" and not model.survival and model.stage < 24:
						selected_stage = model.stage + 1
						_begin(selected_stage)
					else: _begin(model.stage, model.survival)
				elif screen == "pause": screen = "play"
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() - last_touch_msec < 750 and event.position.distance_to(last_touch_position) < 32.0:
			return
		_click(_logical(event.position))
	elif event is InputEventScreenTouch:
		last_touch_position = event.position
		last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_click(_logical(event.position))

func _logical(pos: Vector2) -> Vector2:
	var scale_factor := minf(size.x / 960.0, size.y / 600.0)
	return (pos - (size - Vector2(960, 600) * scale_factor) * 0.5) / scale_factor

func _click(p: Vector2) -> void:
	if screen == "play":
		if p.y > 410:
			_strike(-1 if p.x < 480 else 1)
		elif p.x > 884 and p.y < 62:
			screen = "pause"
		return
	if screen == "title":
		if p.y >= 200 and p.y < 390 and p.x > 120 and p.x < 840:
			var col := clampi(int((p.x - 125) / 120.0), 0, 5)
			var row := clampi(int((p.y - 202) / 46.0), 0, 3)
			var choice := row * 6 + col + 1
			if choice <= model.unlocked:
				selected_stage = choice
				_sound("menu")
		elif p.y > 417 and p.y < 490:
			if p.x < 480: _begin(selected_stage)
			else: _begin(1, true)
	elif screen == "pause":
		if p.y > 300 and p.y < 365:
			if p.x < 480: screen = "play"
			else: _begin(model.stage, model.survival)
		elif p.y >= 385 and p.y < 450: screen = "title"
	elif screen == "result":
		if p.y > 370 and p.y < 435:
			if p.x < 480 and model.state == "victory" and not model.survival and model.stage < 24:
				selected_stage = model.stage + 1
				_begin(selected_stage)
			else:
				_begin(model.stage, model.survival)
		elif p.y >= 455 and p.y < 515: screen = "title"

func _draw() -> void:
	var scale_factor := minf(size.x / 960.0, size.y / 600.0)
	draw_rect(Rect2(Vector2.ZERO, size), DARK)
	draw_set_transform((size - Vector2(960, 600) * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	_draw_backdrop()
	if screen == "title": _draw_title()
	else:
		_draw_arena()
		if screen == "pause": _draw_pause()
		elif screen == "result": _draw_result()
	draw_set_transform(Vector2.ZERO)

func _text(text: String, x: float, y: float, px: int = 20, color: Color = Color.WHITE, align: int = 0) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var dx := x - width * (0.5 if align == 1 else 1.0 if align == 2 else 0.0)
	draw_string(font, Vector2(dx, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _draw_backdrop() -> void:
	draw_rect(Rect2(0, 0, 960, 600), DARK)
	for j in 18:
		var x := float((j * 197 + 39) % 960)
		var y := float((j * 83 + 17) % 210)
		draw_circle(Vector2(x, y), 1.0 + float(j % 3), Color("668991", 0.45))
	for j in 8:
		var bx := 14.0 + j * 128.0
		var h := 90.0 + float((j * 83) % 110)
		draw_rect(Rect2(bx, 295 - h, 95, h), Color("0e202b"))
		for k in 3:
			draw_rect(Rect2(bx + 15 + k * 27, 280 - h * 0.55, 9, 12), Color("80d38b", 0.15 + 0.12 * float((j+k)%2)))
	draw_rect(Rect2(0, 390, 960, 210), Color("0b1a23"))
	for j in 8:
		draw_line(Vector2(j * 130 - 40, 480), Vector2(j * 130 + 20, 480), Color("a0c99e", 0.19), 3)

func _panel(rect: Rect2, fill: Color = Color("11252d"), edge: Color = Color("537d76")) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, edge, false, 2)

func _button(rect: Rect2, text: String, color: Color = LIME, px: int = 20) -> void:
	_panel(rect, Color("193037"), color)
	_text(text, rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5 + px * 0.35, px, color, 1)

func _draw_title() -> void:
	_text("NIGHT SIGNAL  /  야간 교차로", 480, 64, 22, CYAN, 1)
	_text("좌우 결투 신호등", 480, 128, 48, LIME, 1)
	_text("신호선에 닿을 때 방향을 눌러 반격하세요", 480, 169, 19, Color("b8ccc7"), 1)
	_text("CAMPAIGN   •   24 INTERSECTIONS", 480, 196, 16, CYAN, 1)
	for i in 24:
		var col := i % 6
		var row := int(i / 6.0)
		var rect := Rect2(125 + col * 120, 205 + row * 46, 106, 37)
		var available: bool = i < model.unlocked
		var active := selected_stage == i + 1
		_panel(rect, Color("354838") if active else Color("193037") if available else Color("101e25"), LIME if active else Color("527168") if available else Color("283b42"))
		_text("%02d" % (i + 1) if available else "—", rect.position.x + 53, rect.position.y + 26, 21, LIME if available else Color("4d6971"), 1)
	_button(Rect2(125, 418, 345, 66), "▶  %02d 구역 시작" % selected_stage)
	_button(Rect2(490, 418, 345, 66), "◷  90초 생존", CYAN)
	_text("A / ←  왼쪽     D / →  오른쪽     P / ESC  일시정지", 480, 531, 17, Color("a0b9bc"), 1)
	_text("장갑: 두 번   /   전환: 차선 바뀜   /   그림자: 중앙 타이밍", 480, 562, 15, Color("8ba4a9"), 1)

func _draw_arena() -> void:
	var shake := sin(blink * 58.0) * camera_shake
	draw_rect(Rect2(0, 273, 960, 124), ROAD)
	draw_line(Vector2(0, 272), Vector2(960, 272), Color("2b5660"), 2)
	draw_line(Vector2(0, 398), Vector2(960, 398), Color("2b5660"), 2)
	for j in 11:
		draw_line(Vector2(j * 100 + 12, 337), Vector2(j * 100 + 64, 337), Color("41626a", 0.45), 3)
	for side in [-1, 1]:
		var target_x: float = 480 + side * 93
		draw_rect(Rect2(target_x - 5, 272, 10, 126), Color("c6ff69", 0.14 + 0.13 * sin(blink * 5.0)))
		draw_line(Vector2(target_x, 269), Vector2(target_x, 399), LIME, 3)
		_text("HIT", target_x, 264, 14, LIME, 1)
		_draw_signal(target_x, 190, side)
	# central fighter: coat, helmet, bright two-sided baton
	draw_circle(Vector2(480 + shake, 332), 39, Color("102c32"))
	draw_circle(Vector2(480 + shake, 332), 28, CYAN)
	draw_rect(Rect2(466 + shake, 312, 28, 38), Color("10222a"))
	draw_circle(Vector2(480 + shake, 306), 13, LIME)
	draw_line(Vector2(447 + shake, 338), Vector2(513 + shake, 338), LIME, 5)
	for enemy in model.enemies:
		var side: int = enemy.side
		var ratio := clampf(float(enemy.remaining) / maxf(0.1, float(enemy.get("travel", 1.2))), -0.1, 1.0)
		var x := 480 + side * (93 + ratio * 345)
		var kind: int = enemy.kind
		var col: Color = Model.COLORS[kind]
		var radius := 19.0 if kind != 2 else 24.0
		if kind == 4:
			col.a = 0.48 + sin(blink * 16.0) * 0.3
		draw_circle(Vector2(x, 342), radius + 8, Color(col, 0.13))
		draw_circle(Vector2(x, 326), radius, col)
		draw_rect(Rect2(x - 13, 340, 26, 30), col)
		draw_circle(Vector2(x - 6, 324), 2, DARK)
		draw_circle(Vector2(x + 6, 324), 2, DARK)
		var glyph: String = ["●", "≫", "▣", "⇄", "◇"][kind]
		_text(glyph, x, 300, 20, col, 1)
		if kind == 2 and enemy.armor == 1:
			_text("!", x, 313, 20, RED, 1)
		if absf(enemy.remaining) <= model.stage_rules(model.difficulty_stage()).window:
			draw_circle(Vector2(x, 382), 6, LIME)
	for spark in sparks:
		draw_circle(spark.pos, 3.0 * spark.life / 0.3, LIME)
	# traffic crossing sign over combatant
	_text("⚡", 480, 280, 27, LIME, 1)
	_panel(Rect2(28, 22, 904, 85), Color("0e242c"), Color("426369"))
	_text("90초 생존" if model.survival else "구역 %02d / 24" % model.stage, 48, 52, 21, CYAN)
	_text("♥ " .repeat(maxi(0, model.health)).strip_edges(), 48, 86, 25, RED)
	_text("COMBO %02d" % model.combo, 380, 55, 20, LIME)
	_text("SCORE %06d" % model.score, 380, 85, 18, Color("bbd2c4"))
	_text("%02d:%02d" % [int(ceil(model.duration - model.elapsed)) / 60, int(ceil(model.duration - model.elapsed)) % 60], 855, 66, 32, LIME, 2)
	_text("Ⅱ", 908, 55, 25, CYAN, 1)
	draw_rect(Rect2(48, 113, 864, 5), Color("29515b"))
	draw_rect(Rect2(48, 113, 864 * clampf(model.elapsed / model.duration, 0, 1), 5), LIME)
	if feedback_time > 0.0:
		_text(feedback, 480, 160, 25, flash_color, 1)
	_button(Rect2(34, 446, 425, 113), "◀   왼쪽   /   A", CYAN, 26)
	_button(Rect2(501, 446, 425, 113), "오른쪽   /   D   ▶", LIME, 26)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 960, 600), Color(flash_color, flash * 0.12))

func _draw_signal(x: float, y: float, side: int) -> void:
	_panel(Rect2(x - 18, y - 29, 36, 64), Color("10262a"), Color("4f6665"))
	var nearest := INF
	for enemy in model.enemies:
		if enemy.side == side:
			nearest = minf(nearest, enemy.remaining)
	var green: bool = nearest <= model.stage_rules(model.difficulty_stage()).window and nearest >= -0.16
	draw_circle(Vector2(x, y - 10), 9, Color("e65962", 0.2 if green else 0.9))
	draw_circle(Vector2(x, y + 15), 9, Color("baff65", 1.0 if green else 0.2))

func _overlay() -> void:
	draw_rect(Rect2(0, 0, 960, 600), Color("04121b", 0.88))

func _draw_pause() -> void:
	_overlay()
	_text("일시정지 / PAUSED", 480, 229, 42, LIME, 1)
	_button(Rect2(180, 300, 280, 60), "계속 / RESUME")
	_button(Rect2(500, 300, 280, 60), "재시작 / RESTART", CYAN)
	_button(Rect2(320, 385, 320, 60), "메뉴 / MENU", Color("bec9bd"))

func _draw_result() -> void:
	_overlay()
	var clear: bool = model.state == "victory"
	_text("신호 확보 / CLEAR" if clear else "신호 상실 / GAME OVER", 480, 190, 38, LIME if clear else RED, 1)
	_text("%02d 구역" % model.stage if not model.survival else "90초 생존", 480, 243, 25, CYAN, 1)
	_text("SCORE %06d   •   BEST COMBO %02d" % [model.score, model.best_combo], 480, 296, 23, Color("d1e0d2"), 1)
	_text("다음 구역 잠금 해제!" if clear and not model.survival and model.stage < 24 else "다시 도전하세요", 480, 337, 19, LIME if clear else RED, 1)
	_button(Rect2(125, 371, 345, 62), "다음 구역" if clear and not model.survival and model.stage < 24 else "재시작", LIME)
	_button(Rect2(490, 371, 345, 62), "재시작", CYAN)
	_button(Rect2(320, 456, 320, 58), "메뉴 / MENU", Color("bec9bd"))
