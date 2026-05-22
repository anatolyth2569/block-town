extends Node

const TRUCK_GLB    := "res://assets/vehicles/truck.glb"
const DELIVERY_GLB := "res://assets/vehicles/delivery.glb"
const TRACTOR_GLB  := "res://assets/vehicles/tractor.glb"

const VEHICLE_SPEED: float = 14.0  # world-units per second
const DEPOT_WAIT:    float = 1.8   # seconds parked at depot
const SPAWN_MARGIN:  float = 12.0  # units beyond map edge
const VEHICLE_SCALE: float = 1.4

# Called externally (e.g. from a farm harvest) to show a tractor
func spawn_tractor(farm_world_pos: Vector3) -> void:
	_spawn_delivery(TRACTOR_GLB, farm_world_pos)

func _spawn_delivery(glb_path: String, override_target: Vector3 = Vector3(-9999, 0, 0)) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var grid := _get_grid_manager()
	var map_size := Vector3(
		GridManager.GRID_WIDTH  * GridManager.CELL_SIZE,
		0.0,
		GridManager.GRID_HEIGHT * GridManager.CELL_SIZE
	)
	var map_center_z := map_size.z * 0.5

	var target := Vector3(map_size.x * 0.5, 0.0, map_center_z)
	if override_target.x > -9000.0:
		target = override_target

	# Spawn off the right edge of the map
	var spawn_x := map_size.x + SPAWN_MARGIN
	var spawn := Vector3(spawn_x, 0.0, target.z)
	var exit  := spawn  # drive back the same way

	var vehicle := Node3D.new()
	vehicle.position = spawn
	vehicle.scale    = Vector3.ONE * VEHICLE_SCALE
	# Face left (-X direction) when driving toward the depot
	vehicle.rotation_degrees.y = -90.0

	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed:
			vehicle.add_child(packed.instantiate())

	scene_root.add_child(vehicle)

	var dist   := spawn.distance_to(target)
	var travel := dist / VEHICLE_SPEED

	var tw := create_tween()
	# Drive in
	tw.tween_property(vehicle, "position", target, travel).set_ease(Tween.EASE_IN_OUT)
	# Wait at depot
	tw.tween_interval(DEPOT_WAIT)
	# Face right (+X) to drive back out
	tw.tween_callback(func(): vehicle.rotation_degrees.y = 90.0)
	# Drive out
	tw.tween_property(vehicle, "position", exit, travel).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(vehicle.queue_free)

func _get_grid_manager() -> GridManager:
	var nodes := get_tree().get_nodes_in_group("grid_manager")
	if nodes.size() > 0:
		return nodes[0] as GridManager
	return null
