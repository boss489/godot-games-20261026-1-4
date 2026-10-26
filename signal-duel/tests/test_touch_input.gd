extends SceneTree

var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	check(not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), "touch must not generate a second mouse click")
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var pos := Vector2(180, 490)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = pos
	scene._begin(1)
	scene.model.enemies.append({"side": -1, "kind": 0, "remaining": 0.1, "switched": false, "armor": 0, "travel": 1.2})
	scene._input(touch)
	check(scene.model.health == 4 and scene.model.score == 115 and scene.model.enemies.is_empty(), "one touch scores one hit without losing health")
	var duplicate := InputEventMouseButton.new()
	duplicate.pressed = true
	duplicate.button_index = MOUSE_BUTTON_LEFT
	duplicate.position = pos
	scene._input(duplicate)
	check(scene.model.health == 4 and scene.model.score == 115 and scene.feedback != "너무 빨라요 / TOO EARLY", "mouse after scoring touch does not strike twice")
	scene._begin(1)
	scene.model.enemies.append({"side": 1, "kind": 0, "remaining": 0.1, "switched": false, "armor": 0, "travel": 1.2})
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(780, 490)
	scene._input(mouse)
	check(scene.model.health == 4 and scene.model.score == 115, "desktop mouse still scores a hit")
	scene.screen = "title"
	scene.feedback = ""
	scene.feedback_time = 0.0
	var start_pos := Vector2(180, 450)
	touch.position = start_pos
	mouse.position = start_pos
	scene._input(touch)
	check(scene.screen == "play" and scene.model.health == 4, "touch starts game without damage")
	scene._input(mouse)
	check(scene.model.health == 4 and scene.feedback != "너무 빨라요 / TOO EARLY", "same tap's mouse event must not attack on first frame")
	print("TOUCH INPUT: %d failures" % failures)
	scene.audio.stop()
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
