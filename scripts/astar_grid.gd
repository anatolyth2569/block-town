class_name AStarGrid

# Grid-based A* pathfinding. Building cells and water are impassable.
# Returns Array of Vector2i cells (includes start and end), empty if no path.
static func find_path(from: Vector2i, to: Vector2i, gm: GridManager) -> Array:
	if from == to:
		return [from]
	var open: Array = [from]
	var closed: Dictionary = {}
	var came_from: Dictionary = {}
	var g: Dictionary = { from: 0.0 }
	var f: Dictionary = { from: _h(from, to) }

	while not open.is_empty():
		var cur: Vector2i = open[0]
		for c in open:
			if f.get(c, INF) < f.get(cur, INF):
				cur = c
		if cur == to:
			return _reconstruct(came_from, cur)
		open.erase(cur)
		closed[cur] = true
		for nb in _neighbors(cur, to, gm):
			if closed.has(nb):
				continue
			var tg: float = g.get(cur, INF) + 1.0
			if tg < g.get(nb, INF):
				came_from[nb] = cur
				g[nb] = tg
				f[nb] = tg + _h(nb, to)
				if nb not in open:
					open.append(nb)
	return []

# Convert cell path to world positions (center of each cell, y=0).
static func cells_to_world(cells: Array, gm: GridManager) -> Array:
	var result: Array = []
	for cell in cells:
		var w: Vector3 = gm.cell_to_world(cell)
		w.x += GridManager.CELL_SIZE * 0.5
		w.z += GridManager.CELL_SIZE * 0.5
		result.append(w)
	return result

static func _h(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))

static func _neighbors(cell: Vector2i, goal: Vector2i, gm: GridManager) -> Array:
	var result: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = cell + d
		if _walkable(nb, goal, gm):
			result.append(nb)
	return result

static func _walkable(cell: Vector2i, goal: Vector2i, gm: GridManager) -> bool:
	if not gm.is_cell_valid(cell):
		return false
	# The goal cell itself is always "walkable" so we can reach destinations
	# that may be adjacent to buildings (e.g. a field or resource site)
	if cell == goal:
		return true
	if gm._buildings.has(cell):
		return false
	if gm.get_terrain(cell) == GridManager.Terrain.WATER:
		return false
	return true

static func _reconstruct(came_from: Dictionary, cur: Vector2i) -> Array:
	var path: Array = [cur]
	while came_from.has(cur):
		cur = came_from[cur]
		path.push_front(cur)
	return path
