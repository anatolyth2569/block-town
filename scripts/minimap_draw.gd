extends Control

var grid_manager: Node = null

const CELL_PX: int = 18

const C_GRASS  := Color(0.28, 0.65, 0.20)
const C_WATER  := Color(0.12, 0.40, 0.82)
const C_FOREST := Color(0.08, 0.30, 0.10)
const C_ROAD   := Color(0.72, 0.58, 0.40)
const C_PAVED  := Color(0.48, 0.48, 0.52)
const C_POND   := Color(0.24, 0.60, 0.95)
const C_BUILD  := Color(1.00, 0.82, 0.18)

func _draw() -> void:
	if grid_manager == null:
		return
	var t: Dictionary = grid_manager._terrain
	var b: Dictionary = grid_manager._buildings
	var ponds: Dictionary = grid_manager._cell_to_pond
	for xi in range(20):
		for zi in range(20):
			var cell := Vector2i(xi, zi)
			var terrain: int = t.get(cell, 0)
			var col: Color
			match terrain:
				1: col = C_POND if ponds.has(cell) else C_WATER
				2: col = C_FOREST
				3: col = C_ROAD
				4: col = C_PAVED
				_: col = C_GRASS
			draw_rect(Rect2(xi * CELL_PX, zi * CELL_PX, CELL_PX - 1, CELL_PX - 1), col)
	for cell in b:
		var bld = b[cell]
		if bld == null or not is_instance_valid(bld):
			continue
		draw_rect(Rect2(cell.x * CELL_PX + 1, cell.y * CELL_PX + 1, CELL_PX - 2, CELL_PX - 2), C_BUILD)
