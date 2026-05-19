@tool
class_name TreeModel
extends Node3D

@export_group("Tree")
@export var trunk_height: float = 0.8:
	set(v): trunk_height = v; if is_node_ready(): _rebuild()
@export var trunk_radius: float = 0.18:
	set(v): trunk_radius = v; if is_node_ready(): _rebuild()
@export var trunk_color: Color = Color(0.40, 0.24, 0.08):
	set(v): trunk_color = v; if is_node_ready(): _rebuild()
@export_enum("Round", "Pine") var tree_type: int = 0:
	set(v): tree_type = v; if is_node_ready(): _rebuild()
@export var foliage_radius: float = 0.70:
	set(v): foliage_radius = v; if is_node_ready(): _rebuild()
@export var foliage_color: Color = Color(0.10, 0.40, 0.10):
	set(v): foliage_color = v; if is_node_ready(): _rebuild()

@export_group("Preview (editor only)")
@export var show_ground: bool = true:
	set(v): show_ground = v; if is_node_ready(): _rebuild()
@export var show_cell_border: bool = true:
	set(v): show_cell_border = v; if is_node_ready(): _rebuild()

@export_group("Decorations")
@export var show_rocks: bool = false:
	set(v): show_rocks = v; if is_node_ready(): _rebuild()
@export var show_flowers: bool = false:
	set(v): show_flowers = v; if is_node_ready(): _rebuild()
@export var show_grass: bool = false:
	set(v): show_grass = v; if is_node_ready(): _rebuild()

const CELL: float = 3.0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	var to_free: Array = []
	for child in get_children():
		if child is MeshInstance3D or child is Node3D:
			to_free.append(child)
	for child in to_free:
		child.free()

	# --- ground block ---
	if show_ground:
		var ground := MeshInstance3D.new()
		var gbox := BoxMesh.new()
		gbox.size = Vector3(CELL, 0.18, CELL)
		ground.mesh = gbox
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.30, 0.68, 0.20)
		gmat.roughness = 0.95
		ground.material_override = gmat
		ground.position = Vector3(0, -0.09, 0)
		add_child(ground)

	# --- cell border lines ---
	if show_cell_border:
		var half := CELL * 0.5
		var border_mat := StandardMaterial3D.new()
		border_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
		border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for i in range(4):
			var line := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			var is_horiz: bool = (i < 2)
			lbox.size = Vector3(CELL if is_horiz else 0.04, 0.02, 0.04 if is_horiz else CELL)
			line.mesh = lbox
			line.material_override = border_mat
			match i:
				0: line.position = Vector3(0,      0.01,  half)
				1: line.position = Vector3(0,      0.01, -half)
				2: line.position = Vector3( half,  0.01,  0)
				3: line.position = Vector3(-half,  0.01,  0)
			add_child(line)

	# --- trunk ---
	var trunk := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius    = trunk_radius * 0.65
	tcyl.bottom_radius = trunk_radius
	tcyl.height        = trunk_height
	trunk.mesh = tcyl
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = trunk_color
	trunk.material_override = tmat
	trunk.position = Vector3(0, trunk_height * 0.5, 0)
	add_child(trunk)

	# --- foliage ---
	var foliage := MeshInstance3D.new()
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = foliage_color
	if tree_type == 0:
		var sph := SphereMesh.new()
		sph.radius = foliage_radius
		sph.height = foliage_radius * 2.0
		foliage.mesh = sph
		foliage.position = Vector3(0, trunk_height + foliage_radius * 0.8, 0)
	else:
		var cone := CylinderMesh.new()
		cone.top_radius    = 0.0
		cone.bottom_radius = foliage_radius
		cone.height        = foliage_radius * 2.8
		foliage.mesh = cone
		foliage.position = Vector3(0, trunk_height + foliage_radius * 1.0, 0)
	foliage.material_override = fmat
	add_child(foliage)

	# --- decorations ---
	if show_rocks:
		_add_rocks()
	if show_flowers:
		_add_flowers()
	if show_grass:
		_add_grass()

func _add_rocks() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.60, 0.56)
	var positions := [Vector3(0.7, 0.06, 0.4), Vector3(-0.6, 0.05, 0.6), Vector3(0.5, 0.04, -0.7)]
	var sizes     := [Vector3(0.28, 0.18, 0.24), Vector3(0.20, 0.14, 0.18), Vector3(0.16, 0.11, 0.14)]
	for i in range(3):
		var r := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = sizes[i]
		r.mesh = b
		r.material_override = mat
		r.position = positions[i]
		r.rotation_degrees.y = float(i * 40 + 15)
		add_child(r)

func _add_flowers() -> void:
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.22, 0.58, 0.18)
	var colors := [Color(1.0, 0.85, 0.1), Color(0.95, 0.40, 0.62), Color(0.95, 0.95, 1.0)]
	var spots  := [Vector3(0.8, 0, 0.3), Vector3(-0.7, 0, -0.5), Vector3(0.3, 0, -0.8)]
	for s in spots:
		for i in range(3):
			var a := i * 2.094
			var stem := MeshInstance3D.new()
			var sc := CylinderMesh.new()
			sc.top_radius = 0.016; sc.bottom_radius = 0.016; sc.height = 0.16
			stem.mesh = sc; stem.material_override = stem_mat
			stem.position = s + Vector3(cos(a)*0.06, 0.08, sin(a)*0.06)
			add_child(stem)
			var petal := MeshInstance3D.new()
			var ps := SphereMesh.new()
			ps.radius = 0.050; ps.height = 0.10
			petal.mesh = ps
			var pm := StandardMaterial3D.new()
			pm.albedo_color = colors[i % colors.size()]
			petal.material_override = pm
			petal.position = s + Vector3(cos(a)*0.06, 0.19, sin(a)*0.06)
			add_child(petal)

func _add_grass() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.65, 0.18)
	var spots := [Vector3(0.6, 0, 0.7), Vector3(-0.8, 0, 0.2), Vector3(0.2, 0, -0.9)]
	for s in spots:
		for i in range(5):
			var blade := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.035, 0.20, 0.050)
			blade.mesh = b; blade.material_override = mat
			var a := i * 1.257
			blade.position = s + Vector3(cos(a)*0.07, 0.10, sin(a)*0.07)
			add_child(blade)
