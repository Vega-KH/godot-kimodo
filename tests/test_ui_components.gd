extends SceneTree

const GenerationPanel := preload(
	"res://addons/kimodo_motion/ui/generation_take_panel.gd"
)
const PreviewPanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const HistoryPanel := preload("res://addons/kimodo_motion/ui/history_panel.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const MotionResponse := preload(
	"res://addons/kimodo_motion/transport/mmcp_motion_response.gd"
)
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var generation := GenerationPanel.new()
	root.add_child(generation)
	await process_frame
	_check(generation.prompt_edit.get_parent() == generation, "generation panel owns its form")
	generation.set_connection_details("connection diagnostic")
	generation.technical_details_button.emit_signal("pressed")
	_check(generation.technical_details.visible, "generation panel owns detail expansion")
	generation.set_intent_editable(false)
	_check(not generation.prompt_edit.editable, "generation panel owns input locking")

	var preview := PreviewPanel.new()
	root.add_child(preview)
	await process_frame
	var motions: Array[RefCounted] = [_parse_motion(), _parse_motion()]
	_check(preview.replace_takes(motions), "preview panel accepts in-memory takes")
	_check(preview.take_selection.item_count == 2, "preview panel owns take selection")
	preview.seek_all(0.4)
	preview.loop_toggle.button_pressed = false
	preview.loop_toggle.emit_signal("toggled", false)
	preview.follow_root_toggle.button_pressed = false
	preview.follow_root_toggle.emit_signal("toggled", false)
	preview._on_camera_view_changed(0.25, 0.15, 4.0)
	var activated := [-1]
	preview.take_activated.connect(func(index: int) -> void: activated[0] = index)
	preview.take_selection.select(1)
	preview.take_selection.emit_signal("item_selected", 1)
	_check(activated[0] == 1 and preview.active_index() == 1, "preview panel owns take switching")
	_check(absf(preview.source_preview.current_position() - 0.4) < 0.001, "take switch preserves time")
	_check(not preview.source_preview.camera_follows_root(), "take switch preserves root following")
	_check(preview.source_preview.camera_view()["distance"] == 4.0, "take switch preserves camera")
	_check(
		preview.source_preview.animation_player().get_animation("sample_0").loop_mode
		== Animation.LOOP_NONE,
		"take switch preserves looping",
	)

	preview.set_save_availability(true, false, false, false)
	preview.save_kind.select(PreviewPanel.SaveKind.SOMA77_ANIMATION)
	preview.save_kind.emit_signal("item_selected", PreviewPanel.SaveKind.SOMA77_ANIMATION)
	_check(not preview.save_button.disabled, "save state follows the selected output type")
	var selected_save := [-1, ""]
	preview.save_path_selected.connect(func(kind: int, path: String) -> void:
		selected_save[0] = kind
		selected_save[1] = path
	)
	preview.submit_save_path(PreviewPanel.SaveKind.SOMA77_ANIMATION, "res://tests/take.res")
	_check(
		selected_save == [PreviewPanel.SaveKind.SOMA77_ANIMATION, "res://tests/take.res"],
		"preview panel emits one typed save-path request",
	)
	preview.set_accept_destination("res://tests/production.res")
	preview.set_accept_availability(true, false)
	_check(not preview.accept_button.disabled, "Accept enables for character motion and a destination")
	var accepted := ["", "", false]
	preview.accept_requested.connect(func(path: String, name: String, replace: bool) -> void:
		accepted.assign([path, name, replace])
	)
	preview.accept_name.text = "friendly_wave"
	preview.accept_button.emit_signal("pressed")
	_check(
		accepted == ["res://tests/production.res", "friendly_wave", false],
		"preview panel emits one typed acceptance request",
	)
	preview.accept_library_mode.select(1)
	preview.accept_library_mode.emit_signal("item_selected", 1)
	_check(
		preview.accept_destination.is_empty() and preview.accept_button.disabled,
		"changing existing/new destination mode requires a fresh file choice",
	)
	preview.confirm_replace("res://tests/production.res", "friendly_wave")
	preview.replace_dialog.emit_signal("confirmed")
	preview.replace_dialog.hide()
	_check(accepted[2], "preview panel emits explicit Replace only after confirmation")

	var history := HistoryPanel.new()
	root.add_child(history)
	await process_frame
	var session := Session.create_new("History component")
	session.generation_records.assign([{
		"record_id": "record",
		"prompt": "A careful wave",
		"generated_at_utc": "2026-09-26T23:45:00Z",
		"takes": [{
			"take_id": "record:0",
			"sample_name": "sample_0",
			"availability": "available",
		}],
	}])
	history.set_session(session)
	var generation_item := history.tree.get_root().get_first_child()
	var take_item := generation_item.get_first_child()
	take_item.select(0)
	var opened := [""]
	history.take_activated.connect(func(_generation_index: int, take_id: String) -> void:
		opened[0] = take_id
	)
	history.open_button.emit_signal("pressed")
	_check(opened[0] == "record:0", "history panel emits selected durable take")
	var deleted := [""]
	history.delete_confirmed.connect(func(take_id: String) -> void: deleted[0] = take_id)
	history._request_delete()
	history._confirm_delete()
	_check(deleted[0] == "record:0", "history panel confirms explicit source deletion")

	preview.clear_takes()
	generation.queue_free()
	preview.queue_free()
	history.queue_free()
	await process_frame
	_check(root.get_child_count() == 0, "focused UI components clean up their nodes")
	_finish()


func _parse_motion() -> RefCounted:
	var parsed := MotionResponse.parse(
		FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0
	)
	_check(parsed["ok"], "motion fixture parses")
	return parsed["motion"] if parsed["ok"] else null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: focused generation, preview/save, and history component ownership")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
