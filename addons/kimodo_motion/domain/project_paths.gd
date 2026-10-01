class_name KimodoProjectPaths
extends RefCounted


static func validate_directory(path: String) -> Dictionary:
	return _validate(path, "", true)


static func validate_file(path: String, required_extension: String = "") -> Dictionary:
	return _validate(path, required_extension, false)


static func validate_output_file(path: String, required_extension := "") -> Dictionary:
	var result := validate_file(path, required_extension)
	if not result["ok"]:
		return result
	var normalized: String = result["path"].to_lower()
	for reserved in ["res://animations/kimodo/session_data/", "res://animations/kimodo/session_deletions/"]:
		if normalized.begins_with(reserved):
			return _error("reserved_storage", "Save exports and production libraries outside Kimodo's managed session storage.")
	return validate_unlinked(result["path"])


static func validate_unlinked(path: String) -> Dictionary:
	# Used for both files and directories. Godot may localize an existing
	# directory with a trailing slash; do not apply file-only validation here.
	var result := _validate(path, "", true)
	if not result["ok"]:
		return result
	var current := ProjectSettings.globalize_path("res://").simplify_path()
	for part in String(result["path"]).trim_prefix("res://").split("/", false):
		var parent := DirAccess.open(current)
		if parent == null:
			# A missing ancestor cannot currently hide a link.
			break
		if parent.is_link(part):
			return _error("linked_path", "Session deletion cannot follow symbolic links or directory junctions. Move the session storage to an ordinary project directory.", current.path_join(part))
		current = current.path_join(part)
	return result


static func ensure_directory(path: String) -> Dictionary:
	var validation := validate_directory(path)
	if not validation["ok"]:
		return validation
	var unlinked := validate_unlinked(path)
	if not unlinked["ok"]:
		return unlinked
	var error := DirAccess.make_dir_recursive_absolute(validation["absolute_path"])
	if error != OK:
		return _error(
			"create_failed",
			"Godot could not create the project directory.",
			"DirAccess.make_dir_recursive_absolute returned %d" % error,
		)
	return validation


static func ensure_output_directory(path: String) -> Dictionary:
	var validation := validate_output_file(path.path_join("kimodo_output.res"), "res")
	return ensure_directory(path) if validation["ok"] else validation


static func _validate(path: String, required_extension: String, directory: bool) -> Dictionary:
	var clean := path.strip_edges().replace("\\", "/")
	if not clean.begins_with("res://"):
		return _error(
			"outside_project",
			"Path must be inside the project and begin with res://.",
		)
	var absolute := ProjectSettings.globalize_path(clean).simplify_path().replace("\\", "/")
	var project_root := (
		ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").trim_suffix("/")
	)
	var compare_absolute := absolute.to_lower()
	var compare_root := project_root.to_lower()
	if compare_absolute != compare_root and not compare_absolute.begins_with(compare_root + "/"):
		return _error(
			"outside_project",
			"Path resolves outside the Godot project.",
			absolute,
		)
	var normalized := ProjectSettings.localize_path(absolute).replace("\\", "/")
	if not normalized.begins_with("res://"):
		return _error("outside_project", "Path could not be localized to this project.")
	if directory and compare_absolute == compare_root:
		return _error("project_root", "Choose a directory below res://, not the project root.")
	if not directory:
		if normalized.ends_with("/"):
			return _error("not_a_file", "A file path is required.")
		if not required_extension.is_empty():
			var expected := required_extension.to_lower().trim_prefix(".")
			if normalized.get_extension().to_lower() != expected:
				return _error(
					"wrong_extension",
					"Path must use the .%s extension." % expected,
				)
	return {
		"ok": true,
		"path": normalized,
		"absolute_path": absolute,
	}


static func _error(code: String, message: String, technical: String = "") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"technical": technical,
	}
