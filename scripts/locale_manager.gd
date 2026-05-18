extends Node

var _data: Dictionary = {}

func _ready() -> void:
	var file := FileAccess.open("res://locale/th.json", FileAccess.READ)
	if file == null:
		push_error("LocaleManager: cannot open res://locale/th.json")
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("LocaleManager: failed to parse th.json")

func resource(key: String) -> String:
	return _data.get("resources", {}).get(key, key)

func building(key: String) -> String:
	return _data.get("buildings", {}).get(key, key)

func worker(key: String) -> String:
	return _data.get("workers", {}).get(key, key)

func worker_states(job_id: String) -> Array:
	return _data.get("worker_states", {}).get(job_id, ["💤", "🏃", "⚙️", "📦"])

func category(key: String) -> String:
	return _data.get("categories", {}).get(key, key)

func status(key: String) -> String:
	return _data.get("status", {}).get(key, key)

func t(section: String, key: String) -> String:
	return _data.get(section, {}).get(key, key)
