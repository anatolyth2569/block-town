@tool
class_name BuildingModel
extends Node3D

@export_group("Body")
@export var body_color: Color = Color(0.7, 0.7, 0.7):
	set(v): body_color = v; if is_node_ready(): _rebuild()
@export var body_width: float = 1.86:
	set(v): body_width = v; if is_node_ready(): _rebuild()
@export var body_height: float = 1.1:
	set(v): body_height = v; if is_node_ready(): _rebuild()

@export_group("Roof")
@export var has_roof: bool = false:
	set(v): has_roof = v; if is_node_ready(): _rebuild()
@export var roof_color: Color = Color(0.5, 0.3, 0.1):
	set(v): roof_color = v; if is_node_ready(): _rebuild()
@export var roof_height: float = 0.62:
	set(v): roof_height = v; if is_node_ready(): _rebuild()

@export_group("Preview (editor only)")
@export var show_ground: bool = true:
	set(v): show_ground = v; if is_node_ready(): _rebuild()
@export var show_cell_border: bool = true:
	set(v): show_cell_border = v; if is_node_ready(): _rebuild()

const CELL: float = 3.0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	var to_free: Array = []
	for child in get_children():
		if child is MeshInstance3D:
			to_free.append(child)
	for child in to_free:
		child.free()

	if show_ground:
		var g := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(CELL, 0.18, CELL)
		g.mesh = gm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.82, 0.74, 0.58)
		g.material_override = gmat
		g.position = Vector3(0, -0.09, 0)
		add_child(g)

	if show_cell_border:
		var half := CELL * 0.5
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for i in range(4):
			var line := MeshInstance3D.new()
			var lb := BoxMesh.new()
			var horiz: bool = (i < 2)
			lb.size = Vector3(CELL if horiz else 0.04, 0.02, 0.04 if horiz else CELL)
			line.mesh = lb
			line.material_override = bmat
			match i:
				0: line.position = Vector3(0,     0.01,  half)
				1: line.position = Vector3(0,     0.01, -half)
				2: line.position = Vector3( half, 0.01,  0)
				3: line.position = Vector3(-half, 0.01,  0)
			add_child(line)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(body_width, body_height, body_width)
	body.mesh = bm
	var bmat2 := StandardMaterial3D.new()
	bmat2.albedo_color = body_color
	body.material_override = bmat2
	body.position = Vector3(0, body_height * 0.5, 0)
	add_child(body)

	if has_roof:
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(body_width + 0.18, roof_height, body_width + 0.18)
		prism.left_to_right = 0.5
		roof.mesh = prism
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = roof_color
		roof.material_override = rmat
		roof.position = Vector3(0, body_height + roof_height * 0.5, 0)
		add_child(roof)
