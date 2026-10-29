extends Control

const Model = preload("res://game_model.gd")
const DARK := Color("060e17")
const ROAD := Color("13222e")
const LIME := Color("b8ff5c")
const CYAN := Color("5ce6ff")
const GOLD := Color("ffca52")
const RED := Color("ff5c6c")
const VIOLET := Color("c99cff")
const ORANGE := Color("ff9e54")
const PANEL_BG := Color("0c1c28")
const PANEL_EDGE := Color("3b6472")
# Set to the ScoreApiUrl output only after deploying score-backend/template.yaml.
const SCORE_API_URL := "https://xwwkmrlpbbju7nla3bp5lpjxuy0mzipa.lambda-url.ap-northeast-2.on.aws/"

const ARENA_CX := 480.0
const ARENA_CY := 252.0
const HIT_DIST_X := 96.0
const TRAVEL_DIST_X := 330.0
const HIT_DIST_Y := 55.0
const TRAVEL_DIST_Y := 64.0

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
var hit_rings: Array = []
var saved_state := ""
var blink := 0.0
var strike_anim := 0.0
var strike_side := 0
var strike_result := ""
var last_touch_position := Vector2.INF
var last_touch_msec := -10000
var score_http: HTTPRequest
var nickname_input: LineEdit
var board_status := ""
var board_entries: Array = []
var board_name := "stage-01"
var board_return := "title"
var request_mode := ""

func _ready() -> void:
	if DisplayServer.get_name() != "headless" and get_window():
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	model.load_progress()
	selected_stage = model.unlocked
	font = load("res://fonts/NotoSansKR.ttf")
	audio = AudioStreamPlayer.new()
	add_child(audio)
	score_http = HTTPRequest.new()
	add_child(score_http)
	score_http.request_completed.connect(_score_response)
	nickname_input = LineEdit.new()
	nickname_input.placeholder_text = "닉네임 (2~16자)"
	nickname_input.max_length = 16
	nickname_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nickname_input.add_theme_font_override("font", font)
	nickname_input.add_theme_font_size_override("font_size", 18)
	nickname_input.add_theme_color_override("font_color", Color("eefaff"))
	nickname_input.add_theme_color_override("font_placeholder_color", Color("7ca4b5"))
	nickname_input.add_theme_color_override("caret_color", LIME)
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color("091722")
	style_normal.border_color = Color("487d8f")
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(4)
	style_normal.content_margin_left = 10
	style_normal.content_margin_right = 10
	var style_focus := style_normal.duplicate()
	style_focus.bg_color = Color("0f2433")
	style_focus.border_color = LIME
	nickname_input.add_theme_stylebox_override("normal", style_normal)
	nickname_input.add_theme_stylebox_override("focus", style_focus)
	add_child(nickname_input)
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
	var scale_factor := minf(size.x / 960.0, size.y / 600.0)
	nickname_input.visible = screen == "title" or screen == "result"
	if nickname_input.visible:
		var logical_pos := Vector2(298, 492) if screen == "title" else Vector2(128, 524)
		var logical_size := Vector2(280, 38) if screen == "title" else Vector2(246, 43)
		nickname_input.position = (size - Vector2(960, 600) * scale_factor) * 0.5 + logical_pos * scale_factor
		nickname_input.size = logical_size * scale_factor
		nickname_input.add_theme_font_size_override("font_size", clampi(int(17.0 * scale_factor), 10, 22))
	if screen == "play":
		var previous: String = model.state
		model.advance(minf(delta, 0.08))
		if model.last_event == "SWITCH!":
			_feedback("차선 변경! / SWITCH", CYAN, 0.48)
			model.last_event = ""
		if model.last_event == "MISS":
			_feedback("놓쳤습니다 / MISSED", RED, 0.65)
			_sound("wrong")
			camera_shake = 5.0
			model.last_event = ""
		if previous != model.state:
			_on_finished()
	flash = maxf(0.0, flash - delta * 2.3)
	feedback_time = maxf(0.0, feedback_time - delta)
	camera_shake = maxf(0.0, camera_shake - delta * 12.0)
	strike_anim = maxf(0.0, strike_anim - delta)
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i].life -= delta
		sparks[i].pos += sparks[i].velocity * delta
		if sparks[i].life <= 0.0:
			sparks.remove_at(i)
	for i in range(hit_rings.size() - 1, -1, -1):
		hit_rings[i].life -= delta
		if hit_rings[i].life <= 0.0:
			hit_rings.remove_at(i)
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
	board_status = "점수를 등록하려면 닉네임을 입력하세요"

func _current_board() -> String:
	return "survival" if model.survival else "stage-%02d" % model.stage

func _open_board(from_screen: String, board: String) -> void:
	board_return = from_screen
	board_name = board
	screen = "leaderboard"
	board_entries.clear()
	board_status = "점수 서버 미설정" if SCORE_API_URL.is_empty() else "점수표 불러오는 중…"
	if SCORE_API_URL.is_empty():
		return
	if score_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		score_http.cancel_request()
	request_mode = "get"
	var err := score_http.request(SCORE_API_URL + "?board=" + board)
	if err != OK:
		board_status = "점수표 연결 실패"

func _submit_score() -> void:
	var name := nickname_input.text.strip_edges()
	if name.length() < 2 or name.length() > 16:
		board_status = "닉네임은 2~16자로 입력하세요"
		return
	if SCORE_API_URL.is_empty():
		board_status = "점수 서버 미설정"
		return
	if score_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		board_status = "이전 요청 처리 중"
		return
	board_status = "점수 등록 중…"
	request_mode = "post"
	var payload := JSON.stringify({"nickname": name, "board": _current_board(), "score": model.score})
	var err := score_http.request(SCORE_API_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
	if err != OK:
		board_status = "점수 등록 실패"

func _score_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		board_status = "점수 서버 응답 실패"
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		board_status = "점수표 응답 형식 오류"
		return
	if request_mode == "post":
		board_status = "기록 등록 완료" if data.get("updated", false) else "기존 최고 기록 유지"
	else:
		var entries: Variant = data.get("entries", [])
		if not entries is Array:
			board_status = "점수표 응답 형식 오류"
			return
		board_entries = entries.slice(0, mini(entries.size(), 10))
		board_status = "아직 기록이 없습니다" if board_entries.is_empty() else ""

func _begin(stage: int, survival: bool = false) -> void:
	model.start(stage, survival, randi())
	screen = "play"
	strike_anim = 0.0
	sparks.clear()
	hit_rings.clear()
	_sound("menu")

func _impact_point(side: int) -> Vector2:
	if absi(side) == 1:
		return Vector2(ARENA_CX + float(side) * HIT_DIST_X, ARENA_CY)
	return Vector2(ARENA_CX, ARENA_CY + float(signi(side)) * HIT_DIST_Y)

func _strike(side: int) -> void:
	var previous: String = model.state
	var result: Dictionary = model.attack(side)
	strike_side = side
	strike_anim = 0.22
	strike_result = str(result.get("result", ""))
	var impact := _impact_point(side)
	match result.result:
		"hit":
			var perfect: bool = model.last_event == "PERFECT"
			var col := LIME if perfect else CYAN
			_feedback("완벽! / PERFECT" if perfect else "반격! / COUNTER", col)
			_sound("perfect" if perfect else "hit")
			camera_shake = 4.5 if perfect else 3.2
			hit_rings.append({"pos": impact, "color": col, "life": 0.28, "max_r": 46.0 if perfect else 34.0})
			for j in 14:
				var angle := float(j) * TAU / 14.0
				sparks.append({"pos": impact, "velocity": Vector2(cos(angle), sin(angle)) * randf_range(60, 175), "life": 0.32, "color": col})
		"armor":
			_feedback("장갑 파손! 다시! / AGAIN", CYAN, 0.65)
			_sound("armor")
			camera_shake = 3.0
			hit_rings.append({"pos": impact, "color": GOLD, "life": 0.26, "max_r": 36.0})
			for j in 8:
				var angle := float(j) * TAU / 8.0
				sparks.append({"pos": impact, "velocity": Vector2(cos(angle), sin(angle)) * randf_range(45, 120), "life": 0.24, "color": GOLD})
		"early":
			_feedback("너무 빨라요 / TOO EARLY", RED)
			_sound("wrong")
			camera_shake = 4.0
			hit_rings.append({"pos": impact, "color": RED, "life": 0.22, "max_r": 28.0})
		"wrong":
			_feedback("반대 방향! / WRONG SIDE", RED)
			_sound("wrong")
			camera_shake = 4.5
			hit_rings.append({"pos": impact, "color": RED, "life": 0.24, "max_r": 30.0})
	if previous != model.state:
		_on_finished()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if nickname_input.has_focus():
			return
		match event.keycode:
			KEY_A, KEY_LEFT:
				if screen == "play": _strike(-1)
			KEY_D, KEY_RIGHT:
				if screen == "play": _strike(1)
			KEY_W, KEY_UP:
				if screen == "play" and model.difficulty_stage() >= 15: _strike(-2)
			KEY_S, KEY_DOWN:
				if screen == "play" and model.difficulty_stage() >= 15: _strike(2)
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
				elif screen == "leaderboard": screen = board_return
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
		if p.x > 872 and p.y < 82:
			screen = "pause"
			_sound("menu")
			return
		if model.difficulty_stage() >= 15:
			if Rect2(280, 405, 400, 52).has_point(p): _strike(-2)
			elif Rect2(28, 459, 434, 65).has_point(p): _strike(-1)
			elif Rect2(498, 459, 434, 65).has_point(p): _strike(1)
			elif Rect2(280, 526, 400, 62).has_point(p): _strike(2)
		elif p.y > 408:
			_strike(-1 if p.x < 480 else 1)
		return
	if screen == "title":
		if p.y >= 200 and p.y < 392 and p.x > 120 and p.x < 840:
			var col := clampi(int((p.x - 125) / 120.0), 0, 5)
			var row := clampi(int((p.y - 202) / 46.0), 0, 3)
			var choice := row * 6 + col + 1
			if choice <= model.unlocked:
				selected_stage = choice
				_sound("menu")
		elif p.y > 415 and p.y < 488:
			if p.x < 480: _begin(selected_stage)
			else: _begin(1, true)
		elif p.y >= 488 and p.y < 538 and p.x > 588:
			_open_board("title", "stage-%02d" % selected_stage)
	elif screen == "pause":
		if p.y > 296 and p.y < 368:
			if p.x < 480: screen = "play"
			else: _begin(model.stage, model.survival)
		elif p.y >= 380 and p.y < 452: screen = "title"
	elif screen == "result":
		if p.y > 368 and p.y < 438:
			if p.x < 480 and model.state == "victory" and not model.survival and model.stage < 24:
				selected_stage = model.stage + 1
				_begin(selected_stage)
			else:
				_begin(model.stage, model.survival)
		elif p.y >= 452 and p.y < 516: screen = "title"
		elif p.y >= 520 and p.y < 576:
			if p.x > 620: _open_board("result", _current_board())
			elif p.x > 382: _submit_score()
	elif screen == "leaderboard":
		if p.y > 510: screen = board_return

func _draw() -> void:
	var scale_factor := minf(size.x / 960.0, size.y / 600.0)
	draw_rect(Rect2(Vector2.ZERO, size), DARK)
	var step := maxf(24.0, 48.0 * scale_factor)
	var x0 := fmod(size.x * 0.5, step)
	while x0 < size.x:
		draw_line(Vector2(x0, 0), Vector2(x0, size.y), Color("112638", 0.35), 1.0)
		x0 += step
	var y0 := fmod(size.y * 0.5, step)
	while y0 < size.y:
		draw_line(Vector2(0, y0), Vector2(size.x, y0), Color("112638", 0.35), 1.0)
		y0 += step
	draw_set_transform((size - Vector2(960, 600) * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	_draw_backdrop()
	if screen == "title": _draw_title()
	elif screen == "leaderboard": _draw_leaderboard()
	else:
		_draw_arena()
		if screen == "pause": _draw_pause()
		elif screen == "result": _draw_result()
	draw_set_transform(Vector2.ZERO)

func _text(text: String, x: float, y: float, px: int = 20, color: Color = Color.WHITE, align: int = 0) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var dx := x - width * (0.5 if align == 1 else 1.0 if align == 2 else 0.0)
	draw_string(font, Vector2(dx + 1, y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.72 * color.a))
	draw_string(font, Vector2(dx, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _panel(rect: Rect2, fill: Color = PANEL_BG, edge: Color = PANEL_EDGE, border_w: float = 2.0, header_h: float = 0.0) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), Color(0, 0, 0, 0.42))
	draw_rect(rect, fill)
	if header_h > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, header_h)), Color(edge, 0.22))
		draw_line(rect.position + Vector2(0, header_h), rect.position + Vector2(rect.size.x, header_h), Color(edge, 0.55), 1.5)
	else:
		draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, minf(8.0, rect.size.y * 0.22))), Color(1, 1, 1, 0.04))
	draw_rect(rect, edge, false, border_w)
	var c := minf(7.0, minf(rect.size.x, rect.size.y) * 0.20)
	var tl := rect.position
	var br := rect.position + rect.size
	var hi := Color(edge.lightened(0.35), 0.9)
	draw_line(tl, tl + Vector2(c, 0), hi, 2.2)
	draw_line(tl, tl + Vector2(0, c), hi, 2.2)
	draw_line(Vector2(br.x, tl.y), Vector2(br.x - c, tl.y), hi, 2.2)
	draw_line(Vector2(br.x, tl.y), Vector2(br.x, tl.y + c), hi, 2.2)
	draw_line(Vector2(tl.x, br.y), Vector2(tl.x + c, br.y), hi, 2.2)
	draw_line(Vector2(tl.x, br.y), Vector2(tl.x, br.y - c), hi, 2.2)
	draw_line(br, br - Vector2(c, 0), hi, 2.2)
	draw_line(br, br - Vector2(0, c), hi, 2.2)

func _button(rect: Rect2, text: String, color: Color = LIME, px: int = 20, subtext: String = "") -> void:
	var bg := Color("122836").lerp(color, 0.08)
	_panel(rect, bg, color, 2.0)
	draw_rect(Rect2(rect.position.x + 3, rect.position.y + 3, 5, rect.size.y - 6), Color(color, 0.78))
	var cx := rect.position.x + rect.size.x * 0.5
	if subtext.is_empty():
		_text(text, cx, rect.position.y + rect.size.y * 0.5 + px * 0.34, px, color, 1)
	else:
		_text(text, cx, rect.position.y + rect.size.y * 0.42 + px * 0.28, px, color, 1)
		_text(subtext, cx, rect.position.y + rect.size.y * 0.80, maxi(13, px - 6), Color("c4e4ef"), 1)

func _draw_arrow_icon(center: Vector2, dir: Vector2, radius: float, color: Color) -> void:
	var n := dir.normalized()
	var perp := Vector2(-n.y, n.x)
	var tip := center + n * radius
	var b1 := center - n * radius * 0.75 + perp * radius * 0.82
	var b2 := center - n * radius * 0.75 - perp * radius * 0.82
	draw_colored_polygon(PackedVector2Array([tip, b1, b2]), color)

func _draw_heart(center: Vector2, r: float, active: bool) -> void:
	var col := RED if active else Color("29414d")
	var pts := PackedVector2Array([
		center + Vector2(0, r * 0.85),
		center + Vector2(-r * 0.95, -r * 0.1),
		center + Vector2(-r * 0.55, -r * 0.75),
		center + Vector2(0, -r * 0.3),
		center + Vector2(r * 0.55, -r * 0.75),
		center + Vector2(r * 0.95, -r * 0.1)
	])
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color("ffadb6") if active else Color("496a78"), 1.6)
	if active:
		draw_circle(center + Vector2(-r * 0.32, -r * 0.25), r * 0.18, Color(1, 1, 1, 0.55))

func _draw_lock_icon(center: Vector2, col: Color) -> void:
	draw_arc(center + Vector2(0, -3), 4.5, PI, TAU, 10, col, 1.8)
	draw_rect(Rect2(center.x - 6, center.y - 3, 12, 9), col)
	draw_circle(center + Vector2(0, 1.5), 1.4, DARK)

func _draw_backdrop() -> void:
	draw_rect(Rect2(0, 0, 960, 600), DARK)
	draw_rect(Rect2(0, 0, 960, 190), Color("091826"))
	for j in 22:
		var x := float((j * 197 + 39) % 960)
		var y := float((j * 73 + 17) % 165)
		var pulse := 0.35 + 0.25 * sin(blink * 2.2 + float(j))
		draw_circle(Vector2(x, y), 1.0 + float(j % 2), Color("7cc5d9", pulse))
	for j in 10:
		var bx := 6.0 + float(j) * 96.0
		var h := 70.0 + float((j * 67 + 29) % 85)
		var by := 214.0 - h
		draw_rect(Rect2(bx, by, 78, h), Color("0b1c29"))
		draw_line(Vector2(bx, by), Vector2(bx + 78, by), Color("1f4254", 0.7), 1.5)
		for k in 3:
			var win_col := Color("5ce6ff", 0.16) if (j + k) % 2 == 0 else Color("b8ff5c", 0.14)
			draw_rect(Rect2(bx + 12 + k * 22, by + 12, 10, 14), win_col)
			if h > 105.0:
				draw_rect(Rect2(bx + 12 + k * 22, by + 36, 10, 14), win_col)
	draw_rect(Rect2(0, 404, 960, 196), Color("07131d"))
	draw_line(Vector2(0, 404), Vector2(960, 404), Color("284d5c"), 2.0)

func _draw_title() -> void:
	# Header frame (ends at y = 178 so there is plenty of space above the stage grid)
	_panel(Rect2(44, 10, 872, 168), Color("0a1a26", 0.95), Color("3c6c7c"), 2.0, 28.0)
	_text("NIGHT SIGNAL DUEL  ·  야간 교차로 전술 아케이드", 480, 30, 14, CYAN, 1)
	for sx in [156.0, 804.0]:
		_panel(Rect2(sx - 34, 46, 68, 26), Color("0d222e"), Color("487682"), 1.5)
		draw_circle(Vector2(sx - 18, 59), 6, Color(RED, 0.85))
		draw_circle(Vector2(sx, 59), 6, Color(GOLD, 0.85))
		draw_circle(Vector2(sx + 18, 59), 6, LIME)
	_text("좌우 결투 신호등", 480, 77, 39, LIME, 1)
	_text("적이 HIT 판정선에 진입해 초록불(GO)이 켜질 때 해당 방향을 눌러 반격하세요! (15구역부터 상·하 4방향)", 480, 106, 15, Color("dff3fa"), 1)

	# 6 Enemy Types Visual Guide Strip inside header
	var guide_kinds := [
		{"name": "일반", "glyph": "●", "desc": "기본 1타", "col": Model.COLORS[0]},
		{"name": "질주", "glyph": "≫", "desc": "고속 접근", "col": Model.COLORS[1]},
		{"name": "장갑", "glyph": "▣", "desc": "연속 2연타", "col": Model.COLORS[2]},
		{"name": "전환", "glyph": "⇄", "desc": "차선 변경", "col": Model.COLORS[3]},
		{"name": "그림자", "glyph": "◇", "desc": "중앙 정밀", "col": Model.COLORS[4]},
		{"name": "연계", "glyph": "↪", "desc": "반대편 후속", "col": Model.COLORS[5]}
	]
	for idx in guide_kinds.size():
		var item: Dictionary = guide_kinds[idx]
		var gx := 62.0 + float(idx) * 140.0
		var card := Rect2(gx, 117, 132, 52)
		var c: Color = item.col
		draw_rect(card, Color("0f2432"))
		draw_rect(card, Color(c, 0.72), false, 1.5)
		draw_circle(Vector2(gx + 21, 143), 12, Color(c, 0.20))
		draw_arc(Vector2(gx + 21, 143), 11, 0.0, TAU, 16, c, 2.0)
		_text(item.glyph, gx + 21, 149, 14, c, 1)
		_text(item.name, gx + 40, 140, 15, c)
		_text(item.desc, gx + 40, 160, 13, Color("cbe4ee"))

	_text("CAMPAIGN  ·  24개 교차로 구역 선택  (클리어 시 다음 구역 해금 · 15구역부터 4방향)", 480, 196, 14, CYAN, 1)

	for i in 24:
		var col := i % 6
		var row := int(i / 6.0)
		var rect := Rect2(125 + col * 120, 205 + row * 46, 108, 38)
		var available: bool = i < model.unlocked
		var active := selected_stage == i + 1
		var is_4way := (i + 1) >= 15
		var fill := Color("1f3d2b") if active else (Color("122a38") if available else Color("0b1821"))
		var edge := LIME if active else (CYAN if available else Color("28424f"))
		_panel(rect, fill, edge, 2.5 if active else 1.5)
		if available:
			var prefix_str := "▶ " if active else ""
			_text("%s%02d" % [prefix_str, i + 1], rect.position.x + (42 if is_4way else 54), rect.position.y + 26, 20, LIME if active else Color("e6f8ff"), 1)
			if is_4way:
				draw_rect(Rect2(rect.position.x + 70, rect.position.y + 9, 30, 20), Color(GOLD if active else CYAN, 0.22))
				_text("4방향", rect.position.x + 85, rect.position.y + 23, 11, GOLD if active else CYAN, 1)
		else:
			_draw_lock_icon(Vector2(rect.position.x + 36, rect.position.y + 20), Color("567987"))
			_text("%02d" % (i + 1), rect.position.x + 64, rect.position.y + 25, 16, Color("567987"), 1)

	var stage_sub := "상·하·좌·우 4방향 교차로 결투" if selected_stage >= 15 else "좌·우 2방향 신호 결투 · 클리어 시 해금"
	_button(Rect2(125, 418, 345, 64), "▶  %02d 구역 출격 (CAMPAIGN)" % selected_stage, LIME, 21, stage_sub)
	_button(Rect2(490, 418, 345, 64), "◷  90초 생존 모드 (SURVIVAL)", CYAN, 21, "최고 기록: %06d점 · 90초 지구전" % model.best_survival)

	_panel(Rect2(125, 488, 462, 46), Color("0b1c28"), Color("355e6e"), 1.5)
	_text("온라인 닉네임", 210, 517, 16, CYAN, 1)
	_button(Rect2(602, 490, 233, 42), "★  순위표 보기 / RANK", CYAN, 18)

	_panel(Rect2(64, 544, 832, 44), Color("091722"), Color("284957"), 1.5)
	_text("조작 안내   [A / ←] 왼쪽 반격   ·   [D / →] 오른쪽 반격   ·   15구역~ [W·S / ↑·↓] 상·하 반격   ·   [P / ESC] 일시정지", 480, 571, 15, Color("c4e4ef"), 1)

func _draw_leaderboard() -> void:
	_panel(Rect2(88, 28, 784, 548), Color("0a1924", 0.96), CYAN, 2.0, 92.0)
	_text("ONLINE LEADERBOARD  ·  온라인 최고 기록 순위표", 480, 62, 28, LIME, 1)
	var mode_title := "◷  90초 생존 모드 (SURVIVAL)" if board_name == "survival" else "▶  %02d 구역 교차로 (STAGE %02d)" % [int(board_name.trim_prefix("stage-")), int(board_name.trim_prefix("stage-"))]
	_text(mode_title, 480, 102, 20, CYAN, 1)

	var table_rect := Rect2(120, 134, 720, 368)
	_panel(table_rect, Color("07131c"), Color("355d6b"), 1.5, 34.0)
	_text("순위 / RANK", 185, 157, 15, Color("9ec5d4"), 1)
	_text("플레이어 닉네임 / NICKNAME", 380, 157, 15, Color("9ec5d4"), 0)
	_text("점수 / SCORE", 785, 157, 15, Color("9ec5d4"), 2)

	for i in 10:
		var ry := 172.0 + float(i) * 32.0
		var row_rect := Rect2(126, ry, 708, 29)
		if i < board_entries.size() and board_entries[i] is Dictionary:
			var row: Dictionary = board_entries[i]
			var rank_col := GOLD if i == 0 else (Color("d7e8f2") if i == 1 else (ORANGE if i == 2 else CYAN))
			draw_rect(row_rect, Color(rank_col, 0.12 if i < 3 else (0.05 if i % 2 == 0 else 0.02)))
			if i < 3:
				draw_rect(row_rect, Color(rank_col, 0.45), false, 1.2)
			var medal := "★ 01" if i == 0 else ("◆ 02" if i == 1 else ("▲ 03" if i == 2 else "   %02d" % (i + 1)))
			_text(medal, 185, ry + 21, 17, rank_col, 1)
			_text(str(row.get("nickname", "")).substr(0, 16), 300, ry + 21, 18, Color("eefaff"))
			_text("%06d 점" % int(row.get("score", 0)), 790, ry + 21, 18, LIME if i == 0 else rank_col, 2)
		else:
			draw_rect(row_rect, Color("0b1b26", 0.45 if i % 2 == 0 else 0.2))
			_text("%02d" % (i + 1), 185, ry + 20, 15, Color("436473"), 1)
			_text("—", 380, ry + 20, 15, Color("436473"))
			_text("—", 785, ry + 20, 15, Color("436473"), 2)

	if not board_status.is_empty():
		var status_rect := Rect2(250, 290, 460, 56)
		_panel(status_rect, Color("10222f", 0.96), GOLD if "중" in board_status else RED, 2.0)
		_text(board_status, 480, 325, 20, GOLD if "중" in board_status else Color("ff9aa4"), 1)

	_button(Rect2(320, 514, 320, 50), "◀  돌아가기 / BACK", CYAN, 20)

func _lane_nearest(side: int) -> float:
	var nearest := INF
	for enemy in model.enemies:
		if enemy.side == side:
			nearest = minf(nearest, float(enemy.remaining))
	return nearest

func _draw_arena() -> void:
	var shake := sin(blink * 58.0) * camera_shake
	var is_4way := model.difficulty_stage() >= 15
	var window: float = model.stage_rules(model.difficulty_stage()).window

	# Vertical Cross-Street
	var v_road := Rect2(ARENA_CX - 54, 116, 108, 262)
	draw_rect(v_road, ROAD if is_4way else Color("0d1923"))
	draw_line(Vector2(v_road.position.x, 116), Vector2(v_road.position.x, 378), Color("3c6e7d" if is_4way else "1d3442"), 2.0)
	draw_line(Vector2(v_road.end.x, 116), Vector2(v_road.end.x, 378), Color("3c6e7d" if is_4way else "1d3442"), 2.0)

	# Horizontal Main Highway
	var h_road := Rect2(0, ARENA_CY - 50, 960, 100)
	draw_rect(h_road, ROAD)
	draw_line(Vector2(0, h_road.position.y), Vector2(960, h_road.position.y), Color("3c6e7d"), 2.5)
	draw_line(Vector2(0, h_road.end.y), Vector2(960, h_road.end.y), Color("3c6e7d"), 2.5)

	# Road lane markings & directional guide chevrons
	for j in 10:
		var lx := float(j) * 98.0 + 14.0
		if absf(lx + 24.0 - ARENA_CX) > 70.0:
			draw_line(Vector2(lx, ARENA_CY), Vector2(lx + 46.0, ARENA_CY), Color("466d7a", 0.55), 3.0)
	for side in [-1, 1]:
		for step_i in 3:
			var cx := ARENA_CX + float(side) * (155.0 + float(step_i) * 85.0)
			_draw_arrow_icon(Vector2(cx, ARENA_CY), Vector2(-side, 0), 8.0, Color("5ce6ff", 0.18))

	# Crosswalk stripes near Left & Right HIT zones
	for side in [-1, 1]:
		var cw_x := ARENA_CX + float(side) * (HIT_DIST_X + 16.0)
		for s in 5:
			var sy := h_road.position.y + 7.0 + float(s) * 18.0
			draw_rect(Rect2(cw_x - 7, sy, 14, 11), Color("8cb5c2", 0.18))

	# Strike zones & Traffic Signal Pods for Left / Right
	for side in [-1, 1]:
		var target_x := ARENA_CX + float(side) * HIT_DIST_X
		var nearest := _lane_nearest(side)
		var in_win := nearest <= window and nearest >= -0.16
		var band_w := maxf(18.0, window * 76.0)
		var zone_col := LIME if in_win else CYAN
		draw_rect(Rect2(target_x - band_w * 0.5, h_road.position.y + 2, band_w, h_road.size.y - 4), Color(zone_col, 0.24 if in_win else 0.09))
		draw_line(Vector2(target_x, h_road.position.y - 4), Vector2(target_x, h_road.end.y + 4), LIME if in_win else Color(LIME, 0.8), 4.0 if in_win else 2.5)
		var tag := "◀ HIT!" if side == -1 and in_win else ("HIT! ▶" if side == 1 and in_win else "HIT")
		_text(tag, target_x + float(side) * 24.0, h_road.position.y + 18, 13, LIME if in_win else Color("a8e09e"), 1)
		_draw_signal(ARENA_CX + float(side) * 188.0, 156.0, side, false)

	# Stage 15+ Vertical Strike Lines & Signals (Non-overlapping placement)
	if is_4way:
		for s in 4:
			var sx := v_road.position.x + 10.0 + float(s) * 24.0
			draw_rect(Rect2(sx, ARENA_CY - HIT_DIST_Y - 16, 14, 7), Color("8cb5c2", 0.18))
			draw_rect(Rect2(sx, ARENA_CY + HIT_DIST_Y + 9, 14, 7), Color("8cb5c2", 0.18))
		for v_side in [-2, 2]:
			var v_dir := signi(v_side)
			var target_y := ARENA_CY + float(v_dir) * HIT_DIST_Y
			var nearest_v := _lane_nearest(v_side)
			var in_win_v := nearest_v <= window and nearest_v >= -0.16
			draw_rect(Rect2(v_road.position.x + 2, target_y - 8, v_road.size.x - 4, 16), Color(LIME if in_win_v else CYAN, 0.25 if in_win_v else 0.10))
			draw_line(Vector2(v_road.position.x - 4, target_y), Vector2(v_road.end.x + 4, target_y), LIME, 4.0 if in_win_v else 2.5)
		_text("▲ HIT", v_road.end.x + 28, ARENA_CY - HIT_DIST_Y + 4, 13, LIME, 1)
		_text("▼ HIT", v_road.position.x - 28, ARENA_CY + HIT_DIST_Y + 5, 13, LIME, 1)
		_draw_signal(ARENA_CX - 94.0, 152.0, -2, true)
		_draw_signal(ARENA_CX + 94.0, 344.0, 2, true)

	# Central intersection platform & Signal Warden character
	_draw_warden(ARENA_CX + shake, ARENA_CY, is_4way)

	# Expanding impact rings
	for ring in hit_rings:
		var progress := 1.0 - float(ring.life) / 0.28
		var rad := lerpf(10.0, float(ring.max_r), clampf(progress, 0.0, 1.0))
		draw_arc(ring.pos, rad, 0.0, TAU, 24, Color(ring.color, clampf(float(ring.life) * 3.2, 0.0, 1.0)), 3.0)

	# Enemies
	for enemy in model.enemies:
		_draw_enemy(enemy, window)

	# Sparks
	for spark in sparks:
		var scol: Color = spark.get("color", LIME)
		draw_circle(spark.pos, 3.4 * float(spark.life) / 0.32, scol)

	# Tactical Enemy Legend Strip (y = 380..402, crisp 13px text)
	_panel(Rect2(28, 380, 904, 23), Color("091722", 0.94), Color("2f5969"), 1.2)
	_text("적 유형 판독   ●일반: 1타   ·   ≫질주: 고속   ·   ▣장갑: 연속 2연타   ·   ⇄전환: 차선 변경   ·   ◇그림자: 정중앙 정밀   ·   ↪연계: 반대편 후속", 480, 396, 13, Color("cde8f2"), 1)

	# Touch & Keyboard Control Deck
	if is_4way:
		_draw_pad_button(Rect2(300, 407, 360, 48), -2, "▲  위쪽 반격", "W / ↑", CYAN, true)
		_draw_pad_button(Rect2(34, 461, 425, 61), -1, "◀  왼쪽 반격", "A / ←", CYAN, true)
		_panel(Rect2(464, 466, 32, 51), Color("0d222f"), Color("4a7b8c"), 1.5)
		_text("✚", 480, 498, 18, LIME, 1)
		_draw_pad_button(Rect2(501, 461, 425, 61), 1, "오른쪽 반격  ▶", "D / →", LIME, true)
		_draw_pad_button(Rect2(300, 528, 360, 57), 2, "▼  아래쪽 반격", "S / ↓", GOLD, true)
	else:
		_draw_pad_button(Rect2(34, 416, 425, 162), -1, "◀   왼쪽 반격", "키보드 A / ←   ·   초록불에 터치!", CYAN, false)
		_panel(Rect2(465, 446, 30, 102), Color("0c202c"), Color("3c6878"), 1.5)
		_text("⚡", 480, 504, 20, LIME, 1)
		_draw_pad_button(Rect2(501, 416, 425, 162), 1, "오른쪽 반격   ▶", "키보드 D / →   ·   초록불에 터치!", LIME, false)

	_draw_hud()

	if flash > 0.0:
		draw_rect(Rect2(0, 0, 960, 600), Color(flash_color, flash * 0.11))

func _draw_warden(cx: float, cy: float, is_4way: bool) -> void:
	draw_circle(Vector2(cx, cy), 42, Color("091a24"))
	draw_arc(Vector2(cx, cy), 40, 0.0, TAU, 28, Color(CYAN, 0.45), 2.0)
	draw_arc(Vector2(cx, cy), 31, 0.0, TAU, 24, Color(LIME, 0.35), 1.5)
	_draw_arrow_icon(Vector2(cx - 34, cy), Vector2(-1, 0), 5.0, CYAN)
	_draw_arrow_icon(Vector2(cx + 34, cy), Vector2(1, 0), 5.0, LIME)
	if is_4way:
		_draw_arrow_icon(Vector2(cx, cy - 34), Vector2(0, -1), 5.0, CYAN)
		_draw_arrow_icon(Vector2(cx, cy + 34), Vector2(0, 1), 5.0, GOLD)

	if strike_anim > 0.0:
		var alpha := clampf(strike_anim / 0.22, 0.0, 1.0)
		var scol := RED if strike_result in ["early", "wrong"] else (GOLD if strike_result == "armor" else LIME)
		var base_ang := PI if strike_side == -1 else (0.0 if strike_side == 1 else (-PI * 0.5 if strike_side == -2 else PI * 0.5))
		draw_arc(Vector2(cx, cy), 56.0, base_ang - 0.65, base_ang + 0.65, 16, Color(scol, alpha * 0.9), 7.0)
		draw_arc(Vector2(cx, cy), 70.0, base_ang - 0.50, base_ang + 0.50, 16, Color(Color.WHITE, alpha * 0.7), 3.0)

	var lunge := Vector2.ZERO
	if strike_anim > 0.0:
		lunge = Vector2(strike_side * 6.0, 0.0) if absi(strike_side) == 1 else Vector2(0.0, signi(strike_side) * 6.0)
	var px := cx + lunge.x
	var py := cy + lunge.y

	draw_rect(Rect2(px - 20, py - 8, 40, 26), Color("163847"))
	draw_rect(Rect2(px - 20, py - 8, 40, 26), CYAN, false, 1.8)
	draw_rect(Rect2(px - 12, py - 6, 24, 22), Color("0c202b"))
	draw_line(Vector2(px - 32, py + 4), Vector2(px + 32, py + 4), LIME, 5.0)
	draw_circle(Vector2(px - 32, py + 4), 4.0, CYAN)
	draw_circle(Vector2(px + 32, py + 4), 4.0, LIME)
	draw_circle(Vector2(px, py - 12), 14, Color("102a36"))
	draw_arc(Vector2(px, py - 12), 14, 0.0, TAU, 20, LIME, 2.0)
	draw_rect(Rect2(px - 9, py - 15, 18, 6), CYAN)
	_text("⚡", px, py - 26, 15, LIME, 1)

func _enemy_pos(enemy: Dictionary) -> Vector2:
	var side: int = enemy.side
	var ratio := clampf(float(enemy.remaining) / maxf(0.1, float(enemy.get("travel", 1.2))), -0.1, 1.0)
	var x := ARENA_CX + float(side) * (HIT_DIST_X + ratio * TRAVEL_DIST_X) if absi(side) == 1 else ARENA_CX
	var y := ARENA_CY if absi(side) == 1 else ARENA_CY + float(signi(side)) * (HIT_DIST_Y + ratio * TRAVEL_DIST_Y)
	return Vector2(x, y)

func _draw_enemy(enemy: Dictionary, window: float) -> void:
	var side: int = enemy.side
	var pos := _enemy_pos(enemy)
	var x := pos.x
	var y := pos.y
	var kind: int = enemy.kind
	var col: Color = Model.COLORS[kind]
	var in_win := absf(float(enemy.remaining)) <= window
	if kind == 4:
		col.a = 0.54 + sin(blink * 16.0) * 0.28

	# Ground shadow & contracting timing ring
	draw_circle(Vector2(x, y + 11), 19.0, Color(col, 0.15))
	if float(enemy.remaining) > -0.15 and float(enemy.remaining) < window * 2.6:
		var ring_r := clampf(16.0 + (float(enemy.remaining) - window) * 36.0, 15.0, 36.0)
		draw_arc(Vector2(x, y), ring_r, 0.0, TAU, 20, LIME if in_win else Color(col, 0.55), 3.0 if in_win else 1.5)

	# Special cues per enemy type
	if kind == 1:
		if absi(side) == 1:
			var trail_dir := float(side)
			for s in 3:
				var sy := y - 9.0 + float(s) * 8.0
				draw_line(Vector2(x + trail_dir * 15.0, sy), Vector2(x + trail_dir * (28.0 + float(s) * 6.0), sy), Color(col, 0.6), 2.5)
		else:
			var v_trail := float(signi(side))
			for s in 3:
				var sx := x - 9.0 + float(s) * 9.0
				draw_line(Vector2(sx, y + v_trail * 15.0), Vector2(sx, y + v_trail * 27.0), Color(col, 0.6), 2.5)
	elif kind == 3 and not enemy.switched:
		# Pulsing turn-signal indicator arrows next to Switcher
		var turn_dir := Vector2(-float(side), 0)
		var pulse_x := x + turn_dir.x * (22.0 + 4.0 * sin(blink * 12.0))
		_draw_arrow_icon(Vector2(pulse_x, y - 2), turn_dir, 6.5, CYAN)
		_text("⇄ 차선전환", x, y + 28, 12, CYAN, 1)
	elif kind == 3 and enemy.switched:
		_text("⇄ 전환됨!", x, y + 28, 12, CYAN, 1)
	elif kind == 5:
		_text("↪ 반대후속", x, y + 28, 12, ORANGE, 1)

	# Distinct body silhouette per kind
	match kind:
		0: # 일반 (Standard)
			draw_rect(Rect2(x - 11, y - 2, 22, 17), col)
			draw_circle(Vector2(x, y - 6), 13.5, col)
		1: # 질주 (Sprinter - aerodynamic winged runner for both horizontal and vertical lanes)
			var pts := PackedVector2Array([
				Vector2(x, y - 19),
				Vector2(x + 17, y + 4),
				Vector2(x + 11, y + 15),
				Vector2(x - 11, y + 15),
				Vector2(x - 17, y + 4)
			])
			draw_colored_polygon(pts, col)
			draw_circle(Vector2(x, y - 6), 12.5, col)
		2: # 장갑 (Armored - heavy juggernaut + riot shield + 2-pip gauge)
			var intact: bool = int(enemy.armor) == 0
			draw_rect(Rect2(x - 16, y - 14, 32, 29), col)
			draw_rect(Rect2(x - 16, y - 14, 32, 29), LIME if intact else RED, false, 2.5)
			var shield_x := x - float(side) * 14.0 if absi(side) == 1 else x
			if intact:
				draw_rect(Rect2(shield_x - 5, y - 12, 10, 25), Color("183440"))
				draw_rect(Rect2(shield_x - 5, y - 12, 10, 25), Color.WHITE, false, 2.0)
			draw_rect(Rect2(x - 13, y + 18, 11, 5), col if intact else Color("334c57"))
			draw_rect(Rect2(x + 2, y + 18, 11, 5), RED if not intact else col)
		3: # 차선 전환 (Switcher - diamond hull)
			var d_pts := PackedVector2Array([Vector2(x, y - 18), Vector2(x + 17, y - 2), Vector2(x, y + 15), Vector2(x - 17, y - 2)])
			draw_colored_polygon(d_pts, col)
			draw_polyline(d_pts + PackedVector2Array([d_pts[0]]), Color.WHITE, 1.5)
		4: # 그림자 (Shadow - hooded stealth cloak + inner precision diamond)
			var cloak := PackedVector2Array([Vector2(x, y - 19), Vector2(x + 16, y + 14), Vector2(x, y + 9), Vector2(x - 16, y + 14)])
			draw_colored_polygon(cloak, col)
			draw_arc(Vector2(x, y - 2), 8.5, 0.0, TAU, 4, Color.WHITE, 1.8)
			_text("정밀", x, y + 28, 12, VIOLET, 1)
		5: # 연계 (Relay - twin antenna unit)
			draw_rect(Rect2(x - 13, y - 8, 26, 22), col)
			draw_circle(Vector2(x, y - 8), 13, col)
			draw_line(Vector2(x - 8, y - 17), Vector2(x - 13, y - 25), col, 2.2)
			draw_line(Vector2(x + 8, y - 17), Vector2(x + 13, y - 25), col, 2.2)
			draw_circle(Vector2(x - 13, y - 25), 3.0, LIME)
			draw_circle(Vector2(x + 13, y - 25), 3.0, LIME)

	# Visor eyes
	draw_rect(Rect2(x - 8, y - 9, 16, 5), DARK)
	draw_circle(Vector2(x - 4, y - 6.5), 1.8, LIME if in_win else col)
	draw_circle(Vector2(x + 4, y - 6.5), 1.8, LIME if in_win else col)

	# Overhead type badge (Shape + Symbol + Korean short tag)
	var glyph: String = ["●", "≫", "▣", "⇄", "◇", "↪"][kind]
	var short_tag: String = ["일반", "질주", "장갑2타" if int(enemy.armor) == 0 else "1타더!", "전환", "그림자", "연계"][kind]
	var badge_col: Color = RED if (kind == 2 and int(enemy.armor) == 1) else col
	var badge_rect := Rect2(x - 30, y - 36, 60, 17)
	draw_rect(badge_rect, Color("08151f", 0.92))
	draw_rect(badge_rect, badge_col, false, 1.4)
	_text("%s%s" % [glyph, short_tag], x, y - 23, 12, badge_col, 1)

	if in_win:
		_text("HIT!", x, y + 10, 12, LIME, 1)

func _draw_pad_button(rect: Rect2, side: int, label: String, key_hint: String, color: Color, compact: bool) -> void:
	var window: float = model.stage_rules(model.difficulty_stage()).window
	var nearest := _lane_nearest(side)
	var ready_now := nearest <= window and nearest >= -0.16
	var just_pressed := strike_side == side and strike_anim > 0.0
	var active_col := LIME if ready_now else color
	var fill := Color("1d3f2c") if ready_now else (Color("1c3848") if just_pressed else Color("0e222f"))
	_panel(rect, fill, active_col, 3.0 if ready_now or just_pressed else 2.0)

	var dir := Vector2(-1, 0) if side == -1 else (Vector2(1, 0) if side == 1 else (Vector2(0, -1) if side == -2 else Vector2(0, 1)))
	var icon_pos := Vector2(rect.position.x + 36, rect.position.y + rect.size.y * 0.5) if side != 1 else Vector2(rect.end.x - 36, rect.position.y + rect.size.y * 0.5)
	draw_circle(icon_pos, 15.0 if compact else 22.0, Color(active_col, 0.22))
	_draw_arrow_icon(icon_pos, dir, 9.0 if compact else 14.0, active_col)

	var cx := rect.position.x + rect.size.x * 0.5
	if compact:
		var status_suffix := "  ·  지금 타격!" if ready_now else "  [%s]" % key_hint
		_text(label + status_suffix, cx, rect.position.y + rect.size.y * 0.5 + 7, 19, active_col, 1)
	else:
		_text(label, cx, rect.position.y + rect.size.y * 0.42, 28, active_col, 1)
		var sub := "★ 초록불 점등! 지금 누르세요! ★" if ready_now else key_hint
		_text(sub, cx, rect.position.y + rect.size.y * 0.74, 16, LIME if ready_now else Color("b4d8e4"), 1)

func _draw_hud() -> void:
	_panel(Rect2(24, 10, 912, 76), Color("0a1c28", 0.95), Color("3c6978"), 2.0)
	var mode_str := "SURVIVAL · 90초 생존" if model.survival else "CAMPAIGN · 구역 %02d / 24" % model.stage
	_text(mode_str, 44, 36, 19, CYAN)
	if model.difficulty_stage() >= 15:
		draw_rect(Rect2(258, 18, 72, 21), Color(GOLD, 0.22))
		draw_rect(Rect2(258, 18, 72, 21), GOLD, false, 1.3)
		_text("4방향 활성", 294, 34, 12, GOLD, 1)

	for h_idx in model.max_health:
		_draw_heart(Vector2(56 + h_idx * 30, 58), 10.5, h_idx < model.health)
	_text("HP %d/%d" % [maxi(0, model.health), model.max_health], 182, 64, 15, RED if model.health <= 1 else Color("e0f4fa"))

	_panel(Rect2(346, 17, 268, 52), Color("07141d"), Color(LIME if model.combo >= 5 else CYAN, 0.65), 1.5)
	_text("COMBO  ×%02d" % model.combo, 480, 40, 20, GOLD if model.combo >= 10 else LIME, 1)
	_text("SCORE  %06d" % model.score, 480, 62, 16, Color("dcf2fa"), 1)

	var rem_sec := int(ceil(maxf(0.0, model.duration - model.elapsed)))
	_text("남은 시간", 772, 33, 13, Color("a2c8d6"), 2)
	_text("%02d:%02d" % [rem_sec / 60, rem_sec % 60], 856, 62, 30, LIME if rem_sec > 10 else GOLD, 2)

	var pause_rect := Rect2(876, 17, 50, 52)
	_panel(pause_rect, Color("132d3b"), CYAN, 1.8)
	_text("Ⅱ", 901, 45, 20, CYAN, 1)
	_text("정지", 901, 63, 11, Color("c2e5f0"), 1)

	var bar_rect := Rect2(38, 76, 884, 5)
	draw_rect(bar_rect, Color("1e3d4a"))
	var prog := clampf(model.elapsed / maxf(1.0, model.duration), 0.0, 1.0)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * prog, bar_rect.size.y)), LIME)

	if feedback_time > 0.0:
		var fb_rect := Rect2(290, 89, 380, 26)
		_panel(fb_rect, Color("091924", 0.96), flash_color, 2.0)
		_text(feedback, 480, 108, 17, flash_color, 1)
	else:
		_text("신호등이 초록불(GO)로 켜지고 적이 HIT 판정선에 들어올 때 반격하세요!", 480, 107, 13, Color("98c2d1"), 1)

func _draw_signal(x: float, y: float, side: int, compact: bool) -> void:
	var window: float = model.stage_rules(model.difficulty_stage()).window
	var nearest := _lane_nearest(side)
	var green: bool = nearest <= window and nearest >= -0.16
	var amber: bool = not green and nearest <= window * 2.2 and nearest >= 0.0
	var box := Rect2(x - 26, y - 22, 52, 44) if compact else Rect2(x - 24, y - 34, 48, 68)
	_panel(box, Color("0b1e28"), LIME if green else (GOLD if amber else Color("466b78")), 2.0 if green else 1.5)

	if compact:
		draw_circle(Vector2(x - 10, y - 3), 6.5, Color(RED, 0.22 if green else 0.9))
		draw_circle(Vector2(x + 10, y - 3), 7.5, Color(LIME, 1.0 if green else 0.2))
		_text("GO!" if green else ("▲위" if side == -2 else "▼아래"), x, y + 16, 12, LIME if green else CYAN, 1)
	else:
		draw_circle(Vector2(x, y - 19), 7.5, Color(RED, 0.2 if (green or amber) else 0.92))
		if not green and not amber:
			draw_line(Vector2(x - 4, y - 19), Vector2(x + 4, y - 19), DARK, 2.0)
		draw_circle(Vector2(x, y - 2), 6.5, Color(GOLD, 0.95 if amber else 0.18))
		draw_circle(Vector2(x, y + 16), 8.5, Color(LIME, 1.0 if green else 0.18))
		if green:
			draw_arc(Vector2(x, y + 16), 11.5, 0.0, TAU, 16, Color(LIME, 0.65), 2.0)
		_text("GO!" if green else ("READY" if amber else "WAIT"), x, y + 31, 11, LIME if green else (GOLD if amber else Color("a6c8d4")), 1)

func _overlay() -> void:
	draw_rect(Rect2(0, 0, 960, 600), Color("030b12", 0.88))

func _draw_pause() -> void:
	_overlay()
	_panel(Rect2(140, 142, 680, 336), Color("0a1a26", 0.98), CYAN, 2.5, 68.0)
	_text("Ⅱ  일시정지  /  PAUSED", 480, 188, 34, LIME, 1)
	var status_line := "%s   ·   SCORE %06d   ·   COMBO ×%02d" % ["90초 생존" if model.survival else "%02d 구역" % model.stage, model.score, model.combo]
	_text(status_line, 480, 252, 20, CYAN, 1)
	_button(Rect2(180, 300, 280, 60), "▶  계속하기 / RESUME", LIME, 20)
	_button(Rect2(500, 300, 280, 60), "◆  재시작 / RESTART", CYAN, 20)
	_button(Rect2(320, 385, 320, 60), "◀  메인 메뉴 / MENU", Color("d2e5ec"), 20)
	_text("단축키 안내: [P / ESC / Space] 계속하기   ·   [R] 즉시 재시작", 480, 464, 14, Color("98c0cf"), 1)

func _draw_result() -> void:
	_overlay()
	var clear: bool = model.state == "victory"
	var accent := LIME if clear else RED
	_panel(Rect2(92, 118, 776, 476), Color("0a1a26", 0.98), accent, 2.5, 84.0)
	_text("★  신호 확보 / CLEAR" if clear else "✖  신호 상실 / GAME OVER", 480, 172, 36, accent, 1)
	_text("%02d 구역 교차로 (CAMPAIGN)" % model.stage if not model.survival else "90초 생존 모드 (SURVIVAL)", 480, 232, 22, CYAN, 1)

	_panel(Rect2(145, 250, 670, 56), Color("07131c"), Color("355e6e"), 1.5)
	_text("FINAL SCORE  %06d     ·     BEST COMBO  ×%02d     ·     HP  %d/%d" % [model.score, model.best_combo, maxi(0, model.health), model.max_health], 480, 285, 21, Color("e6f7fc"), 1)

	var sub_msg := "다음 구역 잠금 해제 완료! (%02d 구역 오픈)" % mini(24, model.stage + 1) if clear and not model.survival and model.stage < 24 else ("모든 캠페인 구역 제패 완료!" if clear and not model.survival else "신호 타이밍을 맞춰 다시 도전해 보세요!")
	_text(sub_msg, 480, 340, 18, LIME if clear else GOLD, 1)

	_button(Rect2(125, 371, 345, 62), "▶  다음 구역 출격" if clear and not model.survival and model.stage < 24 else "▶  다시 도전 / RETRY", LIME, 21)
	_button(Rect2(490, 371, 345, 62), "◆  현재 구역 재시작", CYAN, 21)
	_button(Rect2(320, 456, 320, 56), "◀  메인 메뉴 / MENU", Color("d2e5ec"), 20)

	_button(Rect2(390, 524, 218, 43), "▲  기록 등록", LIME, 18)
	_button(Rect2(630, 524, 220, 43), "★  순위표 보기", CYAN, 18)
	_text(board_status, 480, 586, 15, GOLD if "중" in board_status else CYAN, 1)
