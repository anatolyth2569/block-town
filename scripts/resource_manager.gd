extends Node

signal resource_changed(resource_name: String, new_amount: int)
signal population_changed(available: int, used: int)
signal gold_depleted

var population: int = 0
var population_used: int = 0

# Only currency-type resources live here.
# All materials (Wood, Wheat, etc.) are physical — stored in building._local_stock.
var _amounts: Dictionary = {
	"Gold":     500,
	"Gasoline": 20,
}

const WAGE_INTERVAL: float = 30.0
const WAGE_PER_WORKER: int = 1

func _ready() -> void:
	var wage_timer := Timer.new()
	wage_timer.wait_time = WAGE_INTERVAL
	wage_timer.autostart = true
	wage_timer.timeout.connect(_pay_wages)
	add_child(wage_timer)

func _pay_wages() -> void:
	if population_used <= 0:
		return
	var cost: int = population_used * WAGE_PER_WORKER
	var was_positive: bool = _amounts["Gold"] > 0
	_amounts["Gold"] = max(0, _amounts["Gold"] - cost)
	resource_changed.emit("Gold", _amounts["Gold"])
	if _amounts["Gold"] == 0 and was_positive:
		gold_depleted.emit()

func get_amount(res_name: String) -> int:
	return _amounts.get(res_name, 0)

func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if get_amount(res) < cost[res]:
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		_amounts[res] = _amounts.get(res, 0) - cost[res]
		resource_changed.emit(res, _amounts.get(res, 0))
	return true

func add_resource(res_name: String, amount: int) -> int:
	if not _amounts.has(res_name):
		return 0  # Non-currency materials are physical; don't track here
	_amounts[res_name] += amount
	resource_changed.emit(res_name, _amounts[res_name])
	return amount

func remove_resource(res_name: String, amount: int) -> bool:
	if not _amounts.has(res_name): return false
	if _amounts[res_name] < amount: return false
	_amounts[res_name] -= amount
	resource_changed.emit(res_name, _amounts[res_name])
	return true

func has_resources(required: Dictionary) -> bool:
	for res in required:
		if get_amount(res) < required[res]:
			return false
	return true

# Physical storage is in building._local_stock; always return true here
func has_storage_for(_amount: int) -> bool:
	return true

func get_total_stored() -> int:
	return 0

func add_population(amount: int) -> void:
	population += amount
	population_changed.emit(population, population_used)

func remove_population(amount: int) -> void:
	population = max(0, population - amount)
	population_changed.emit(population, population_used)

func use_worker() -> bool:
	if population_used >= population:
		return false
	population_used += 1
	population_changed.emit(population, population_used)
	return true

func free_worker() -> void:
	population_used = max(0, population_used - 1)
	population_changed.emit(population, population_used)

func has_free_worker() -> bool:
	return population_used < population

func get_save_data() -> Dictionary:
	return _amounts.duplicate()

func load_from_save(data: Dictionary) -> void:
	for key in data:
		_amounts[key] = int(data[key])
	resource_changed.emit("Gold", _amounts.get("Gold", 0))
	resource_changed.emit("Gasoline", _amounts.get("Gasoline", 0))
