extends Node3D

var _building: Node = null

func _process(delta: float) -> void:
	if _building == null or not is_instance_valid(_building):
		var p: Node = get_parent()
		while p != null:
			if p.has_method("get_production_status"):
				_building = p
				break
			p = p.get_parent()

	var spinning: bool = true
	if _building != null and is_instance_valid(_building):
		spinning = _building.get_production_status() == "Producing"

	if spinning:
		rotation.z += 0.9 * delta
