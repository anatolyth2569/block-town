extends Node

# Ordered list of buildings waiting for a Builder (placement order = priority)
var _queue: Array = []

# Buildings currently being constructed (each has a Builder worker assigned)
var _active: Array = []

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 1.5
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)

# Called when a building is placed and needs construction
func register(building: Node) -> void:
	if not _queue.has(building):
		_queue.append(building)
	_tick()

# Called when a building is demolished before construction completes
func unregister(building: Node) -> void:
	_queue.erase(building)
	_active.erase(building)

# Called by building when construction trips are all done
func on_build_complete(building: Node) -> void:
	_queue.erase(building)
	_active.erase(building)
	_tick()

# Builder NPC polls this to find jobs
func get_active_buildings() -> Array:
	return _active.duplicate()

func _tick() -> void:
	# Prune invalid references
	for i in range(_queue.size() - 1, -1, -1):
		if not is_instance_valid(_queue[i]):
			_queue.remove_at(i)
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]):
			_active.remove_at(i)

	# Move all queued buildings to active immediately
	for b in _queue:
		if not _active.has(b):
			_active.append(b)
			b.begin_construction()
	_queue.clear()

func _set_build_label(building: Node, text: String) -> void:
	if not is_instance_valid(building):
		return
	var lbl := building.get_node_or_null("StatusLabel") as Label3D
	if lbl != null:
		lbl.text = text
