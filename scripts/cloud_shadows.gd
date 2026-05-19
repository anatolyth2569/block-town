extends Node3D

const CLOUD_COUNT := 2
const SHADOW_Y := 2.0           # above buildings (~1.1 units tall)
const MAP_W := 60.0             # GRID_WIDTH * CELL_SIZE
const MAP_D := 60.0             # GRID_HEIGHT * CELL_SIZE
const SPAWN_MARGIN := 20.0

var _clouds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _shadow_mat: StandardMaterial3D

func _ready() -> void:
	_rng.randomize()
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.03, 0.05, 0.10, 0.22)
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for _i in CLOUD_COUNT:
		_spawn_cloud()

func _spawn_cloud() -> void:
	var root := Node3D.new()
	var blob_count: int = _rng.randi_range(3, 5)
	for _b in blob_count:
		var inst := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(
			_rng.randf_range(7.0, 13.0),
			_rng.randf_range(5.0, 9.0)
		)
		plane.subdivide_depth = 0
		plane.subdivide_width = 0
		inst.mesh = plane
		inst.material_override = _shadow_mat
		inst.position = Vector3(
			_rng.randf_range(-5.0, 5.0),
			0.0,
			_rng.randf_range(-4.0, 4.0)
		)
		root.add_child(inst)

	root.position = Vector3(
		_rng.randf_range(-SPAWN_MARGIN, MAP_W + SPAWN_MARGIN),
		SHADOW_Y,
		_rng.randf_range(-10.0, MAP_D + 10.0)
	)

	add_child(root)
	_clouds.append({
		"node": root,
		"speed": _rng.randf_range(0.8, 1.5),
		"dir": _rand_dir(),
	})

func _rand_dir() -> Vector3:
	var a := _rng.randf_range(-0.25, 0.25)
	return Vector3(cos(a), 0.0, sin(a)).normalized()

func _process(delta: float) -> void:
	for data in _clouds:
		var n: Node3D = data["node"]
		n.position += (data["dir"] as Vector3) * (data["speed"] as float) * delta
		if n.position.x > MAP_W + SPAWN_MARGIN:
			n.position.x = -SPAWN_MARGIN
			n.position.z = _rng.randf_range(-10.0, MAP_D + 10.0)
			data["dir"] = _rand_dir()
		elif n.position.x < -(SPAWN_MARGIN + 5.0):
			n.position.x = MAP_W + SPAWN_MARGIN
			n.position.z = _rng.randf_range(-10.0, MAP_D + 10.0)
			data["dir"] = _rand_dir()
