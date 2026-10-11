@tool
extends EditorPlugin

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const PosePanel := preload("res://addons/kimodo_motion/ui/pose_library_panel.gd")

var _client: Node
var _generation_client: Node
var _dock: Control
var _pose_panel: Control


func _enter_tree() -> void:
	_client = Client.new()
	_client.name = "MmcpCapabilitiesClient"
	add_child(_client)
	_generation_client = GenerationClient.new()
	_generation_client.name = "MmcpGenerationClient"
	add_child(_generation_client)
	_dock = Dock.new()
	_dock.configure(_client, _generation_client, self)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)
	_pose_panel = PosePanel.new()
	_pose_panel.editor_plugin = self
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, _pose_panel)
	_pose_panel.prepare_constraint = Callable(_dock, "prepare_pose_keyframe")
	_pose_panel.queue_constraint = Callable(_dock, "queue_pose_keyframe")
	_pose_panel.remove_constraint = Callable(_dock, "remove_pose_keyframe")
	_dock.pose_keyframes_changed.connect(_pose_panel.set_constraint_entries)
	print("[Kimodo Motion Studio] editor plugin enabled")


func _exit_tree() -> void:
	if _pose_panel != null:
		remove_control_from_docks(_pose_panel)
		_pose_panel.free()
		_pose_panel = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null
	if _client != null:
		_client.disconnect_from_backend()
		_client.free()
		_client = null
	if _generation_client != null:
		_generation_client.reset()
		_generation_client.free()
		_generation_client = null
