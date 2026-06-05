extends Node

signal orders_changed

const SLOTS: int = 3

# tier: 1=easy/fast, 2=medium, 3=hard/slow
# reward is Gold for fulfilling the full order
const _POOL: Array = [
	# ── Tier 1: single-good (fast/easy) ──────────────────────────────────
	{"tier": 1, "goods": {"Wheat": 5},              "reward": 52,  "ttl": 90.0},
	{"tier": 1, "goods": {"Corn": 5},               "reward": 55,  "ttl": 90.0},
	{"tier": 1, "goods": {"Wood": 6},               "reward": 46,  "ttl": 90.0},
	{"tier": 1, "goods": {"Salt": 4},               "reward": 50,  "ttl": 90.0},
	{"tier": 1, "goods": {"Milk": 3},               "reward": 58,  "ttl": 90.0},
	{"tier": 1, "goods": {"Egg": 4},                "reward": 56,  "ttl": 90.0},
	{"tier": 1, "goods": {"Sugarcane": 5},          "reward": 58,  "ttl": 90.0},
	# ── Tier 1: multi-good ───────────────────────────────────────────────
	{"tier": 1, "goods": {"Wheat": 3, "Corn": 3},   "reward": 80,  "ttl": 120.0},
	{"tier": 1, "goods": {"Milk": 2, "Egg": 3},     "reward": 88,  "ttl": 120.0},
	{"tier": 1, "goods": {"Wood": 4, "Salt": 2},    "reward": 78,  "ttl": 120.0},
	# ── Tier 2: single-good ───────────────────────────────────────────────
	{"tier": 2, "goods": {"Flour": 3},              "reward": 72,  "ttl": 150.0},
	{"tier": 2, "goods": {"Feed": 5},               "reward": 65,  "ttl": 150.0},
	{"tier": 2, "goods": {"Wool": 3},               "reward": 134, "ttl": 150.0},
	{"tier": 2, "goods": {"Butter": 2},             "reward": 90,  "ttl": 150.0},
	{"tier": 2, "goods": {"Sugar": 3},              "reward": 120, "ttl": 150.0},
	{"tier": 2, "goods": {"Planks": 4},             "reward": 86,  "ttl": 150.0},
	{"tier": 2, "goods": {"Tomato": 5},             "reward": 68,  "ttl": 150.0},
	# ── Tier 2: multi-good ───────────────────────────────────────────────
	{"tier": 2, "goods": {"Flour": 2, "Butter": 2},         "reward": 145, "ttl": 180.0},
	{"tier": 2, "goods": {"Wool": 2, "Sugar": 2},           "reward": 170, "ttl": 180.0},
	{"tier": 2, "goods": {"Planks": 3, "Feed": 3},          "reward": 128, "ttl": 180.0},
	{"tier": 2, "goods": {"Milk": 2, "Flour": 2, "Egg": 2}, "reward": 155, "ttl": 180.0},
	{"tier": 2, "goods": {"PadKrapao": 2},           "reward": 130, "ttl": 180.0},
	{"tier": 2, "goods": {"Somtam": 2},              "reward": 125, "ttl": 180.0},
	{"tier": 2, "goods": {"TomYum": 2},              "reward": 135, "ttl": 180.0},
	{"tier": 2, "goods": {"Pork": 2},                "reward": 125, "ttl": 180.0},
	{"tier": 2, "goods": {"Fabric": 2},              "reward": 140, "ttl": 180.0},
	{"tier": 2, "goods": {"Pork": 1, "Bread": 1},           "reward": 160, "ttl": 180.0},
	# ── Tier 3: single-good ───────────────────────────────────────────────
	{"tier": 3, "goods": {"Bread": 3},              "reward": 210, "ttl": 240.0},
	{"tier": 3, "goods": {"Cookie": 2},             "reward": 180, "ttl": 240.0},
	{"tier": 3, "goods": {"Cake": 2},               "reward": 240, "ttl": 240.0},
	{"tier": 3, "goods": {"Tools": 2},              "reward": 140, "ttl": 240.0},
	{"tier": 3, "goods": {"Gasoline": 3},           "reward": 210, "ttl": 240.0},
	{"tier": 3, "goods": {"DairyCake": 2},          "reward": 232, "ttl": 240.0},
	# ── Tier 3: multi-good ───────────────────────────────────────────────
	{"tier": 3, "goods": {"Bread": 2, "Butter": 2},         "reward": 295, "ttl": 270.0},
	{"tier": 3, "goods": {"Cake": 1, "Cookie": 2},          "reward": 330, "ttl": 270.0},
	{"tier": 3, "goods": {"Tools": 2, "Gasoline": 2},       "reward": 340, "ttl": 270.0},
	{"tier": 3, "goods": {"Bread": 2, "Cookie": 1, "Egg": 3}, "reward": 310, "ttl": 270.0},
	{"tier": 3, "goods": {"PadKrapao": 2, "Pork": 1},         "reward": 250, "ttl": 270.0},
	{"tier": 3, "goods": {"Somtam": 2, "TomYum": 1},          "reward": 270, "ttl": 270.0},
	{"tier": 3, "goods": {"Fabric": 2, "Butter": 1},          "reward": 280, "ttl": 270.0},
]

# Each slot: {goods, reward, ttl, remaining, tier}
var _slots: Array = []

func _ready() -> void:
	randomize()
	_slots.resize(SLOTS)
	for i in SLOTS:
		_slots[i] = _pick(i)

func _process(delta: float) -> void:
	var dirty: bool = false
	for i in SLOTS:
		_slots[i]["remaining"] -= delta
		if _slots[i]["remaining"] <= 0.0:
			_slots[i] = _pick(i)
			dirty = true
	if dirty:
		orders_changed.emit()

func get_slots() -> Array:
	return _slots

func get_available_stock(gm) -> Dictionary:
	var stock: Dictionary = {}
	if gm == null:
		return stock
	var seen: Dictionary = {}
	for cell in gm._buildings.keys():
		var bld = gm._buildings[cell]
		if not is_instance_valid(bld):
			continue
		var uid: int = bld.get_instance_id()
		if seen.has(uid):
			continue
		seen[uid] = true
		for res in bld._local_stock:
			stock[res] = stock.get(res, 0) + bld._local_stock.get(res, 0)
	return stock

func can_fulfill(slot_idx: int, stock: Dictionary) -> bool:
	if slot_idx < 0 or slot_idx >= SLOTS:
		return false
	for res in _slots[slot_idx]["goods"]:
		if stock.get(res, 0) < _slots[slot_idx]["goods"][res]:
			return false
	return true

func fulfill(slot_idx: int, gm) -> int:
	if slot_idx < 0 or slot_idx >= SLOTS:
		return 0
	var stock: Dictionary = get_available_stock(gm)
	if not can_fulfill(slot_idx, stock):
		return 0
	var to_deduct: Dictionary = _slots[slot_idx]["goods"].duplicate()
	var seen: Dictionary = {}
	if gm != null:
		for cell in gm._buildings.keys():
			if to_deduct.is_empty():
				break
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld):
				continue
			var uid: int = bld.get_instance_id()
			if seen.has(uid):
				continue
			seen[uid] = true
			for res in to_deduct.keys().duplicate():
				var have: int = bld._local_stock.get(res, 0)
				if have <= 0:
					continue
				var take: int = min(to_deduct[res], have)
				bld._local_stock[res] -= take
				if bld._local_stock[res] <= 0:
					bld._local_stock.erase(res)
				to_deduct[res] -= take
				if to_deduct[res] <= 0:
					to_deduct.erase(res)
	var reward: int = _slots[slot_idx]["reward"]
	_slots[slot_idx] = _pick(slot_idx)
	orders_changed.emit()
	return reward

func _pick(slot_idx: int) -> Dictionary:
	var used: Array = []
	for i in SLOTS:
		if i == slot_idx:
			continue
		if i < _slots.size() and _slots[i] is Dictionary and not _slots[i].is_empty():
			for g in _slots[i]["goods"].keys():
				used.append(g)
	var pool: Array = []
	for t in _POOL:
		var conflict: bool = false
		for g in t["goods"].keys():
			if used.has(g):
				conflict = true
				break
		if not conflict:
			pool.append(t)
	if pool.is_empty():
		pool = _POOL
	var t: Dictionary = pool[randi() % pool.size()]
	return {
		"goods": t["goods"].duplicate(),
		"reward": t["reward"],
		"ttl": t["ttl"],
		"remaining": t["ttl"],
		"tier": t["tier"],
	}

func get_save_data() -> Dictionary:
	return {"slots": _slots.duplicate(true)}

func load_from_save(data: Dictionary) -> void:
	if data.has("slots") and (data["slots"] as Array).size() == SLOTS:
		_slots = data["slots"]
	orders_changed.emit()
