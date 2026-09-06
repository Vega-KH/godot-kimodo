extends SceneTree

const Loader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")
const Baker := preload("res://addons/kimodo_motion/animation/native_animation_baker.gd")
const SOURCE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const OUTPUT_DIRECTORY := "res://tests/native/generated"


func _init() -> void:
	var imported: Node = Loader.load_from_buffer(FileAccess.get_file_as_bytes(SOURCE))
	if imported == null:
		quit(1)
		return
	var result := Baker.bake(imported, OUTPUT_DIRECTORY, "soma77_walk")
	imported.free()
	if result.is_empty():
		quit(1)
		return
	print("Generated native fixture: ", result["scene_path"])
	quit(0)

