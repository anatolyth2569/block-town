extends Node3D

func _process(delta: float) -> void:
	rotation.z += 0.9 * delta
