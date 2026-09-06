extends Node

const DEFAULT_PORT := 18766

var port := DEFAULT_PORT
var request_count := 0
var _server := TCPServer.new()
var _responses: Array[Dictionary] = []
var _connections: Array[Dictionary] = []


func start(listen_port: int = DEFAULT_PORT) -> Error:
	port = listen_port
	return _server.listen(port, "127.0.0.1")


func stop() -> void:
	for connection in _connections:
		var peer: StreamPeerTCP = connection["peer"]
		peer.disconnect_from_host()
	_connections.clear()
	_server.stop()


func enqueue_json(body: String, delay_seconds: float = 0.0, status: int = 200) -> void:
	_responses.append({
		"body": body,
		"delay_seconds": delay_seconds,
		"status": status,
	})


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	# Accept at most one socket per frame. On Windows, a canceled connection can
	# leave `is_connection_available()` true briefly after the queue is drained.
	if _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_connections.append({"peer": peer, "response": {}, "ready_at": 0})

	for index in range(_connections.size() - 1, -1, -1):
		var connection := _connections[index]
		var peer: StreamPeerTCP = connection["peer"]
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_NONE:
			_connections.remove_at(index)
			continue
		if connection["response"].is_empty() and peer.get_available_bytes() > 0:
			peer.get_data(peer.get_available_bytes())
			request_count += 1
			var response: Dictionary = _responses.pop_front() if not _responses.is_empty() else {
				"body": "{}", "delay_seconds": 0.0, "status": 500,
			}
			connection["response"] = response
			connection["ready_at"] = Time.get_ticks_msec() + int(
				float(response["delay_seconds"]) * 1000.0
			)
			_connections[index] = connection
		if not connection["response"].is_empty() and Time.get_ticks_msec() >= connection["ready_at"]:
			_send_response(peer, connection["response"])
			_connections.remove_at(index)


func _send_response(peer: StreamPeerTCP, response: Dictionary) -> void:
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var body: String = response["body"]
	var status: int = response["status"]
	var reason := "OK" if status == 200 else "Error"
	var body_bytes := body.to_utf8_buffer()
	var headers := (
		"HTTP/1.1 %d %s\r\n" % [status, reason]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body_bytes.size()
		+ "Connection: close\r\n\r\n"
	).to_utf8_buffer()
	# Never block the main thread if a cancellation races this response.
	peer.put_partial_data(headers + body_bytes)
	peer.disconnect_from_host()
