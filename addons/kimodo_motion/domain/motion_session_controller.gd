@tool
class_name KimodoSessionController
extends Node

signal session_changed(session: Resource, path: String)
signal save_state_changed(state: String, message: String)

const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")

var session: Resource
var path := ""
var dirty := false
var debounce_seconds := 0.4
var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = debounce_seconds
	_save_timer.timeout.connect(flush)
	add_child(_save_timer)


func create(title: String) -> Dictionary:
	var close_result := flush()
	if not close_result["ok"]:
		return close_result
	var next := SessionStore.create_session(title)
	var result := SessionStore.save_new(next, title)
	if not result["ok"]:
		return result
	session = next
	path = result["path"]
	dirty = false
	session_changed.emit(session, path)
	save_state_changed.emit("saved", "Saved")
	return {"ok": true, "session": session, "path": path}


func open(session_path: String) -> Dictionary:
	var close_result := flush()
	if not close_result["ok"]:
		return close_result
	var result := SessionStore.open(session_path)
	if not result["ok"]:
		return result
	session = result["session"]
	path = result["path"]
	dirty = false
	session_changed.emit(session, path)
	save_state_changed.emit("saved", "Saved")
	return result


func mark_dirty() -> void:
	if session == null or path.is_empty():
		return
	dirty = true
	save_state_changed.emit("saving", "Saving…")
	if _save_timer != null:
		_save_timer.start(debounce_seconds)


func flush() -> Dictionary:
	if session == null or path.is_empty() or not dirty:
		return {"ok": true, "path": path}
	if _save_timer != null:
		_save_timer.stop()
	var result := SessionStore.save(session, path)
	if result["ok"]:
		dirty = false
		save_state_changed.emit("saved", "Saved")
	else:
		save_state_changed.emit("error", result["message"])
	return result


func close() -> Dictionary:
	var result := flush()
	if not result["ok"]:
		return result
	session = null
	path = ""
	dirty = false
	session_changed.emit(null, "")
	return {"ok": true}


func _exit_tree() -> void:
	flush()
