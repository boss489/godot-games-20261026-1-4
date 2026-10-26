extends SceneTree
const Main = preload("res://main.tscn")
func _initialize() -> void:
	var ui = Main.instantiate()
	ui.save_path = "user://island_progress_test.json"
	root.add_child.call_deferred(ui)
	await process_frame
	assert(ui.mode == "title")
	ui.show_select()
	assert(ui.mode == "select")
	ui.start_level(0)
	assert(ui.mode == "play" and ui.state.player == Vector2i(2, 3))
	for step in ui.levels[0].solution:
		if typeof(step) == TYPE_STRING:
			ui.state.cut()
		else:
			ui.state.move(step)
	ui.complete_if_won()
	assert(ui.mode == "win" and ui.unlocked >= 2)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(ui.save_path))
	assert(saved.unlocked >= 2)
	ui.start_level(1)
	assert(ui.mode == "play")
	ui.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://island_progress_test.json"))
	print("PASS: title, select, play, victory, progression and next stage")
	quit()
