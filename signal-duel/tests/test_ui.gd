extends SceneTree

var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.screen == "title", "title visible at launch")
	scene.selected_stage = 1
	scene._click(Vector2(200, 445))
	check(scene.screen == "play", "campaign button begins game")
	scene._strike(-1)
	check(scene.model.health == 3, "too early damages player")
	scene._click(Vector2(920, 40))
	check(scene.screen == "pause", "pause button")
	scene._click(Vector2(300, 330))
	check(scene.screen == "play", "resume button")
	scene.model.elapsed = scene.model.duration - 0.001
	scene.model.enemies.clear()
	scene._process(0.05)
	check(scene.screen == "result" and scene.model.state == "victory", "complete stage result")
	check(scene.model.unlocked >= 2, "stage two unlocked")
	var fresh = load("res://game_model.gd").new()
	fresh.load_progress()
	check(fresh.unlocked >= 2, "progress reloaded from disk")
	scene._click(Vector2(240, 405))
	check(scene.screen == "play" and scene.model.stage == 2, "next-stage button advances")
	scene._click(Vector2(925, 42))
	scene._click(Vector2(580, 330))
	check(scene.screen == "play" and scene.model.stage == 2 and scene.model.health == 4, "pause restart resets")
	print("UI INTEGRATION: %d failures" % errors)
	scene.audio.stop()
	await create_timer(0.25).timeout
	scene.queue_free()
	await process_frame
	quit(1 if errors else 0)
