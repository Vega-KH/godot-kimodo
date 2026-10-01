class_name KimodoRigProfileStore
extends RefCounted

const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const DEFAULT_DIRECTORY := "res://animations/kimodo/rig_profiles"

static func save(profile: Resource, path: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var directory := ProjectPaths.ensure_directory(validation["path"].get_base_dir())
	if not directory["ok"]:
		return directory
	if profile == null or not profile is Profile:
		return _error("invalid_profile", "The selected resource is not a Kimodo rig profile.")
	var token := str(Time.get_ticks_usec())
	var temporary := "%s.saving-%s.tres" % [path.trim_suffix(".tres"), token]
	if ResourceSaver.save(profile, temporary) != OK:
		return _error("save_failed", "Godot could not stage the rig profile.")
	var absolute: String = validation["absolute_path"]
	var temporary_absolute := ProjectSettings.globalize_path(temporary)
	var backup := "%s.backup-%s" % [absolute, token]
	var existed := FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(absolute, backup) != OK:
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not prepare the rig profile update.")
	if DirAccess.rename_absolute(temporary_absolute, absolute) != OK:
		if existed:
			DirAccess.rename_absolute(backup, absolute)
		DirAccess.remove_absolute(temporary_absolute)
		return _error("save_failed", "Godot could not finish saving the rig profile.")
	if existed:
		DirAccess.remove_absolute(backup)
	profile.take_over_path(validation["path"])
	return {"ok": true, "path": validation["path"]}

static func load_current(path: String, skeleton: Skeleton3D, signature: String) -> Dictionary:
	var validation := ProjectPaths.validate_file(path, "tres")
	if not validation["ok"]:
		return validation
	var loaded := ResourceLoader.load(validation["path"], "KimodoRigProfile", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded is Profile:
		return _error("invalid_profile", "The saved rig profile could not be loaded.")
	if loaded.schema_version == 1:
		loaded.upgrade_legacy(skeleton, signature)
	if not loaded.is_current(skeleton, signature):
		return _error("stale_profile", "The rig profile does not match the character's current skeleton. Open Rig Setup to review it.")
	return {"ok": true, "profile": loaded, "path": validation["path"]}

static func suggested_path(scene_path: String) -> String:
	var stem := scene_path.get_file().get_basename().validate_filename().to_snake_case()
	var identity := scene_path.md5_text().substr(0, 8)
	return DEFAULT_DIRECTORY.path_join("%s_%s_rig.tres" % [(stem if not stem.is_empty() else "character"), identity])

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
