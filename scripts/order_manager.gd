extends Node

signal orders_changed
signal trade_orders_changed
signal sale_made(reward: int, is_trade: bool)

const MAX_ORDERS: int = 3

var orders: Array = []  # Array of Dictionary: {items: Dict, reward: int, label: String}
var trade_orders: Array = []  # Array of Dictionary: {city, item, qty, reward, duration, remaining}

const ORDER_TEMPLATES: Array = [
	# Tier 1 — raw
	{"label": "Deliver Wheat",        "items": {"Wheat": 8},            "reward": 90},
	{"label": "Deliver Wood",         "items": {"Wood": 6},             "reward": 70},
	{"label": "Deliver Cotton",       "items": {"Cotton": 5},           "reward": 90},
	{"label": "Deliver Corn",         "items": {"Corn": 6},             "reward": 85},
	{"label": "Deliver Sugarcane",    "items": {"Sugarcane": 5},        "reward": 80},
	# Tier 2-3 — processed
	{"label": "Deliver Flour",        "items": {"Flour": 5},            "reward": 110},
	{"label": "Deliver Planks",       "items": {"Planks": 4},           "reward": 110},
	{"label": "Deliver Sugar",        "items": {"Sugar": 4},            "reward": 140},
	{"label": "Deliver Milk & Eggs",  "items": {"Milk": 3, "Egg": 3},   "reward": 130},
	{"label": "Deliver Wool",         "items": {"Wool": 3},             "reward": 120},
	{"label": "Deliver Tools",        "items": {"Tools": 3},            "reward": 160},
	{"label": "Deliver Oil",          "items": {"Oil": 4},              "reward": 110},
	{"label": "Deliver Gasoline",     "items": {"Gasoline": 3},         "reward": 155},
	# Tier 4 — food
	{"label": "Deliver Bread",        "items": {"Bread": 4},            "reward": 190},
	{"label": "Deliver Bread (bulk)", "items": {"Bread": 8},            "reward": 380},
	{"label": "Deliver Cake",         "items": {"Cake": 3},             "reward": 260},
	{"label": "Deliver Cookies",      "items": {"Cookie": 4},           "reward": 250},
	{"label": "Deliver Pumpkin Pie",  "items": {"PumpkinPie": 3},       "reward": 245},
	{"label": "Deliver Dairy Cake",   "items": {"DairyCake": 3},        "reward": 245},
	{"label": "Deliver Flour & Bread","items": {"Flour": 2, "Bread": 3}, "reward": 175},
]

const TRADE_TEMPLATES: Array = [
	{"city": "Bangkok",      "item": "Bread",      "qty": 4,  "reward": 220,  "duration": 120},
	{"city": "Chiang Mai",   "item": "Cake",        "qty": 2,  "reward": 180,  "duration": 180},
	{"city": "Phuket",       "item": "Flour",       "qty": 5,  "reward": 130,  "duration": 150},
	{"city": "Pattaya",      "item": "Planks",      "qty": 4,  "reward": 110,  "duration": 90},
	{"city": "Khon Kaen",    "item": "Bread",       "qty": 8,  "reward": 420,  "duration": 240},
	{"city": "Hat Yai",      "item": "Wheat",       "qty": 10, "reward": 160,  "duration": 120},
	{"city": "Korat",        "item": "Wood",        "qty": 4,  "reward": 95,   "duration": 60},
	{"city": "Nakhon Ratch.","item": "Cookie",      "qty": 3,  "reward": 200,  "duration": 150},
	{"city": "Udon Thani",   "item": "PumpkinPie",  "qty": 3,  "reward": 240,  "duration": 180},
	{"city": "Surat Thani",  "item": "Wool",        "qty": 4,  "reward": 180,  "duration": 120},
	{"city": "Chiang Rai",   "item": "Gasoline",    "qty": 3,  "reward": 160,  "duration": 90},
	{"city": "Rayong",       "item": "Tools",       "qty": 3,  "reward": 170,  "duration": 150},
]

func _ready() -> void:
	_refill_orders()
	_refill_trade_orders()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick_trade_timers)
	add_child(t)

func _refill_orders() -> void:
	var pool: Array = ORDER_TEMPLATES.duplicate()
	pool.shuffle()
	orders.clear()
	for i in range(min(MAX_ORDERS, pool.size())):
		orders.append(pool[i].duplicate(true))
	orders_changed.emit()

func _refill_trade_orders() -> void:
	trade_orders.clear()
	var pool: Array = TRADE_TEMPLATES.duplicate()
	pool.shuffle()
	for i in range(min(5, pool.size())):
		var o: Dictionary = pool[i].duplicate()
		o["remaining"] = o["duration"]
		trade_orders.append(o)
	trade_orders_changed.emit()

func _tick_trade_timers() -> void:
	for i in range(trade_orders.size()):
		trade_orders[i]["remaining"] -= 1
		if trade_orders[i]["remaining"] <= 0:
			var pool: Array = TRADE_TEMPLATES.duplicate()
			pool.shuffle()
			trade_orders[i] = pool[0].duplicate()
			trade_orders[i]["remaining"] = trade_orders[i]["duration"]
	trade_orders_changed.emit()

func try_fulfill(index: int, resource_manager) -> bool:
	if index < 0 or index >= orders.size():
		return false
	var order: Dictionary = orders[index]
	if not resource_manager.has_resources(order["items"]):
		return false
	# Fulfilling an order dispatches a Truck — requires Gasoline
	if resource_manager.get_amount("Gasoline") < 1:
		return false
	for res in order["items"]:
		resource_manager.remove_resource(res, order["items"][res])
	resource_manager.remove_resource("Gasoline", 1)
	resource_manager.add_resource("Gold", order["reward"])
	sale_made.emit(order["reward"], false)
	orders.remove_at(index)
	# Add a new random order to replace the fulfilled one
	var pool: Array = ORDER_TEMPLATES.duplicate()
	pool.shuffle()
	for tmpl in pool:
		var already_in: bool = false
		for o in orders:
			if o["label"] == tmpl["label"]:
				already_in = true
				break
		if not already_in:
			orders.append(tmpl.duplicate(true))
			break
	orders_changed.emit()
	return true

func get_save_data() -> Dictionary:
	return {
		"orders": orders.duplicate(true),
		"trade_orders": trade_orders.duplicate(true),
	}

func load_from_save(data: Dictionary) -> void:
	if data.has("orders") and data["orders"] is Array:
		orders = data["orders"].duplicate(true)
		orders_changed.emit()
	if data.has("trade_orders") and data["trade_orders"] is Array:
		trade_orders = data["trade_orders"].duplicate(true)
		trade_orders_changed.emit()

func try_trade(index: int, resource_manager) -> bool:
	if index < 0 or index >= trade_orders.size():
		return false
	var order: Dictionary = trade_orders[index]
	var item: String = order["item"]
	var qty: int = order["qty"]
	if resource_manager.get_amount(item) < qty:
		return false
	if resource_manager.get_amount("Gasoline") < 1:
		return false
	resource_manager.remove_resource(item, qty)
	resource_manager.remove_resource("Gasoline", 1)
	resource_manager.add_resource("Gold", order["reward"])
	sale_made.emit(order["reward"], true)
	# Replace with new order
	var pool: Array = TRADE_TEMPLATES.duplicate()
	pool.shuffle()
	trade_orders[index] = pool[0].duplicate()
	trade_orders[index]["remaining"] = trade_orders[index]["duration"]
	trade_orders_changed.emit()
	return true
