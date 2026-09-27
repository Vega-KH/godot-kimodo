@tool
class_name KimodoGenerationArchiveManifest
extends Resource

const SCHEMA_VERSION := 1

@export var schema_version := SCHEMA_VERSION
@export var session_id := ""
@export var record_id := ""
@export var rig_snapshot_path := ""
@export var rig_signature := ""
@export var generation_record: Dictionary = {}


func validation_error() -> String:
	if schema_version != SCHEMA_VERSION:
		return "Unsupported generation manifest schema %d." % schema_version
	if session_id.is_empty() or record_id.is_empty():
		return "Generation manifest identity is incomplete."
	if rig_snapshot_path.is_empty() or rig_signature.is_empty():
		return "Generation manifest source rig is incomplete."
	if generation_record.get("record_id", "") != record_id:
		return "Generation manifest record identity does not match."
	var takes: Variant = generation_record.get("takes", [])
	if not takes is Array or takes.is_empty():
		return "Generation manifest contains no takes."
	return ""
