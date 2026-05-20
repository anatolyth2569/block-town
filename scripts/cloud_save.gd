extends Node

const FIREBASE_DB_URL := "REPLACE_WITH_YOUR_FIREBASE_URL"
const UID_PATH := "user://uid.txt"

var _uid: String = ""

func _ready() -> void:
	_uid = _load_or_create_uid()

func _load_or_create_uid() -> String:
	if FileAccess.file_exists(UID_PATH):
		var f := FileAccess.open(UID_PATH, FileAccess.READ)
		var id := f.get_as_text().strip_edges()
		if id.length() > 0:
			return id
	var id := "%08x%08x" % [randi(), randi()]
	var f := FileAccess.open(UID_PATH, FileAccess.WRITE)
	f.store_string(id)
	return id

func is_configured() -> bool:
	return FIREBASE_DB_URL != "REPLACE_WITH_YOUR_FIREBASE_URL" and FIREBASE_DB_URL.length() > 0

func push(data: Dictionary) -> void:
	if not is_configured():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request("%s/saves/%s.json" % [FIREBASE_DB_URL, _uid], [], HTTPClient.METHOD_PUT, JSON.stringify(data))

func fetch(on_done: Callable) -> void:
	if not is_configured():
		on_done.call(null)
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code == 200:
			var parsed = JSON.parse_string(body.get_string_from_utf8())
			if parsed is Dictionary:
				on_done.call(parsed)
				return
		on_done.call(null)
	)
	http.request("%s/saves/%s.json" % [FIREBASE_DB_URL, _uid])
