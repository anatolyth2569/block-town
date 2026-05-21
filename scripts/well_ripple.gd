extends Node3D

@export var water_y: float = 0.80
@export var ring_count: int = 2
@export var max_scale: float = 1.8

func _ready() -> void:
	for i in range(ring_count):
		_add_ring(i)

func _add_ring(i: int) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.24
	tm.outer_radius = 0.26
	tm.rings = 8
	tm.ring_segments = 12
	ring.mesh = tm
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(0.0, water_y, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.60, 0.85, 0.80)
	ring.material_override = mat
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_loops()
	tw.tween_interval(i * 1.4)
	tw.tween_property(ring, "scale", Vector3.ONE * max_scale, 1.5).from(Vector3.ONE * 0.2)
	tw.parallel().tween_method(func(v: float): mat.albedo_color.a = v, 0.80, 0.0, 1.5)
	tw.tween_callback(func():
		if not is_instance_valid(ring): return
		ring.scale = Vector3.ONE * 0.2
		mat.albedo_color.a = 0.80
	)
