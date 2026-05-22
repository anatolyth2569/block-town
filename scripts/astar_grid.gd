class_name AStarGrid

# 8-directional A* pathfinding.
# Building access rules:
#   Livestock pens (is_livestock_cell) = impassable for non-assigned workers.
#   Other buildings: cardinal through = blocked; diagonal through corner = expensive (base 3.0).
# Roads = cost 0.5.  Grass = cost 1.0.

static func find_path(from: Vector2i, to: Vector2i, gm: GridManager, caller_job: String = "") -> Array:
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
		for nb in _neighbors(cur, to, gm, caller_job):
			if closed.has(nb):
				continue
			var diag: bool = nb.x != cur.x and nb.y != cur.y
			var step_cost: float = _cell_cost(nb, to, gm, caller_job, diag)
			if step_cost >= 9999.0:
				continue
			var tg: float = g.get(cur, INF) + step_cost
			if tg < g.get(nb, INF):
				came_from[nb] = cur
				g[nb] = tg
				f[nb] = tg + _h(nb, to)
				if nb not in open:
					open.append(nb)
	return []

static func _cell_cost(cell: Vector2i, goal: Vector2i, gm: GridManager, caller_job: String, diag: bool) -> float:
	var sq2: float = sqrt(2.0)
	if cell == goal:
		return sq2 if diag else 1.0

	var base: float
	if gm._buildings.has(cell):
		if gm.is_livestock_cell(cell):
			if caller_job != "" and caller_job == gm.get_building_id(cell):
				base = 1.0
			else:
				return 9999.0
		else:
			# Cardinal goes through 80% core — blocked; diagonal only clips 10% corner.
			if not diag:
				return 9999.0
			base = 3.0
	elif gm.is_road_terrain(gm.get_terrain(cell)):
		base = 0.5
	else:
		base = 1.0

	return base * (sq2 if diag else 1.0)

# Octile distance × min-step-cost (0.5) — admissible for 8-directional movement
static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return 0.5 * (max(dx, dy) + (sqrt(2.0) - 1.0) * min(dx, dy))

static func _neighbors(cell: Vector2i, goal: Vector2i, gm: GridManager, caller_job: String) -> Array:
	var result: Array = []
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for d: Vector2i in dirs:
		var nb: Vector2i = cell + d
		if not _walkable(nb, goal, gm, caller_job):
			continue
		# Diagonal: don't cut through water corners
		if d.x != 0 and d.y != 0:
			var adj1: Vector2i = cell + Vector2i(d.x, 0)
			var adj2: Vector2i = cell + Vector2i(0, d.y)
			var t1: int = gm.get_terrain(adj1) if gm.is_cell_valid(adj1) else GridManager.Terrain.WATER
			var t2: int = gm.get_terrain(adj2) if gm.is_cell_valid(adj2) else GridManager.Terrain.WATER
			if t1 == GridManager.Terrain.WATER or t2 == GridManager.Terrain.WATER:
				continue
		result.append(nb)
	return result

static func _walkable(cell: Vector2i, goal: Vector2i, gm: GridManager, caller_job: String) -> bool:
	if not gm.is_cell_valid(cell):
		return false
	if gm.get_terrain(cell) == GridManager.Terrain.WATER:
		return false
	# Livestock pens block non-assigned workers (destination is always reachable)
	if cell != goal and gm._buildings.has(cell):
		if gm.is_livestock_cell(cell):
			return caller_job != "" and caller_job == gm.get_building_id(cell)
	return true

static func _reconstruct(came_from: Dictionary, cur: Vector2i) -> Array:
	var path: Array = [cur]
	while came_from.has(cur):
		cur = came_from[cur]
		path.push_front(cur)
	return path
