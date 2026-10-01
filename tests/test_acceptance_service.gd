extends SceneTree

const Acceptance := preload("res://addons/kimodo_motion/domain/acceptance_service.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const HumanoidBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd"
)
const CharacterBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd"
)
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const HUMANOID := preload(
	"res://tests/retargeting/fixtures/godot_humanoid_a_pose.tscn"
)
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const TEST_DIRECTORY := "res://tests/.goal17_acceptance"

var _failures: Array[String] = []
var _session_data_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(TEST_DIRECTORY)
	var parsed := MotionResponse.parse(FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0)
	_check(parsed["ok"], "source motion parses")
	if not parsed["ok"]:
		_finish()
		return
	var source_motion: RefCounted = parsed["motion"]
	var target_probe := JENNY.instantiate() as Node3D
	var target_skeleton := _find_first(target_probe, "Skeleton3D") as Skeleton3D
	var session := SessionStore.create_session("Goal 17 acceptance")
	_check(SessionStore.set_target(session, JENNY_PATH, target_skeleton)["ok"], "session target records")
	target_probe.free()
	var session_save := SessionStore.save_as(session, TEST_DIRECTORY, "acceptance_session")
	_check(session_save["ok"], "acceptance session saves")
	if not session_save["ok"]:
		source_motion.scene.free()
		_finish()
		return
	var session_path: String = session_save["path"]
	_session_data_path = Archive.DATA_ROOT.path_join(session.session_id)
	var capabilities_json := FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	var capabilities_result := Capabilities.parse_json_text(capabilities_json)
	var archive_result := Archive.archive_generation(
		session,
		session_path,
		JSON.stringify({"options": {"num_samples": 1, "seed": 1234}}),
		capabilities_json,
		FileAccess.get_file_as_bytes(MOTION_FIXTURE),
		capabilities_result["capabilities"],
		[source_motion],
	)
	_check(archive_result["ok"], "source take archives before acceptance")
	if not archive_result["ok"]:
		source_motion.scene.free()
		_cleanup()
		_finish()
		return

	var humanoid_template := HUMANOID.instantiate()
	var humanoid_motion: RefCounted = HumanoidBaker.create_motion(
		source_motion.scene, humanoid_template
	)
	humanoid_template.free()
	_check(humanoid_motion != null, "source retargets to humanoid")
	var character_motion: RefCounted = CharacterBaker.create_motion(
		humanoid_motion.scene, JENNY.instantiate() as Node3D
	)
	_check(character_motion != null, "humanoid retargets to Jenny")
	var expected_animation: Animation = character_motion.player.get_animation("motion")
	var expected_hash := Acceptance.animation_hash(expected_animation)

	var new_path := TEST_DIRECTORY.path_join("production_new.res")
	var prepared := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		new_path, "friendly_wave"
	)
	_check(prepared["ok"], "new production library preflight succeeds")
	if not prepared["ok"]:
		printerr("Acceptance preflight failed: ", prepared)
		character_motion.scene.free()
		humanoid_motion.scene.free()
		source_motion.scene.free()
		_cleanup()
		_finish()
		return
	var transaction: RefCounted = prepared["transaction"]
	transaction.apply_after()
	_check(transaction.last_result["ok"], "new production library accepts")
	_check(FileAccess.file_exists(new_path), "accept creates the selected library")
	_check(ResourceLoader.get_dependencies(new_path).is_empty(), "accepted library has no fixture dependencies")
	_check(session.acceptances.size() == 1, "acceptance provenance is durable")
	_check(session.animation_destination == new_path, "session remembers destination")
	_check(_animation_hash_at(new_path, "friendly_wave") == expected_hash, "accepted animation matches preview")
	_check(
		_clean_playback_matches(new_path, "friendly_wave", expected_animation),
		"reloaded accepted animation plays identically on a clean Jenny instance",
	)
	_check(SessionStore.validate_session(session).is_empty(), "accepted session remains valid")
	var accepted_bytes := FileAccess.get_file_as_bytes(new_path)
	var accepted_record: Dictionary = prepared["record"]
	var undo_reopened := SessionStore.open(session_path)
	_check(undo_reopened["ok"], "accepted session reopens independently of retained transaction")
	var newer: Resource = undo_reopened["session"]
	newer.notes = "Newer edits must survive an old acceptance undo"
	newer.prompt = "A new prompt after reopening"
	newer.artifacts["later_export"] = {"path": new_path}
	SessionStore.save(newer, session_path)
	var later_archive := Archive.archive_generation(newer, session_path, "{}", capabilities_json, FileAccess.get_file_as_bytes(MOTION_FIXTURE), capabilities_result["capabilities"], [source_motion])
	_check(later_archive["ok"], "new generation added after session reopen")

	transaction.apply_before()
	_check(transaction.last_result["ok"], "new-library acceptance undoes")
	_check(FileAccess.file_exists(new_path), "undo retains the new production library container")
	var empty_library := ResourceLoader.load(
		new_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	_check(
		empty_library != null and empty_library.get_animation_list().is_empty(),
		"undo removes the accepted animation and leaves an empty reusable library",
	)
	_check(session.acceptances.is_empty(), "undo restores acceptance provenance absence")
	var after_old_undo := SessionStore.open(session_path)
	_check(after_old_undo["session"].notes == newer.notes and after_old_undo["session"].prompt == newer.prompt and after_old_undo["session"].artifacts.has("later_export"), "old acceptance undo preserves newer saved session fields")
	_check(after_old_undo["session"].generation_records.size() == 2, "old acceptance undo preserves newer generation history")
	transaction.apply_after()
	_check(transaction.last_result["ok"], "new-library acceptance redoes")
	_check(FileAccess.get_file_as_bytes(new_path) == accepted_bytes, "redo restores identical library bytes")
	_check(
		session.acceptances.values()[0]["acceptance_id"] == accepted_record["acceptance_id"],
		"redo restores the same acceptance identity",
	)

	var existing_path := TEST_DIRECTORY.path_join("production_existing.res")
	var existing := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 0.5
	var idle_track := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(idle_track, NodePath(".:test_value"))
	idle.track_insert_key(idle_track, 0.0, 17)
	_check(existing.add_animation("idle", idle) == OK, "existing fixture adds unrelated animation")
	_check(ResourceSaver.save(existing, existing_path) == OK, "existing production library saves")
	var existing_before := FileAccess.get_file_as_bytes(existing_path)
	var idle_hash := Acceptance.animation_hash(idle)
	var add_prepared := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		existing_path, "friendly_wave"
	)
	_check(add_prepared["ok"], "existing library Add preflight succeeds")
	var add_transaction: RefCounted = add_prepared["transaction"]
	add_transaction.apply_after()
	_check(add_transaction.last_result["ok"], "existing library Add succeeds")
	_check(_animation_hash_at(existing_path, "idle") == idle_hash, "Add preserves unrelated animation")
	_check(_animation_hash_at(existing_path, "friendly_wave") == expected_hash, "Add stores selected animation")
	var existing_after_add := FileAccess.get_file_as_bytes(existing_path)
	add_transaction.apply_before()
	_check(add_transaction.last_result["ok"], "existing library Add undoes")
	_check(FileAccess.get_file_as_bytes(existing_path) == existing_before, "Add undo restores exact prior bytes")
	add_transaction.apply_after()
	_check(add_transaction.last_result["ok"], "existing library Add redoes")
	_check(FileAccess.get_file_as_bytes(existing_path) == existing_after_add, "Add redo restores exact accepted bytes")

	var collision_hash := FileAccess.get_sha256(existing_path)
	var collision := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		existing_path, "idle"
	)
	_check(not collision["ok"] and collision["code"] == "name_collision", "collision blocks by default")
	_check(FileAccess.get_sha256(existing_path) == collision_hash, "blocked collision changes nothing")
	var replace := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		existing_path, "idle", true
	)
	_check(replace["ok"] and replace["mode"] == "replace", "explicit Replace preflight succeeds")
	var replace_transaction: RefCounted = replace["transaction"]
	var before_replace := FileAccess.get_file_as_bytes(existing_path)
	replace_transaction.apply_after()
	_check(replace_transaction.last_result["ok"], "explicit Replace succeeds")
	_check(_animation_hash_at(existing_path, "idle") == expected_hash, "Replace installs selected animation")
	var after_replace := FileAccess.get_file_as_bytes(existing_path)
	replace_transaction.apply_before()
	_check(replace_transaction.last_result["ok"], "Replace undoes")
	_check(FileAccess.get_file_as_bytes(existing_path) == before_replace, "Replace undo restores exact library")
	_check(_animation_hash_at(existing_path, "idle") == idle_hash, "Replace undo restores prior animation")
	replace_transaction.apply_after()
	_check(replace_transaction.last_result["ok"], "Replace redoes")
	_check(FileAccess.get_file_as_bytes(existing_path) == after_replace, "Replace redo restores exact library")

	for failure_step in ["do_promotion", "do_after_library", "do_session"]:
		var failure_path := TEST_DIRECTORY.path_join("failure_%s.res" % failure_step)
		var before_session_hash := FileAccess.get_sha256(session_path)
		var before_acceptances: Dictionary = session.acceptances.duplicate(true)
		var failure_prepare := Acceptance.prepare(
			session, session_path, character_motion.scene, JENNY,
			failure_path, "failure_motion", false, {"fail_at": failure_step}
		)
		_check(failure_prepare["ok"], "%s prepares" % failure_step)
		failure_prepare["transaction"].apply_after()
		_check(not failure_prepare["transaction"].last_result["ok"], "%s reports failure" % failure_step)
		_check(not FileAccess.file_exists(failure_path), "%s leaves no destination" % failure_step)
		_check(session.acceptances == before_acceptances, "%s restores acceptance state" % failure_step)
		_check(FileAccess.get_sha256(session_path) == before_session_hash, "%s leaves session file unchanged" % failure_step)
	var staging_failure := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		TEST_DIRECTORY.path_join("staging_failure.res"), "failure_motion", false,
		{"fail_at": "staging"},
	)
	_check(
		not staging_failure["ok"] and staging_failure["code"] == "injected_failure",
		"staging failure is reported before mutation",
	)
	_check(
		not FileAccess.file_exists(TEST_DIRECTORY.path_join("staging_failure.res")),
		"staging failure leaves no destination",
	)
	_check(
		not Acceptance.prepare(
			session, session_path, character_motion.scene, JENNY,
			"res://.godot/forbidden.res", "motion"
		)["ok"],
		"imported Godot data directory is rejected",
	)
	_check(
		not Acceptance.prepare(
			session, session_path, character_motion.scene, JENNY,
			TEST_DIRECTORY.path_join("invalid_name.res"), "bad/name"
		)["ok"],
		"unsafe animation name is rejected",
	)

	var undo_failure_path := TEST_DIRECTORY.path_join("undo_failure.res")
	var undo_failure := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		undo_failure_path, "undo_failure"
	)
	var undo_transaction: RefCounted = undo_failure["transaction"]
	undo_transaction.apply_after()
	var undo_after_bytes := FileAccess.get_file_as_bytes(undo_failure_path)
	var undo_after_acceptances: Dictionary = session.acceptances.duplicate(true)
	undo_transaction.test_options = {"fail_at": "undo_session"}
	undo_transaction.apply_before()
	_check(not undo_transaction.last_result["ok"], "undo failure is reported")
	_check(FileAccess.get_file_as_bytes(undo_failure_path) == undo_after_bytes, "failed undo restores library")
	_check(session.acceptances == undo_after_acceptances, "failed undo restores session state")
	undo_transaction.test_options = {}
	undo_transaction.apply_before()
	_check(undo_transaction.last_result["ok"] and FileAccess.file_exists(undo_failure_path), "undo succeeds after retry")
	var undo_empty_bytes := FileAccess.get_file_as_bytes(undo_failure_path)
	var before_failed_redo_acceptances: Dictionary = session.acceptances.duplicate(true)
	undo_transaction.test_options = {"fail_at": "redo_after_library"}
	undo_transaction.apply_after()
	_check(not undo_transaction.last_result["ok"], "redo failure is reported")
	_check(
		FileAccess.get_file_as_bytes(undo_failure_path) == undo_empty_bytes,
		"failed redo restores the empty library",
	)
	_check(session.acceptances == before_failed_redo_acceptances, "failed redo restores session state")
	undo_transaction.test_options = {}

	var delete_take_id: String = session.selected_take_id
	var delete_result := Archive.delete_take(session, session_path, delete_take_id)
	_check(delete_result["ok"], "accepted source take can be deleted")
	_check(FileAccess.file_exists(existing_path), "source deletion preserves production library")
	var deleted_source_accept := Acceptance.prepare(
		session, session_path, character_motion.scene, JENNY,
		TEST_DIRECTORY.path_join("deleted_source.res"), "cannot_accept_deleted"
	)
	_check(
		not deleted_source_accept["ok"] and deleted_source_accept["code"] == "missing_take",
		"a deleted automatic source cannot create a new acceptance",
	)
	var reopened := SessionStore.open(session_path)
	_check(reopened["ok"], "session with acceptance reopens")
	_check(reopened["session"].acceptances.size() >= 1, "acceptance provenance survives restart")
	_check(_animation_hash_at(existing_path, "idle") == expected_hash, "accepted replacement survives restart")
	_check(not _has_transaction_debris(TEST_DIRECTORY), "acceptance leaves no staging or backup debris")

	character_motion.scene.free()
	humanoid_motion.scene.free()
	source_motion.scene.free()
	_cleanup()
	_finish()


func _animation_hash_at(path: String, name: String) -> String:
	var library := ResourceLoader.load(
		path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	if library == null or not library.has_animation(name):
		return ""
	return Acceptance.animation_hash(library.get_animation(name))


func _clean_playback_matches(path: String, name: String, expected: Animation) -> bool:
	var actual_root := JENNY.instantiate() as Node3D
	var expected_root := JENNY.instantiate() as Node3D
	var actual_player := AnimationPlayer.new()
	var expected_player := AnimationPlayer.new()
	actual_root.add_child(actual_player)
	expected_root.add_child(expected_player)
	var actual_library := ResourceLoader.load(
		path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	var expected_library := AnimationLibrary.new()
	if actual_library == null or expected_library.add_animation(name, expected.duplicate(true)) != OK:
		actual_root.free()
		expected_root.free()
		return false
	if (
		actual_player.add_animation_library("accepted", actual_library) != OK
		or expected_player.add_animation_library("accepted", expected_library) != OK
	):
		actual_root.free()
		expected_root.free()
		return false
	actual_player.play("accepted/%s" % name)
	expected_player.play("accepted/%s" % name)
	var actual_skeleton := _find_first(actual_root, "Skeleton3D") as Skeleton3D
	var expected_skeleton := _find_first(expected_root, "Skeleton3D") as Skeleton3D
	var matches := actual_skeleton != null and expected_skeleton != null
	for sample_time in [0.0, expected.length * 0.5, expected.length]:
		actual_player.seek(sample_time, true)
		expected_player.seek(sample_time, true)
		if not matches:
			break
		for bone_index in actual_skeleton.get_bone_count():
			var bone_name := actual_skeleton.get_bone_name(bone_index)
			var expected_index := expected_skeleton.find_bone(bone_name)
			if expected_index < 0:
				matches = false
				break
			var actual_pose := actual_skeleton.get_bone_pose(bone_index)
			var expected_pose := expected_skeleton.get_bone_pose(expected_index)
			if (
				not actual_pose.origin.is_equal_approx(expected_pose.origin)
				or actual_pose.basis.get_rotation_quaternion().angle_to(
					expected_pose.basis.get_rotation_quaternion()
				) > 0.001
				or not actual_pose.basis.get_scale().is_equal_approx(expected_pose.basis.get_scale())
			):
				matches = false
				break
		if not matches:
			break
	actual_root.free()
	expected_root.free()
	return matches


func _has_transaction_debris(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for filename in directory.get_files():
		if ".accept-" in filename or ".accepting-" in filename:
			return true
	for child in directory.get_directories():
		if _has_transaction_debris(path.path_join(child)):
			return true
	return false


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _cleanup() -> void:
	_remove_tree(TEST_DIRECTORY)
	_remove_tree(_session_data_path)


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(filename))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: production-library Add, Replace, undo, redo, rollback, and independence")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
