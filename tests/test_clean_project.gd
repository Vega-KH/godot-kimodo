extends SceneTree

# This harness is copied into a new project. It must not preload test fixtures,
# repository-generated scenes, pre-existing profiles or source response files.
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const PreviewPanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const CHARACTER := "res://models/character.glb"

var failures: Array[String] = []
var capture_directory := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var capture_index := arguments.find("--capture-dir")
	if capture_index >= 0 and capture_index + 1 < arguments.size():
		capture_directory = arguments[capture_index + 1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var offline := arguments.has("--offline")
	var character_hash := FileAccess.get_sha256(CHARACTER)
	var client := Client.new()
	var generation := Generation.new()
	generation.timeout_seconds = 240.0
	root.add_child(client)
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var session_path := ""
	if offline:
		for entry in Store.list_sessions():
			if entry["title"] == "Clean install live smoke":
				session_path = entry["path"]
		_check(not session_path.is_empty(), "live smoke session exists for offline restart")
		dock._open_session_path(session_path)
		_check(dock._draft != null and dock._rig_profile != null, "fresh process reopens session/profile without connecting")
		if dock._draft == null:
			_finish(dock, client, generation)
			return
		_check(dock._draft.generation_records.size() == 2, "one/two-take generations survived restart")
		var record: Dictionary = dock._draft.generation_records.back()
		dock._on_history_take_activated(dock._draft.generation_records.size() - 1, record["takes"][1]["take_id"])
		_check(dock._character_preview.has_motion(), "offline history rebuilds character preview")
	else:
		dock._session_title_edit.text = "Clean install live smoke"
		dock._on_new_session_pressed()
		session_path = dock._draft_path
		dock._on_character_target_changed(load(CHARACTER))
		dock._rig_setup_panel.save_button.emit_signal("pressed")
		_check(dock._rig_profile != null and not dock._draft.rig_profile_path.is_empty(), "new imported character has reviewed saved rig profile")
		if dock._rig_profile == null:
			printerr(dock._character_status.text)
			_finish(dock, client, generation)
			return
		(dock.find_child("ConnectionAction", true, false) as Button).emit_signal("pressed")
		await _wait(client, Client.ConnectionState.CONNECTING, 40.0)
		_check(client.state == Client.ConnectionState.READY, "clean add-on connects to live backend")
		if client.state != Client.ConnectionState.READY:
			printerr(client.message)
			_finish(dock, client, generation)
			return
		for count in [1, 2]:
			dock._prompt_edit.text = "A person celebrates with a cheerful dance."
			dock._duration_edit.value = 30
			dock._diffusion_steps_edit.value = 100
			dock._take_count_edit.value = count
			var started := Time.get_ticks_msec()
			dock._on_generate_pressed()
			await _wait(generation, Generation.GenerationState.GENERATING, 250.0)
			_check(generation.state == Generation.GenerationState.READY, "live generation succeeds for %d takes" % count)
			_check(dock._take_set.size() == count and dock._character_preview.has_motion(), "live batch archives and retargets all %d takes" % count)
			print("CLEAN LIVE: takes=%d steps=100 frames=30 elapsed=%.2fs" % [count, (Time.get_ticks_msec() - started) / 1000.0])
			if generation.state != Generation.GenerationState.READY:
				printerr(generation.message)
				_finish(dock, client, generation)
				return
		var first: RefCounted = dock._take_set.at(0)
		var second: RefCounted = dock._take_set.at(1)
		_check(first.content_sha256 != second.content_sha256, "two live takes differ")
		dock._preview_panel.take_selection.select(1)
		dock._preview_panel.take_selection.emit_signal("item_selected", 1)
		_check(dock._take_set.active_index == 1, "preview switches selected take")
		for pair in [[PreviewPanel.SaveKind.CHARACTER_ANIMATION, "character.res"], [PreviewPanel.SaveKind.HUMANOID_ANIMATION, "humanoid.res"], [PreviewPanel.SaveKind.SOMA77_ANIMATION, "soma77.res"], [PreviewPanel.SaveKind.CHARACTER_PREVIEW, "preview.tscn"]]:
			var path := "res://exports/" + String(pair[1])
			dock._preview_panel.submit_save_path(pair[0], path)
			_check(FileAccess.file_exists(path), "clean export " + path)
		dock._on_accept_requested("res://exports/production.res", "dance", false)
		_check(FileAccess.file_exists("res://exports/production.res"), "clean production acceptance")
		dock._fallback_undo_redo.undo()
		dock._fallback_undo_redo.redo()
		var accepted := load("res://exports/production.res") as AnimationLibrary
		_check(accepted != null and accepted.has_animation("dance"), "clean production Undo/Redo")
	dock._workspace_tabs.current_tab = dock._preview_panel.get_index()
	for width in [360, 680]:
		root.size = Vector2i(width, 1100)
		for frame in 5:
			await process_frame
		var viewport: Control = dock._character_preview
		_check(absf(viewport.size.x - viewport.size.y) < 2.0, "square preview at dock width %d (%s)" % [width, viewport.size])
		_check(absf(dock._preview_panel.preview_frame.size.y - viewport.size.y) < 2.0, "square frame reserves its viewport height")
		_check(dock._preview_panel.preview_selection.position.y >= dock._preview_panel.preview_frame.position.y + viewport.size.y, "controls below viewport without overlap")
		_check(dock._preview_panel.save_button.is_visible_in_tree(), "save controls remain present at width %d" % width)
		_check(viewport.get_global_rect().end.x <= root.size.x, "viewport fits the narrow project window")
		_check(dock._preview_panel.save_button.get_global_rect().end.x <= root.size.x, "Save button not clipped horizontally")
		if not capture_directory.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_directory.path_join("clean_preview_%d.png" % width))
	var fresh_preview := load("res://exports/preview.tscn") as PackedScene
	_check(fresh_preview != null, "saved Character Preview reloads independently")
	if fresh_preview != null:
		var instance := fresh_preview.instantiate()
		root.add_child(instance)
		await process_frame
		var player := instance.get_node_or_null("KimodoAnimationPlayer") as AnimationPlayer
		_check(player != null and player.has_animation("motion"), "fresh preview has playable animation")
		instance.queue_free()
	await _validate_fresh_character_library(dock)
	_check(FileAccess.get_sha256(CHARACTER) == character_hash, "imported model not modified")
	print("CLEAN PROJECT SESSION: ", session_path)
	_finish(dock, client, generation)


func _validate_fresh_character_library(dock: Control) -> void:
	var character := (load(CHARACTER) as PackedScene).instantiate()
	var player := AnimationPlayer.new()
	character.add_child(player)
	player.root_node = NodePath("..")
	var library := load("res://exports/character.res") as AnimationLibrary
	_check(library != null and library.has_animation("motion"), "character animation library reloads")
	if library == null:
		character.free()
		return
	player.add_animation_library("", library)
	root.add_child(character)
	await process_frame
	player.play("motion")
	player.seek(0.5, true)
	player.pause()
	var probe := character.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var expected: Skeleton3D = dock._character_preview.skeleton()
	dock._preview_panel.source_preview.set_playing(false)
	dock._preview_panel.humanoid_preview.set_playing(false)
	dock._preview_panel.character_preview.set_playing(false)
	dock._preview_panel.seek_all(0.5)
	for bone in probe.get_bone_count():
		_check(probe.get_bone_pose_rotation(bone).is_equal_approx(expected.get_bone_pose_rotation(bone)), "fresh character library rotation matches selected take: " + String(probe.get_bone_name(bone)))
		_check(probe.get_bone_pose_position(bone).is_equal_approx(expected.get_bone_pose_position(bone)), "fresh character library position matches selected take")
	character.queue_free()


func _wait(client: Node, busy: int, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while client.state == busy and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(dock: Control, client: Node, generation: Node) -> void:
	dock.queue_free()
	client.queue_free()
	generation.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: clean add-on install, character/profile, live/offline history, exports, Accept and responsive preview")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)
