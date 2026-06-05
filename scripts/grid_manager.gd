class_name GridManager
extends Node3D

const GRID_WIDTH: int = 20
const GRID_HEIGHT: int = 20
const CELL_SIZE: float = 3.0

enum Terrain { GRASS, WATER, FOREST, ROAD, PAVED_ROAD }

var _grid: Dictionary = {}
var _buildings: Dictionary = {}
var _terrain: Dictionary = {}
var _cell_decos: Dictionary = {}   # Vector2i -> Node3D
var _tree_nodes: Dictionary = {}    # Vector2i -> Node3D (container)
var _tree_harvests: Dictionary = {} # Vector2i -> int (remaining)
var _cleared_tree_cells: Dictionary = {} # Vector2i -> true  (manually sold — never regrow)
var _pond_origins: Dictionary = {}       # Vector2i origin -> int radius
var _pond_nodes: Dictionary = {}         # Vector2i origin -> Node3D container
var _cell_to_pond: Dictionary = {}       # Vector2i cell -> Vector2i origin
var _shadow_counts: Dictionary = {}      # Vector2i cell -> int (number of shadow sources)
var _pollution_counts: Dictionary = {}   # Vector2i cell -> int (number of pollution sources)
var _water_cell_bonuses: Dictionary = {} # Vector2i cell -> int (water bonus from wind pumps)
var _electricity_counts: Dictionary = {} # Vector2i cell -> int (electricity level, tiered 3-2-1)
var _field_harvest_at: Dictionary = {}   # Vector2i cell -> float (unix time when ready to harvest)
var _field_job_claimed: Dictionary = {}  # Vector2i cell -> String (job type being worked on)
var _field_inputs: Dictionary = {}       # Vector2i cell -> {res -> int} (all resources delivered by farmer)

const HARVEST_BIG: int = 15
const HARVEST_SMALL: int = 7

const COLOR_GRASS  := Color(0.26, 0.52, 0.09)
const COLOR_WATER  := Color(0.18, 0.52, 0.70)
const COLOR_FOREST := Color(0.09, 0.28, 0.08)
const COLOR_ROAD       := Color(0.74, 0.60, 0.38)
const COLOR_PAVED_ROAD := Color(0.54, 0.54, 0.58)

const GRASS_BLOCK_PATH: String = "res://assets/used/block-grass-low-large.glb"
const STONES_PATH: String = "res://assets/used/stones.glb"
const TREE_SCENE_PATH: String = "res://scenes/tree.tscn"

func _ready() -> void:
	add_to_group("grid_manager")
	_generate_terrain()
	_create_tiles()
	_create_grid_lines()
	_create_grid_labels()

func _create_grid_labels() -> void:
	var col_chars := "ABCDEFGHIJKLMNOPQRST"
	for x in range(GRID_WIDTH):
		var lbl := Label3D.new()
		lbl.text = col_chars[x]
		lbl.font_size = 28
		lbl.modulate = Color(1.0, 1.0, 1.0)
		lbl.outline_size = 4
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = Vector3(x * CELL_SIZE + CELL_SIZE * 0.5, 0.8, -1.2)
		add_child(lbl)

	for z in range(GRID_HEIGHT):
		var lbl := Label3D.new()
		lbl.text = str(z + 1)
		lbl.font_size = 28
		lbl.modulate = Color(1.0, 1.0, 1.0)
		lbl.outline_size = 4
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = Vector3(-1.2, 0.8, z * CELL_SIZE + CELL_SIZE * 0.5)
		add_child(lbl)

# --- Terrain generation ---

func _generate_terrain() -> void:
	for x in range(GRID_WIDTH):
		for z in range(GRID_HEIGHT):
			var cell := Vector2i(x, z)
			# water border
			if x == 0 or x == GRID_WIDTH - 1 or z == 0 or z == GRID_HEIGHT - 1:
				_terrain[cell] = Terrain.WATER
			elif x >= GRID_WIDTH - 2:   # x=18,19 = right water edge
				_terrain[cell] = Terrain.WATER
			# dense left-side forest (Town Star style)
			elif x == 1 and z >= 1 and z <= 18:
				_terrain[cell] = Terrain.FOREST
			elif x == 2 and z >= 1 and z <= 18:
				_terrain[cell] = Terrain.FOREST
			elif x == 3 and z >= 1 and z <= 17:
				_terrain[cell] = Terrain.FOREST
			elif x == 4 and z >= 2 and z <= 14:
				_terrain[cell] = Terrain.FOREST
			elif x == 5 and z >= 3 and z <= 7:
				_terrain[cell] = Terrain.FOREST
			# top forest cluster
			elif x >= 6 and x <= 9 and z == 1:
				_terrain[cell] = Terrain.FOREST
			elif (x == 7 or x == 8) and z == 2:
				_terrain[cell] = Terrain.FOREST
			# right-side forest — with gap in middle (z=8-11) for roads
			elif x == 15 and (z <= 6 or z >= 13):
				_terrain[cell] = Terrain.FOREST
			elif x == 16 and (z <= 7 or z >= 12):
				_terrain[cell] = Terrain.FOREST
			else:
				_terrain[cell] = Terrain.GRASS

# --- Visual ---

func _create_tiles() -> void:
	for x in range(GRID_WIDTH):
		for z in range(GRID_HEIGHT):
			var cell := Vector2i(x, z)
			_spawn_tile(cell, _terrain.get(cell, Terrain.GRASS))

	for cell in _terrain:
		match _terrain[cell]:
			Terrain.FOREST:
				_spawn_tree(cell)
			Terrain.GRASS:
				_spawn_grass_deco(cell)

	# Ground collider (top surface at y=0)
	var body := StaticBody3D.new()
	body.name = "GroundCollider"
	add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GRID_WIDTH * CELL_SIZE, 0.1, GRID_HEIGHT * CELL_SIZE)
	col.shape = box
	col.position = Vector3(GRID_WIDTH * CELL_SIZE * 0.5, -0.05, GRID_HEIGHT * CELL_SIZE * 0.5)
	body.add_child(col)

func _force_color(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.92
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_force_color(child, color)

func _spawn_tile(cell: Vector2i, terrain: Terrain) -> void:
	var cx := cell.x * CELL_SIZE + CELL_SIZE * 0.5
	var cz := cell.y * CELL_SIZE + CELL_SIZE * 0.5

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var center_y: float = -0.06
	var mat := StandardMaterial3D.new()

	match terrain:
		Terrain.GRASS:
			mesh.size = Vector3(CELL_SIZE, 0.18, CELL_SIZE)
			mat.albedo_color = COLOR_GRASS
			mat.roughness = 0.95
			center_y = -0.09
		Terrain.WATER:
			mesh.size = Vector3(CELL_SIZE, 0.12, CELL_SIZE)
			mat.albedo_color = COLOR_WATER
			mat.roughness = 0.1
			mat.metallic_specular = 0.6
			center_y = -0.10
		Terrain.FOREST:
			mesh.size = Vector3(CELL_SIZE, 0.18, CELL_SIZE)
			mat.albedo_color = COLOR_FOREST
			mat.roughness = 0.9
			center_y = -0.09
		Terrain.ROAD:
			mesh.size = Vector3(CELL_SIZE, 0.20, CELL_SIZE)
			mat.albedo_color = COLOR_ROAD
			mat.roughness = 0.85
			center_y = -0.08
		Terrain.PAVED_ROAD:
			mesh.size = Vector3(CELL_SIZE, 0.22, CELL_SIZE)
			mat.albedo_color = COLOR_PAVED_ROAD
			mat.roughness = 0.60
			center_y = -0.07

	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "tile_%d_%d" % [cell.x, cell.y]
	mi.position = Vector3(cx, center_y, cz)
	add_child(mi)

func _spawn_tree(cell: Vector2i) -> void:
	var cx := cell.x * CELL_SIZE + CELL_SIZE * 0.5
	var cz := cell.y * CELL_SIZE + CELL_SIZE * 0.5
	var h: int = cell.x * 7 + cell.y * 13
	var big_variant: bool = (h % 2 == 1)

	var scene: PackedScene = null
	if ResourceLoader.exists(TREE_SCENE_PATH):
		scene = load(TREE_SCENE_PATH) as PackedScene

	var container := Node3D.new()
	container.name = "trees_%d_%d" % [cell.x, cell.y]
	add_child(container)
	_tree_nodes[cell] = container

	if big_variant:
		var offsets := [Vector3(-0.55, 0.0, -0.45), Vector3(0.50, 0.0, 0.50)]
		var scales  := [0.70, 1.0 + (h % 5) * 0.10]
		var rots    := [float((h % 8) * 45), float(((h + 5) % 8) * 45)]
		for i in range(2):
			var node: Node3D = _make_tree_node(scene, (h + i) % 2)
			node.scale = Vector3.ONE * scales[i]
			node.position = Vector3(cx, 0.0, cz) + offsets[i]
			node.rotation_degrees.y = rots[i]
			container.add_child(node)
		_tree_harvests[cell] = HARVEST_BIG
	else:
		var node: Node3D = _make_tree_node(scene, h % 2)
		node.scale = Vector3.ONE * 0.65
		node.position = Vector3(cx, 0.0, cz) + Vector3(sin(h * 0.9) * 0.3, 0.0, cos(h * 1.3) * 0.3)
		node.rotation_degrees.y = float((h % 8) * 45)
		container.add_child(node)
		_tree_harvests[cell] = HARVEST_SMALL

# Decrement harvest count — returns false if cannot be harvested
func harvest_tree(cell: Vector2i) -> bool:
	if _terrain.get(cell, Terrain.GRASS) != Terrain.FOREST:
		return false
	if not _tree_harvests.has(cell):
		return false
	_tree_harvests[cell] -= 1
	if _tree_harvests[cell] <= 0:
		_remove_tree_at(cell)
	return true

func clear_tree_immediately(cell: Vector2i) -> bool:
	if _terrain.get(cell, Terrain.GRASS) != Terrain.FOREST:
		return false
	_cleared_tree_cells[cell] = true
	_remove_tree_at(cell)
	return true

func get_tree_harvest_info(cell: Vector2i) -> Dictionary:
	if _terrain.get(cell, Terrain.GRASS) != Terrain.FOREST:
		return {}
	var remaining: int = _tree_harvests.get(cell, 0)
	var h: int = cell.x * 7 + cell.y * 13
	var is_big: bool = (h % 2 == 1)
	var max_h: int = HARVEST_BIG if is_big else HARVEST_SMALL
	return {"remaining": remaining, "max": max_h, "is_big": is_big}

func _remove_tree_at(cell: Vector2i) -> void:
	if _tree_nodes.has(cell):
		var n: Node3D = _tree_nodes[cell]
		if is_instance_valid(n):
			n.queue_free()
		_tree_nodes.erase(cell)
	_tree_harvests.erase(cell)
	_terrain[cell] = Terrain.GRASS
	_set_tile_color(cell, COLOR_GRASS)
	var t := Timer.new()
	t.wait_time = randf_range(60.0, 120.0)
	t.one_shot = true
	t.timeout.connect(_respawn_tree.bind(cell))
	add_child(t)
	t.start()

func _respawn_tree(cell: Vector2i) -> void:
	if _cleared_tree_cells.has(cell):
		return
	if _terrain.get(cell, Terrain.GRASS) != Terrain.GRASS:
		return
	if _buildings.has(cell):
		return
	_terrain[cell] = Terrain.FOREST
	_set_tile_color(cell, COLOR_FOREST)
	_spawn_tree(cell)

func _make_tree_node(scene: PackedScene, variant: int) -> Node3D:
	if scene != null:
		var node := scene.instantiate() as Node3D
		if node is TreeModel:
			node.show_ground = false
			node.show_cell_border = false
		return node
	return _make_fallback_tree(variant)

func _make_fallback_tree(variant: int) -> Node3D:
	var root := Node3D.new()

	# trunk
	var trunk := MeshInstance3D.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.12
	trunk_cyl.bottom_radius = 0.18
	trunk_cyl.height = 0.8
	trunk.mesh = trunk_cyl
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.40, 0.24, 0.08)
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, 0.4, 0)
	root.add_child(trunk)

	# foliage
	var foliage := MeshInstance3D.new()
	var foliage_mat := StandardMaterial3D.new()
	if variant == 0:
		var sphere := SphereMesh.new()
		sphere.radius = 0.70
		sphere.height = 1.4
		foliage.mesh = sphere
		foliage_mat.albedo_color = Color(0.15, 0.58, 0.15)
		foliage.position = Vector3(0, 1.5, 0)
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.65
		cone.height = 1.9
		foliage.mesh = cone
		foliage_mat.albedo_color = Color(0.08, 0.45, 0.18)
		foliage.position = Vector3(0, 1.75, 0)
	foliage.material_override = foliage_mat
	root.add_child(foliage)
	return root

# 0-1 = flower, 2-3 = grass, 4 = plant, 5-6 = small rocks, 7-8 = big rock, 9-11 = plain
func _spawn_grass_deco(cell: Vector2i) -> void:
	var h: int = (cell.x * 31 + cell.y * 17 + cell.x * cell.y * 3) % 12
	if h >= 9:
		return

	var ox: float = sin(cell.x * 1.9 + cell.y * 0.7) * 0.55
	var oz: float = cos(cell.x * 0.6 + cell.y * 2.3) * 0.55
	var px := cell.x * CELL_SIZE + CELL_SIZE * 0.5 + ox
	var pz := cell.y * CELL_SIZE + CELL_SIZE * 0.5 + oz
	var rot_y: float = float((cell.x * 47 + cell.y * 83) % 360)

	var node: Node3D
	match h:
		0, 1: node = _make_flower(h)
		2, 3: node = _make_grass_tuft()
		4:    node = _make_small_plant()
		5, 6: node = _make_small_rocks()
		_:    node = _make_big_rock(h % 2)

	node.position = Vector3(px, 0.0, pz)
	node.rotation_degrees.y = rot_y
	add_child(node)
	_cell_decos[cell] = node

# Decorative ponds — returns water amount that from_cell receives from surrounding ponds
# Small pond (coverage=1): distance 1 = +1 water
# Large pond (coverage=2): distance 1 = +2 water, distance 2 = +1 water
# WATER terrain adjacency: any cell touching a river/lake border gives +1 free water
func get_water_bonus(from_cell: Vector2i) -> int:
	var total: int = _water_cell_bonuses.get(from_cell, 0)
	# Find min Chebyshev distance to each pond (from any of its cells)
	var min_dist: Dictionary = {}  # origin -> int
	for pond_cell in _cell_to_pond:
		var origin = _cell_to_pond[pond_cell]
		var d: int = max(abs(from_cell.x - pond_cell.x), abs(from_cell.y - pond_cell.y))
		if not min_dist.has(origin) or d < min_dist[origin]:
			min_dist[origin] = d
	for origin in min_dist:
		var coverage: int = _pond_origins.get(origin, 1)
		var d: int = min_dist[origin]
		if d == 1:
			total += coverage
		elif d == 2 and coverage >= 2:
			total += 1
	return total

# ===== Field Job Queue =====

func is_field_growing(cell: Vector2i) -> bool:
	if not _field_harvest_at.has(cell):
		return false
	return Time.get_unix_time_from_system() < _field_harvest_at[cell]

func is_field_harvest_ready(cell: Vector2i) -> bool:
	if not _field_harvest_at.has(cell):
		return false
	return Time.get_unix_time_from_system() >= _field_harvest_at[cell]

func is_field_job_claimed(cell: Vector2i) -> bool:
	return _field_job_claimed.has(cell)

func claim_field_job(cell: Vector2i, job_type: String) -> bool:
	if _field_job_claimed.has(cell):
		return false
	_field_job_claimed[cell] = job_type
	return true

func release_field_job(cell: Vector2i) -> void:
	_field_job_claimed.erase(cell)

func get_field_input(cell: Vector2i, res: String) -> int:
	if not _field_inputs.has(cell): return 0
	return _field_inputs[cell].get(res, 0)

func add_field_input(cell: Vector2i, res: String, amount: int) -> void:
	if not _field_inputs.has(cell): _field_inputs[cell] = {}
	_field_inputs[cell][res] = _field_inputs[cell].get(res, 0) + amount

func start_field_growth(cell: Vector2i, grow_time: float) -> void:
	_field_harvest_at[cell] = Time.get_unix_time_from_system() + grow_time
	_field_job_claimed.erase(cell)  # release claim so farmer can do other work while waiting

func get_field_remaining(cell: Vector2i) -> float:
	if not _field_harvest_at.has(cell):
		return 0.0
	return maxf(0.0, _field_harvest_at[cell] - Time.get_unix_time_from_system())

func mark_field_harvested(cell: Vector2i) -> void:
	_field_harvest_at.erase(cell)
	_field_job_claimed.erase(cell)
	_field_inputs.erase(cell)

# Returns nearest building that wants resource res (checks consumes or recipe consumes)
func find_building_wanting_resource(res: String, near_cell: Vector2i) -> Node3D:
	var best: Node3D = null
	var best_dist := 9999.0
	var seen: Array = []
	for cell in _buildings:
		var bld = _buildings[cell]
		if seen.has(bld):
			continue
		seen.append(bld)
		if not (bld is Building):
			continue
		var bldg := bld as Building
		if not bldg._is_active or bldg.data == null:
			continue
		var wants := bldg.data.consumes.has(res)
		if not wants:
			for recipe in bldg.data.recipes:
				if recipe.get("consumes", {}).has(res):
					wants = true
					break
		if wants:
			var d := (Vector2(cell) - Vector2(near_cell)).length()
			if d < best_dist:
				best_dist = d
				best = bldg
	return best

# cells: Array[Vector2i] of all cells this pond occupies (each is 1 block)
# coverage: water bonus (1=small pond, 2=large pond)
func _spawn_pond(cells: Array, coverage: int) -> void:
	if cells.is_empty():
		return
	for cell in cells:
		if not is_cell_valid(cell) or _terrain.get(cell, Terrain.GRASS) != Terrain.GRASS:
			return

	var origin: Vector2i = cells[0]
	_pond_origins[origin] = coverage

	var pond_node := Node3D.new()
	pond_node.name = "pond_%d_%d" % [origin.x, origin.y]
	add_child(pond_node)
	_pond_nodes[origin] = pond_node

	const WATER_Y: float = -0.26
	const BANK_H:  float = 0.45

	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.56, 0.44, 0.28)
	dirt_mat.roughness = 0.95

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.16, 0.50, 0.82)
	water_mat.roughness = 0.06
	water_mat.metallic_specular = 0.55

	for cell in cells:
		_terrain[cell] = Terrain.WATER
		_cell_to_pond[cell] = origin

		var cx: float = cell.x * CELL_SIZE + CELL_SIZE * 0.5
		var cz: float = cell.y * CELL_SIZE + CELL_SIZE * 0.5

		# Replace shallow tile with sunken dirt bowl (top flush with ground)
		var old_tile := get_node_or_null("tile_%d_%d" % [cell.x, cell.y])
		if old_tile != null:
			old_tile.queue_free()
		var bowl := MeshInstance3D.new()
		bowl.name = "tile_%d_%d" % [cell.x, cell.y]
		var bm := BoxMesh.new()
		bm.size = Vector3(CELL_SIZE, BANK_H, CELL_SIZE)
		bowl.mesh = bm
		bowl.material_override = dirt_mat
		bowl.position = Vector3(cx, -BANK_H * 0.5, cz)
		add_child(bowl)

		# Water surface — large fills cell, small is a puddle
		var water_w: float = CELL_SIZE - 0.08 if coverage >= 2 else CELL_SIZE * 0.58
		var water := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(water_w, 0.06, water_w)
		water.mesh = wm
		water.material_override = water_mat
		water.position = Vector3(cx, WATER_Y, cz)
		pond_node.add_child(water)

	_add_ripples(cells, pond_node, WATER_Y, coverage)
	if coverage == 1:
		_add_lily_pads(cells, pond_node, WATER_Y)
	_add_pond_reeds(cells, pond_node, WATER_Y)

func _add_ripples(cells: Array, parent: Node3D, water_y: float, coverage: int) -> void:
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 1.0, 1.0, 0.65)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var count := mini(cells.size(), 3) if coverage >= 2 else 1
	for i in range(count):
		var idx: int = (i * cells.size()) / maxi(count, 1)
		var cell: Vector2i = cells[idx]
		var cx := cell.x * CELL_SIZE + CELL_SIZE * 0.5
		var cz := cell.y * CELL_SIZE + CELL_SIZE * 0.5

		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var base_r: float = 0.30 if coverage >= 2 else 0.16
		tm.inner_radius = base_r
		tm.outer_radius = base_r + 0.08
		tm.rings = 10
		tm.ring_segments = 16
		ring.mesh = tm
		ring.rotation_degrees.x = 90.0
		ring.position = Vector3(cx, water_y + 0.05, cz)
		ring.material_override = rmat.duplicate()
		parent.add_child(ring)

		var mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
		var tw := ring.create_tween()
		tw.set_loops()
		tw.tween_interval(i * 1.2)
		var max_scale: float = 2.0 if coverage >= 2 else 1.6
		tw.tween_property(ring, "scale", Vector3.ONE * max_scale, 1.3).from(Vector3.ONE * 0.2)
		tw.parallel().tween_method(func(v: float): mat.albedo_color.a = v, 0.85, 0.0, 1.3)
		tw.tween_callback(func():
			ring.scale = Vector3.ONE * 0.2
			mat.albedo_color.a = 0.85
		)

func _add_lily_pads(cells: Array, parent: Node3D, water_y: float) -> void:
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.15, 0.52, 0.16)
	for i in range(mini(cells.size(), 2)):
		var cell: Vector2i = cells[i]
		var h := cell.x * 31 + cell.y * 17 + i * 7
		var ox := sin(h * 1.7) * 0.30
		var oz := cos(h * 2.1) * 0.30
		var pad := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22 + (h % 5) * 0.04
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.022
		cyl.radial_segments = 12
		pad.mesh = cyl
		pad.material_override = pmat
		var cx := cell.x * CELL_SIZE + CELL_SIZE * 0.5 + ox
		var cz := cell.y * CELL_SIZE + CELL_SIZE * 0.5 + oz
		pad.position = Vector3(cx, water_y + 0.05, cz)
		parent.add_child(pad)

func _add_pond_reeds(cells: Array, parent: Node3D, water_y: float) -> void:
	var cell_set: Dictionary = {}
	for c in cells:
		cell_set[c] = true
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.24, 0.52, 0.18)
	var dirs4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for cell in cells:
		var is_edge := false
		for d in dirs4:
			if not cell_set.has(cell + d):
				is_edge = true
				break
		if not is_edge:
			continue
		var h: int = cell.x * 31 + cell.y * 17
		var rcount: int = 1 + (h % 2)
		for i in range(rcount):
			var a: float = (h + i * 47) * 0.618 * TAU
			var r: float = CELL_SIZE * 0.34 + (i % 3) * 0.10
			var cx: float = cell.x * CELL_SIZE + CELL_SIZE * 0.5 + cos(a) * r
			var cz: float = cell.y * CELL_SIZE + CELL_SIZE * 0.5 + sin(a) * r
			var rh: float = 0.35 + (h * 3 + i) % 5 * 0.07
			var reed := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.020
			cyl.bottom_radius = 0.028
			cyl.height = rh
			reed.mesh = cyl
			reed.material_override = reed_mat
			reed.position = Vector3(cx, water_y + rh * 0.5 + 0.06, cz)
			reed.rotation_degrees.y = a * 57.3
			parent.add_child(reed)

func get_pond_at(cell: Vector2i) -> Vector2i:
	return _cell_to_pond.get(cell, Vector2i(-1, -1))

func clear_pond(origin: Vector2i) -> bool:
	if not _pond_origins.has(origin):
		return false
	if _pond_nodes.has(origin):
		var n: Node3D = _pond_nodes[origin]
		if is_instance_valid(n):
			n.queue_free()
		_pond_nodes.erase(origin)
	var to_erase: Array = []
	for cell in _cell_to_pond:
		if _cell_to_pond[cell] == origin:
			to_erase.append(cell)
	for cell in to_erase:
		_cell_to_pond.erase(cell)
		_terrain[cell] = Terrain.GRASS
		# Restore tile mesh (deep bowl → shallow grass tile)
		var old := get_node_or_null("tile_%d_%d" % [cell.x, cell.y])
		if old != null:
			old.queue_free()
		_spawn_tile(cell, Terrain.GRASS)
	_pond_origins.erase(origin)
	return true

# --- Decoration helpers ---

func _make_flower(variant: int) -> Node3D:
	var root := Node3D.new()
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.22, 0.58, 0.18)
	var petal_colors: Array = [
		Color(1.00, 0.85, 0.10),  # yellow
		Color(0.95, 0.40, 0.62),  # pink
		Color(0.95, 0.95, 1.00),  # white
	]
	for i in range(3):
		var angle := i * 2.094  # 120°
		var r := 0.07
		var stem := MeshInstance3D.new()
		var scyl := CylinderMesh.new()
		scyl.top_radius = 0.016
		scyl.bottom_radius = 0.016
		scyl.height = 0.16
		stem.mesh = scyl
		stem.material_override = stem_mat
		stem.position = Vector3(cos(angle) * r, 0.08, sin(angle) * r)
		root.add_child(stem)

		var petal := MeshInstance3D.new()
		var psph := SphereMesh.new()
		psph.radius = 0.050
		psph.height = 0.10
		petal.mesh = psph
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = petal_colors[(i + variant) % petal_colors.size()]
		petal.material_override = pmat
		petal.position = Vector3(cos(angle) * r, 0.19, sin(angle) * r)
		root.add_child(petal)
	return root

func _make_grass_tuft() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.65, 0.18)
	for i in range(5):
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 0.20 + (i % 2) * 0.04, 0.050)
		blade.mesh = box
		blade.material_override = mat
		var a := i * 1.257  # 72° apart
		blade.position = Vector3(cos(a) * 0.07, 0.10, sin(a) * 0.07)
		blade.rotation_degrees = Vector3((i % 3 - 1) * 12, 0, (i % 2) * 10 - 5)
		root.add_child(blade)
	return root

func _make_small_plant() -> Node3D:
	var root := Node3D.new()
	var stem := MeshInstance3D.new()
	var scyl := CylinderMesh.new()
	scyl.top_radius = 0.022
	scyl.bottom_radius = 0.028
	scyl.height = 0.18
	stem.mesh = scyl
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.28, 0.58, 0.20)
	stem.material_override = smat
	stem.position = Vector3(0, 0.09, 0)
	root.add_child(stem)
	var leaf := MeshInstance3D.new()
	var lsph := SphereMesh.new()
	lsph.radius = 0.085
	lsph.height = 0.17
	leaf.mesh = lsph
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.20, 0.62, 0.16)
	leaf.material_override = lmat
	leaf.position = Vector3(0, 0.24, 0)
	root.add_child(leaf)
	return root

func _make_small_rocks() -> Node3D:
	if ResourceLoader.exists(STONES_PATH):
		var scene := load(STONES_PATH) as PackedScene
		if scene != null:
			var inst := scene.instantiate()
			inst.scale = Vector3.ONE * 0.38
			_force_color(inst, Color(0.62, 0.60, 0.56))
			return inst
	# fallback
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.60, 0.56)
	var sizes := [Vector3(0.13, 0.09, 0.11), Vector3(0.10, 0.07, 0.09), Vector3(0.08, 0.06, 0.08)]
	var offsets := [Vector3(0, 0.045, 0), Vector3(0.10, 0.035, 0.04), Vector3(-0.08, 0.030, 0.06)]
	for i in range(3):
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = sizes[i]
		rock.mesh = box
		rock.material_override = mat
		rock.position = offsets[i]
		rock.rotation_degrees.y = float(i * 37)
		root.add_child(rock)
	return root

func _make_big_rock(variant: int) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.56, 0.52)
	if variant == 0:
		# single large rock
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.32, 0.24, 0.28)
		rock.mesh = box
		rock.material_override = mat
		rock.position = Vector3(0, 0.12, 0)
		rock.rotation_degrees.y = 22.0
		root.add_child(rock)
		# small pebble beside it
		var pebble := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.14, 0.10, 0.12)
		pebble.mesh = pb
		pebble.material_override = mat
		pebble.position = Vector3(0.22, 0.05, 0.08)
		pebble.rotation_degrees.y = 55.0
		root.add_child(pebble)
	else:
		# two rocks in the middle
		var positions := [Vector3(-0.12, 0.10, 0), Vector3(0.14, 0.09, 0.06)]
		var bsizes := [Vector3(0.26, 0.20, 0.22), Vector3(0.22, 0.18, 0.20)]
		for i in range(2):
			var rock := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = bsizes[i]
			rock.mesh = box
			rock.material_override = mat
			rock.position = positions[i]
			rock.rotation_degrees.y = float(i * 40 + 15)
			root.add_child(rock)
	return root

func _create_grid_lines() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for x in range(GRID_WIDTH + 1):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.015, GRID_HEIGHT * CELL_SIZE)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(x * CELL_SIZE, 0.005, GRID_HEIGHT * CELL_SIZE * 0.5)
		add_child(mi)

	for z in range(GRID_HEIGHT + 1):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(GRID_WIDTH * CELL_SIZE, 0.015, 0.035)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(GRID_WIDTH * CELL_SIZE * 0.5, 0.005, z * CELL_SIZE)
		add_child(mi)

# --- Terrain query ---

func get_nearest_building_cell(building_id: String, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 9999.0
	var seen: Array = []
	for cell in _buildings:
		var bld: Node = _buildings[cell]
		if seen.has(bld):
			continue
		seen.append(bld)
		if bld is Building and bld.data != null and bld.data.id == building_id:
			var d: float = (Vector2(cell) - Vector2(from)).length()
			if d < best_dist:
				best_dist = d
				best = cell
	return best

func get_all_local_stocks() -> Dictionary:
	var totals: Dictionary = {}
	var seen: Array = []
	for cell in _buildings:
		var bld: Node = _buildings[cell]
		if seen.has(bld):
			continue
		seen.append(bld)
		if bld is Building:
			for res in bld._local_stock:
				totals[res] = totals.get(res, 0) + bld._local_stock[res]
	return totals

func get_all_building_cells(building_id: String) -> Array:
	var result: Array = []
	var seen: Array = []
	for cell in _buildings:
		var bld: Node = _buildings[cell]
		if seen.has(bld):
			continue
		seen.append(bld)
		if bld is Building and bld.data != null and bld.data.id == building_id:
			result.append(cell)
	return result

func get_building_node_at(cell: Vector2i) -> Building:
	var node = _buildings.get(cell, null)
	if node is Building:
		return node as Building
	return null

func get_building_id(cell: Vector2i) -> String:
	if not _buildings.has(cell):
		return ""
	var bld = _buildings.get(cell)
	if bld is Building and bld.data != null:
		return bld.data.id
	return ""

func is_livestock_cell(cell: Vector2i) -> bool:
	if not _buildings.has(cell):
		return false
	var bld = _buildings.get(cell)
	if bld is Building and bld.data != null:
		return bld.data.worker_domain == BuildingData.WorkerDomain.LIVESTOCK
	return false

func get_nearest_terrain_cell(from: Vector2i, terrain_type: Terrain) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 9999.0
	for cell in _terrain:
		if _terrain[cell] == terrain_type:
			var d := (Vector2(cell) - Vector2(from)).length()
			if d < best_dist:
				best_dist = d
				best = cell
	return best

func get_nearest_terrain_cell_excluding(from: Vector2i, terrain_type: int, exclude: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 9999.0
	for cell in _terrain:
		if _terrain[cell] == terrain_type and not exclude.has(cell):
			var d := (Vector2(cell) - Vector2(from)).length()
			if d < best_dist:
				best_dist = d
				best = cell
	return best

# --- Grid API ---

func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_SIZE), int(world_pos.z / CELL_SIZE))

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)

func is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT

func get_terrain(cell: Vector2i) -> Terrain:
	return _terrain.get(cell, Terrain.GRASS)

func is_buildable(cell: Vector2i) -> bool:
	return is_cell_valid(cell) and get_terrain(cell) == Terrain.GRASS

func build_road(cell: Vector2i) -> bool:
	if not is_cell_valid(cell):
		return false
	if _terrain.get(cell, Terrain.GRASS) != Terrain.GRASS:
		return false
	if _buildings.has(cell):
		return false
	_terrain[cell] = Terrain.ROAD
	_set_tile_color(cell, COLOR_ROAD)
	if _cell_decos.has(cell):
		_cell_decos[cell].visible = false
	return true

func build_paved_road(cell: Vector2i) -> bool:
	if _terrain.get(cell, Terrain.GRASS) != Terrain.ROAD:
		return false  # must have a dirt road first
	_terrain[cell] = Terrain.PAVED_ROAD
	_set_tile_color(cell, COLOR_PAVED_ROAD)
	return true

func remove_road_at(cell: Vector2i) -> bool:
	var t: int = _terrain.get(cell, Terrain.GRASS)
	if t == Terrain.PAVED_ROAD:
		# paved road → downgrade to dirt
		_terrain[cell] = Terrain.ROAD
		_set_tile_color(cell, COLOR_ROAD)
		return true
	if t != Terrain.ROAD:
		return false
	_terrain[cell] = Terrain.GRASS
	_set_tile_color(cell, COLOR_GRASS)
	if _cell_decos.has(cell):
		_cell_decos[cell].visible = true
	# Notify buildings that were adjacent to this road — they may have lost connectivity
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var notified: Array = []
	for d in dirs:
		var neighbor: Vector2i = cell + d
		if _buildings.has(neighbor):
			var bld = _buildings[neighbor]
			if bld != null and is_instance_valid(bld) and not (bld in notified):
				notified.append(bld)
				if bld.data != null and bld.data.grow_time <= 0.0:
					if not is_area_adjacent_to_road(bld.origin_cell, bld.data.size):
						bld.on_road_disconnected()
	return true

func build_pond(cell: Vector2i, big: bool) -> bool:
	if not is_cell_valid(cell):
		return false
	if _terrain.get(cell, Terrain.GRASS) != Terrain.GRASS:
		return false
	if _buildings.has(cell):
		return false
	_spawn_pond([cell], 2 if big else 1)
	return true

func remove_pond_at(cell: Vector2i) -> bool:
	var origin := get_pond_at(cell)
	if origin == Vector2i(-1, -1):
		return false
	return clear_pond(origin)

func is_area_free(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dz in range(size.y):
			var cell := origin + Vector2i(dx, dz)
			if not is_buildable(cell):
				return false
			if _grid.has(cell):
				return false
	return true

func is_road_terrain(t: int) -> bool:
	return t == Terrain.ROAD or t == Terrain.PAVED_ROAD

func get_nearest_road_cell(from_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999999
	for c in _terrain:
		if is_road_terrain(_terrain[c]):
			var d: int = abs(c.x - from_cell.x) + abs(c.y - from_cell.y)
			if d < best_d:
				best_d = d
				best = c
	return best

func is_area_adjacent_to_road(origin: Vector2i, size: Vector2i) -> bool:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dx in range(size.x):
		for dz in range(size.y):
			var cell := origin + Vector2i(dx, dz)
			for d in dirs:
				if is_road_terrain(_terrain.get(cell + d, Terrain.GRASS)):
					return true
	return false

func get_production_modifier(cell: Vector2i) -> float:
	var shadow: int = _shadow_counts.get(cell, 0)
	var pollution: int = _pollution_counts.get(cell, 0)
	var total: int = clampi(shadow + pollution, 0, 3)
	return pow(2.0, total)  # 1x, 2x, 4x, 8x

func get_shadow_count(cell: Vector2i) -> int:
	return _shadow_counts.get(cell, 0)

func get_pollution_count(cell: Vector2i) -> int:
	return _pollution_counts.get(cell, 0)

func get_electricity_count(cell: Vector2i) -> int:
	return _electricity_counts.get(cell, 0)

func _apply_building_effects(bld: Node3D, placing: bool) -> void:
	var bld_data: BuildingData = bld.get("data") as BuildingData
	if bld_data == null:
		return
	var origin_var = bld.get("origin_cell")
	if origin_var == null:
		return
	var origin_cell = origin_var  # Vector2i from bld.get() — untyped to avoid invalid as-cast
	var sz: Vector2i = bld_data.size
	var sign: int = 1 if placing else -1

	if bld_data.shadow_radius > 0:
		var r: int = bld_data.shadow_radius
		for dx in range(-r, sz.x + r):
			for dz in range(-r, sz.y + r):
				if dx >= 0 and dx < sz.x and dz >= 0 and dz < sz.y:
					continue  # skip cells the building itself occupies
				var cell: Vector2i = origin_cell + Vector2i(dx, dz)
				_shadow_counts[cell] = max(0, _shadow_counts.get(cell, 0) + sign)

	if bld_data.pollution_radius > 0:
		var r: int = bld_data.pollution_radius
		for dx in range(-r, sz.x + r):
			for dz in range(-r, sz.y + r):
				if dx >= 0 and dx < sz.x and dz >= 0 and dz < sz.y:
					continue
				var cell: Vector2i = origin_cell + Vector2i(dx, dz)
				_pollution_counts[cell] = max(0, _pollution_counts.get(cell, 0) + sign)

	if bld_data.water_radius > 0:
		var r: int = bld_data.water_radius
		for dx in range(-r, sz.x + r):
			for dz in range(-r, sz.y + r):
				if dx >= 0 and dx < sz.x and dz >= 0 and dz < sz.y:
					continue
				var cell: Vector2i = origin_cell + Vector2i(dx, dz)
				_water_cell_bonuses[cell] = max(0, _water_cell_bonuses.get(cell, 0) + sign)

	if bld_data.electricity_radius > 0:
		var r: int = bld_data.electricity_radius
		for dx in range(-r, sz.x + r):
			for dz in range(-r, sz.y + r):
				if dx >= 0 and dx < sz.x and dz >= 0 and dz < sz.y:
					continue
				var cell: Vector2i = origin_cell + Vector2i(dx, dz)
				# Chebyshev distance from nearest building cell → tiered level 3-2-1
				var near_dx: int = clampi(dx, 0, sz.x - 1)
				var near_dz: int = clampi(dz, 0, sz.y - 1)
				var dist: int = max(abs(dx - near_dx), abs(dz - near_dz))
				var level: int = r - dist + 1
				_electricity_counts[cell] = max(0, _electricity_counts.get(cell, 0) + sign * level)

func remove_building_at(cell: Vector2i) -> bool:
	if not _buildings.has(cell):
		return false
	var building: Node3D = _buildings[cell]
	_apply_building_effects(building, false)
	var to_erase: Array = []
	for c in _buildings:
		if _buildings[c] == building:
			to_erase.append(c)
	for c in to_erase:
		_grid.erase(c)
		_buildings.erase(c)
	building.queue_free()
	return true

func place_building(building: Node3D, data: BuildingData, origin: Vector2i, override_size: Vector2i = Vector2i(-1, -1)) -> bool:
	var sz := override_size if override_size.x > 0 else data.size
	if not is_area_free(origin, sz):
		return false
	for dx in range(sz.x):
		for dz in range(sz.y):
			var cell := origin + Vector2i(dx, dz)
			_grid[cell] = data
			_buildings[cell] = building
			if _cell_decos.has(cell):
				_cell_decos[cell].visible = false
			_set_tile_color(cell, COLOR_GRASS if data.water_radius > 0 else Color(0.82, 0.74, 0.58))
	var wp := cell_to_world(origin)
	wp.x += sz.x * CELL_SIZE * 0.5
	wp.z += sz.y * CELL_SIZE * 0.5
	building.position = wp
	add_child(building)
	_apply_building_effects(building, true)
	return true

func _set_tile_color(cell: Vector2i, color: Color) -> void:
	var tile := get_node_or_null("tile_%d_%d" % [cell.x, cell.y])
	if tile is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.95
		(tile as MeshInstance3D).material_override = mat
