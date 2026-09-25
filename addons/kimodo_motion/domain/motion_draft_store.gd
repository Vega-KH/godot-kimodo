@tool
class_name KimodoMotionDraftStore
extends RefCounted

const MotionDraft := preload("res://addons/kimodo_motion/domain/motion_draft.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")


static func create_draft() -> Resource:
	return MotionDraft.create_new()


static func sync_editable_intent(
	draft: Resource,
	prompt: String,
	duration_frames: int,
	seed: int,
	diffusion_steps: int,
) -> void:
	draft.prompt = prompt
	draft.duration_frames = duration_frames
	draft.seed = seed
	draft.diffusion_steps = diffusion_steps
	draft.touch()


static func set_target(draft: Resource, scene_path: String, skeleton: Skeleton3D) -> Dictionary:
	if scene_path.is_empty():
		draft.target_scene_path = ""
		draft.target_skeleton_signature = ""
		draft.touch()
		return {"ok": true}
	var path_result := ProjectPaths.validate_file(scene_path)
	if not path_result["ok"]:
		return path_result
	if skeleton == null:
		return _error("missing_skeleton", "The target has no skeleton to identify.")
	draft.target_scene_path = path_result["path"]
	draft.target_skeleton_signature = skeleton_signature(skeleton)
	draft.touch()
	return {"ok": true, "signature": draft.target_skeleton_signature}


static func append_generation_record(
	draft: Resource,
	request_json: String,
	capabilities_json: String,
	response_bytes: PackedByteArray,
	capabilities: RefCounted,
) -> Dictionary:
	if request_json.is_empty() or capabilities_json.is_empty() or response_bytes.is_empty():
		return _error(
			"missing_provenance",
			"The validated result is missing request, capability, or response provenance.",
		)
	if capabilities == null:
		return _error("missing_capabilities", "Generation capabilities are unavailable.")
	var record := {
		"record_id": MotionDraft.create_uuid(),
		"generated_at_utc": MotionDraft.utc_now(),
		"request_json": request_json,
		"request_sha256": sha256_text(request_json),
		"capabilities_json": capabilities_json,
		"capabilities_sha256": sha256_text(capabilities_json),
		"response_sha256": sha256_bytes(response_bytes),
		"protocol_version": capabilities.protocol_version,
		"model_id": capabilities.model_id,
		"fps": capabilities.fps,
		"skeleton_signature": sha256_text(canonical_json(capabilities.skeleton_payload)),
	}
	draft.generation_records.append(record.duplicate(true))
	draft.active_generation_index = draft.generation_records.size() - 1
	draft.touch()
	return {"ok": true, "record": record.duplicate(true)}


static func record_artifact(draft: Resource, artifact_type: String, path: String) -> Dictionary:
	if artifact_type.strip_edges().is_empty():
		return _error("missing_type", "Artifact type cannot be empty.")
	var validation := ProjectPaths.validate_file(path)
	if not validation["ok"]:
		return validation
	if not FileAccess.file_exists(validation["path"]):
		return _error("missing_artifact", "The saved artifact does not exist.", validation["path"])
	var generation_record: Dictionary = draft.active_generation_record()
	draft.artifacts[artifact_type] = {
		"status": "saved",
		"path": validation["path"],
		"recorded_at_utc": MotionDraft.utc_now(),
		"generation_record_id": generation_record.get("record_id", ""),
	}
	draft.touch()
	return {"ok": true, "artifact": draft.artifacts[artifact_type].duplicate(true)}


static func save_as(draft: Resource, directory: String, requested_stem: String) -> Dictionary:
	var directory_result := ProjectPaths.ensure_directory(directory)
	if not directory_result["ok"]:
		return directory_result
	var stem := requested_stem.validate_filename().strip_edges()
	if stem.is_empty():
		stem = "kimodo_motion_draft"
	var candidate := stem
	var suffix := 2
	while FileAccess.file_exists(directory_result["path"].path_join(candidate + ".tres")):
		candidate = "%s_%d" % [stem, suffix]
		suffix += 1
	return save(draft, directory_result["path"].path_join(candidate + ".tres"))


static func save(draft: Resource, path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var parent_result := ProjectPaths.ensure_directory(validation["path"].get_base_dir())
	if not parent_result["ok"]:
		return parent_result
	var draft_error := validate_draft(draft)
	if not draft_error.is_empty():
		return _error("invalid_draft", draft_error)
	draft.touch()
	var save_result := _atomic_save(draft, validation["path"], validation["absolute_path"])
	if not save_result["ok"]:
		return save_result
	draft.take_over_path(validation["path"])
	return {"ok": true, "path": validation["path"]}


static func load_draft(path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	if not FileAccess.file_exists(validation["path"]):
		return _error("missing_draft", "The selected draft does not exist.", validation["path"])
	var loaded := ResourceLoader.load(
		validation["path"], "KimodoMotionDraft", ResourceLoader.CACHE_MODE_IGNORE
	)
	if not loaded is MotionDraft:
		return _error("invalid_draft", "The selected resource is not a MotionDraft.")
	var draft := loaded as Resource
	var draft_error := validate_draft(draft)
	if not draft_error.is_empty():
		return _error("invalid_draft", draft_error)
	var available: Array[String] = []
	var missing: Array[String] = []
	for artifact_type in draft.artifacts:
		var entry: Variant = draft.artifacts[artifact_type]
		if not entry is Dictionary or not entry.get("path") is String:
			missing.append(String(artifact_type))
			continue
		var artifact_path: String = entry["path"]
		var artifact_validation := ProjectPaths.validate_file(artifact_path)
		if artifact_validation["ok"] and FileAccess.file_exists(artifact_validation["path"]):
			available.append(String(artifact_type))
		else:
			missing.append(String(artifact_type))
	return {
		"ok": true,
		"draft": draft,
		"path": validation["path"],
		"available_artifacts": available,
		"missing_artifacts": missing,
	}


static func validate_draft(draft: Resource) -> String:
	if draft == null or not draft is MotionDraft:
		return "Resource is not a MotionDraft."
	if draft.schema_version != MotionDraft.SCHEMA_VERSION:
		return "Unsupported MotionDraft schema version %d (expected %d)." % [
			draft.schema_version, MotionDraft.SCHEMA_VERSION,
		]
	if draft.draft_id.is_empty():
		return "MotionDraft has no stable draft ID."
	if draft.created_at_utc.is_empty() or draft.updated_at_utc.is_empty():
		return "MotionDraft timestamps are incomplete."
	if not draft.target_scene_path.is_empty():
		var target_result := ProjectPaths.validate_file(draft.target_scene_path)
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
			"parent": (
				String(skeleton.get_bone_name(parent_index)) if parent_index >= 0 else null
			),
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


static func _atomic_save(draft: Resource, path: String, absolute_path: String) -> Dictionary:
	var token := MotionDraft.create_uuid().replace("-", "")
	var temporary_path := "%s.saving-%s.tres" % [path.trim_suffix(".tres"), token]
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path).simplify_path()
	var save_error := ResourceSaver.save(draft, temporary_path)
	if save_error != OK:
		return _error(
			"save_failed",
			"Godot could not write the draft.",
			"ResourceSaver.save returned %d" % save_error,
		)
	var backup_absolute := "%s.backup-%s" % [absolute_path, token]
	var had_existing := FileAccess.file_exists(path)
	if had_existing:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_absolute)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_absolute)
			return _error("save_failed", "Godot could not prepare the existing draft for update.")
	var rename_error := DirAccess.rename_absolute(temporary_absolute, absolute_path)
	if rename_error != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_absolute, absolute_path)
		DirAccess.remove_absolute(temporary_absolute)
		return _error(
			"save_failed",
			"Godot could not finish saving the draft.",
			"DirAccess.rename_absolute returned %d" % rename_error,
		)
	if had_existing:
		DirAccess.remove_absolute(backup_absolute)
	return {"ok": true}


static func _error(code: String, message: String, technical: String = "") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"technical": technical,
	}
