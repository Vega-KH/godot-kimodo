@tool
class_name KimodoTakeArchiveService
extends RefCounted

const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const RigSnapshot := preload("res://addons/kimodo_motion/domain/soma77_rig_snapshot.gd")
const Manifest := preload("res://addons/kimodo_motion/domain/generation_archive_manifest.gd")
const NativeAnimationBaker := preload(
	"res://addons/kimodo_motion/animation/native_animation_baker.gd"
)

const DATA_ROOT := "res://animations/kimodo/session_data"
const ANIMATION_NAME := &"motion"


class ArchivedMotion extends RefCounted:
	var scene: Node
	var animation_name: StringName = ANIMATION_NAME
	var sample_index := 0
	var content_sha256 := ""
	var duration_seconds := 0.0


static func archive_generation(
	session: Resource,
	session_path: String,
	request_json: String,
	capabilities_json: String,
	response_bytes: PackedByteArray,
	capabilities: RefCounted,
	motions: Array,
	test_options: Dictionary = {},
) -> Dictionary:
	if session == null or not session is Session or session.schema_version != Session.SCHEMA_VERSION:
		return _error("invalid_session", "A current Kimodo session is required for archival.")
	if request_json.is_empty() or capabilities_json.is_empty() or response_bytes.is_empty():
		return _error("missing_provenance", "Validated generation provenance is incomplete.")
	if capabilities == null or motions.is_empty():
		return _error("missing_generation", "The validated generation has no takes.")
	var session_validation := ProjectPaths.validate_file(session_path, "tres")
	if not session_validation["ok"]:
		return session_validation

	var source_skeleton := _find_first(motions[0].scene, "Skeleton3D") as Skeleton3D
	var snapshot := RigSnapshot.capture(source_skeleton)
	if snapshot == null:
		return _error("invalid_rig", "The generated source rig could not be archived.")
	for motion in motions:
		var candidate := RigSnapshot.capture(_find_first(motion.scene, "Skeleton3D") as Skeleton3D)
		if candidate == null or candidate.signature != snapshot.signature:
			return _error("mixed_rigs", "All takes in one generation must use the same SOMA rig.")

	var record_id := Session.create_uuid()
	var session_root := DATA_ROOT.path_join(session.session_id)
	var rigs_directory := session_root.path_join("rigs")
	var generations_directory := session_root.path_join("generations")
	for directory in [rigs_directory, generations_directory]:
		var directory_result := ProjectPaths.ensure_directory(directory)
		if not directory_result["ok"]:
			return directory_result
	var token := Session.create_uuid().replace("-", "")
	var staging_directory := generations_directory.path_join(".staging-%s-%s" % [record_id, token])
	var staging_result := ProjectPaths.ensure_directory(staging_directory)
	if not staging_result["ok"]:
		return staging_result
	var final_directory := generations_directory.path_join(record_id)
	var rig_path := rigs_directory.path_join(snapshot.signature + ".tres")
	var rig_created := false
	var promoted := false

	var rig_result := _ensure_rig_snapshot(snapshot, rig_path, token)
	if not rig_result["ok"]:
		_remove_tree(staging_directory)
		return rig_result
	rig_created = rig_result["created"]
	if test_options.get("fail_at", "") == "rig":
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, false)
		return _error("injected_failure", "Injected archive failure after rig persistence.")

	var request_payload: Variant = JSON.parse_string(request_json)
	var request_options: Dictionary = (
		request_payload.get("options", {}) if request_payload is Dictionary else {}
	)
	var take_summaries: Array[Dictionary] = []
	for index in motions.size():
		var motion: RefCounted = motions[index]
		var library := NativeAnimationBaker.create_library(motion.scene)
		if library == null:
			_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
			return _error("archive_failed", "Take %d could not be converted for archival." % (index + 1))
		var staged_path := staging_directory.path_join("take_%02d.res" % (index + 1))
		var final_path := final_directory.path_join("take_%02d.res" % (index + 1))
		var expected_archive_hash := _hash_animation(library.get_animation(ANIMATION_NAME))
		if ResourceSaver.save(library, staged_path) != OK:
			_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
			return _error("archive_failed", "Godot could not stage take %d." % (index + 1))
		var verified := _verify_library(staged_path, expected_archive_hash)
		if not verified["ok"]:
			_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
			return verified
		take_summaries.append({
			"take_id": "%s:%d" % [record_id, index],
			"sample_index": index,
			"sample_name": String(motion.animation_name),
			"content_sha256": motion.content_sha256,
			"archive_content_sha256": expected_archive_hash,
			"archive_file_sha256": FileAccess.get_sha256(staged_path),
			"archive_size_bytes": FileAccess.get_file_as_bytes(staged_path).size(),
			"archive_path": final_path,
			"rig_snapshot_path": rig_path,
			"rig_signature": snapshot.signature,
			"source_contract_id": snapshot.contract_id,
			"source_contract_version": snapshot.contract_version,
			"source_rig_schema_version": snapshot.schema_version,
			"duration_seconds": motion.duration_seconds,
			"payload_status": "archived",
			"availability": "available",
		})
		if test_options.get("fail_at", "") == "take_%d" % index:
			_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
			return _error("injected_failure", "Injected archive failure after take %d." % (index + 1))

	var record := {
		"record_id": record_id,
		"generated_at_utc": Session.utc_now(),
		"prompt": session.prompt,
		"request_json": request_json,
		"request_sha256": _sha256_text(request_json),
		"request_seed": int(request_options.get("seed", session.seed)),
		"requested_take_count": int(request_options.get("num_samples", motions.size())),
		"capabilities_json": capabilities_json,
		"capabilities_sha256": _sha256_text(capabilities_json),
		"response_sha256": _sha256_bytes(response_bytes),
		"protocol_version": capabilities.protocol_version,
		"model_id": capabilities.model_id,
		"fps": capabilities.fps,
		"skeleton_signature": _sha256_text(_canonical_json(capabilities.skeleton_payload)),
		"source_rig_signature": snapshot.signature,
		"rig_snapshot_path": rig_path,
		"target_scene_path": session.target_scene_path,
		"target_skeleton_signature": session.target_skeleton_signature,
		"takes": take_summaries,
	}
	var manifest := Manifest.new()
	manifest.session_id = session.session_id
	manifest.record_id = record_id
	manifest.rig_snapshot_path = rig_path
	manifest.rig_signature = snapshot.signature
	manifest.generation_record = record.duplicate(true)
	var manifest_path := staging_directory.path_join("generation.tres")
	if ResourceSaver.save(manifest, manifest_path) != OK:
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
		return _error("archive_failed", "Godot could not stage the generation manifest.")
	var loaded_manifest := ResourceLoader.load(
		manifest_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE
	) as Resource
	if loaded_manifest == null or not loaded_manifest is Manifest or not loaded_manifest.validation_error().is_empty():
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
		return _error("archive_failed", "The staged generation manifest did not validate.")
	if test_options.get("fail_at", "") == "manifest":
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
		return _error("injected_failure", "Injected archive failure after manifest staging.")

	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(staging_directory),
		ProjectSettings.globalize_path(final_directory),
	) != OK:
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
		return _error("archive_failed", "Godot could not promote the complete take batch.")
	promoted = true
	if test_options.get("simulate_crash_after_promotion", false):
		return _error("simulated_crash", "A complete orphan generation was left for recovery.")

	var old_records: Array[Dictionary] = session.generation_records.duplicate(true)
	var old_active: int = session.active_generation_index
	var old_selected: String = session.selected_take_id
	var old_updated: String = session.updated_at_utc
	session.generation_records.append(record.duplicate(true))
	session.active_generation_index = session.generation_records.size() - 1
	session.selected_take_id = take_summaries[0]["take_id"]
	session.touch()
	var save_result := (
		_error("injected_failure", "Injected session save failure.")
		if test_options.get("fail_at", "") == "session_save"
		else _atomic_save_session(session, session_path)
	)
	if not save_result["ok"]:
		session.generation_records.assign(old_records)
		session.active_generation_index = old_active
		session.selected_take_id = old_selected
		session.updated_at_utc = old_updated
		session.take_over_path(session_path)
		_cleanup_failed(staging_directory, final_directory, rig_path, rig_created, promoted)
		return save_result
	return {"ok": true, "record": record.duplicate(true), "rig_created": rig_created}


static func recover_orphans(session: Resource, session_path: String) -> Dictionary:
	if session == null or not session is Session:
		return _error("invalid_session", "Cannot recover archives without a session.")
	_recover_pending_deletions(session)
	var generations_directory := DATA_ROOT.path_join(session.session_id).path_join("generations")
	var directory_validation := ProjectPaths.validate_directory(generations_directory)
	if not directory_validation["ok"] or not DirAccess.dir_exists_absolute(directory_validation["absolute_path"]):
		return {"ok": true, "recovered": 0}
	var known := {}
	for record in session.generation_records:
		known[String(record.get("record_id", ""))] = true
	var directory := DirAccess.open(generations_directory)
	if directory == null:
		return _error("recovery_failed", "Session archive storage could not be inspected.")
	var recovered := 0
	for child in directory.get_directories():
		if child.begins_with(".staging-"):
			_remove_tree(generations_directory.path_join(child))
			continue
		if known.has(child):
			continue
		var manifest_path := generations_directory.path_join(child).path_join("generation.tres")
		var result := _load_verified_manifest(manifest_path, session.session_id)
		if not result["ok"]:
			return result
		var record: Dictionary = result["record"]
		session.generation_records.append(record.duplicate(true))
		session.active_generation_index = session.generation_records.size() - 1
		session.selected_take_id = record["takes"][0]["take_id"]
		recovered += 1
	if recovered > 0:
		session.touch()
		var save_result := _atomic_save_session(session, session_path)
		if not save_result["ok"]:
			return save_result
	return {"ok": true, "recovered": recovered}


static func load_motion(take: Dictionary) -> Dictionary:
	if take.get("availability", "") != "available":
		return _error("unavailable_take", "The selected source take is not available.")
	var archive_path := String(take.get("archive_path", ""))
	var relative := archive_path.trim_prefix(DATA_ROOT + "/")
	var owner_id := relative.get_slice("/", 0)
	if relative == archive_path or owner_id.is_empty() or not paths_belong_to_session(owner_id, take):
		return _error("unsafe_path", "The selected source archive is outside session storage.")
	var library_path := String(take.get("archive_path", ""))
	var rig_path := String(take.get("rig_snapshot_path", ""))
	for path in [library_path, rig_path]:
		var validation := ProjectPaths.validate_file(path)
		if not validation["ok"] or not FileAccess.file_exists(validation["path"]):
			return _error("missing_take", "The selected source archive is missing.", path)
	if FileAccess.get_sha256(library_path) != take.get("archive_file_sha256", ""):
		return _error("corrupt_take", "The selected source archive failed its file hash.")
	var snapshot := ResourceLoader.load(rig_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if snapshot == null or not snapshot is RigSnapshot or not snapshot.validation_error().is_empty():
		return _error("corrupt_rig", "The selected source rig snapshot is invalid.")
	if snapshot.signature != take.get("rig_signature", ""):
		return _error("corrupt_rig", "The selected source rig signature does not match.")
	var verified := _verify_library(library_path, String(take.get("archive_content_sha256", "")))
	if not verified["ok"]:
		return verified
	var root := Node3D.new()
	root.name = "ArchivedSoma77Motion"
	var skeleton: Skeleton3D = snapshot.instantiate_skeleton()
	root.add_child(skeleton)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library := ResourceLoader.load(
		library_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	if player.add_animation_library("", library) != OK:
		root.free()
		return _error("corrupt_take", "The archived animation could not be attached.")
	root.add_child(player)
	player.play(ANIMATION_NAME)
	var motion := ArchivedMotion.new()
	motion.scene = root
	motion.sample_index = int(take.get("sample_index", 0))
	motion.content_sha256 = String(take.get("content_sha256", ""))
	motion.duration_seconds = float(take.get("duration_seconds", 0.0))
	return {"ok": true, "motion": motion}


static func delete_take(session: Resource, session_path: String, take_id: String) -> Dictionary:
	var found := _find_take(session, take_id)
	if not found["ok"]:
		return found
	var generation_index: int = found["generation_index"]
	var take_index: int = found["take_index"]
	var record: Dictionary = session.generation_records[generation_index].duplicate(true)
	var takes: Array = record["takes"].duplicate(true)
	var take: Dictionary = takes[take_index].duplicate(true)
	if take.get("availability", "") != "available":
		return _error("unavailable_take", "Only an available archived take can be deleted.")
	var path := String(take.get("archive_path", ""))
	var validation := ProjectPaths.validate_file(path, "res")
	if not validation["ok"] or not _is_owned_take_path(session.session_id, validation["path"]):
		return _error("unsafe_path", "The archived take path is outside its owning session.")
	if not FileAccess.file_exists(validation["path"]):
		return _error("missing_take", "The archived take file is already missing.")
	var deleting_path := "%s.deleting-%s" % [validation["absolute_path"], Session.create_uuid()]
	if DirAccess.rename_absolute(validation["absolute_path"], deleting_path) != OK:
		return _error("delete_failed", "Godot could not prepare the archived take for deletion.")
	var old_record: Dictionary = session.generation_records[generation_index].duplicate(true)
	var old_updated: String = session.updated_at_utc
	var old_selected: String = session.selected_take_id
	take["availability"] = "deleted"
	take["payload_status"] = "deleted"
	take["deleted_at_utc"] = Session.utc_now()
	takes[take_index] = take
	record["takes"] = takes
	session.generation_records[generation_index] = record
	if session.selected_take_id == take_id:
		session.selected_take_id = ""
	session.touch()
	var save_result := _atomic_save_session(session, session_path)
	if not save_result["ok"]:
		session.generation_records[generation_index] = old_record
		session.updated_at_utc = old_updated
		session.selected_take_id = old_selected
		DirAccess.rename_absolute(deleting_path, validation["absolute_path"])
		return save_result
	DirAccess.remove_absolute(deleting_path)
	return {"ok": true, "take": take.duplicate(true)}


static func refresh_availability(session: Resource) -> void:
	for generation_index in session.generation_records.size():
		var record: Dictionary = session.generation_records[generation_index].duplicate(true)
		var takes: Array = record.get("takes", []).duplicate(true)
		for take_index in takes.size():
			var take: Dictionary = takes[take_index].duplicate(true)
			if take.get("payload_status", "") != "archived":
				continue
			if not paths_belong_to_session(session.session_id, take):
				take["availability"] = "corrupt"
				takes[take_index] = take
				continue
			var path := String(take.get("archive_path", ""))
			var rig_path := String(take.get("rig_snapshot_path", ""))
			if not FileAccess.file_exists(path) or not FileAccess.file_exists(rig_path):
				take["availability"] = "missing"
			elif FileAccess.get_sha256(path) != take.get("archive_file_sha256", ""):
				take["availability"] = "corrupt"
			elif not _rig_snapshot_matches(take):
				take["availability"] = "corrupt"
			else:
				take["availability"] = "available"
			takes[take_index] = take
		record["takes"] = takes
		session.generation_records[generation_index] = record


static func _ensure_rig_snapshot(snapshot: Resource, path: String, token: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var loaded := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as Resource
		if loaded == null or not loaded is RigSnapshot or not loaded.validation_error().is_empty():
			return _error("rig_collision", "An existing source rig snapshot is invalid.")
		if loaded.signature != snapshot.signature:
			return _error("rig_collision", "An existing source rig snapshot has conflicting contents.")
		return {"ok": true, "created": false}
	var temporary := "%s.saving-%s.tres" % [path.trim_suffix(".tres"), token]
	if ResourceSaver.save(snapshot, temporary) != OK:
		return _error("archive_failed", "Godot could not stage the SOMA rig snapshot.")
	var loaded := ResourceLoader.load(temporary, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if loaded == null or not loaded is RigSnapshot or not loaded.validation_error().is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("archive_failed", "The staged SOMA rig snapshot did not validate.")
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)
	) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("archive_failed", "Godot could not promote the SOMA rig snapshot.")
	return {"ok": true, "created": true}


static func _load_verified_manifest(path: String, session_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("recovery_failed", "An orphan generation has no manifest.", path)
	var manifest := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if manifest == null or not manifest is Manifest or not manifest.validation_error().is_empty():
		return _error("recovery_failed", "An orphan generation manifest is invalid.", path)
	if manifest.session_id != session_id:
		return _error("recovery_failed", "An orphan generation belongs to another session.", path)
	if not String(manifest.rig_snapshot_path).begins_with(
		DATA_ROOT.path_join(session_id).path_join("rigs") + "/"
	):
		return _error("recovery_failed", "An orphan generation source rig is outside its session.")
	if not FileAccess.file_exists(manifest.rig_snapshot_path):
		return _error("recovery_failed", "An orphan generation source rig is missing.")
	var snapshot := ResourceLoader.load(
		manifest.rig_snapshot_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE
	) as Resource
	if (
		snapshot == null
		or not snapshot is RigSnapshot
		or not snapshot.validation_error().is_empty()
		or snapshot.signature != manifest.rig_signature
	):
		return _error("recovery_failed", "An orphan generation source rig is invalid.")
	var record: Dictionary = manifest.generation_record.duplicate(true)
	for take in record["takes"]:
		var library_path := String(take.get("archive_path", ""))
		if not _is_owned_take_path(session_id, library_path) or not FileAccess.file_exists(library_path):
			return _error("recovery_failed", "An orphan generation take is missing.", library_path)
		if FileAccess.get_sha256(library_path) != take.get("archive_file_sha256", ""):
			return _error("recovery_failed", "An orphan generation take failed its hash.", library_path)
	return {"ok": true, "record": record}


static func paths_belong_to_session(session_id: String, take: Dictionary) -> bool:
	var archive_validation := ProjectPaths.validate_file(
		String(take.get("archive_path", "")), "res"
	)
	var rig_validation := ProjectPaths.validate_file(
		String(take.get("rig_snapshot_path", "")), "tres"
	)
	if not archive_validation["ok"] or not rig_validation["ok"]:
		return false
	var session_root := DATA_ROOT.path_join(session_id)
	return (
		archive_validation["path"].begins_with(session_root.path_join("generations") + "/")
		and rig_validation["path"].begins_with(session_root.path_join("rigs") + "/")
	)


static func _verify_library(path: String, expected_animation_hash: String) -> Dictionary:
	var library := ResourceLoader.load(
		path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	if library == null or not library.has_animation(ANIMATION_NAME):
		return _error("archive_failed", "An archived take could not be reloaded.", path)
	var animation := library.get_animation(ANIMATION_NAME)
	if animation == null or _hash_animation(animation) != expected_animation_hash:
		return _error("archive_failed", "An archived take changed during serialization.", path)
	return {"ok": true}


static func _hash_animation(animation: Animation) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for track in animation.get_track_count():
		context.update((str(animation.track_get_type(track)) + "|" + str(animation.track_get_path(track))).to_utf8_buffer())
		for key in animation.track_get_key_count(track):
			context.update(var_to_bytes(animation.track_get_key_time(track, key)))
			context.update(var_to_bytes(animation.track_get_key_value(track, key)))
	return context.finish().hex_encode()


static func _find_take(session: Resource, take_id: String) -> Dictionary:
	for generation_index in session.generation_records.size():
		var takes: Array = session.generation_records[generation_index].get("takes", [])
		for take_index in takes.size():
			if takes[take_index].get("take_id", "") == take_id:
				return {"ok": true, "generation_index": generation_index, "take_index": take_index}
	return _error("missing_take", "The selected take is not part of this session.")


static func _recover_pending_deletions(session: Resource) -> void:
	for record in session.generation_records:
		for take in record.get("takes", []):
			var path := String(take.get("archive_path", ""))
			if path.is_empty() or FileAccess.file_exists(path):
				continue
			var directory := DirAccess.open(path.get_base_dir())
			if directory == null:
				continue
			var prefix := path.get_file() + ".deleting-"
			for filename in directory.get_files():
				if not filename.begins_with(prefix):
					continue
				var pending_absolute := ProjectSettings.globalize_path(path.get_base_dir().path_join(filename))
				if take.get("payload_status", "") == "deleted":
					DirAccess.remove_absolute(pending_absolute)
				elif take.get("payload_status", "") == "archived":
					DirAccess.rename_absolute(pending_absolute, ProjectSettings.globalize_path(path))
				break


static func _rig_snapshot_matches(take: Dictionary) -> bool:
	var path := String(take.get("rig_snapshot_path", ""))
	if not FileAccess.file_exists(path):
		return false
	var snapshot := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	return (
		snapshot != null
		and snapshot is RigSnapshot
		and snapshot.validation_error().is_empty()
		and snapshot.signature == take.get("rig_signature", "")
	)


static func _atomic_save_session(session: Resource, path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var token := Session.create_uuid().replace("-", "")
	var temporary_path := "%s.saving-%s.tres" % [path.trim_suffix(".tres"), token]
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path).simplify_path()
	if ResourceSaver.save(session, temporary_path) != OK:
		return _error("save_failed", "Godot could not stage the updated session.")
	var backup_absolute := "%s.backup-%s" % [validation["absolute_path"], token]
	var had_existing := FileAccess.file_exists(path)
	if had_existing and DirAccess.rename_absolute(validation["absolute_path"], backup_absolute) != OK:
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not prepare the session for update.")
	if DirAccess.rename_absolute(temporary_absolute, validation["absolute_path"]) != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_absolute, validation["absolute_path"])
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not finish updating the session.")
	if had_existing:
		DirAccess.remove_absolute(backup_absolute)
	session.take_over_path(path)
	return {"ok": true, "path": path}


static func _cleanup_failed(
	staging_directory: String,
	final_directory: String,
	rig_path: String,
	rig_created: bool,
	promoted: bool,
) -> void:
	_remove_tree(final_directory if promoted else staging_directory)
	if rig_created and FileAccess.file_exists(rig_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rig_path))


static func _remove_tree(path: String) -> void:
	var validation := ProjectPaths.validate_directory(path)
	if not validation["ok"] or not DirAccess.dir_exists_absolute(validation["absolute_path"]):
		return
	var directory := DirAccess.open(validation["path"])
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(validation["absolute_path"].path_join(filename))
	for child in directory.get_directories():
		_remove_tree(validation["path"].path_join(child))
	DirAccess.remove_absolute(validation["absolute_path"])


static func _is_owned_take_path(session_id: String, path: String) -> bool:
	var validation := ProjectPaths.validate_file(path, "res")
	if not validation["ok"]:
		return false
	var root := DATA_ROOT.path_join(session_id).path_join("generations") + "/"
	return validation["path"].begins_with(root)


static func _find_first(node: Node, type_name: StringName) -> Node:
	if node == null:
		return null
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


static func _canonical_json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys():
			keys.append(String(key))
		keys.sort()
		var members: Array[String] = []
		for key in keys:
			members.append("%s:%s" % [JSON.stringify(key), _canonical_json(value[key])])
		return "{%s}" % ",".join(members)
	if value is Array:
		var items: Array[String] = []
		for item in value:
			items.append(_canonical_json(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


static func _sha256_text(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


static func _sha256_bytes(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


static func _error(code: String, message: String, technical := "") -> Dictionary:
	return {"ok": false, "code": code, "message": message, "technical": technical}
