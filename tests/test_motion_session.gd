extends SceneTree

const DraftStore := preload("res://addons/kimodo_motion/domain/motion_draft_store.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const SessionController := preload("res://addons/kimodo_motion/domain/motion_session_controller.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const TEST_DIRECTORY := "res://tests/.generated_sessions"

var _failures: Array[String] = []
var _paths: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := SessionStore.create_session("Session round trip")
	_check(not session.session_id.is_empty(), "new session has stable identity")
	SessionStore.sync_editable_intent(session, "A careful wave", 45, 77, 120, 2)
	var saved := SessionStore.save_as(session, TEST_DIRECTORY, "round_trip")
	_check(saved["ok"], "session saves atomically")
	if saved["ok"]:
		_paths.append(saved["path"])
		var stable_hash := FileAccess.get_sha256(saved["path"])
		session.schema_version = 999
		var rejected_save := SessionStore.save(session, saved["path"])
		_check(not rejected_save["ok"], "invalid session update is rejected")
		_check(FileAccess.get_sha256(saved["path"]) == stable_hash, "failed update leaves prior session byte-identical")
		session.schema_version = Session.SCHEMA_VERSION
		var opened := SessionStore.open(saved["path"])
		_check(opened["ok"], "session opens")
		if opened["ok"]:
			_check(opened["session"].prompt == "A careful wave", "intent round-trips")
			_check(opened["session"].requested_take_count == 2, "take count round-trips")

	var draft := DraftStore.create_draft()
	var draft_saved := DraftStore.save_as(draft, TEST_DIRECTORY, "legacy_draft")
	_check(draft_saved["ok"], "legacy draft fixture saves")
	if draft_saved["ok"]:
		_paths.append(draft_saved["path"])
		var original_hash := FileAccess.get_sha256(draft_saved["path"])
		var rejected_draft := SessionStore.open(draft_saved["path"])
		_check(not rejected_draft["ok"], "pre-Goal-16 draft is rejected without migration")
		_check(FileAccess.get_sha256(draft_saved["path"]) == original_hash, "legacy rejection leaves draft byte-identical")

	var legacy_session := SessionStore.create_session("Disposable v1 session")
	legacy_session.schema_version = 1
	var legacy_session_path := TEST_DIRECTORY.path_join("legacy_session.tres")
	_check(ResourceSaver.save(legacy_session, legacy_session_path) == OK, "legacy session fixture saves directly")
	_paths.append(legacy_session_path)
	var legacy_hash := FileAccess.get_sha256(legacy_session_path)
	var rejected_session := SessionStore.open(legacy_session_path)
	_check(not rejected_session["ok"], "pre-Goal-16 session is rejected without migration")
	_check(FileAccess.get_sha256(legacy_session_path) == legacy_hash, "legacy rejection leaves session byte-identical")

	var controller := SessionController.new()
	root.add_child(controller)
	await process_frame
	controller.session = session
	controller.path = saved.get("path", "")
	var save_events := [0]
	controller.save_state_changed.connect(func(state: String, _message: String) -> void:
		if state == "saved":
			save_events[0] += 1
	)
	session.notes = "autosaved"
	controller.mark_dirty()
	controller.mark_dirty()
	controller.mark_dirty()
	var deadline := Time.get_ticks_msec() + 1000
	while controller.dirty and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not controller.dirty, "debounced autosave flushes dirty state")
	_check(save_events[0] == 1, "rapid edits coalesce into one autosave")
	var autosaved := SessionStore.open(controller.path)
	_check(autosaved["ok"] and autosaved["session"].notes == "autosaved", "autosave is durable")
	var controller_path: String = controller.path
	session.notes = "shutdown flush"
	controller.mark_dirty()
	controller.queue_free()
	await process_frame
	var shutdown_saved := SessionStore.open(controller_path)
	_check(shutdown_saved["ok"] and shutdown_saved["session"].notes == "shutdown flush", "controller exit forces a final save")
	_cleanup()
	_finish()


func _cleanup() -> void:
	for path in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: KimodoSession v2 round-trip, autosave, and explicit legacy rejection")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
