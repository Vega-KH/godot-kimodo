class_name MmcpGltfLoader
extends RefCounted


static func load_from_buffer(
	data: PackedByteArray, base_path: String = "res://", report_error := true
) -> Node:
	var state := parse_from_buffer(data, base_path, report_error)
	if state == null:
		return null
	return GLTFDocument.new().generate_scene(state)


static func parse_from_buffer(
	data: PackedByteArray, base_path: String = "res://", report_error := true
) -> GLTFState:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_buffer(data, base_path, state)
	if error != OK:
		if report_error:
			push_error("MMCP glTF import failed with error %d" % error)
		return null
	return state
