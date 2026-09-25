@tool
class_name KimodoSessionStore
extends RefCounted

const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const MotionDraft := preload("res://addons/kimodo_motion/domain/motion_draft.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const DEFAULT_DIRECTORY := "res://animations/kimodo/sessions"


static func create_session(title := "Untitled session") -> Resource:
	return Session.create_new(title)


static func sync_editable_intent(
	session: Resource,
	prompt: String,
	duration_frames: int,
	seed: int,
	diffusion_steps: int,
	take_count: int,
) -> void:
	session.prompt = prompt
	session.duration_frames = duration_frames
	session.seed = seed
	session.diffusion_steps = diffusion_steps
	session.requested_take_count = take_count
	session.touch()


static func set_target(session: Resource, scene_path: String, skeleton: Skeleton3D) -> Dictionary:
	if scene_path.is_empty():
		session.target_scene_path = ""
		session.target_skeleton_signature = ""
		session.touch()
		return {"ok": true}
	var path_result := ProjectPaths.validate_file(scene_path)
	if not path_result["ok"]:
		return path_result
	if skeleton == null:
		return _error("missing_skeleton", "The target has no skeleton to identify.")
	session.target_scene_path = path_result["path"]
	session.target_skeleton_signature = skeleton_signature(skeleton)
	session.touch()
	return {"ok": true, "signature": session.target_skeleton_signature}


static func append_generation_record(
	session: Resource,
	request_json: String,
	capabilities_json: String,
	response_bytes: PackedByteArray,
	capabilities: RefCounted,
	motions: Array,
) -> Dictionary:
	if request_json.is_empty() or capabilities_json.is_empty() or response_bytes.is_empty():
		return _error("missing_provenance", "Validated generation provenance is incomplete.")
	if capabilities == null or motions.is_empty():
		return _error("missing_generation", "The validated generation has no takes.")
	var record_id := Session.create_uuid()
	var request_payload: Variant = JSON.parse_string(request_json)
	var request_options: Dictionary = (
		request_payload.get("options", {}) if request_payload is Dictionary else {}
	)
	var take_summaries: Array[Dictionary] = []
	for index in motions.size():
		var motion: RefCounted = motions[index]
		take_summaries.append({
			"take_id": "%s:%d" % [record_id, index],
			"sample_index": index,
			"sample_name": String(motion.animation_name),
			"content_sha256": motion.content_sha256,
			"duration_seconds": motion.duration_seconds,
			"payload_status": "transient",
		})
	var record := {
		"record_id": record_id,
		"generated_at_utc": Session.utc_now(),
		"request_json": request_json,
		"request_sha256": sha256_text(request_json),
		"request_seed": int(request_options.get("seed", session.seed)),
		"requested_take_count": int(request_options.get("num_samples", motions.size())),
		"capabilities_json": capabilities_json,
		"capabilities_sha256": sha256_text(capabilities_json),
		"response_sha256": sha256_bytes(response_bytes),
		"protocol_version": capabilities.protocol_version,
		"model_id": capabilities.model_id,
		"fps": capabilities.fps,
		"skeleton_signature": sha256_text(canonical_json(capabilities.skeleton_payload)),
		"target_scene_path": session.target_scene_path,
		"target_skeleton_signature": session.target_skeleton_signature,
		"takes": take_summaries,
	}
	session.generation_records.append(record.duplicate(true))
	session.active_generation_index = session.generation_records.size() - 1
	session.selected_take_id = take_summaries[0]["take_id"]
	session.touch()
	return {"ok": true, "record": record.duplicate(true)}


static func record_artifact(
	session: Resource, artifact_type: String, path: String, take_id := ""
) -> Dictionary:
	if session == null or not session is Session:
		return _error("missing_session", "Open a session before recording an artifact.")
	if artifact_type.strip_edges().is_empty():
		return _error("missing_type", "Artifact type cannot be empty.")
	var validation := ProjectPaths.validate_file(path)
	if not validation["ok"]:
		return validation
	if not FileAccess.file_exists(validation["path"]):
		return _error("missing_artifact", "The saved artifact does not exist.", validation["path"])
	var key := "%s:%s" % [take_id, artifact_type] if not take_id.is_empty() else artifact_type
	var generation_record: Dictionary = session.active_generation_record()
	session.artifacts[key] = {
		"status": "saved",
		"type": artifact_type,
		"path": validation["path"],
		"take_id": take_id,
		"recorded_at_utc": Session.utc_now(),
		"generation_record_id": generation_record.get("record_id", ""),
	}
	session.touch()
	return {"ok": true, "artifact": session.artifacts[key].duplicate(true)}


static func save_new(session: Resource, requested_title := "") -> Dictionary:
	if not requested_title.strip_edges().is_empty():
		session.title = requested_title.strip_edges()
	var stem: String = session.title.validate_filename().strip_edges().to_snake_case()
	if stem.is_empty():
		stem = "kimodo_session"
	return save_as(session, DEFAULT_DIRECTORY, stem)


static func save_as(session: Resource, directory: String, requested_stem: String) -> Dictionary:
	var directory_result := ProjectPaths.ensure_directory(directory)
	if not directory_result["ok"]:
		return directory_result
	var stem := requested_stem.validate_filename().strip_edges()
	if stem.is_empty():
		stem = "kimodo_session"
	var candidate := stem
	var suffix := 2
	while FileAccess.file_exists(directory_result["path"].path_join(candidate + ".tres")):
		candidate = "%s_%d" % [stem, suffix]
		suffix += 1
	return save(session, directory_result["path"].path_join(candidate + ".tres"))


static func save(session: Resource, path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var parent_result := ProjectPaths.ensure_directory(validation["path"].get_base_dir())
	if not parent_result["ok"]:
		return parent_result
	var session_error := validate_session(session)
	if not session_error.is_empty():
		return _error("invalid_session", session_error)
	session.touch()
	var save_result := _atomic_save(session, validation["path"], validation["absolute_path"])
	if not save_result["ok"]:
		return save_result
	session.take_over_path(validation["path"])
	return {"ok": true, "path": validation["path"]}


static func open(path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	if not FileAccess.file_exists(validation["path"]):
		return _error("missing_session", "The selected session does not exist.", validation["path"])
	var loaded := ResourceLoader.load(validation["path"], "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded is MotionDraft:
		var original_hash := FileAccess.get_sha256(validation["path"])
		var session := migrate_draft(loaded)
		var migrated_result := save_as(session, DEFAULT_DIRECTORY, session.title.to_snake_case())
		if not migrated_result["ok"]:
			return migrated_result
		if FileAccess.get_sha256(validation["path"]) != original_hash:
			return _error("migration_failed", "Draft migration changed the original resource.")
		return _load_result(session, migrated_result["path"], validation["path"])
	if not loaded is Session:
		return _error("invalid_session", "The selected resource is not a Kimodo session or draft.")
	var session_error := validate_session(loaded)
	if not session_error.is_empty():
		return _error("invalid_session", session_error)
	return _load_result(loaded, validation["path"])


static func migrate_draft(draft: Resource) -> Resource:
	var session := Session.create_new("Migrated motion session")
	session.session_id = draft.draft_id
	session.migrated_from_draft_id = draft.draft_id
	session.created_at_utc = draft.created_at_utc
	session.updated_at_utc = draft.updated_at_utc
	session.target_scene_path = draft.target_scene_path
	session.target_skeleton_signature = draft.target_skeleton_signature
	session.rig_profile_path = draft.rig_profile_path
	session.animation_destination = draft.animation_destination
	session.prompt = draft.prompt
	session.duration_frames = draft.duration_frames
	session.seed = draft.seed
	session.diffusion_steps = draft.diffusion_steps
	session.requested_take_count = clampi(draft.requested_candidate_count, 1, 2)
	session.generation_preset = draft.generation_preset
	session.notes = draft.notes
	session.generation_records.assign(draft.generation_records.duplicate(true))
	session.active_generation_index = draft.active_generation_index
	session.artifacts = draft.artifacts.duplicate(true)
	return session


static func list_sessions(limit := 8) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory_result := ProjectPaths.validate_directory(DEFAULT_DIRECTORY)
	if not directory_result["ok"] or not DirAccess.dir_exists_absolute(directory_result["absolute_path"]):
		return result
	var directory := DirAccess.open(directory_result["path"])
	if directory == null:
		return result
	for filename in directory.get_files():
		if not filename.ends_with(".tres"):
			continue
		var path: String = directory_result["path"].path_join(filename)
		var loaded := ResourceLoader.load(path, "KimodoSession", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is Session and validate_session(loaded).is_empty():
			result.append({"path": path, "title": loaded.title, "updated_at_utc": loaded.updated_at_utc})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["updated_at_utc"]) > String(b["updated_at_utc"])
	)
	return result.slice(0, mini(limit, result.size()))


static func validate_session(session: Resource) -> String:
	if session == null or not session is Session:
		return "Resource is not a KimodoSession."
	if session.schema_version != Session.SCHEMA_VERSION:
		return "Unsupported KimodoSession schema version %d (expected %d)." % [
			session.schema_version, Session.SCHEMA_VERSION,
		]
	if session.session_id.is_empty():
		return "KimodoSession has no stable session ID."
	if session.created_at_utc.is_empty() or session.updated_at_utc.is_empty():
		return "KimodoSession timestamps are incomplete."
	if not session.target_scene_path.is_empty():
		var target_result := ProjectPaths.validate_file(session.target_scene_path)
		if not target_result["ok"]:
			return target_result["message"]
	return ""


static func skeleton_signature(skeleton: Skeleton3D) -> String:
	var bones: Array[Dictionary] = []
	for index in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		var parent_index := skeleton.get_bone_parent(index)
		bones.append({
			"name": String(skeleton.get_bone_name(index)),
			"parent": String(skeleton.get_bone_name(parent_index)) if parent_index >= 0 else null,
			"rest": [
				rest.basis.x.x, rest.basis.x.y, rest.basis.x.z,
				rest.basis.y.x, rest.basis.y.y, rest.basis.y.z,
				rest.basis.z.x, rest.basis.z.y, rest.basis.z.z,
				rest.origin.x, rest.origin.y, rest.origin.z,
			],
		})
	return sha256_text(canonical_json(bones))


static func canonical_json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys():
			keys.append(String(key))
		keys.sort()
		var members: Array[String] = []
		for key in keys:
			members.append("%s:%s" % [JSON.stringify(key), canonical_json(value[key])])
		return "{%s}" % ",".join(members)
	if value is Array:
		var items: Array[String] = []
		for item in value:
			items.append(canonical_json(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


static func sha256_text(text: String) -> String:
	return sha256_bytes(text.to_utf8_buffer())


static func sha256_bytes(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


static func _load_result(session: Resource, path: String, migrated_from := "") -> Dictionary:
	var available: Array[String] = []
	var missing: Array[String] = []
	for artifact_key in session.artifacts:
		var entry: Variant = session.artifacts[artifact_key]
		var artifact_path := String(entry.get("path", "")) if entry is Dictionary else ""
		var validation := ProjectPaths.validate_file(artifact_path)
		if validation["ok"] and FileAccess.file_exists(validation["path"]):
			available.append(String(artifact_key))
		else:
			missing.append(String(artifact_key))
	return {
		"ok": true, "session": session, "path": path,
		"migrated_from": migrated_from,
		"available_artifacts": available, "missing_artifacts": missing,
	}


static func _atomic_save(session: Resource, path: String, absolute_path: String) -> Dictionary:
	var token := Session.create_uuid().replace("-", "")
	var temporary_path := "%s.saving-%s.tres" % [path.trim_suffix(".tres"), token]
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path).simplify_path()
	var save_error := ResourceSaver.save(session, temporary_path)
	if save_error != OK:
		return _error("save_failed", "Godot could not write the session.", str(save_error))
	var backup_absolute := "%s.backup-%s" % [absolute_path, token]
	var had_existing := FileAccess.file_exists(path)
	if had_existing and DirAccess.rename_absolute(absolute_path, backup_absolute) != OK:
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not prepare the session for update.")
	var rename_error := DirAccess.rename_absolute(temporary_absolute, absolute_path)
	if rename_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_absolute, absolute_path)
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not finish saving the session.", str(rename_error))
	if had_existing:
		DirAccess.remove_absolute(backup_absolute)
	return {"ok": true}


static func _error(code: String, message: String, technical := "") -> Dictionary:
	return {"ok": false, "code": code, "message": message, "technical": technical}
