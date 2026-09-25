@tool
class_name KimodoMotionDraft
extends Resource

const SCHEMA_VERSION := 1

@export var schema_version := SCHEMA_VERSION
@export var draft_id := ""
@export var created_at_utc := ""
@export var updated_at_utc := ""

@export_file("*.tscn", "*.scn", "*.glb", "*.gltf") var target_scene_path := ""
@export var target_skeleton_signature := ""
@export var rig_profile_path := ""
@export var animation_destination := ""

@export_multiline var prompt := "A person walks forward."
@export_range(1, 900, 1) var duration_frames := 30
@export_range(0, 2147483647, 1) var seed := 1234
@export_range(1, 200, 1) var diffusion_steps := 100
@export_range(1, 16, 1) var requested_candidate_count := 1
@export var generation_preset := "quality"
@export_multiline var notes := ""

@export var generation_records: Array[Dictionary] = []
@export var active_generation_index := -1
@export var artifacts: Dictionary = {}


func touch() -> void:
	updated_at_utc = utc_now()


func active_generation_record() -> Dictionary:
	if active_generation_index < 0 or active_generation_index >= generation_records.size():
		return {}
	return generation_records[active_generation_index].duplicate(true)


static func create_new() -> KimodoMotionDraft:
	var draft := KimodoMotionDraft.new()
	draft.draft_id = create_uuid()
	draft.created_at_utc = utc_now()
	draft.updated_at_utc = draft.created_at_utc
	return draft


static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


static func create_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var encoded := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		encoded.substr(0, 8),
		encoded.substr(8, 4),
		encoded.substr(12, 4),
		encoded.substr(16, 4),
		encoded.substr(20, 12),
	]
