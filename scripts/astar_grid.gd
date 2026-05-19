class_name AStarGrid

# Grid-based A* pathfinding.
# Water is impassable. Building cells cost 200 so workers always prefer going
# around them. Roads cost 0.5 (workers prefer roads). Empty grass = 1.0.
# Heuristic uses min-cost (0.5) so it stays admissible.
# Returns Array of Vector2i cells (includes start and end), empty only if
# completely surrounded by water with no exit.
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
			var step_cost: float = _cell_cost(nb, to, gm)
			var tg: float = g.get(cur, INF) + step_cost
			if tg < g.get(nb, INF):
				came_from[nb] = cur
				g[nb] = tg
				f[nb] = tg + _h(nb, to)
				if nb not in open:
					open.append(nb)
	return []

static func _cell_cost(cell: Vector2i, goal: Vector2i, gm: GridManager) -> float:
	if cell == goal:
		return 1.0  # always cheap to enter the destination
	if gm._buildings.has(cell):
		return 200.0  # very expensive — workers strongly avoid walking through buildings
	if gm.is_road_terrain(gm.get_terrain(cell)):
		return 0.5  # roads are preferred
	return 1.0

# Heuristic: Manhattan distance scaled by min step cost (0.5) → admissible
static func _h(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y)) * 0.5

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
	if gm.get_terrain(cell) == GridManager.Terrain.WATER:
		return false
	return true

static func _reconstruct(came_from: Dictionary, cur: Vector2i) -> Array:
	var path: Array = [cur]
	while came_from.has(cur):
		cur = came_from[cur]
		path.push_front(cur)
	return path
