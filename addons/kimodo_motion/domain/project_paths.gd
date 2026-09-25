class_name KimodoProjectPaths
extends RefCounted


static func validate_directory(path: String) -> Dictionary:
	return _validate(path, "", true)


static func validate_file(path: String, required_extension: String = "") -> Dictionary:
	return _validate(path, required_extension, false)


static func ensure_directory(path: String) -> Dictionary:
	var validation := validate_directory(path)
	if not validation["ok"]:
		return validation
	var error := DirAccess.make_dir_recursive_absolute(validation["absolute_path"])
	if error != OK:
		return _error(
			"create_failed",
			"Godot could not create the project directory.",
			"DirAccess.make_dir_recursive_absolute returned %d" % error,
		)
	return validation


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
