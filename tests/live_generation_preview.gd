extends Control

const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const Preview := preload("res://addons/kimodo_motion/ui/soma77_preview.gd")

var _preview: Control
var _capture_dir := ""
var _capture_frame := 0


func _ready() -> void:
	var motion_path := ""
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == "--motion" and index + 1 < arguments.size():
			motion_path = arguments[index + 1]
		elif arguments[index] == "--capture-dir" and index + 1 < arguments.size():
			_capture_dir = arguments[index + 1]
	if motion_path.is_empty():
		push_error("Pass --motion <generated.gltf> to the live preview scene")
		get_tree().quit(1)
		return
	var result := MotionResponse.parse(FileAccess.get_file_as_bytes(motion_path), 30, 30.0)
	if not result["ok"]:
		push_error("Live preview rejected motion: %s" % result["message"])
		get_tree().quit(1)
		return

	_preview = Preview.new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_preview)
	await get_tree().process_frame
	if not _preview.set_motion(result["motion"]):
		push_error("Live preview could not take ownership of generated motion")
		get_tree().quit(1)
		return

	var label := Label.new()
	label.text = "LIVE MMCP • A person walks forward. • SOMA-77"
	label.position = Vector2(18.0, 16.0)
	label.add_theme_font_size_override("font_size", 22)
	add_child(label)


func _process(_delta: float) -> void:
	if _capture_dir.is_empty() or _preview == null or not _preview.has_motion():
		return
	_capture_frame += 1
	if _capture_frame in [2, 8, 14]:
		var viewport: SubViewport = _preview.get_node("PreviewViewport")
		var image := viewport.get_texture().get_image()
		var error := image.save_png(_capture_dir.path_join("frame_%02d.png" % _capture_frame))
		if error != OK:
			push_error("Could not save preview frame %d" % _capture_frame)
	if _capture_frame >= 15:
		get_tree().quit(0)
