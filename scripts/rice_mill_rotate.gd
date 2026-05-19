extends Node3D

const SPEED: float = 0.5
var _pivot: Node3D

func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "MillPivot"
	add_child(_pivot)
	var rotating := [
		"M_034","M_036","M_038","M_040","M_042","M_044","M_046","M_048","M_050",
		"M_052","M_054","M_056","M_058","M_060","M_062","M_064","M_066","M_068","M_070",
		"M_072","M_074","M_076","M_078","M_080","M_082","M_084",
		"M_148","M_150","M_152","M_154","M_156","M_158"
	]
	for n in rotating:
		var node := get_node_or_null(n)
		if node:
			node.reparent(_pivot, true)

func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotate_y(SPEED * delta)
