@tool
class_name KimodoAcceptanceService
extends RefCounted

const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const CharacterBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd"
)


class AcceptanceTransaction extends RefCounted:
	signal state_changed(state: String, result: Dictionary)

	var library_path := ""
	var session_path := ""
	var animation_name := ""
	var acceptance_id := ""
	var created_destination := false
	var session: Resource
	var before_exists := false
	var before_bytes := PackedByteArray()
	var after_bytes := PackedByteArray()
	var before_acceptances: Dictionary = {}
	var after_acceptances: Dictionary = {}
	var before_destination := ""
	var after_destination := ""
	var test_options: Dictionary = {}
	var last_result: Dictionary = {"ok": true}
	var applied := false
	var has_committed := false


	func apply_after() -> void:
		last_result = _apply_state(
			true,
			after_bytes,
			after_acceptances,
			after_destination,
			"redo" if has_committed else "do",
		)
		if last_result["ok"]:
			applied = true
			has_committed = true
		state_changed.emit("accepted" if last_result["ok"] else "error", last_result)


	func apply_before() -> void:
		last_result = _apply_state(
			before_exists,
			before_bytes,
			before_acceptances,
			before_destination,
			"undo",
		)
		if last_result["ok"]:
			applied = false
		state_changed.emit("undone" if last_result["ok"] else "error", last_result)


	func _apply_state(
		target_exists: bool,
		target_bytes: PackedByteArray,
		target_acceptances: Dictionary,
		target_destination: String,
		phase: String,
	) -> Dictionary:
		var current_exists := FileAccess.file_exists(library_path)
		var current_bytes := (
			FileAccess.get_file_as_bytes(library_path) if current_exists else PackedByteArray()
		)
		var current_acceptances: Dictionary = session.acceptances.duplicate(true)
		var current_destination: String = session.animation_destination
		var current_updated: String = session.updated_at_utc
		if test_options.get("fail_at", "") == "%s_promotion" % phase:
			return _error("injected_failure", "Injected acceptance promotion failure.")
		var library_result: Dictionary = KimodoAcceptanceService._write_file_state(
			library_path, target_exists, target_bytes
		)
		if not library_result["ok"]:
			return library_result
		if test_options.get("fail_at", "") == "%s_after_library" % phase:
			KimodoAcceptanceService._write_file_state(library_path, current_exists, current_bytes)
			return _error("injected_failure", "Injected acceptance failure after library update.")
		session.acceptances = target_acceptances.duplicate(true)
		session.animation_destination = target_destination
		session.updated_at_utc = Session.utc_now()
		var save_result: Dictionary = (
			_error("injected_failure", "Injected acceptance session-save failure.")
			if test_options.get("fail_at", "") == "%s_session" % phase
			else KimodoAcceptanceService._atomic_save_resource(session, session_path)
		)
		if not save_result["ok"]:
			session.acceptances = current_acceptances
			session.animation_destination = current_destination
			session.updated_at_utc = current_updated
			KimodoAcceptanceService._write_file_state(library_path, current_exists, current_bytes)
			return save_result
		KimodoAcceptanceService._refresh_library_cache(library_path, target_exists)
		return {
			"ok": true,
			"phase": phase,
			"path": library_path,
			"animation_name": animation_name,
			"acceptance_id": acceptance_id,
			"created_destination": created_destination,
		}


	func _error(code: String, message: String, technical := "") -> Dictionary:
		return {
			"ok": false,
			"code": code,
			"message": message,
			"technical": technical,
		}


static func prepare(
	session: Resource,
	session_path: String,
	character_root: Node3D,
	target_scene: PackedScene,
	destination_path: String,
	requested_name: String,
	replace_existing := false,
	test_options: Dictionary = {},
) -> Dictionary:
	if session == null or not session is Session or session_path.is_empty():
		return _error("missing_session", "Open a current Kimodo session before accepting.")
	if character_root == null or target_scene == null:
		return _error("missing_target", "Select and preview a compatible character first.")
	if session.selected_take_id.is_empty():
		return _error("missing_take", "Select an available generated take before accepting.")
	var take_record := _take_record(session, session.selected_take_id)
	if (
		take_record.is_empty()
		or take_record.get("availability", "") != "available"
		or not FileAccess.file_exists(String(take_record.get("archive_path", "")))
	):
		return _error(
			"missing_take",
			"The selected take's automatic source archive is no longer available.",
		)
	var path_result := ProjectPaths.validate_file(destination_path, "res")
	if not path_result["ok"]:
		return path_result
	if String(path_result["path"]).begins_with("res://.godot/"):
		return _error(
			"imported_resource",
			"Choose a project-owned library outside Godot's imported .godot data directory.",
		)
	var name_result := _validate_animation_name(requested_name)
	if not name_result["ok"]:
		return name_result
	var animation_name: String = name_result["name"]
	var source_player := character_root.get_node_or_null(
		CharacterBaker.PLAYER_NODE_NAME
	) as AnimationPlayer
	if source_player == null or not source_player.has_animation(CharacterBaker.ANIMATION_NAME):
		return _error("missing_animation", "The selected character preview has no animation to accept.")
	if source_player.get_parent() != character_root or source_player.root_node != NodePath(".."):
		return _error(
			"invalid_player_root",
			"The character preview AnimationPlayer no longer uses the target root as its track basis.",
		)
	var source_animation := source_player.get_animation(
		CharacterBaker.ANIMATION_NAME
	).duplicate(true) as Animation
	if not is_finite(source_animation.length) or source_animation.length <= 0.0:
		return _error("invalid_duration", "The selected animation has no finite positive duration.")
	var target_result := _validate_clean_target(
		target_scene, session.target_scene_path, session.target_skeleton_signature, source_animation
	)
	if not target_result["ok"]:
		return target_result
	if test_options.get("fail_at", "") == "preflight":
		return _error("injected_failure", "Injected acceptance preflight failure.")

	var library_path: String = path_result["path"]
	var existed := FileAccess.file_exists(library_path)
	if existed and FileAccess.get_read_only_attribute(path_result["absolute_path"]):
		return _error(
			"read_only_resource",
			"The selected library is read-only. Choose or create a project-owned editable library.",
		)
	var before_bytes := (
		FileAccess.get_file_as_bytes(library_path) if existed else PackedByteArray()
	)
	if not existed:
		var empty_staged := _stage_library(AnimationLibrary.new(), library_path)
		if not empty_staged["ok"]:
			return empty_staged
		before_bytes = empty_staged["bytes"]
	var library: AnimationLibrary
	if existed:
		library = ResourceLoader.load(
			library_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
		) as AnimationLibrary
		if library == null:
			return _error(
				"wrong_resource", "The selected .res is not a readable AnimationLibrary."
			)
		library = library.duplicate(true) as AnimationLibrary
	else:
		library = AnimationLibrary.new()
	var collision := library.has_animation(animation_name)
	if collision and not replace_existing:
		return {
			"ok": false,
			"code": "name_collision",
			"message": "Animation '%s' already exists. Confirm Replace to overwrite it." % animation_name,
			"path": library_path,
			"animation_name": animation_name,
		}
	var previous_hash := ""
	if collision:
		previous_hash = animation_hash(library.get_animation(animation_name))
		library.remove_animation(animation_name)
	if library.add_animation(animation_name, source_animation) != OK:
		return _error("library_failed", "Godot could not add the selected animation.")
	if test_options.get("fail_at", "") == "staging":
		return _error("injected_failure", "Injected acceptance staging failure.")
	var staged := _serialize_and_validate_library(
		library,
		library_path,
		animation_name,
		animation_hash(source_animation),
		target_scene,
		session.target_scene_path,
		session.target_skeleton_signature,
	)
	if not staged["ok"]:
		return staged

	var acceptance_id := Session.create_uuid()
	var record := {
		"acceptance_id": acceptance_id,
		"status": "accepted",
		"accepted_at_utc": Session.utc_now(),
		"take_id": session.selected_take_id,
		"generation_record_id": _generation_id_for_take(session, session.selected_take_id),
		"target_scene_path": session.target_scene_path,
		"target_skeleton_signature": session.target_skeleton_signature,
		"destination_path": library_path,
		"animation_name": animation_name,
		"mode": "replace" if collision else "add",
		"created_destination": not existed,
		"animation_sha256": animation_hash(source_animation),
		"previous_animation_sha256": previous_hash,
		"library_file_sha256": _sha256_bytes(staged["bytes"]),
	}
	var transaction := AcceptanceTransaction.new()
	transaction.library_path = library_path
	transaction.session_path = session_path
	transaction.animation_name = animation_name
	transaction.acceptance_id = acceptance_id
	transaction.created_destination = not existed
	transaction.session = session
	# Once Accept creates a project-owned library, Undo removes the animation but
	# retains the empty container for the artist to reuse or delete explicitly.
	transaction.before_exists = true
	transaction.before_bytes = before_bytes
	transaction.after_bytes = staged["bytes"]
	transaction.before_acceptances = session.acceptances.duplicate(true)
	transaction.after_acceptances = session.acceptances.duplicate(true)
	transaction.after_acceptances["%s::%s" % [library_path, animation_name]] = record
	transaction.before_destination = session.animation_destination
	transaction.after_destination = library_path
	transaction.test_options = test_options.duplicate(true)
	return {
		"ok": true,
		"transaction": transaction,
		"record": record,
		"mode": record["mode"],
	}


static func animation_hash(animation: Animation) -> String:
	if animation == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(snappedf(animation.length, 0.000001)))
	context.update(var_to_bytes(animation.loop_mode))
	for track in animation.get_track_count():
		context.update(var_to_bytes(animation.track_get_type(track)))
		context.update(String(animation.track_get_path(track)).to_utf8_buffer())
		context.update(var_to_bytes(animation.track_get_interpolation_type(track)))
		context.update(var_to_bytes(animation.track_is_enabled(track)))
		for key in animation.track_get_key_count(track):
			context.update(var_to_bytes(snappedf(animation.track_get_key_time(track, key), 0.000001)))
			context.update(var_to_bytes(_canonical_key_value(animation.track_get_key_value(track, key))))
	return context.finish().hex_encode()


static func _canonical_key_value(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, 0.000001)
	if value is Vector3:
		return Vector3(
			snappedf(value.x, 0.000001),
			snappedf(value.y, 0.000001),
			snappedf(value.z, 0.000001),
		)
	if value is Quaternion:
		return Quaternion(
			snappedf(value.x, 0.000001),
			snappedf(value.y, 0.000001),
			snappedf(value.z, 0.000001),
			snappedf(value.w, 0.000001),
		)
	return value


static func _validate_animation_name(requested_name: String) -> Dictionary:
	var value := requested_name.strip_edges()
	if value.is_empty():
		return _error("invalid_name", "Enter an animation name before accepting.")
	if value.contains("/") or value.contains("\\") or value.contains(":"):
		return _error(
			"invalid_name", "Animation names cannot contain '/', '\\', or ':'."
		)
	for index in value.length():
		if value.unicode_at(index) < 32:
			return _error("invalid_name", "Animation names cannot contain control characters.")
	return {"ok": true, "name": value}


static func _validate_clean_target(
	target_scene: PackedScene,
	target_path: String,
	expected_signature: String,
	animation: Animation,
) -> Dictionary:
	if target_scene.resource_path != target_path:
		return _error("stale_target", "The preview target no longer matches the session target.")
	var target := target_scene.instantiate() as Node3D
	if target == null:
		return _error("invalid_target", "The selected target could not be instantiated.")
	var skeleton := _find_first(target, "Skeleton3D") as Skeleton3D
	if skeleton == null or SessionStore.skeleton_signature(skeleton) != expected_signature:
		target.free()
		return _error("stale_target", "The target skeleton changed after the preview was built.")
	for track in animation.get_track_count():
		if animation.track_get_type(track) not in [
			Animation.TYPE_POSITION_3D,
			Animation.TYPE_ROTATION_3D,
			Animation.TYPE_SCALE_3D,
		]:
			target.free()
			return _error("unsupported_track", "Accepted animation contains an unsupported track type.")
		var path := animation.track_get_path(track)
		var node := target.get_node_or_null(NodePath(path.get_concatenated_names()))
		if node == null:
			target.free()
			return _error("unresolved_track", "Accepted track cannot resolve node '%s'." % path)
		if not node is Skeleton3D or path.get_subname_count() != 1:
			target.free()
			return _error("unresolved_track", "Accepted track is not a character bone path: '%s'." % path)
		if (node as Skeleton3D).find_bone(path.get_subname(0)) < 0:
			target.free()
			return _error("unresolved_track", "Accepted track cannot resolve bone '%s'." % path)
		for key in animation.track_get_key_count(track):
			var value: Variant = animation.track_get_key_value(track, key)
			if (value is Quaternion and not value.is_finite()) or (
				value is Vector3 and not value.is_finite()
			):
				target.free()
				return _error("non_finite", "Accepted animation contains a non-finite key.")
	target.free()
	return {"ok": true}


static func _serialize_and_validate_library(
	library: AnimationLibrary,
	destination_path: String,
	animation_name: String,
	expected_hash: String,
	target_scene: PackedScene,
	target_path: String,
	target_signature: String,
) -> Dictionary:
	var staged := _stage_library(library, destination_path)
	if not staged["ok"]:
		return staged
	var loaded: AnimationLibrary = staged["library"]
	if (
		not loaded.has_animation(animation_name)
		or animation_hash(loaded.get_animation(animation_name)) != expected_hash
	):
		return _error("serialize_failed", "The staged accepted animation did not validate.")
	var playback_validation := _validate_clean_target(
		target_scene,
		target_path,
		target_signature,
		loaded.get_animation(animation_name),
	)
	if not playback_validation["ok"]:
		return playback_validation
	return {"ok": true, "bytes": staged["bytes"]}


static func _stage_library(library: AnimationLibrary, destination_path: String) -> Dictionary:
	var parent := destination_path.get_base_dir()
	var directory_result := ProjectPaths.ensure_directory(parent)
	if not directory_result["ok"]:
		return directory_result
	var temporary := "%s.accept-preflight-%s.res" % [
		destination_path.trim_suffix(".res"), Session.create_uuid().replace("-", ""),
	]
	if ResourceSaver.save(library, temporary) != OK:
		return _error("serialize_failed", "Godot could not stage the destination library.")
	var loaded := ResourceLoader.load(
		temporary, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	if loaded == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("serialize_failed", "The staged animation library did not reload.")
	var bytes := FileAccess.get_file_as_bytes(temporary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return {"ok": true, "bytes": bytes, "library": loaded}


static func _write_file_state(path: String, should_exist: bool, bytes: PackedByteArray) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "res")
	if not validation["ok"]:
		return validation
	if not should_exist:
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(validation["absolute_path"])
			if remove_error != OK:
				return _error("write_failed", "Godot could not remove the new destination library.")
		return {"ok": true}
	var directory_result := ProjectPaths.ensure_directory(path.get_base_dir())
	if not directory_result["ok"]:
		return directory_result
	var token := Session.create_uuid().replace("-", "")
	var temporary := "%s.accepting-%s" % [validation["absolute_path"], token]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("write_failed", "Godot could not stage the destination library.")
	file.store_buffer(bytes)
	file.flush()
	file.close()
	var backup := "%s.accept-backup-%s" % [validation["absolute_path"], token]
	var had_existing := FileAccess.file_exists(path)
	if had_existing and DirAccess.rename_absolute(validation["absolute_path"], backup) != OK:
		DirAccess.remove_absolute(temporary)
		return _error("write_failed", "Godot could not prepare the destination library.")
	if DirAccess.rename_absolute(temporary, validation["absolute_path"]) != OK:
		if had_existing:
			DirAccess.rename_absolute(backup, validation["absolute_path"])
		DirAccess.remove_absolute(temporary)
		return _error("write_failed", "Godot could not promote the destination library.")
	if had_existing:
		DirAccess.remove_absolute(backup)
	return {"ok": true}


static func _atomic_save_resource(resource: Resource, path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var token := Session.create_uuid().replace("-", "")
	var temporary_path := "%s.accepting-%s.tres" % [path.trim_suffix(".tres"), token]
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	if ResourceSaver.save(resource, temporary_path) != OK:
		return _error("session_save_failed", "Godot could not stage acceptance provenance.")
	var backup := "%s.accept-backup-%s" % [validation["absolute_path"], token]
	if DirAccess.rename_absolute(validation["absolute_path"], backup) != OK:
		DirAccess.remove_absolute(temporary_absolute)
		return _error("session_save_failed", "Godot could not prepare the session update.")
	if DirAccess.rename_absolute(temporary_absolute, validation["absolute_path"]) != OK:
		DirAccess.rename_absolute(backup, validation["absolute_path"])
		DirAccess.remove_absolute(temporary_absolute)
		return _error("session_save_failed", "Godot could not finish acceptance provenance.")
	DirAccess.remove_absolute(backup)
	resource.take_over_path(path)
	return {"ok": true}


static func _refresh_library_cache(path: String, exists: bool) -> void:
	if exists and FileAccess.file_exists(path):
		ResourceLoader.load(path, "AnimationLibrary", ResourceLoader.CACHE_MODE_REPLACE)


static func _generation_id_for_take(session: Resource, take_id: String) -> String:
	for record in session.generation_records:
		for take in record.get("takes", []):
			if take.get("take_id", "") == take_id:
				return String(record.get("record_id", ""))
	return ""


static func _take_record(session: Resource, take_id: String) -> Dictionary:
	for record in session.generation_records:
		for take in record.get("takes", []):
			if take.get("take_id", "") == take_id:
				return take
	return {}


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


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _error(code: String, message: String, technical := "") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"technical": technical,
	}
