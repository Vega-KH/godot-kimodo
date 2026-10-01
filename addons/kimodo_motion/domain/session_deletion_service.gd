@tool
class_name KimodoSessionDeletionService
extends RefCounted

# Only verified, session-owned files are deleted. Explicit exports are never
# followed. A durable receipt separates reversible staging from committed purge.
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const Manifest := preload("res://addons/kimodo_motion/domain/generation_archive_manifest.gd")
const RigSnapshot := preload("res://addons/kimodo_motion/domain/soma77_rig_snapshot.gd")
const Paths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const Lifecycle := preload("res://addons/kimodo_motion/domain/session_lifecycle.gd")


static func preflight(path: String) -> Dictionary:
	var validation := Paths.validate_unlinked(path)
	if not validation["ok"]:
		return validation
	if path.replace("\\", "/").split("/").has(".."):
		return _error("unsafe_path", "Choose the session directly; traversal paths cannot be deleted.")
	path = validation["path"]
	if not FileAccess.file_exists(path) or path.get_extension() != "tres":
		return _error("missing_session", "The selected session file is missing or is not a .tres resource.")
	var readable := FileAccess.open(path, FileAccess.READ)
	if readable == null:
		return _error("unreadable_session", "The session file is locked or unreadable. Close applications holding it and retry.")
	readable.close()
	var session := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	var problem := Store.validate_session(session)
	if not problem.is_empty():
		return _error("invalid_session", "Cannot prove this session's data ownership: " + problem)
	if Lifecycle.is_retired(session.session_id):
		return _error("deletion_pending", "This session has a deletion recovery receipt. Reopen the dock to retry recovery.")
	var root := Archive.DATA_ROOT.path_join(session.session_id)
	var inventory := _inventory(root)
	if not inventory["ok"]:
		return inventory
	var project_sessions := _session_files("res://")
	if not project_sessions["ok"]:
		return project_sessions
	for candidate in project_sessions["paths"]:
		var other := ResourceLoader.load(candidate, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
		if not other is Session:
			return _error("unprovable_owner", "A project session cannot be read. Repair it before deleting shared archive data.", candidate)
		if candidate != path and other.session_id == session.session_id:
			return _error("duplicate_id", "Another session file uses the same session ID. Remove or separate the duplicate before deleting either session.", candidate)
		var conflict := _external_reference(other, root)
		if not conflict.is_empty():
			return _error("protected_output", "A saved output, model or shared rig profile is inside this session's managed data. Move it outside session_data and update its reference before deleting.", conflict)
		if candidate != path:
			for record in other.generation_records:
				for take in record.get("takes", []):
					for field in ["archive_path", "rig_snapshot_path"]:
						if _under(String(take.get(field, "")), root):
							return _error("shared_archive", "Another session references this session's source data. Deletion is blocked.", candidate)
	var takes := {}
	var allowed := {}
	for record in session.generation_records:
		var record_result := _register_record(record, session.session_id, takes, allowed)
		if not record_result["ok"]:
			return record_result
	# Include durable generations not yet recovered into the session index,
	# without calling recover_session (preflight must be read-only).
	for file_path in inventory["files"]:
		if String(file_path).get_file() != "generation.tres":
			continue
		var manifest := ResourceLoader.load(file_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
		if not manifest is Manifest or not manifest.validation_error().is_empty() or manifest.session_id != session.session_id:
			return _error("unprovable_archive", "A generation manifest has invalid or different ownership. Open/recover the session or repair its archive before deletion.", file_path)
		if String(file_path).get_base_dir() != root.path_join("generations").path_join(manifest.record_id):
			return _error("unprovable_archive", "A generation manifest is outside its declared generation directory.", file_path)
		var record_result := _register_record(manifest.generation_record, session.session_id, takes, allowed)
		if not record_result["ok"]:
			return record_result
		allowed[file_path] = true
	for file_path in inventory["files"]:
		if not allowed.has(file_path):
			# A verified deduplicated snapshot can survive a failed generation
			# before its manifest was committed. It is still managed source data.
			if String(file_path).get_base_dir() == root.path_join("rigs") and String(file_path).get_extension() == "tres":
				var snapshot := ResourceLoader.load(file_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
				if snapshot is RigSnapshot and snapshot.validation_error().is_empty() and String(file_path).get_file() == snapshot.signature + ".tres":
					continue
			return _error("unrecognized_data", "Unrecognized files exist in the managed session directory. Open the session to recover interrupted archive work, or move independently saved files out before deletion.", file_path)
	var count := 0
	var missing := 0
	for take in takes.values():
		if take.get("payload_status") != "archived":
			continue
		if FileAccess.file_exists(String(take["archive_path"])):
			count += 1
		else:
			missing += 1
	var fingerprint := Store.sha256_text(Store.canonical_json({
		"session": FileAccess.get_sha256(path), "inventory": inventory,
		"sessions": project_sessions["hashes"],
	}))
	return {"ok": true, "path": path, "session_id": session.session_id, "title": session.title,
		"owned_hashes": inventory["hashes"], "session_hash": FileAccess.get_sha256(path),
		"data_root": root, "draft_count": count, "missing_count": missing, "fingerprint": fingerprint}


static func execute(plan: Dictionary, test_options := {}) -> Dictionary:
	if not plan.get("ok", false) or not plan.get("path") is String:
		return _error("invalid_plan", "A verified deletion confirmation is required.")
	var fresh := preflight(plan["path"])
	if not fresh["ok"]:
		return fresh
	if fresh["fingerprint"] != plan.get("fingerprint", ""):
		return _error("stale_plan", "The session or its data changed after confirmation. Review a new deletion warning.")
	var id: String = fresh["session_id"]
	var receipt := {"version": 1, "session_id": id, "session_path": fresh["path"], "phase": "staging"}
	var quarantine := Lifecycle.receipt_path(id).get_base_dir()
	var owned_files := {quarantine.path_join("session.tres"): fresh["session_hash"]}
	for path in fresh["owned_hashes"]:
		owned_files[quarantine.path_join("data") + String(path).trim_prefix(fresh["data_root"])] = fresh["owned_hashes"][path]
	receipt["owned_files"] = owned_files
	var written := Lifecycle.write_receipt(id, receipt)
	if not written["ok"]:
		return written
	var root: String = fresh["data_root"]
	if DirAccess.dir_exists_absolute(root):
		if DirAccess.rename_absolute(root, quarantine.path_join("data")) != OK:
			return _rollback(receipt, "The archive directory is locked or could not be staged. No deletion was committed.")
	if test_options.get("fail_at") == "after_data":
		return _rollback(receipt, "Injected failure after data staging.")
	if DirAccess.rename_absolute(fresh["path"], quarantine.path_join("session.tres")) != OK:
		return _rollback(receipt, "The session file is locked or could not be staged. No deletion was committed.")
	if test_options.get("fail_at") == "after_session":
		return _rollback(receipt, "Injected failure after session staging.")
	if test_options.get("fail_at") == "interrupt_staging":
		return _error("recovery_pending", "Injected interruption; staged files will be restored on recovery.")
	receipt["phase"] = "committed"
	written = Lifecycle.write_receipt(id, receipt)
	if not written["ok"]:
		return _rollback(receipt, written["message"])
	if test_options.get("fail_at") == "interrupt_committed":
		return {"ok": true, "session_id": id, "cleanup_pending": true, "message": "Session deleted; source cleanup will resume on recovery."}
	return _purge(receipt)


static func recover_pending() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var validation := Paths.validate_unlinked(Lifecycle.RECEIPT_ROOT)
	if not validation["ok"]:
		results.append(validation)
		return results
	var directory := DirAccess.open(Lifecycle.RECEIPT_ROOT)
	if directory == null:
		return results
	for id in directory.get_directories():
		if not Lifecycle.valid_id(id):
			continue
		var checked := Paths.validate_unlinked(Lifecycle.receipt_path(id))
		if not checked["ok"]:
			results.append(checked)
			continue
		if not FileAccess.file_exists(Lifecycle.receipt_path(id)):
			results.append(_error("invalid_receipt", "A deletion staging directory has no durable receipt. Original session data was not committed for deletion; inspect the staging directory before retrying.", id))
			continue
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(Lifecycle.receipt_path(id)))
		if not receipt is Dictionary or receipt.get("version") != 1 or receipt.get("session_id") != id:
			results.append(_error("invalid_receipt", "Session deletion recovery receipt is unreadable. Files were not removed.", id))
			continue
		if receipt.get("phase") == "staging":
			results.append(_rollback(receipt, "Restored an interrupted session deletion.", true))
		elif receipt.get("phase") == "committed":
			results.append(_purge(receipt))
	return results


static func _rollback(receipt: Dictionary, message: String, recovery := false) -> Dictionary:
	var id: String = receipt["session_id"]
	var quarantine := Lifecycle.receipt_path(id).get_base_dir()
	var original: String = receipt.get("session_path", "")
	var checked := Paths.validate_unlinked(original)
	var data_root := Archive.DATA_ROOT.path_join(id)
	var inventory := _inventory(quarantine)
	if not checked["ok"] or not inventory["ok"] or not Paths.validate_unlinked(data_root)["ok"]:
		return _error("recovery_pending", "Deletion rollback needs attention; staged files remain preserved.", quarantine)
	for pair in [[quarantine.path_join("session.tres"), original], [quarantine.path_join("data"), data_root]]:
		if FileAccess.file_exists(pair[0]) or DirAccess.dir_exists_absolute(pair[0]):
			if FileAccess.file_exists(pair[1]) or DirAccess.dir_exists_absolute(pair[1]) or DirAccess.rename_absolute(pair[0], pair[1]) != OK:
				return _error("recovery_pending", "Could not restore staged files. Close files/editors and reopen the dock to retry recovery.", quarantine)
	if DirAccess.remove_absolute(Lifecycle.receipt_path(id)) != OK:
		return _error("recovery_pending", "Original files were restored, but the recovery receipt is locked. Reopen the dock after releasing the lock.", quarantine)
	DirAccess.remove_absolute(quarantine)
	return {"ok": recovery, "code": "rolled_back", "message": message}


static func _purge(receipt: Dictionary) -> Dictionary:
	var id: String = receipt["session_id"]
	var quarantine := Lifecycle.receipt_path(id).get_base_dir()
	# Check the complete tree before removing any file; never follow junctions.
	var inventory := _inventory(quarantine)
	if not inventory["ok"]:
		return {"ok": true, "session_id": id, "cleanup_pending": true, "message": inventory["message"]}
	var pending := false
	var owned_files: Dictionary = receipt.get("owned_files", {})
	for path in inventory["files"]:
		if path == Lifecycle.receipt_path(id):
			continue
		if not owned_files.has(path) or owned_files[path] != inventory["hashes"][path]:
			return {"ok": true, "session_id": id, "cleanup_pending": true, "message": "Session deleted, but staged files changed or unrecognized files were added. Cleanup is paused; review " + quarantine}
	for path in inventory["files"]:
		if path == Lifecycle.receipt_path(id):
			continue
		if DirAccess.remove_absolute(path) != OK:
			pending = true
	var directories: Array = inventory["directories"]
	directories.reverse()
	for path in directories:
		if path != quarantine and DirAccess.remove_absolute(path) != OK:
			pending = true
	if not pending and not owned_files.is_empty():
		# Keep only a small identity receipt after source data is gone.
		receipt["owned_files"] = {}
		var written := Lifecycle.write_receipt(id, receipt)
		if not written["ok"]:
			pending = true
	return {"ok": true, "session_id": id, "cleanup_pending": pending,
		"message": "Session deleted; locked source files will be cleaned up on restart." if pending else "Session and managed source data deleted. Saved outputs were kept."}


static func _register_record(record: Dictionary, id: String, takes: Dictionary, allowed: Dictionary) -> Dictionary:
	for take in record.get("takes", []):
		if not take is Dictionary or not Archive.paths_belong_to_session(id, take):
			return _error("unprovable_archive", "A take refers outside this session's managed data.")
		var take_id := String(take.get("take_id", ""))
		if take_id.is_empty() or take.get("payload_status", "") not in ["archived", "deleted"]:
			return _error("unprovable_archive", "A take has invalid archive identity or status.")
		for known_id in takes:
			if known_id != take_id and takes[known_id].get("archive_path") == take.get("archive_path"):
				return _error("shared_archive", "Different take IDs reference the same archive file. Repair their ownership before deletion.")
		if takes.has(take_id) and Store.canonical_json(takes[take_id]) != Store.canonical_json(take):
			for field in ["archive_path", "rig_snapshot_path", "rig_signature", "archive_file_sha256", "archive_content_sha256"]:
				if takes[take_id].get(field) != take.get(field):
					return _error("archive_conflict", "Session and generation manifest disagree about a take's ownership. Recover it before deleting.")
			# Generation manifests are immutable; the session's later explicit
			# deletion tombstone takes precedence over the archived manifest entry.
			if takes[take_id].get("payload_status") == "deleted":
				continue
		takes[take_id] = take
		allowed[String(take["archive_path"])] = true
		allowed[String(take["rig_snapshot_path"])] = true
	return {"ok": true}


static func _inventory(root: String) -> Dictionary:
	var validation := Paths.validate_unlinked(root)
	if not validation["ok"]:
		return validation
	var result := {"ok": true, "files": [], "directories": [], "hashes": {}}
	if not DirAccess.dir_exists_absolute(root):
		return result
	var directory := DirAccess.open(root)
	if directory == null:
		return _error("unreadable_directory", "A managed directory could not be read. Nothing was deleted.", root)
	directory.include_hidden = true
	result["directories"].append(root)
	for filename in directory.get_files():
		var path := root.path_join(filename)
		if directory.is_link(filename):
			return _error("linked_path", "Deletion cannot follow a linked file or directory junction.", path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _error("unreadable_file", "A managed file is locked or unreadable. Nothing was deleted.", path)
		file.close()
		result["files"].append(path)
		result["hashes"][path] = FileAccess.get_sha256(path)
	for child in directory.get_directories():
		if directory.is_link(child):
			return _error("linked_path", "Deletion cannot follow a linked file or directory junction.", root.path_join(child))
		var subtree := _inventory(root.path_join(child))
		if not subtree["ok"]:
			return subtree
		result["files"].append_array(subtree["files"])
		result["directories"].append_array(subtree["directories"])
		result["hashes"].merge(subtree["hashes"])
	result["files"].sort()
	result["directories"].sort()
	return result


static func _session_files(root: String) -> Dictionary:
	var result := {"ok": true, "paths": [], "hashes": {}}
	var directory := DirAccess.open(root)
	if directory == null:
		return _error("unprovable_owner", "Could not scan project sessions for shared ownership.", root)
	directory.include_hidden = true
	for filename in directory.get_files():
		if filename.get_extension() != "tres":
			continue
		if directory.is_link(filename):
			return _error("linked_session", "A linked resource prevents proving exclusive session ownership.", root.path_join(filename))
		var path := root.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _error("unprovable_owner", "A project resource is unreadable, so exclusive session ownership could not be checked. Close applications holding it and retry.", path)
		var contents := file.get_as_text()
		file.close()
		if contents.contains("addons/kimodo_motion/domain/motion_session.gd"):
			result["paths"].append(path)
			result["hashes"][path] = FileAccess.get_sha256(path)
	for child in directory.get_directories():
		if child in [".git", ".godot"]:
			continue
		if directory.is_link(child):
			return _error("linked_directory", "A linked project directory prevents proving exclusive session ownership. Keep sessions in ordinary project directories.", root.path_join(child))
		var subtree := _session_files(root.path_join(child))
		if not subtree["ok"]:
			return subtree
		result["paths"].append_array(subtree["paths"])
		result["hashes"].merge(subtree["hashes"])
	return result


static func _external_reference(session: Resource, root: String) -> String:
	for path in [session.animation_destination, session.target_scene_path, session.rig_profile_path]:
		if _under(path, root):
			return path
	for artifact in session.artifacts.values():
		if artifact is Dictionary and _under(String(artifact.get("path", "")), root):
			return artifact["path"]
	for acceptance in session.acceptances.values():
		if acceptance is Dictionary and _under(String(acceptance.get("destination_path", "")), root):
			return acceptance["destination_path"]
	return ""


static func _under(path: String, root: String) -> bool:
	var validation := Paths.validate_file(path)
	return validation["ok"] and (validation["path"] == root or String(validation["path"]).to_lower().begins_with(root.to_lower() + "/"))


static func _error(code: String, message: String, technical := "") -> Dictionary:
	return {"ok": false, "code": code, "message": message, "technical": technical}
