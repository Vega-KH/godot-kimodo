@tool
class_name KimodoSession
extends Resource

const SCHEMA_VERSION := 1

@export var schema_version := SCHEMA_VERSION
@export var session_id := ""
@export var title := "Untitled session"
@export var created_at_utc := ""
@export var updated_at_utc := ""
@export var migrated_from_draft_id := ""

@export_file("*.tscn", "*.scn", "*.glb", "*.gltf") var target_scene_path := ""
@export var target_skeleton_signature := ""
@export var rig_profile_path := ""
@export var animation_destination := ""

@export_multiline var prompt := "A person walks forward."
@export_range(1, 900, 1) var duration_frames := 30
@export_range(0, 2147483647, 1) var seed := 1234
@export_range(1, 200, 1) var diffusion_steps := 100
@export_range(1, 2, 1) var requested_take_count := 1
@export var generation_preset := "quality"
@export_multiline var notes := ""

@export var generation_records: Array[Dictionary] = []
@export var active_generation_index := -1
@export var selected_take_id := ""
@export var artifacts: Dictionary = {}


func touch() -> void:
	updated_at_utc = utc_now()


func active_generation_record() -> Dictionary:
	if active_generation_index < 0 or active_generation_index >= generation_records.size():
		return {}
	return generation_records[active_generation_index].duplicate(true)


func active_take_summaries() -> Array:
	var record := active_generation_record()
	var takes: Variant = record.get("takes", [])
	return takes.duplicate(true) if takes is Array else []


static func create_new(session_title := "Untitled session") -> KimodoSession:
	var session := KimodoSession.new()
	session.session_id = create_uuid()
	session.title = session_title.strip_edges()
	if session.title.is_empty():
		session.title = "Untitled session"
	session.created_at_utc = utc_now()
	session.updated_at_utc = session.created_at_utc
	return session


static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


static func create_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var encoded := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		encoded.substr(0, 8), encoded.substr(8, 4), encoded.substr(12, 4),
		encoded.substr(16, 4), encoded.substr(20, 12),
	]
