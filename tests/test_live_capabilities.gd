extends SceneTree

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var url := Client.DEFAULT_URL
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == "--url" and index + 1 < arguments.size():
			url = arguments[index + 1]

	var client := Client.new()
	client.timeout_seconds = 20.0
	root.add_child(client)
	client.connect_to_backend(url)
	var deadline := Time.get_ticks_msec() + 25000
	while client.state == Client.ConnectionState.CONNECTING and Time.get_ticks_msec() < deadline:
		await process_frame

	if client.state != Client.ConnectionState.READY:
		printerr("FAIL: live capability handshake: ", client.message, " ", client.technical_details)
		quit(1)
		return

	var model: RefCounted = client.capabilities
	print(
		"PASS: live MMCP capabilities — model=%s fps=%.0f joints=%d constraints=%d contacts=%d"
		% [
			model.model_id,
			model.fps,
			model.joint_names.size(),
			model.constraint_types.size(),
			model.contact_joints.size(),
		]
	)
	client.disconnect_from_backend()
	client.queue_free()
	await process_frame
	quit(0)
