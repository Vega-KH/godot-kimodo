extends SceneTree

const Baker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd"
)
const SOURCE := "res://tests/native/generated/soma77_walk.tscn"
const TARGET := "res://tests/retargeting/fixtures/godot_humanoid_a_pose.tscn"
const OUTPUT_DIRECTORY := "res://tests/retargeting/generated"


func _init() -> void:
	var source := (load(SOURCE) as PackedScene).instantiate()
	var target := (load(TARGET) as PackedScene).instantiate()
	# This tool owns its named review fixture and rebuilds only those exact files.
	var scene_path := OUTPUT_DIRECTORY.path_join("soma77_walk_humanoid.tscn")
	var library_path := OUTPUT_DIRECTORY.path_join("soma77_walk_humanoid.res")
	if FileAccess.file_exists(scene_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))
	if FileAccess.file_exists(library_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(library_path))
	var result := Baker.bake(source, target, OUTPUT_DIRECTORY, "soma77_walk_humanoid")
	source.free()
	target.free()
	if result.is_empty():
		printerr("FAIL: could not bake humanoid review fixture")
		quit(1)
		return
	print("PASS: wrote humanoid motion fixture to ", result["scene_path"])
	quit(0)
