class_name MmcpGltfLoader
extends RefCounted


static func load_from_buffer(data: PackedByteArray, base_path: String = "res://") -> Node:
	var state := parse_from_buffer(data, base_path)
	if state == null:
		return null
	return GLTFDocument.new().generate_scene(state)


static func parse_from_buffer(data: PackedByteArray, base_path: String = "res://") -> GLTFState:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_buffer(data, base_path, state)
	if error != OK:
		push_error("MMCP glTF import failed with error %d" % error)
		return null
	return state
