@tool
class_name KimodoSessionLifecycle
extends RefCounted

const Paths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const RECEIPT_ROOT := "res://animations/kimodo/session_deletions"


static func valid_id(id: String) -> bool:
	return RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").search(id) != null


static func receipt_path(id: String) -> String:
	return RECEIPT_ROOT.path_join(id).path_join("receipt.json") if valid_id(id) else ""


static func is_retired(id: String) -> bool:
	# Pending deletion also blocks writers until startup recovery resolves it.
	var path := receipt_path(id)
	return not path.is_empty() and FileAccess.file_exists(path)


static func write_receipt(id: String, receipt: Dictionary) -> Dictionary:
	var path := receipt_path(id)
	if path.is_empty():
		return {"ok": false, "message": "Invalid session deletion identity."}
	var validation := Paths.validate_unlinked(path)
	if not validation["ok"]:
		return validation
	var directory := Paths.ensure_directory(path.get_base_dir())
	if not directory["ok"]:
		return directory
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not write the session deletion recovery receipt."}
	file.store_string(JSON.stringify(receipt))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "Could not commit the session deletion recovery receipt."}
	return {"ok": true}
