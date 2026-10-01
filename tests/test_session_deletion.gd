extends SceneTree

const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Deletion := preload("res://addons/kimodo_motion/domain/session_deletion_service.gd")
const Lifecycle := preload("res://addons/kimodo_motion/domain/session_lifecycle.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Response := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const Paths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const Controller := preload("res://addons/kimodo_motion/domain/motion_session_controller.gd")
const Acceptance := preload("res://addons/kimodo_motion/domain/acceptance_service.gd")
const TEST_DIRECTORY := "res://tests/.goal21_deletion"

var failures: Array[String] = []
var receipts: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var capabilities_json := FileAccess.get_file_as_string("res://tests/fixtures/soma77_capabilities.json")
	var capabilities: RefCounted = Capabilities.parse_json_text(capabilities_json)["capabilities"]
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/soma77_mmcp_1_0.gltf")
	var document: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var extra: Dictionary = document["animations"][0].duplicate(true)
	extra["name"] = "sample_1"
	document["animations"].append(extra)
	var sample: Dictionary = document["extensions"]["MMCP_motion"]["samples"][0].duplicate(true)
	sample["name"] = "sample_1"
	document["extensions"]["MMCP_motion"]["samples"].append(sample)
	bytes = JSON.stringify(document).to_utf8_buffer()
	var motions: Array = Response.parse(bytes, 30, 30.0, capabilities.skeleton_payload)["motions"]
	var session := Store.create_session("Delete two generations")
	var saved := Store.save_as(session, TEST_DIRECTORY, "session")
	var path: String = saved["path"]
	var root_path := Archive.DATA_ROOT.path_join(session.session_id)
	receipts.append(session.session_id)
	var empty_plan := Deletion.preflight(path)
	_check(empty_plan.get("ok", false) and empty_plan.get("draft_count") == 0, "empty session preflight")
	for index in 2:
		var result := Archive.archive_generation(session, path, "{}", capabilities_json, bytes, capabilities, motions)
		_check(result["ok"], "generation %d archived" % index)
	var plan := Deletion.preflight(path)
	_check(plan.get("ok", false) and plan.get("draft_count") == 4, "counts multiple takes, not rigs or generations")
	if not plan.get("ok", false):
		printerr(plan)
		_cleanup(motions)
		return
	var initial_hash := FileAccess.get_sha256(path)
	if OS.get_name() == "Windows":
		await _check_file_lock(String(session.generation_records[0]["takes"][0]["archive_path"]), path, false)
	_check(FileAccess.get_sha256(path) == initial_hash, "preflight is read-only (cancel has no writes)")
	var duplicate := Store.save_as(session.duplicate(true), TEST_DIRECTORY, "duplicate")
	_check(Deletion.preflight(path).get("code") == "duplicate_id", "duplicate UUID rejected")
	DirAccess.remove_absolute(duplicate["path"])
	var shared := session.duplicate(true)
	shared.generation_records[1]["takes"][0]["archive_path"] = shared.generation_records[0]["takes"][0]["archive_path"]
	Store.save(shared, path)
	_check(Deletion.preflight(path).get("code") == "shared_archive", "shared archive file rejects ambiguous draft count")
	Store.save(session, path)
	var conflict := session.duplicate(true)
	conflict.artifacts["protected_export"] = {"path": session.generation_records[0]["takes"][0]["archive_path"]}
	Store.save(conflict, path)
	_check(Deletion.preflight(path).get("code") == "protected_output", "explicit output within managed storage blocks deletion")
	Store.save(session, path)
	# A manifest whose generation is absent from the index remains recoverable.
	var orphaned := session.duplicate(true)
	orphaned.generation_records.pop_back()
	orphaned.active_generation_index = 0
	orphaned.selected_take_id = orphaned.generation_records[0]["takes"][0]["take_id"]
	Store.save(orphaned, path)
	_check(Deletion.preflight(path).get("draft_count") == 4, "recoverable manifests included without index mutation")
	Store.save(session, path)
	initial_hash = FileAccess.get_sha256(path)
	var unknown_path := root_path.path_join("independent_export.res")
	ResourceSaver.save(AnimationLibrary.new(), unknown_path)
	_check(Deletion.preflight(path).get("code") == "unrecognized_data", "unknown managed files block deletion")
	DirAccess.remove_absolute(unknown_path)
	if OS.get_name() == "Windows":
		var link_path := root_path.path_join("linked")
		var outside := TEST_DIRECTORY.path_join("outside")
		DirAccess.make_dir_recursive_absolute(outside)
		var sentinel := outside.path_join("sentinel.res")
		ResourceSaver.save(AnimationLibrary.new(), sentinel)
		var command := "New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null" % [ProjectSettings.globalize_path(link_path), ProjectSettings.globalize_path(outside)]
		var output := []
		var code := OS.execute("powershell.exe", ["-NoProfile", "-Command", command], output, true)
		_check(code == 0, "Windows junction fixture created")
		if code == 0:
			_check(Deletion.preflight(path).get("code") == "linked_path", "Windows junction rejected before recursion")
			DirAccess.remove_absolute(link_path)
			_check(FileAccess.file_exists(sentinel), "junction target untouched")
	for fail_at in ["after_data", "after_session"]:
		var failed := Deletion.execute(Deletion.preflight(path), {"fail_at": fail_at})
		_check(not failed["ok"], "staging failure reported: " + fail_at)
		_check(FileAccess.get_sha256(path) == initial_hash and DirAccess.dir_exists_absolute(root_path), "staging failure restores originals")
		_check(not Lifecycle.is_retired(session.session_id), "rolled-back session is writable")
	var changed_plan := Deletion.preflight(path)
	session.notes = "Changed after the warning"
	Store.save(session, path)
	_check(Deletion.execute(changed_plan).get("code") == "stale_plan", "stale confirmation rejected")
	var take: Dictionary = session.generation_records[0]["takes"][0]
	DirAccess.remove_absolute(take["archive_path"])
	var missing_plan := Deletion.preflight(path)
	_check(missing_plan.get("draft_count") == 3 and missing_plan.get("missing_count") == 1, "missing archive counted honestly")
	var delete_take := Archive.delete_take(session, path, session.generation_records[0]["takes"][1]["take_id"])
	_check(delete_take["ok"], "one take explicitly deleted")
	var tombstone_plan := Deletion.preflight(path)
	_check(tombstone_plan.get("draft_count") == 2 and tombstone_plan.get("missing_count") == 1, "deleted takes are not counted from immutable manifests")
	# Independent outputs remain outside the managed tree.
	var output_path := TEST_DIRECTORY.path_join("saved.res")
	ResourceSaver.save(AnimationLibrary.new(), output_path)
	var output_hash := FileAccess.get_sha256(output_path)
	session.artifacts["test"] = {"path": output_path}
	Store.save(session, path)
	var interrupted := Deletion.execute(Deletion.preflight(path), {"fail_at": "interrupt_staging"})
	_check(not interrupted["ok"] and not FileAccess.file_exists(path), "interruption leaves durable staging receipt")
	Deletion.recover_pending()
	_check(FileAccess.file_exists(path) and not Lifecycle.is_retired(session.session_id), "startup restores uncommitted deletion")
	var controller := Controller.new()
	root.add_child(controller)
	controller.open(path)
	controller.mark_dirty()
	var deleted := Deletion.execute(Deletion.preflight(path), {"fail_at": "interrupt_committed"})
	_check(deleted["ok"] and deleted["cleanup_pending"], "committed interruption is retryable cleanup")
	if OS.get_name() == "Windows":
		await _check_file_lock(Lifecycle.receipt_path(session.session_id).get_base_dir().path_join("session.tres"), path, true)
	controller.detach_deleted()
	await create_timer(0.5).timeout
	_check(not FileAccess.file_exists(path), "autosave cannot resurrect deleted session")
	_check(not Store.save(session, path)["ok"], "retained resources cannot resurrect deleted session")
	# Simulate an existing production-library transaction retained by Godot undo.
	var transaction := Acceptance.AcceptanceTransaction.new()
	transaction.session = session
	transaction.session_path = path
	transaction.library_path = output_path
	transaction.before_exists = true
	transaction.before_bytes = FileAccess.get_file_as_bytes(output_path)
	transaction.after_bytes = transaction.before_bytes
	transaction.apply_before()
	transaction.apply_after()
	_check(transaction.last_result["ok"] and transaction.last_result.get("detached_session", false), "library Undo/Redo survives session deletion")
	_check(not FileAccess.file_exists(path), "old acceptance cannot resurrect deleted session")
	Deletion.recover_pending()
	_check(not DirAccess.dir_exists_absolute(root_path), "source tree removed")
	_check(FileAccess.get_sha256(output_path) == output_hash, "explicit output remains byte-identical")
	var quarantine := Lifecycle.receipt_path(session.session_id).get_base_dir()
	_check(not DirAccess.dir_exists_absolute(quarantine.path_join("data")), "restart purges committed staged data")
	var unsafe := Deletion.preflight("res://tests/../tests/session.tres")
	_check(not unsafe["ok"], "traversal path rejected")
	_check(not Paths.validate_output_file(root_path.path_join("export.res"))["ok"], "reserved export destination rejected")
	controller.queue_free()
	await process_frame
	_cleanup(motions)


func _check_file_lock(lock_path: String, session_path: String, committed: bool) -> void:
	var ready := TEST_DIRECTORY.path_join("lock_ready")
	DirAccess.remove_absolute(ready)
	var script := "$stream = [IO.File]::Open('%s', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None); [IO.File]::WriteAllText('%s', 'ready'); Start-Sleep -Seconds 20; $stream.Dispose()" % [ProjectSettings.globalize_path(lock_path), ProjectSettings.globalize_path(ready)]
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	var output := []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-Command", "(Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile','-EncodedCommand','%s' -WindowStyle Hidden -PassThru).Id" % encoded], output, true)
	var pid := String(output[0]).strip_edges().to_int() if code == 0 and not output.is_empty() else 0
	var deadline := Time.get_ticks_msec() + 4000
	while not FileAccess.file_exists(ready) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	_check(FileAccess.file_exists(ready), "Windows exclusive file lock established")
	if FileAccess.file_exists(ready):
		if committed:
			var pending := false
			for result in Deletion.recover_pending():
				pending = pending or result.get("cleanup_pending", false)
			_check(pending and not FileAccess.file_exists(session_path), "locked committed cleanup remains pending without resurrection")
		else:
			_check(Deletion.preflight(session_path).get("code") == "unreadable_file", "locked archive blocks deletion before staging")
	if pid > 0:
		OS.execute("powershell.exe", ["-NoProfile", "-Command", "Stop-Process -Id %d -ErrorAction SilentlyContinue" % pid], output, true)
	DirAccess.remove_absolute(ready)


func _cleanup(motions: Array) -> void:
	for motion in motions:
		motion.scene.free()
	for id in receipts:
		Archive._remove_tree(Archive.DATA_ROOT.path_join(id))
		Archive._remove_tree(Lifecycle.receipt_path(id).get_base_dir())
	Archive._remove_tree(TEST_DIRECTORY)
	if failures.is_empty():
		print("PASS: verified session deletion, counts, rollback/restart, preservation and no resurrection")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
