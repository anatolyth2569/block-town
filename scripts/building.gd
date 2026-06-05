class_name Building
extends Node3D

var data: BuildingData
const _GM_CELL: float = 3.0   # = GridManager.CELL_SIZE — local copy avoids circular compile dep
const _GM_FOREST: int = 2     # = GridManager.Terrain.FOREST (enum value)
var origin_cell: Vector2i
var facing: int = 0               # rotation state 0-3 (matches building_placer _rotation)
var skip_construction: bool = false  # true for starter buildings

var _resource_manager = null
var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _indicator: MeshInstance3D
var _status_label: Label3D
var _has_worker: bool = false
var _current_recipe: int = 0
var _worker = null
var _is_active: bool = false
var _construction_trips: Array = []   # resource types to transport (Gold excluded)
var _trips_done: int = 0
var _lumberyard_target: Vector2i = Vector2i(-1, -1)
var _pending_output: Dictionary = {}   # produced goods waiting for a worker to deliver to storage
var _local_stock: Dictionary = {}      # stock inside the building (used when max_stock > 0)
var _is_selected: bool = false
var _highlight: MeshInstance3D = null
var _info_label: Label3D = null
var _prod_timer: Timer = null
var _last_countdown_secs: int = -1
var _farmer_carrying: String = ""   # goods the farmer is carrying while walking to deliver
var _woodcutter_has_wood: bool = false
var _woodcutter_delivery_queue: Array = []
var _woodcutter_target_tree: Vector2i = Vector2i(-1, -1)
static var _claimed_forest_cells: Dictionary = {}
var _farmer_job_queue: Array = []   # {type, cell, produce} job queue for farmer
var _rancher_job_queue: Array = []  # {type, cell} job queue for rancher
var _rancher_carry: Dictionary = {} # resource → amount the rancher is currently carrying
var _engineer_job_queue: Array = [] # {cell} job queue for engineer
var _engineer_carry: Dictionary = {} # resource → amount the engineer is carrying
var _field_bar_bg: MeshInstance3D = null
var _field_bar_fill: MeshInstance3D = null
var _field_bar_mat: StandardMaterial3D = null
var _input_stock: Dictionary = {}   # input buffer for factory buildings (non-Water consumes)
var _carrier: Node = null           # carrier worker that fetches materials from storage
var _feed_in_trough: MeshInstance3D = null
var _produce_icon_label: Label3D = null
var _label_y: float = 2.5

# Returns the grid cell directly in front of this building's door.
func get_exit_cell() -> Vector2i:
	if data == null:
		return origin_cell
	var sz := data.size
	if facing % 2 == 1:
		sz = Vector2i(sz.y, sz.x)
	match facing % 4:
		0: return origin_cell + Vector2i(sz.x / 2, sz.y)
		1: return origin_cell + Vector2i(-1, sz.y / 2)
		2: return origin_cell + Vector2i(sz.x / 2, -1)
		3: return origin_cell + Vector2i(sz.x, sz.y / 2)
	return origin_cell + Vector2i(0, sz.y)

func _get_exit_world_pos() -> Vector3:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return position
	var ec := get_exit_cell()
	if not gm.is_cell_valid(ec) or gm._buildings.has(ec):
		return position
	return gm.cell_to_world(ec) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)

func _ready() -> void:
	_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		push_error("Building: ResourceManager not found")
		return
	if data == null:
		push_error("Building: data not set before adding to scene")
		return

	if data.population_bonus > 0:
		_resource_manager.add_population(data.population_bonus)

	_create_visual()

	if not skip_construction and data.build_time > 0.0:
		_start_construction()
	else:
		_activate_building()

func _process(_delta: float) -> void:
	if _is_active and data != null and data.grow_time > 0.0 and _field_bar_bg != null:
		_update_field_progress()
	if not _is_active or data == null or data.max_stock != 1 or data.workers_needed > 0:
		return
	if _prod_timer == null or not is_instance_valid(_prod_timer) or _status_label == null:
		return
	var stock_full: bool = get_local_stock_total() >= data.max_stock
	if stock_full:
		if _last_countdown_secs != -2:
			_last_countdown_secs = -2
			_update_stock_label()
		return
	var secs: int = ceili(_prod_timer.time_left)
	if secs != _last_countdown_secs:
		_last_countdown_secs = secs
		var res_icon: String = ""
		if not data.produces.is_empty():
			res_icon = _RES_ICON.get(data.produces.keys()[0], "")
		_status_label.text = "%s %d/%d ⏳%ds" % [res_icon, get_local_stock_total(), data.max_stock, secs]

func _exit_tree() -> void:
	# Unregister from build queue (frees builder worker if one was assigned)
	var bq = get_node_or_null("/root/BuildQueue")
	if bq != null:
		bq.unregister(self)
	if _resource_manager == null or data == null:
		return
	if data.population_bonus > 0:
		_resource_manager.remove_population(data.population_bonus)
	if _has_worker and data.workers_needed > 0:
		_resource_manager.free_worker()
	if _woodcutter_target_tree != Vector2i(-1, -1):
		_claimed_forest_cells.erase(_woodcutter_target_tree)
		_woodcutter_target_tree = Vector2i(-1, -1)
	if _worker != null and is_instance_valid(_worker):
		_worker.queue_free()
		_worker = null
	if _carrier != null and is_instance_valid(_carrier):
		_carrier.queue_free()
		_carrier = null

# ---- Construction Phase ----

func _start_construction() -> void:
	_set_construction_mode(true)
	if data.build_cost.is_empty():
		# Free building — start immediately
		_begin_construction_internal()
		return
	# Register with BuildQueue; actual work begins when a Builder is assigned
	var bq = get_node_or_null("/root/BuildQueue")
	if bq != null:
		if _status_label != null:
			var _lm_s = get_node_or_null("/root/LocaleManager")
			_status_label.text = _lm_s.status("waiting_builder") if _lm_s != null else "⏳ Waiting for Builder"
		bq.register(self)
	else:
		_begin_construction_internal()

# Called by BuildQueue when materials have been paid and a Builder is assigned
func begin_construction() -> void:
	_begin_construction_internal()

func _begin_construction_internal() -> void:
	_construction_trips = []
	for res in data.build_cost:
		if res != "Gold":
			for _i in range(data.build_cost[res]):
				_construction_trips.append(res)
	_trips_done = 0
	_update_construction_label()
	if _construction_trips.is_empty():
		_on_construction_done()

const TRUCK_CAPACITY: int = 20

# Gold earned per unit when sold by Truck — higher-tier items worth more
const SALE_PRICE: Dictionary = {
	"Wood": 6,     "Planks": 18,
	"Wheat": 8,    "Flour": 15,   "Bread": 35,
	"Sugarcane": 10, "Sugar": 25, "Cotton": 12,
	"Corn": 10,    "Pumpkin": 12, "Tomato": 10, "Salt": 12,
	"Milk": 15,    "Egg": 12,     "Butter": 28,
	"Cake": 60,    "Cookie": 45,  "PumpkinPie": 58, "DairyCake": 58,
	"Feed": 8,     "Wool": 28,
	"Oil": 18,     "Gasoline": 35, "Plastic": 30, "Chemical": 30,
	"Tools": 35,
}

const _RES_ICON: Dictionary = {
	"Gold": "🪙", "Wood": "🪵", "Water": "💧",
	"Wheat": "🌾", "Flour": "🌀", "Bread": "🍞",
	"Planks": "📋", "Gasoline": "⛽",
	"Sugarcane": "🌿", "Cotton": "🌸", "Pumpkin": "🎃",
	"Corn": "🌽", "Tomato": "🍅",
	"Sugar": "🍬", "Milk": "🥛", "Egg": "🥚",
	"Butter": "🧈", "Cake": "🎂", "Power": "⚡",
	"Tools": "🔧", "Salt": "🧂",
	"PumpkinPie": "🥧", "DairyCake": "🍰", "Cookie": "🍪",
	"Feed": "🌾", "Wool": "🧶",
	"Oil": "🛢️", "Plastic": "🧴", "Chemical": "⚗️",
	"Battery": "🔋",
}

const _FIELD_BAR_W: float = 1.5
const _FIELD_BAR_H: float = 0.09
const _FIELD_BAR_Y: float = 2.2


func _update_construction_label() -> void:
	if _status_label == null or data == null:
		return
	var needed: Dictionary = {}
	for res in _construction_trips:
		needed[res] = needed.get(res, 0) + 1
	var delivered: Dictionary = {}
	for i in range(_trips_done):
		var r: String = _construction_trips[i]
		delivered[r] = delivered.get(r, 0) + 1
	var parts: Array = []
	for res in needed:
		parts.append("%s%d/%d" % [_RES_ICON.get(res, "📦"), delivered.get(res, 0), needed[res]])
	if parts.is_empty():
		var _lm_u = get_node_or_null("/root/LocaleManager")
		_status_label.text = _lm_u.status("building") if _lm_u != null else "⚒ Building..."
	else:
		_status_label.text = "⚒\n" + "\n".join(parts)

func _set_construction_mode(active: bool) -> void:
	if _status_label != null:
		if active:
			var _lm_c = get_node_or_null("/root/LocaleManager")
			_status_label.text = _lm_c.status("building") if _lm_c != null else "⚒ Building..."
		else:
			_status_label.text = data.display_name
	if _mat != null:
		if active:
			_mat.albedo_color = Color(0.76, 0.76, 0.76, 0.65)
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			_mat.albedo_color = data.color
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	if _roof_mat != null:
		if active:
			_roof_mat.albedo_color = Color(0.56, 0.56, 0.56, 0.65)
			_roof_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			_roof_mat.albedo_color = _get_roof_color()
			_roof_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

func _get_roof_color() -> Color:
	return data.color.darkened(0.38)

func _on_construction_done() -> void:
	var bq = get_node_or_null("/root/BuildQueue")
	if bq != null:
		bq.on_build_complete(self)
	_activate_building()

func is_built() -> bool:
	return _is_active

func has_pending_construction_work() -> bool:
	return not _is_active and _trips_done < _construction_trips.size()

func take_next_construction_material(gm) -> Dictionary:
	for i in range(_trips_done, _construction_trips.size()):
		var res: String = _construction_trips[i]
		if res == "Wood":
			var ly_cell: Vector2i = gm.get_nearest_building_cell("lumberyard", origin_cell)
			if ly_cell != Vector2i(-1, -1):
				var bld = gm.get_building_node_at(ly_cell)
				if bld != null and is_instance_valid(bld) and bld.take_from_local_stock("Wood", 1):
					if i != _trips_done:
						var tmp: String = _construction_trips[_trips_done]
						_construction_trips[_trips_done] = _construction_trips[i]
						_construction_trips[i] = tmp
					_trips_done += 1  # claim trip immediately so no other builder double-takes
					var sp: Vector3 = gm.cell_to_world(ly_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
					return {"res": "Wood", "source_pos": sp, "needs_source_trip": true}
		else:
			if _resource_manager != null and _resource_manager.has_resources({res: 1}):
				_resource_manager.remove_resource(res, 1)
				if i != _trips_done:
					var tmp: String = _construction_trips[_trips_done]
					_construction_trips[_trips_done] = _construction_trips[i]
					_construction_trips[i] = tmp
				_trips_done += 1
				return {"res": res, "source_pos": position, "needs_source_trip": false}
	return {}

func deliver_construction_material(_res: String) -> void:
	if _is_active:
		return
	_update_construction_label()
	if _trips_done >= _construction_trips.size():
		_on_construction_done()

# ---- Activation ----

func _activate_building() -> void:
	_is_active = true
	_set_construction_mode(false)
	if _status_label != null:
		_status_label.visible = false
	if data.id in ["well", "wind_pump"]:
		_local_stock = {"Water": 1}
		_setup_well_timer()
		_update_stock_label()
		_assign_worker()
		return
	var has_production: bool = data.recipes.size() > 0 or data.produces.size() > 0 or data.consumes.size() > 0
	if data.production_time > 0 and has_production:
		_setup_timer()
	if data.id == "farm_house":
		_spawn_farmer()
	elif data.id == "ranch_house":
		_spawn_rancher()
	elif data.id == "woodcutter_house":
		_spawn_woodcutter()
	elif data.id == "builder_house":
		_spawn_builder()
	elif data.id == "engineer_house":
		_spawn_engineer()
	elif data.category == BuildingData.Category.HOUSING:
		_spawn_house_resident()
	elif data.workers_needed > 0 and data.production_time > 0:
		_spawn_worker()
	_assign_worker()
	if data.grow_time > 0.0:
		_create_field_bar()
	if data.id in ["animal_barn", "chicken_coop", "sheep_pen", "pig_pen"]:
		_spawn_livestock_animals()
	_update_produce_icon()

func is_factory_building() -> bool:
	if data == null or data.grow_time > 0.0: return false
	if data.id in ["well", "small_pond", "large_pond", "wind_pump", "water_facility"]: return false
	for res in data.consumes:
		if res != "Water": return true
	for recipe in data.recipes:
		var rc: Dictionary = recipe.get("consumes", {})
		for res in rc:
			if res != "Water": return true
	return false

func _spawn_carrier() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	_carrier = Worker.new()
	gm.add_child(_carrier)
	_carrier.setup(_get_exit_world_pos(), position, 0.0, "carrier")
	_carrier.set_cycle_callback(_carrier_get_trip_waypoints)

func _carrier_get_trip_waypoints() -> Array:
	if data == null or _resource_manager == null: return []
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return []

	var waypoints: Array = []
	var building_ref := self

	var trip_consumes: Dictionary = data.consumes
	if data.recipes.size() > 0:
		var recipe: Dictionary = data.recipes[_current_recipe % data.recipes.size()]
		trip_consumes = recipe.get("consumes", {})

	# One trip = one resource. Find the first missing resource and build a single pickup waypoint.
	for res in trip_consumes:
		var have: int = _input_stock.get(res, 0)
		var need: int = trip_consumes.get(res, 0)
		if have >= need: continue
		var to_take: int = 1

		# 1) First look for a building that has local stock of this resource
		var local_cell: Vector2i = _find_building_with_local_stock(gm, res, origin_cell)
		if local_cell != Vector2i(-1, -1):
			var src_pos: Vector3 = gm.cell_to_world(local_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			var cap_res: String = res
			var cap_take: int = to_take
			var cap_cell: Vector2i = local_cell
			var _cb_local := func():
				if not is_instance_valid(building_ref): return
				var src_bld = gm.get_building_node_at(cap_cell)
				if src_bld == null or not is_instance_valid(src_bld): return
				var taken: int = min(cap_take, src_bld._local_stock.get(cap_res, 0) as int)
				if taken <= 0: return
				if src_bld.take_from_local_stock(cap_res, taken):
					building_ref._input_stock[cap_res] = building_ref._input_stock.get(cap_res, 0) + taken
				if building_ref._worker != null and is_instance_valid(building_ref._worker):
					building_ref._worker.set_carrying(true)
			waypoints.append({"pos": src_pos, "pause": 0.6, "on_arrive": _cb_local})
			break

		# 2) Goods are in the global pool — find the nearest storage building
		var pool_amt: int = _resource_manager.get_amount(res)
		if pool_amt <= 0: continue
		var actual_take: int = min(to_take, pool_amt)
		var cap_res2: String = res
		var cap_take2: int = actual_take
		var storage_cell: Vector2i = _find_nearest_storage_building(gm, origin_cell)
		if storage_cell != Vector2i(-1, -1):
			var sto_pos: Vector3 = gm.cell_to_world(storage_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			var _cb_global := func():
				if not is_instance_valid(building_ref): return
				var take: int = min(cap_take2, building_ref._resource_manager.get_amount(cap_res2))
				if take > 0 and building_ref._resource_manager.pay({cap_res2: take}):
					building_ref._input_stock[cap_res2] = building_ref._input_stock.get(cap_res2, 0) + take
				if building_ref._worker != null and is_instance_valid(building_ref._worker):
					building_ref._worker.set_carrying(true)
			waypoints.append({"pos": sto_pos, "pause": 0.6, "on_arrive": _cb_global})
			break
		else:
			# No storage building but goods are in pool → take directly without walking
			var take: int = min(actual_take, _resource_manager.get_amount(res))
			if take > 0 and _resource_manager.pay({res: take}):
				_input_stock[res] = _input_stock.get(res, 0) + take

	if waypoints.is_empty(): return []

	var _cb_home := func():
		if not is_instance_valid(building_ref): return
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(false)
	waypoints.append({"pos": position, "pause": 0.3, "on_arrive": _cb_home})
	return waypoints

func _find_building_with_local_stock(gm, res: String, near_cell: Vector2i) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	var seen := {}
	for cell in gm._buildings.keys():
		var bld = gm._buildings[cell]
		if not is_instance_valid(bld): continue
		var uid: int = bld.get_instance_id()
		if seen.has(uid): continue
		seen[uid] = true
		if not (bld is Building): continue
		if bld._local_stock.get(res, 0) <= 0: continue
		var d: float = (Vector2(bld.origin_cell) - Vector2(near_cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best_cell = bld.origin_cell
	return best_cell

func _find_nearest_storage_building(gm, near_cell: Vector2i) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	for bid in ["silo", "warehouse", "barn"]:
		for cell in gm.get_all_building_cells(bid):
			var d: float = (Vector2(cell) - Vector2(near_cell)).length_squared()
			if d < best_dist:
				best_dist = d
				best_cell = cell
	return best_cell

func _find_nearest_silo(gm, near_cell: Vector2i) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	for cell in gm.get_all_building_cells("silo"):
		var d: float = (Vector2(cell) - Vector2(near_cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best_cell = cell
	return best_cell

func get_input_stock_amount(res: String) -> int:
	return _input_stock.get(res, 0)

func on_road_disconnected() -> void:
	if _worker != null and is_instance_valid(_worker):
		_worker.go_home()

func _assign_worker() -> void:
	if data.workers_needed <= 0:
		_has_worker = true
		return
	_has_worker = _resource_manager.use_worker()
	_update_indicator(_get_indicator_color())

func _spawn_house_resident() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	var home_pos := _get_exit_world_pos()
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(home_pos, home_pos, 0.0, data.id)
	_worker.paused = true

func _setup_well_timer() -> void:
	_prod_timer = Timer.new()
	_prod_timer.wait_time = data.production_time
	_prod_timer.one_shot = true
	_prod_timer.autostart = true
	_prod_timer.timeout.connect(_on_well_refill)
	add_child(_prod_timer)

func _on_well_refill() -> void:
	_local_stock["Water"] = 1
	_last_countdown_secs = -1
	_update_stock_label()

func take_from_local_stock(res: String, amount: int) -> bool:
	if _local_stock.get(res, 0) < amount:
		return false
	_local_stock[res] -= amount
	if _local_stock[res] <= 0:
		_local_stock.erase(res)
	_update_stock_label()
	# Restart production after all output is collected (Livestock and Industrial)
	if data != null and (data.worker_domain == BuildingData.WorkerDomain.LIVESTOCK or data.worker_domain == BuildingData.WorkerDomain.INDUSTRIAL):
		if get_local_stock_total() == 0 and _prod_timer != null and is_instance_valid(_prod_timer) and _prod_timer.is_stopped():
			_prod_timer.start()
			_update_indicator(Color(0.1, 0.9, 0.2))
	return true

func receive_resource(res: String, amount: int) -> bool:
	if data == null: return false
	var cap: int = data.max_stock
	if cap <= 0 and data.storage_bonus > 0:
		cap = data.storage_bonus  # Storage buildings use storage_bonus as capacity
	if cap <= 0: return false
	if get_local_stock_total() + amount > cap: return false
	_local_stock[res] = _local_stock.get(res, 0) + amount
	_update_stock_label()
	return true

func take_water() -> bool:
	if data == null or data.id not in ["well", "wind_pump"]:
		return false
	if _local_stock.get("Water", 0) <= 0:
		return false
	_local_stock.erase("Water")
	_last_countdown_secs = -1
	_update_stock_label()
	if _prod_timer != null and is_instance_valid(_prod_timer) and _prod_timer.is_stopped():
		_prod_timer.start()
	return true

func _spawn_farmer() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), position, 0.0, "farm_house",
			"res://assets/mini-characters/Models/GLB format/character-male-a.glb")
	_worker.set_cycle_callback(_farmer_find_job)
	_worker.arrived_home.connect(func():
		if _worker == null or not is_instance_valid(_worker): return
		# Refresh queue first, then let IDLE cycle_callback pick up the work.
		# Do NOT call _farmer_find_job() here — it would claim a job that IDLE
		# immediately re-checks and can't find (already claimed), causing WALKING_BACK loop.
		_farmer_scan_fields()
		_worker.paused = _farmer_job_queue.is_empty()
	)
	# Scan for jobs every 2 seconds, add to queue, and wake farmer if work is pending
	var scan_timer := Timer.new()
	scan_timer.wait_time = 2.0
	scan_timer.autostart = true
	scan_timer.timeout.connect(_farmer_scan_fields)
	add_child(scan_timer)
	_farmer_scan_fields()
	var wps: Array = _farmer_find_job()
	if wps.size() > 0:
		_worker.redirect(wps)

func _farmer_scan_fields() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return

	var queued_cells: Array = []
	for j in _farmer_job_queue:
		queued_cells.append(j["cell"])

	var seen: Array = []
	for map_cell in gm._buildings:
		var bld = gm._buildings[map_cell]
		if seen.has(bld): continue
		seen.append(bld)
		if not (bld is Building): continue
		var field_bld := bld as Building
		if field_bld.data == null: continue
		if field_bld.data.worker_domain != BuildingData.WorkerDomain.CROP_FIELD: continue

		var field_cell: Vector2i = field_bld.origin_cell
		if gm.is_field_growing(field_cell): continue

		var produce: String = ""
		if not field_bld.data.produces.is_empty():
			produce = field_bld.data.produces.keys()[0]

		if gm.is_field_harvest_ready(field_cell):
			# Queue harvest job for farmer
			if not queued_cells.has(field_cell) and not gm.is_field_job_claimed(field_cell):
				_farmer_job_queue.append({"type": "harvest", "cell": field_cell, "produce": produce})
				queued_cells.append(field_cell)
		else:
			# Check all input conditions — each resource must be fully met
			var all_met: bool = true
			var missing_res: String = ""
			for res in field_bld.data.consumes:
				var need: int = field_bld.data.consumes.get(res, 0)
				var have: int = gm.get_field_input(field_cell, res)
				if res == "Water": have += gm.get_water_bonus(field_cell)
				if have < need:
					all_met = false
					missing_res = res
					break
			if all_met:
				if field_bld.data.grow_time > 0.0:
					gm.start_field_growth(field_cell, field_bld.data.grow_time * gm.get_production_modifier(field_cell))
			elif not queued_cells.has(field_cell) and not gm.is_field_job_claimed(field_cell):
				_farmer_job_queue.append({"type": "supply", "cell": field_cell, "produce": produce, "res": missing_res})
				queued_cells.append(field_cell)

	# Sort harvest jobs by distance from farmer
	var farmer_pos: Vector3 = _worker.position if (_worker != null and is_instance_valid(_worker)) else position
	_farmer_job_queue.sort_custom(func(a, b):
		var da: float = farmer_pos.distance_squared_to(gm.cell_to_world(a["cell"]))
		var db: float = farmer_pos.distance_squared_to(gm.cell_to_world(b["cell"]))
		return da < db
	)

	# Wake farmer if idle and harvest work is available
	if _worker != null and is_instance_valid(_worker) and _worker.paused and not _farmer_job_queue.is_empty():
		var wps: Array = _farmer_find_job()
		if not wps.is_empty():
			_worker.paused = false
			_worker.redirect(wps)

func _farmer_find_job() -> Array:
	if _farmer_carrying != "":
		return _farmer_deliver()

	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return []

	while not _farmer_job_queue.is_empty():
		var job: Dictionary = _farmer_job_queue.pop_front()
		var cell: Vector2i = job["cell"]
		var job_type: String = job.get("type", "harvest")
		if gm.is_field_job_claimed(cell): continue

		if job_type == "harvest":
			if not gm.is_field_harvest_ready(cell): continue
			if not gm.claim_field_job(cell, "harvest"): continue
			return _farmer_build_waypoints(job, gm)
		elif job_type == "supply":
			if gm.is_field_growing(cell): continue
			var field_bld := gm.get_building_node_at(cell) as Building
			if field_bld == null or field_bld.data == null: continue
			var supply_res: String = job.get("res", "")
			if supply_res == "": continue
			var need: int = field_bld.data.consumes.get(supply_res, 0)
			var have: int = gm.get_field_input(cell, supply_res)
			if supply_res == "Water": have += gm.get_water_bonus(cell)
			if have >= need: continue
			var src_check: Vector2i = _find_nearest_well_with_water(gm) if supply_res == "Water" else _find_building_with_local_stock(gm, supply_res, origin_cell)
			if src_check == Vector2i(-1, -1): continue
			if not gm.claim_field_job(cell, "supply"): continue
			return _farmer_build_waypoints(job, gm)

	return []

func _farmer_build_waypoints(job: Dictionary, gm) -> Array:
	var job_type: String = job.get("type", "harvest")
	var job_cell: Vector2i = job["cell"]
	var job_produce: String = job.get("produce", "")
	var job_cell_world: Vector3 = gm.cell_to_world(job_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var captured_cell := job_cell
	var captured_produce := job_produce

	if job_type == "harvest":
		var _cb_harvest := func():
			_farmer_carrying = captured_produce
			gm.mark_field_harvested(captured_cell)
			if _worker != null and is_instance_valid(_worker): _worker.set_carrying(true)
		return [{"pos": job_cell_world, "pause": 1.5, "on_arrive": _cb_harvest}]

	# Supply delivery: fetch the missing resource → bring to field
	var supply_res: String = job.get("res", "")
	if supply_res == "":
		gm.release_field_job(captured_cell)
		return []
	# Water comes from wells; everything else comes from warehouse/silo local_stock
	var src_cell: Vector2i
	if supply_res == "Water":
		src_cell = _find_nearest_well_with_water(gm)
	else:
		src_cell = _find_building_with_local_stock(gm, supply_res, origin_cell)
	if src_cell == Vector2i(-1, -1):
		gm.release_field_job(captured_cell)
		return []
	var src_pos: Vector3 = gm.cell_to_world(src_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var captured_src := src_cell
	var captured_res := supply_res
	var _cb_take := func():
		if captured_res == "Water":
			var well_bld = gm.get_building_node_at(captured_src)
			if well_bld != null and is_instance_valid(well_bld): well_bld.take_water()
		else:
			var src_bld = gm.get_building_node_at(captured_src) as Building
			if src_bld != null and is_instance_valid(src_bld): src_bld.take_from_local_stock(captured_res, 1)
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(true)
	var _cb_deliver := func():
		gm.add_field_input(captured_cell, captured_res, 1)
		gm.release_field_job(captured_cell)
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
	return [
		{"pos": src_pos, "pause": 0.8, "on_arrive": _cb_take},
		{"pos": job_cell_world, "pause": 0.8, "on_arrive": _cb_deliver}
	]

func _find_nearest_well_with_water(gm) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	var farmer_cell: Vector2i = gm.world_to_cell((_worker.position if (_worker != null and is_instance_valid(_worker)) else position))
	var all_water_cells: Array = []
	for wid in ["well", "wind_pump"]:
		all_water_cells.append_array(gm.get_all_building_cells(wid))
	for cell in all_water_cells:
		var bld = gm.get_building_node_at(cell)
		if bld == null or not is_instance_valid(bld): continue
		var stock = bld.get("_local_stock")
		if stock == null or stock.get("Water", 0) <= 0: continue
		var d: float = (Vector2(cell) - Vector2(farmer_cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best_cell = cell
	return best_cell

# ===== Rancher (ranch_house) — feeds livestock and collects products =====

func _spawn_rancher() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), position, 0.0, "ranch_house",
			"res://assets/mini-characters/Models/GLB format/character-female-a.glb")
	_worker.set_cycle_callback(_rancher_find_job)
	_worker.arrived_home.connect(func():
		if _worker == null or not is_instance_valid(_worker): return
		_rancher_scan_barns()
		_worker.paused = _rancher_job_queue.is_empty() and _rancher_carry.is_empty()
	)
	var scan_timer := Timer.new()
	scan_timer.wait_time = 3.0
	scan_timer.autostart = true
	scan_timer.timeout.connect(_rancher_scan_barns)
	add_child(scan_timer)
	_rancher_scan_barns()
	var wps: Array = _rancher_find_job()
	if wps.size() > 0:
		_worker.redirect(wps)

func _rancher_scan_barns() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	# Track queued jobs per type so collect and feed can coexist for same barn
	var queued_collect: Array = []
	var queued_feed: Array = []
	var queued_supply: Array = []
	for j in _rancher_job_queue:
		match j.get("type", "collect"):
			"collect": queued_collect.append(j["cell"])
			"supply_mill": queued_supply.append(j["cell"])
			_: queued_feed.append(j["cell"])
	var seen: Dictionary = {}
	for map_cell in gm._buildings:
		var bld = gm._buildings[map_cell]
		if not is_instance_valid(bld): continue
		var uid: int = bld.get_instance_id()
		if seen.has(uid): continue
		seen[uid] = true
		if not (bld is Building): continue
		var barn := bld as Building
		if barn.data == null: continue
		# ── Passive factory buildings (e.g. feed_mill) — rancher supplies inputs ──
		if barn.data.workers_needed == 0 and barn.is_factory_building():
			var mill_cell: Vector2i = barn.origin_cell
			if not gm.is_field_job_claimed(mill_cell) and not queued_supply.has(mill_cell):
				for res in barn.data.consumes:
					if res == "Water": continue
					if barn._input_stock.get(res, 0) < barn.data.consumes.get(res, 0):
						_rancher_job_queue.append({"type": "supply_mill", "cell": mill_cell, "res": res})
						queued_supply.append(mill_cell)
						break
			continue
		if barn.data.worker_domain != BuildingData.WorkerDomain.LIVESTOCK: continue
		var barn_cell: Vector2i = barn.origin_cell
		if gm.is_field_job_claimed(barn_cell): continue
		# Collect output if ready
		if barn.get_local_stock_total() > 0 and not queued_collect.has(barn_cell):
			_rancher_job_queue.append({"type": "collect", "cell": barn_cell})
			queued_collect.append(barn_cell)
		# Feed barn if it needs Feed (independent of collect)
		if barn.data.consumes.has("Feed") and not queued_feed.has(barn_cell):
			var have: int = barn._input_stock.get("Feed", 0)
			var need: int = barn.data.consumes.get("Feed", 0)
			if have < need:
				_rancher_job_queue.append({"type": "feed", "cell": barn_cell})
				queued_feed.append(barn_cell)
	if _worker != null and is_instance_valid(_worker) and _worker.paused:
		if not _rancher_job_queue.is_empty() or not _rancher_carry.is_empty():
			var wps: Array = _rancher_find_job()
			if not wps.is_empty():
				_worker.paused = false
				_worker.redirect(wps)

func _rancher_find_job() -> Array:
	if not _rancher_carry.is_empty():
		return _rancher_deliver_output()
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return []
	while not _rancher_job_queue.is_empty():
		var job: Dictionary = _rancher_job_queue.pop_front()
		var cell: Vector2i = job["cell"]
		var job_type: String = job.get("type", "collect")
		if gm.is_field_job_claimed(cell): continue
		var barn_bld := gm.get_building_node_at(cell) as Building
		if barn_bld == null or not is_instance_valid(barn_bld): continue
		if job_type == "collect":
			if barn_bld.get_local_stock_total() <= 0: continue
			if not gm.claim_field_job(cell, "collect"): continue
			return _rancher_build_waypoints(job, gm)
		elif job_type == "feed":
			if barn_bld.data == null: continue
			var need: int = barn_bld.data.consumes.get("Feed", 0)
			if barn_bld._input_stock.get("Feed", 0) >= need: continue
			if not gm.claim_field_job(cell, "feed"): continue
			return _rancher_build_waypoints(job, gm)
		elif job_type == "supply_mill":
			if barn_bld.data == null: continue
			var res: String = job.get("res", "")
			if res == "": continue
			if barn_bld._input_stock.get(res, 0) >= barn_bld.data.consumes.get(res, 0): continue
			if not gm.claim_field_job(cell, "supply_mill"): continue
			return _rancher_build_waypoints(job, gm)
	return []

func _rancher_build_waypoints(job: Dictionary, gm) -> Array:
	var job_type: String = job.get("type", "collect")
	var cell: Vector2i = job["cell"]
	var barn_pos: Vector3 = gm.cell_to_world(cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var captured_cell := cell
	var building_ref := self
	if job_type == "collect":
		var cb_collect := func():
			var barn_bld = gm.get_building_node_at(captured_cell) as Building
			if barn_bld != null and is_instance_valid(barn_bld):
				for res in barn_bld._local_stock.keys().duplicate():
					var amt: int = barn_bld._local_stock.get(res, 0)
					if amt > 0 and barn_bld.take_from_local_stock(res, amt):
						building_ref._rancher_carry[res] = building_ref._rancher_carry.get(res, 0) + amt
			gm.release_field_job(captured_cell)
			if building_ref._worker != null and is_instance_valid(building_ref._worker):
				building_ref._worker.set_carrying(not building_ref._rancher_carry.is_empty())
		return [{"pos": barn_pos, "pause": 0.8, "on_arrive": cb_collect}]
	# Supply mill: storage → feed_mill (deliver one unit of the required input)
	if job_type == "supply_mill":
		var res: String = job.get("res", "Wheat")
		var src_cell: Vector2i = _find_building_with_local_stock(gm, res, origin_cell)
		if src_cell == Vector2i(-1, -1):
			gm.release_field_job(captured_cell)
			return []
		var src_pos: Vector3 = gm.cell_to_world(src_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		var captured_src := src_cell
		var captured_res := res
		var cb_take_res := func():
			var src_bld = gm.get_building_node_at(captured_src) as Building
			if src_bld != null and is_instance_valid(src_bld) and src_bld.take_from_local_stock(captured_res, 1):
				building_ref._rancher_carry[captured_res] = 1
			if building_ref._worker != null and is_instance_valid(building_ref._worker):
				building_ref._worker.set_carrying(true)
		var cb_deliver_res := func():
			var mill_bld = gm.get_building_node_at(captured_cell) as Building
			if mill_bld != null and is_instance_valid(mill_bld):
				var amt: int = building_ref._rancher_carry.get(captured_res, 0)
				if amt > 0:
					mill_bld._input_stock[captured_res] = mill_bld._input_stock.get(captured_res, 0) + amt
					building_ref._rancher_carry.erase(captured_res)
			gm.release_field_job(captured_cell)
			if building_ref._worker != null and is_instance_valid(building_ref._worker):
				building_ref._worker.set_carrying(false)
		return [
			{"pos": src_pos,   "pause": 0.6, "on_arrive": cb_take_res},
			{"pos": barn_pos,  "pause": 0.6, "on_arrive": cb_deliver_res},
		]
	# Feed delivery: silo → barn
	var feed_src: Vector2i = _find_building_with_local_stock(gm, "Feed", origin_cell)
	if feed_src == Vector2i(-1, -1):
		gm.release_field_job(captured_cell)
		return []
	var feed_pos: Vector3 = gm.cell_to_world(feed_src) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var captured_feed_src := feed_src
	var cb_take_feed := func():
		var src_bld = gm.get_building_node_at(captured_feed_src) as Building
		if src_bld != null and is_instance_valid(src_bld) and src_bld.take_from_local_stock("Feed", 1):
			building_ref._rancher_carry["Feed"] = 1
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(true)
	var cb_deliver_feed := func():
		var barn_bld = gm.get_building_node_at(captured_cell) as Building
		if barn_bld != null and is_instance_valid(barn_bld):
			var feed_amt: int = building_ref._rancher_carry.get("Feed", 0)
			if feed_amt > 0:
				barn_bld._input_stock["Feed"] = barn_bld._input_stock.get("Feed", 0) + feed_amt
				building_ref._rancher_carry.erase("Feed")
		gm.release_field_job(captured_cell)
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(false)
	return [
		{"pos": feed_pos, "pause": 0.6, "on_arrive": cb_take_feed},
		{"pos": barn_pos, "pause": 0.6, "on_arrive": cb_deliver_feed}
	]

func _rancher_deliver_output() -> Array:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		_rancher_carry.clear()
		return []
	var worker_cell: Vector2i = gm.world_to_cell((_worker.position if (_worker != null and is_instance_valid(_worker)) else position))
	var building_ref := self
	var cb_discard := func():
		building_ref._rancher_carry.clear()
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(false)
	# Try silo first, fall back to warehouse
	var sto_cell: Vector2i = _find_nearest_silo(gm, worker_cell)
	var sto_bld: Building = null
	if sto_cell != Vector2i(-1, -1):
		var bld := gm.get_building_node_at(sto_cell) as Building
		if bld != null and is_instance_valid(bld) and bld.data != null \
				and bld.get_local_stock_total() < bld.data.storage_bonus:
			sto_bld = bld
	if sto_bld == null:
		var wh_cell: Vector2i = _find_nearest_warehouse(gm, worker_cell)
		if wh_cell != Vector2i(-1, -1):
			var bld := gm.get_building_node_at(wh_cell) as Building
			if bld != null and is_instance_valid(bld):
				sto_bld = bld
				sto_cell = wh_cell
	if sto_bld != null:
		var sto_pos: Vector3 = gm.cell_to_world(sto_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		var cap_sto := sto_bld
		var cb_deposit := func():
			if is_instance_valid(cap_sto):
				for res in building_ref._rancher_carry.keys().duplicate():
					cap_sto.receive_resource(res, building_ref._rancher_carry.get(res, 0))
			building_ref._rancher_carry.clear()
			if building_ref._worker != null and is_instance_valid(building_ref._worker):
				building_ref._worker.set_carrying(false)
		return [{"pos": sto_pos, "pause": 0.5, "on_arrive": cb_deposit}]
	var road_cell: Vector2i = gm.get_nearest_road_cell(worker_cell)
	if road_cell != Vector2i(-1, -1):
		var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		return [{"pos": road_pos, "pause": 0.3, "on_arrive": cb_discard}]
	cb_discard.call()
	return []

# ===== Engineer (engineer_house) — collects output from INDUSTRIAL buildings =====

func _spawn_engineer() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), position, 0.0, "engineer_house",
			"res://assets/mini-characters/Models/GLB format/character-male-c.glb")
	_worker.set_cycle_callback(_engineer_find_job)
	_worker.arrived_home.connect(func():
		if _worker == null or not is_instance_valid(_worker): return
		_engineer_scan_buildings()
		_worker.paused = _engineer_job_queue.is_empty() and _engineer_carry.is_empty()
	)
	var scan_timer := Timer.new()
	scan_timer.wait_time = 3.0
	scan_timer.autostart = true
	scan_timer.timeout.connect(_engineer_scan_buildings)
	add_child(scan_timer)
	_engineer_scan_buildings()
	var wps: Array = _engineer_find_job()
	if wps.size() > 0:
		_worker.redirect(wps)

func _engineer_scan_buildings() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	var queued_cells: Array = []
	for j in _engineer_job_queue:
		queued_cells.append(j["cell"])
	var seen: Dictionary = {}
	for map_cell in gm._buildings:
		var bld = gm._buildings[map_cell]
		if not is_instance_valid(bld): continue
		var uid: int = bld.get_instance_id()
		if seen.has(uid): continue
		seen[uid] = true
		if not (bld is Building): continue
		var target := bld as Building
		if target.data == null: continue
		if target.data.worker_domain != BuildingData.WorkerDomain.INDUSTRIAL: continue
		var target_cell: Vector2i = target.origin_cell
		if queued_cells.has(target_cell): continue
		if gm.is_field_job_claimed(target_cell): continue
		if target.get_local_stock_total() > 0:
			_engineer_job_queue.append({"cell": target_cell})
			queued_cells.append(target_cell)
	if _worker != null and is_instance_valid(_worker) and _worker.paused:
		if not _engineer_job_queue.is_empty() or not _engineer_carry.is_empty():
			var wps: Array = _engineer_find_job()
			if not wps.is_empty():
				_worker.paused = false
				_worker.redirect(wps)

func _engineer_find_job() -> Array:
	if not _engineer_carry.is_empty():
		return _engineer_deliver_output()
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return []
	while not _engineer_job_queue.is_empty():
		var job: Dictionary = _engineer_job_queue.pop_front()
		var cell: Vector2i = job["cell"]
		if gm.is_field_job_claimed(cell): continue
		var target_bld := gm.get_building_node_at(cell) as Building
		if target_bld == null or not is_instance_valid(target_bld): continue
		if target_bld.get_local_stock_total() <= 0: continue
		if not gm.claim_field_job(cell, "collect"): continue
		return _engineer_build_collect_waypoints(cell, gm)
	return []

func _engineer_build_collect_waypoints(cell: Vector2i, gm) -> Array:
	var target_pos: Vector3 = gm.cell_to_world(cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var captured_cell := cell
	var building_ref := self
	var cb_collect := func():
		var target_bld = gm.get_building_node_at(captured_cell) as Building
		if target_bld != null and is_instance_valid(target_bld):
			for res in target_bld._local_stock.keys().duplicate():
				var amt: int = target_bld._local_stock.get(res, 0)
				if amt > 0 and target_bld.take_from_local_stock(res, amt):
					building_ref._engineer_carry[res] = building_ref._engineer_carry.get(res, 0) + amt
		gm.release_field_job(captured_cell)
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(not building_ref._engineer_carry.is_empty())
	return [{"pos": target_pos, "pause": 0.8, "on_arrive": cb_collect}]

func _find_nearest_fuel_tank(gm, near_cell: Vector2i) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	for cell in gm.get_all_building_cells("fuel_tank"):
		var d: float = (Vector2(cell) - Vector2(near_cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best_cell = cell
	return best_cell

func _engineer_deliver_output() -> Array:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		_engineer_carry.clear()
		return []
	var worker_cell: Vector2i = gm.world_to_cell((_worker.position if (_worker != null and is_instance_valid(_worker)) else position))
	# Prefer fuel_tank, fall back to warehouse
	var sto_cell: Vector2i = _find_nearest_fuel_tank(gm, worker_cell)
	if sto_cell == Vector2i(-1, -1):
		sto_cell = _find_nearest_warehouse(gm, worker_cell)
	var building_ref := self
	var cb_discard := func():
		building_ref._engineer_carry.clear()
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(false)
	if sto_cell != Vector2i(-1, -1):
		var sto_bld := gm.get_building_node_at(sto_cell) as Building
		if sto_bld != null and is_instance_valid(sto_bld):
			var sto_pos: Vector3 = gm.cell_to_world(sto_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			var cap_sto := sto_bld
			var cb_deposit := func():
				if is_instance_valid(cap_sto):
					for res in building_ref._engineer_carry.keys().duplicate():
						cap_sto.receive_resource(res, building_ref._engineer_carry.get(res, 0))
				building_ref._engineer_carry.clear()
				if building_ref._worker != null and is_instance_valid(building_ref._worker):
					building_ref._worker.set_carrying(false)
			return [{"pos": sto_pos, "pause": 0.5, "on_arrive": cb_deposit}]
	var road_cell: Vector2i = gm.get_nearest_road_cell(worker_cell)
	if road_cell != Vector2i(-1, -1):
		var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		return [{"pos": road_pos, "pause": 0.3, "on_arrive": cb_discard}]
	cb_discard.call()
	return []

# Farmer delivers to silo; if full/missing → drop at road
func _farmer_deliver() -> Array:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		_farmer_carrying = ""
		return []

	var captured_produce: String = _farmer_carrying
	var farmer_cell: Vector2i = gm.world_to_cell((_worker.position if (_worker != null and is_instance_valid(_worker)) else position))

	var _cb_discard := func():
		_farmer_carrying = ""
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)

	var sto_cell: Vector2i = _find_nearest_silo(gm, farmer_cell)
	if sto_cell != Vector2i(-1, -1):
		var sto_bld: Building = gm.get_building_node_at(sto_cell) as Building
		# Check if silo still has capacity
		var silo_full: bool = sto_bld != null and is_instance_valid(sto_bld) and sto_bld.data != null \
			and sto_bld.get_local_stock_total() >= sto_bld.data.storage_bonus
		if not silo_full:
			var sto_pos: Vector3 = gm.cell_to_world(sto_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			var cap_sto: Building = sto_bld
			var _cb_sto := func():
				if is_instance_valid(cap_sto):
					cap_sto.receive_resource(captured_produce, 1)
				_farmer_carrying = ""
				if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
			return [{"pos": sto_pos, "pause": 0.8, "on_arrive": _cb_sto}]

	# Silo full or missing → drop at nearest road
	var road_cell: Vector2i = gm.get_nearest_road_cell(farmer_cell)
	if road_cell != Vector2i(-1, -1):
		var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		return [{"pos": road_pos, "pause": 0.3, "on_arrive": _cb_discard}]
	_cb_discard.call()
	return []

func _spawn_woodcutter() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), position, 0.0, "woodcutter_house",
			"res://assets/mini-characters/Models/GLB format/character-male-b.glb")
	_worker.set_cycle_callback(_woodcutter_cycle)
	_worker.arrived_home.connect(func():
		if _worker == null or not is_instance_valid(_worker): return
		var wps: Array = _woodcutter_cycle()
		if not wps.is_empty(): _worker.set_waypoints(wps)
	)
	var wc_scan := Timer.new()
	wc_scan.wait_time = 1.0
	wc_scan.autostart = true
	wc_scan.timeout.connect(_woodcutter_check_abort)
	add_child(wc_scan)
	var wps: Array = _woodcutter_cycle()
	if wps.size() > 0:
		_worker.set_waypoints(wps)

func _spawn_builder() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), position, 0.0, "builder_house",
			"res://assets/mini-characters/Models/GLB format/character-male-d.glb")
	_worker.set_cycle_callback(_builder_cycle)
	_worker.arrived_home.connect(func():
		if _worker == null or not is_instance_valid(_worker): return
		var wps: Array = _builder_cycle()
		if not wps.is_empty(): _worker.set_waypoints(wps)
	)
	var wps: Array = _builder_cycle()
	if wps.size() > 0:
		_worker.set_waypoints(wps)

func _builder_cycle() -> Array:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return []
	var bq = get_node_or_null("/root/BuildQueue")
	if bq == null:
		return []
	for job_bld in bq.get_active_buildings():
		if not is_instance_valid(job_bld):
			continue
		if not job_bld.has_pending_construction_work():
			continue
		var mat: Dictionary = job_bld.take_next_construction_material(gm)
		if mat.is_empty():
			continue
		var res: String = mat["res"]
		var site_pos: Vector3 = job_bld.position
		var captured_job := job_bld as Building
		var captured_res: String = res
		var waypoints: Array = []
		var _cb_deliver := func():
			if is_instance_valid(captured_job): captured_job.deliver_construction_material(captured_res)
			if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
		if mat.get("needs_source_trip", false):
			var _cb_source := func():
				if _worker != null and is_instance_valid(_worker): _worker.set_carrying(true)
			waypoints.append({"pos": mat["source_pos"], "pause": 0.5, "on_arrive": _cb_source})
		else:
			if _worker != null and is_instance_valid(_worker): _worker.set_carrying(true)
		waypoints.append({"pos": site_pos, "pause": 1.5, "on_arrive": _cb_deliver})
		return waypoints
	return []

# =============================================================================
# WOODCUTTER SYSTEM — LOCKED, DO NOT MODIFY
# - Iterates all lumberyards, picks the nearest one with space (road is the last resort)
# - No two woodcutters target the same tree (static _claimed_forest_cells)
# - Scans every 1 second → redirects immediately if the target lumberyard became full
# - Drops at road only when every lumberyard is truly full
# =============================================================================
func _woodcutter_cycle() -> Array:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return []

	# Delivery phase: scan all lumberyards, pick nearest with space; road is last resort
	if _woodcutter_has_wood:
		var wc_pos: Vector3 = _worker.position if (_worker != null and is_instance_valid(_worker)) else position
		var wc_cell: Vector2i = gm.world_to_cell(wc_pos)
		var _cb_drop := func():
			_woodcutter_has_wood = false
			if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
		var best_ly_cell := Vector2i(-1, -1)
		var best_ly_dist: float = 1e9
		var best_ly_bld: Building = null
		for ly_c: Vector2i in gm.get_all_building_cells("lumberyard"):
			var bld: Building = gm.get_building_node_at(ly_c) as Building
			if bld == null or not is_instance_valid(bld) or bld.data == null:
				continue
			if bld.get_local_stock_total() >= bld.data.max_stock:
				continue
			var d: float = (Vector2(ly_c) - Vector2(wc_cell)).length_squared()
			if d < best_ly_dist:
				best_ly_dist = d
				best_ly_cell = ly_c
				best_ly_bld = bld
		if best_ly_cell != Vector2i(-1, -1):
			var ly_pos: Vector3 = gm.cell_to_world(best_ly_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			var captured_ly: Building = best_ly_bld
			var _cb_ly := func():
				if not _woodcutter_has_wood: return
				# If deposit succeeds, clear state; if full, let cycle find another lumberyard
				if is_instance_valid(captured_ly) and captured_ly.receive_resource("Wood", 1):
					_woodcutter_has_wood = false
					if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
			return [{"pos": ly_pos, "pause": 0.5, "on_arrive": _cb_ly}]
		# All lumberyards full or none exist → drop at nearest road (last resort)
		var road_cell: Vector2i = gm.get_nearest_road_cell(wc_cell)
		if road_cell != Vector2i(-1, -1):
			var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			return [{"pos": road_pos, "pause": 0.3, "on_arrive": _cb_drop}]
		_cb_drop.call()  # no road at all → discard immediately

	# Cutting phase: find unclaimed forest cell nearest to the worker
	var worker_pos: Vector3 = _worker.position if (_worker != null and is_instance_valid(_worker)) else position
	var worker_cell: Vector2i = gm.world_to_cell(worker_pos)
	var forest_cell: Vector2i = gm.get_nearest_terrain_cell_excluding(worker_cell, _GM_FOREST, _claimed_forest_cells)
	if forest_cell == Vector2i(-1, -1):
		return []  # no forest → stay home

	# Claim the tree before walking there
	_woodcutter_target_tree = forest_cell
	_claimed_forest_cells[forest_cell] = true

	# Sort lumberyards by distance from the cut point (not from home) to avoid backtracking
	var all_ly: Array = gm.get_all_building_cells("lumberyard")
	all_ly.sort_custom(func(a, b):
		var da := (Vector2(a) - Vector2(forest_cell)).length_squared()
		var db := (Vector2(b) - Vector2(forest_cell)).length_squared()
		return da < db
	)
	_woodcutter_delivery_queue = all_ly

	var forest_pos: Vector3 = gm.cell_to_world(forest_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var fc := forest_cell
	var _cb_cut := func():
		# Always release the claim regardless of cut success
		_claimed_forest_cells.erase(fc)
		_woodcutter_target_tree = Vector2i(-1, -1)
		var cut: bool = is_instance_valid(gm) and gm.harvest_tree(fc)
		if not cut:
			_woodcutter_delivery_queue.clear()
			return
		_woodcutter_has_wood = true
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(true)
	return [{"pos": forest_pos, "pause": 2.0, "on_arrive": _cb_cut}]

func _woodcutter_check_abort() -> void:
	if not _woodcutter_has_wood: return
	if _worker == null or not is_instance_valid(_worker): return
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return
	var wc_cell: Vector2i = gm.world_to_cell(_worker.position)
	# Find the nearest lumberyard with space from current position
	var best_ly_cell := Vector2i(-1, -1)
	var best_ly_dist: float = 1e9
	var best_ly_bld: Building = null
	for ly_c: Vector2i in gm.get_all_building_cells("lumberyard"):
		var bld: Building = gm.get_building_node_at(ly_c) as Building
		if bld == null or not is_instance_valid(bld) or bld.data == null:
			continue
		if bld.get_local_stock_total() >= bld.data.max_stock:
			continue
		var d: float = (Vector2(ly_c) - Vector2(wc_cell)).length_squared()
		if d < best_ly_dist:
			best_ly_dist = d
			best_ly_cell = ly_c
			best_ly_bld = bld
	if best_ly_cell != Vector2i(-1, -1):
		# There is a free lumberyard → redirect immediately (handles case where target lumberyard became full)
		var ly_pos: Vector3 = gm.cell_to_world(best_ly_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		var captured_ly: Building = best_ly_bld
		var _cb_ly := func():
			if not _woodcutter_has_wood: return
			if is_instance_valid(captured_ly) and captured_ly.receive_resource("Wood", 1):
				_woodcutter_has_wood = false
				if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
		_worker.redirect([{"pos": ly_pos, "pause": 0.5, "on_arrive": _cb_ly}])
		return
	# All lumberyards full or none → drop at road (last resort)
	_woodcutter_has_wood = false  # prevent repeated abort next second
	var road_cell: Vector2i = gm.get_nearest_road_cell(wc_cell)
	var _cb_drop := func():
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
	if road_cell != Vector2i(-1, -1):
		var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
		_worker.redirect([{"pos": road_pos, "pause": 0.3, "on_arrive": _cb_drop}])
	else:
		_cb_drop.call()
		_worker.go_home()

func _get_indicator_color() -> Color:
	if not _has_worker:
		return Color(0.9, 0.15, 0.1)
	return Color(1.0, 0.85, 0.1)

# ---- Visual ----

func _create_visual() -> void:
	var label_y := 2.5

	if data.model_path != "" and ResourceLoader.exists(data.model_path):
		var scene := load(data.model_path) as PackedScene
		if scene:
			var inst := scene.instantiate()
			inst.scale = Vector3.ONE * data.model_scale
			add_child(inst)
			if data.id == "feed_mill":
				_feed_in_trough = inst.find_child("FeedInTrough", true, false) as MeshInstance3D
			_mat = null
			_roof_mat = null
			label_y = data.model_scale * 1.8
	elif data.id == "silo":
		label_y = _create_silo_mesh()
	elif data.id == "well":
		label_y = _create_well_mesh()
	elif data.id == "oil_pump":
		label_y = _create_oil_pump_mesh()
	elif data.category == BuildingData.Category.HOUSING:
		label_y = _create_house_mesh()
	else:
		_mesh_inst = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			data.size.x * _GM_CELL * 0.62,
			1.1,
			data.size.y * _GM_CELL * 0.62
		)
		_mesh_inst.mesh = box
		_mesh_inst.position = Vector3(0, 0.55, 0)
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = data.color
		_mesh_inst.material_override = _mat
		add_child(_mesh_inst)
		if data.id in ["animal_barn", "chicken_coop", "sheep_pen"]:
			_create_ranch_animals()

	_label_y = label_y

	_status_label = Label3D.new()
	_status_label.name = "StatusLabel"
	_status_label.text = data.display_name
	_status_label.font_size = 42
	_status_label.position = Vector3(0, label_y, 0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.modulate = Color.WHITE
	_status_label.outline_modulate = Color.BLACK
	_status_label.outline_size = 12
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_create_indicator(label_y)
	_create_highlight()
	_create_info_label(label_y)

func _create_house_mesh() -> float:
	var cell_sz: float = data.size.x * _GM_CELL
	var body_w: float = cell_sz * 0.60   # 60% of cell size = 1.8 units

	# Walls
	_mesh_inst = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(body_w, 1.0, body_w)
	_mesh_inst.mesh = box
	_mesh_inst.position = Vector3(0, 0.50, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = data.color
	_mesh_inst.material_override = _mat
	add_child(_mesh_inst)

	# Roof
	var roof_mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(body_w + 0.18, 0.62, body_w + 0.18)
	prism.left_to_right = 0.5
	roof_mi.mesh = prism
	roof_mi.position = Vector3(0, 1.0 + 0.31, 0)
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = _get_roof_color()
	roof_mi.material_override = _roof_mat
	add_child(roof_mi)

	return 2.1  # label_y

func _create_well_mesh() -> float:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.76, 0.73, 0.65)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.52, 0.32, 0.12)

	# Stone well rim
	var rim := MeshInstance3D.new()
	var rim_cyl := CylinderMesh.new()
	rim_cyl.top_radius = 0.58
	rim_cyl.bottom_radius = 0.62
	rim_cyl.height = 0.40
	rim.mesh = rim_cyl
	rim.material_override = stone_mat
	rim.position = Vector3(0, 0.20, 0)
	add_child(rim)

	# Inner water surface
	var water_mi := MeshInstance3D.new()
	var water_cyl := CylinderMesh.new()
	water_cyl.top_radius = 0.46
	water_cyl.bottom_radius = 0.46
	water_cyl.height = 0.06
	water_mi.mesh = water_cyl
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.18, 0.50, 0.82)
	water_mat.roughness = 0.1
	water_mat.metallic_specular = 0.4
	water_mi.material_override = water_mat
	water_mi.position = Vector3(0, 0.08, 0)
	add_child(water_mi)

	# Left post
	_add_box_child(Vector3(0.10, 0.95, 0.10), Vector3(-0.40, 0.40 + 0.475, 0), wood_mat)
	# Right post
	_add_box_child(Vector3(0.10, 0.95, 0.10), Vector3( 0.40, 0.40 + 0.475, 0), wood_mat)
	# Cross beam
	_add_box_child(Vector3(0.92, 0.10, 0.10), Vector3(0, 0.40 + 0.95, 0), wood_mat)

	# Mini roof
	var roof_mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.05, 0.44, 0.48)
	prism.left_to_right = 0.5
	roof_mi.mesh = prism
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.58, 0.28, 0.10)
	roof_mi.material_override = roof_mat
	roof_mi.position = Vector3(0, 0.40 + 0.95 + 0.22, 0)
	add_child(roof_mi)

	_mat = stone_mat  # use stone_mat as primary mat for construction dimming
	return 2.1

func _create_oil_pump_mesh() -> float:
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.22, 0.22, 0.26)

	var rust_mat := StandardMaterial3D.new()
	rust_mat.albedo_color = Color(0.50, 0.22, 0.08)

	# Base platform
	_add_box_child(Vector3(1.10, 0.18, 1.10), Vector3(0, 0.09, 0), steel_mat)

	# Vertical tower
	_add_box_child(Vector3(0.18, 1.60, 0.18), Vector3(0, 0.18 + 0.80, 0), steel_mat)

	# Cross beam (pump arm)
	_add_box_child(Vector3(1.00, 0.12, 0.12), Vector3(0, 0.18 + 1.60 + 0.06, 0), rust_mat)

	# Counterweight (one end of arm)
	_add_box_child(Vector3(0.22, 0.28, 0.18), Vector3(-0.40, 0.18 + 1.60 + 0.20, 0), steel_mat)

	# Drill rod going down
	_add_box_child(Vector3(0.08, 0.80, 0.08), Vector3(0.40, 0.18 + 0.80 + 0.06 + 0.20, 0), rust_mat)

	# Barrel on ground
	_add_box_child(Vector3(0.32, 0.40, 0.32), Vector3(0.55, 0.20, 0.40), rust_mat)

	_mat = steel_mat
	return 2.2

func _create_silo_mesh() -> float:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = data.color  # golden yellow (silo)

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.55, 0.32, 0.10)  # terracotta roof

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.70, 0.65, 0.55)  # concrete base

	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = data.color.darkened(0.25)  # darker decorative ring bands

	# Foundation ring
	var base_mi := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 0.58
	base_cyl.bottom_radius = 0.60
	base_cyl.height = 0.18
	base_mi.mesh = base_cyl
	base_mi.material_override = base_mat
	base_mi.position = Vector3(0, 0.09, 0)
	add_child(base_mi)

	# Main tall cylinder body
	var body_mi := MeshInstance3D.new()
	var body_cyl := CylinderMesh.new()
	body_cyl.top_radius = 0.50
	body_cyl.bottom_radius = 0.50
	body_cyl.height = 2.6
	body_cyl.radial_segments = 18
	body_mi.mesh = body_cyl
	body_mi.material_override = body_mat
	body_mi.position = Vector3(0, 0.18 + 1.3, 0)
	add_child(body_mi)

	# Decorative band rings (3 rings along the body)
	for band_i in range(3):
		var band_mi := MeshInstance3D.new()
		var band_cyl := CylinderMesh.new()
		band_cyl.top_radius = 0.52
		band_cyl.bottom_radius = 0.52
		band_cyl.height = 0.06
		band_cyl.radial_segments = 18
		band_mi.mesh = band_cyl
		band_mi.material_override = band_mat
		band_mi.position = Vector3(0, 0.18 + 0.5 + band_i * 0.85, 0)
		add_child(band_mi)

	# Conical roof (cone: top_radius = 0)
	var cone_mi := MeshInstance3D.new()
	var cone_cyl := CylinderMesh.new()
	cone_cyl.top_radius = 0.0
	cone_cyl.bottom_radius = 0.56
	cone_cyl.height = 0.80
	cone_cyl.radial_segments = 18
	cone_mi.mesh = cone_cyl
	cone_mi.material_override = roof_mat
	cone_mi.position = Vector3(0, 0.18 + 2.6 + 0.40, 0)
	add_child(cone_mi)

	_mat = body_mat
	_roof_mat = roof_mat
	return 3.6

func _create_ranch_animals() -> void:
	match data.id:
		"animal_barn":
			var body_mat := StandardMaterial3D.new()
			body_mat.albedo_color = Color(0.48, 0.30, 0.14)
			var head_mat := StandardMaterial3D.new()
			head_mat.albedo_color = Color(0.36, 0.22, 0.10)
			_add_box_child(Vector3(0.50, 0.32, 0.28), Vector3(-0.52, 0.16, 0.72), body_mat)
			_add_box_child(Vector3(0.19, 0.19, 0.16), Vector3(-0.52, 0.39, 0.88), head_mat)
			_add_box_child(Vector3(0.50, 0.32, 0.28), Vector3( 0.50, 0.16, 0.72), body_mat)
			_add_box_child(Vector3(0.19, 0.19, 0.16), Vector3( 0.50, 0.39, 0.88), head_mat)
		"chicken_coop":
			var chk_mat := StandardMaterial3D.new()
			chk_mat.albedo_color = Color(0.90, 0.78, 0.18)
			var chk_mat2 := StandardMaterial3D.new()
			chk_mat2.albedo_color = Color(0.88, 0.50, 0.08)
			_add_box_child(Vector3(0.15, 0.13, 0.13), Vector3(-0.48, 0.065, 0.65), chk_mat)
			_add_box_child(Vector3(0.15, 0.13, 0.13), Vector3( 0.08, 0.065, 0.72), chk_mat2)
			_add_box_child(Vector3(0.15, 0.13, 0.13), Vector3( 0.48, 0.065, 0.62), chk_mat)
		"sheep_pen":
			var wool_mat := StandardMaterial3D.new()
			wool_mat.albedo_color = Color(0.90, 0.88, 0.84)
			var face_mat := StandardMaterial3D.new()
			face_mat.albedo_color = Color(0.50, 0.46, 0.44)
			_add_box_child(Vector3(0.46, 0.36, 0.36), Vector3(-0.50, 0.18, 0.70), wool_mat)
			_add_box_child(Vector3(0.19, 0.19, 0.15), Vector3(-0.50, 0.42, 0.88), face_mat)
			_add_box_child(Vector3(0.46, 0.36, 0.36), Vector3( 0.46, 0.18, 0.70), wool_mat)
			_add_box_child(Vector3(0.19, 0.19, 0.15), Vector3( 0.46, 0.42, 0.88), face_mat)

func _add_box_child(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _spawn_livestock_animals() -> void:
	var animal_type: String
	var count: int
	var offsets: Array

	match data.id:
		"animal_barn":
			animal_type = "cow"
			offsets = [Vector3(-0.50, 0, 0.30), Vector3(0.48, 0, -0.25)]
		"chicken_coop":
			animal_type = "chicken"
			offsets = [Vector3(-0.40, 0, 0.20), Vector3(0.10, 0, 0.45), Vector3(0.42, 0, -0.10)]
		"sheep_pen":
			animal_type = "sheep"
			offsets = [Vector3(-0.45, 0, 0.25), Vector3(0.42, 0, -0.20)]
		"pig_pen":
			animal_type = "pig"
			offsets = [Vector3(-0.38, 0, 0.20), Vector3(0.36, 0, -0.18)]
		_:
			return

	for offset in offsets:
		var animal := Animal.new()
		add_child(animal)
		animal.setup(animal_type, offset)

# ---- Production ----

func _update_trough_visual() -> void:
	if _feed_in_trough == null or not is_instance_valid(_feed_in_trough):
		return
	_feed_in_trough.visible = not _pending_output.is_empty()

func _setup_timer() -> void:
	_prod_timer = Timer.new()
	_prod_timer.wait_time = data.production_time
	_prod_timer.autostart = true
	_prod_timer.timeout.connect(_on_produce)
	add_child(_prod_timer)

func _get_effective_production_time() -> float:
	# Shadow/pollution slow-down applies only to crops (grow_time > 0)
	if data == null or data.grow_time <= 0.0:
		return data.production_time
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return data.production_time
	return data.production_time * float(gm.get_production_modifier(origin_cell))

func _on_produce() -> void:
	# Recalculate interval for next cycle based on current shadow/pollution
	if _prod_timer != null and is_instance_valid(_prod_timer):
		_prod_timer.wait_time = _get_effective_production_time()
	if _resource_manager == null or data == null or not _is_active:
		return
	if not _has_worker:
		_update_indicator(Color(0.9, 0.15, 0.1))
		return
	# Battery consumption check (replaces spatial electricity system)
	if data.electricity_needed > 0:
		if not _resource_manager.has_resources({"Battery": data.electricity_needed}):
			_update_indicator(Color(0.9, 0.75, 0.0))  # yellow = waiting for battery
			return
		_resource_manager.remove_resource("Battery", data.electricity_needed)
	# Check if still adjacent to a road (only for buildings that require road access)
	if data.grow_time <= 0.0 and data.id not in ["well", "small_pond", "large_pond", "wind_pump", "water_facility", "builder_house", "farm_house", "woodcutter_house", "ranch_house", "feed_mill", "solar_panel", "house", "engineer_house"]:
		var gm_road = get_tree().get_first_node_in_group("grid_manager")
		if gm_road != null and not gm_road.is_area_adjacent_to_road(origin_cell, data.size):
			_update_indicator(Color(0.9, 0.15, 0.1))
			return

	# Lumberyard must actually cut a tree to get wood
	if data.id == "lumberyard":
		# If local stock is full → wait for batch deposit
		if data.max_stock > 0 and get_local_stock_total() >= data.max_stock:
			_update_indicator(Color(0.85, 0.10, 0.10))
			return
		# If still carrying pending wood → don't cut more
		if not _pending_output.is_empty():
			_update_indicator(Color(1.0, 0.65, 0.0))
			return
		var gm = get_tree().get_first_node_in_group("grid_manager")
		if gm == null:
			return
		var forest_cell = gm.get_nearest_terrain_cell(origin_cell, _GM_FOREST)
		if forest_cell == Vector2i(-1, -1):
			_update_indicator(Color(1.0, 0.5, 0.0))
			return
		if not gm.harvest_tree(forest_cell):
			_update_indicator(Color(1.0, 0.5, 0.0))
			return
		# Update worker target if cell changed
		if _worker != null and is_instance_valid(_worker) and forest_cell != _lumberyard_target:
			_lumberyard_target = forest_cell
			var new_pos = gm.cell_to_world(forest_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			_worker.update_work_target(new_pos)

	var active_produces: Dictionary = data.produces
	var active_consumes: Dictionary = data.consumes
	if data.recipes.size() > 0:
		var recipe: Dictionary = data.recipes[_current_recipe % data.recipes.size()]
		active_produces = recipe.get("produces", {})
		active_consumes = recipe.get("consumes", {})

	# Reduce required Water if near a pond (spatial bonus)
	if active_consumes.has("Water"):
		var gm_node = get_tree().get_first_node_in_group("grid_manager")
		if gm_node != null:
			var bonus: int = gm_node.get_water_bonus(origin_cell)
			if bonus > 0:
				active_consumes = active_consumes.duplicate()
				var reduced: int = max(0, active_consumes["Water"] - bonus)
				if reduced == 0:
					active_consumes.erase("Water")
				else:
					active_consumes["Water"] = reduced

	# If there is pending output not yet deposited → wait, do not produce more
	if not _pending_output.is_empty():
		_update_indicator(Color(1.0, 0.65, 0.0))  # orange = waiting for storage
		return

	# If storage is full for this output → do not produce (do not consume input)
	# Passive buildings (workers_needed=0) write to local_stock — skip global storage check
	if not active_produces.is_empty() and data.workers_needed > 0:
		var total_out: int = 0
		for v in active_produces.values():
			total_out += v
		if not _resource_manager.has_storage_for(total_out):
			_update_indicator(Color(0.85, 0.10, 0.10))  # red = storage full
			return

	if is_factory_building():
		# All inputs (including Water) must be in _input_stock
		for res in active_consumes:
			if _input_stock.get(res, 0) < active_consumes.get(res, 0):
				_set_glow(false)
				_update_indicator(Color(1.0, 0.85, 0.1))
				return
		for res in active_consumes:
			_input_stock[res] = max(0, _input_stock.get(res, 0) - active_consumes.get(res, 0))
	else:
		# Non-factory buildings: check Gasoline if needed (currency resource)
		var gasoline_need: int = active_consumes.get("Gasoline", 0)
		if gasoline_need > 0 and not _resource_manager.has_resources({"Gasoline": gasoline_need}):
			_set_glow(false)
			_update_indicator(Color(1.0, 0.85, 0.1))
			return
		if gasoline_need > 0:
			_resource_manager.remove_resource("Gasoline", gasoline_need)

	_set_glow(true)
	_flash()
	if active_produces.is_empty():
		_update_indicator(Color(0.1, 0.9, 0.2))
	elif data.workers_needed <= 0:
		# Pause after producing until worker collects output (Livestock and Industrial)
		var _is_pause_domain := data.worker_domain == BuildingData.WorkerDomain.LIVESTOCK or data.worker_domain == BuildingData.WorkerDomain.INDUSTRIAL
		if _is_pause_domain and get_local_stock_total() > 0:
			if _prod_timer != null and is_instance_valid(_prod_timer):
				_prod_timer.stop()
			_update_indicator(Color(1.0, 0.65, 0.0))  # orange = waiting for collection
			return
		# Passive: global-currency outputs (Battery, etc.) go to resource pool; physical go to local_stock
		var phys_out: Dictionary = {}
		var curr_out: Dictionary = {}
		for res in active_produces:
			if _resource_manager._amounts.has(res):
				curr_out[res] = active_produces[res]
			else:
				phys_out[res] = active_produces[res]
		if not phys_out.is_empty():
			var total_out: int = 0
			for v in phys_out.values(): total_out += v
			var cap: int = data.max_stock if data.max_stock > 0 else 20
			if get_local_stock_total() + total_out > cap:
				_update_indicator(Color(0.85, 0.10, 0.10))  # full — stop producing
				return
		for res in curr_out:
			_resource_manager.add_resource(res, curr_out[res])
		for res in phys_out:
			_local_stock[res] = _local_stock.get(res, 0) + phys_out[res]
		if not phys_out.is_empty():
			_last_countdown_secs = -1
			_update_stock_label()
		# Pause after producing physical output — only restart when collector takes everything
		if not phys_out.is_empty() and _is_pause_domain:
			if _prod_timer != null and is_instance_valid(_prod_timer):
				_prod_timer.stop()
			_update_indicator(Color(1.0, 0.65, 0.0))  # orange = waiting for collection
		else:
			_update_indicator(Color(0.1, 0.9, 0.2))
	else:
		# Worker carries output; enqueue as pending, worker will deliver to storage building
		for res in active_produces:
			_pending_output[res] = _pending_output.get(res, 0) + active_produces[res]
		if _worker != null and is_instance_valid(_worker):
			_worker.set_carrying(true)
		_update_indicator(Color(0.1, 0.9, 0.2))
		_update_trough_visual()

func _do_truck_delivery() -> void:
	if not _pending_output.is_empty():
		_update_indicator(Color(1.0, 0.65, 0.0))
		return
	if not _resource_manager.has_resources({"Gasoline": 1}):
		_update_indicator(Color(1.0, 0.85, 0.1))
		return

	# Scan ALL buildings for sellable goods in their local_stock
	var gm = get_tree().get_first_node_in_group("grid_manager")
	var res_totals: Dictionary = {}
	if gm != null:
		var seen := {}
		for cell in gm._buildings.keys():
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld): continue
			var uid: int = bld.get_instance_id()
			if seen.has(uid): continue
			seen[uid] = true
			if not (bld is Building): continue
			for res in bld._local_stock:
				res_totals[res] = res_totals.get(res, 0) + bld._local_stock.get(res, 0)

	var sellable: Array = []
	for res in SALE_PRICE:
		var amt: int = res_totals.get(res, 0)
		if amt > 0:
			sellable.append({"res": res, "price": SALE_PRICE[res], "amt": amt})
	sellable.sort_custom(func(a, b): return a["price"] > b["price"])

	var remaining: int = TRUCK_CAPACITY
	var gold_earned: int = 0
	var loaded: Dictionary = {}
	for item in sellable:
		if remaining <= 0: break
		var take: int = min(item["amt"], remaining)
		loaded[item["res"]] = take
		gold_earned += take * item["price"]
		remaining -= take

	if gold_earned == 0:
		_update_indicator(Color(1.0, 0.85, 0.1))
		return

	# Deduct loaded goods from buildings' local_stocks
	if gm != null:
		var to_deduct: Dictionary = loaded.duplicate()
		var seen2 := {}
		for cell in gm._buildings.keys():
			if to_deduct.is_empty(): break
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld): continue
			var uid: int = bld.get_instance_id()
			if seen2.has(uid): continue
			seen2[uid] = true
			if not (bld is Building): continue
			for res in to_deduct.keys():
				var have: int = bld._local_stock.get(res, 0)
				if have <= 0: continue
				var take: int = min(to_deduct[res], have)
				bld._local_stock[res] -= take
				if bld._local_stock[res] <= 0: bld._local_stock.erase(res)
				to_deduct[res] -= take
				if to_deduct[res] <= 0: to_deduct.erase(res)

	_resource_manager.remove_resource("Gasoline", 1)
	_pending_output = {"Gold": gold_earned}
	_set_glow(true)
	_flash()
	_update_indicator(Color(0.55, 0.90, 0.20))

# Player-triggered truck dispatch from Garage popup — Gold added immediately.
func trigger_truck_delivery() -> bool:
	if _resource_manager == null or not _is_active:
		return false
	if _resource_manager.get_amount("Gasoline") < 1:
		return false
	var gm = get_tree().get_first_node_in_group("grid_manager")
	var res_totals: Dictionary = {}
	if gm != null:
		var seen := {}
		for cell in gm._buildings.keys():
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld): continue
			var uid: int = bld.get_instance_id()
			if seen.has(uid): continue
			seen[uid] = true
			if not (bld is Building): continue
			for res in bld._local_stock:
				res_totals[res] = res_totals.get(res, 0) + bld._local_stock.get(res, 0)
	var sellable: Array = []
	for res in SALE_PRICE:
		var amt: int = res_totals.get(res, 0)
		if amt > 0:
			sellable.append({"res": res, "price": SALE_PRICE[res], "amt": amt})
	sellable.sort_custom(func(a, b): return a["price"] > b["price"])
	var remaining: int = TRUCK_CAPACITY
	var gold_earned: int = 0
	var loaded: Dictionary = {}
	for item in sellable:
		if remaining <= 0: break
		var take: int = min(item["amt"], remaining)
		loaded[item["res"]] = take
		gold_earned += take * item["price"]
		remaining -= take
	if gold_earned == 0:
		return false
	if gm != null:
		var to_deduct: Dictionary = loaded.duplicate()
		var seen2 := {}
		for cell in gm._buildings.keys():
			if to_deduct.is_empty(): break
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld): continue
			var uid: int = bld.get_instance_id()
			if seen2.has(uid): continue
			seen2[uid] = true
			if not (bld is Building): continue
			for res in to_deduct.keys():
				var have: int = bld._local_stock.get(res, 0)
				if have <= 0: continue
				var take: int = min(to_deduct[res], have)
				bld._local_stock[res] -= take
				if bld._local_stock[res] <= 0: bld._local_stock.erase(res)
				to_deduct[res] -= take
				if to_deduct[res] <= 0: to_deduct.erase(res)
	_resource_manager.remove_resource("Gasoline", 1)
	_resource_manager.add_resource("Gold", gold_earned)
	_set_glow(true)
	_flash()
	_update_indicator(Color(0.55, 0.90, 0.20))
	_spawn_delivery_truck()
	return true

func _spawn_delivery_truck() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var truck_node := Node3D.new()
	truck_node.position = Vector3(position.x, 0.0, position.z)
	truck_node.scale = Vector3.ONE * 1.4
	truck_node.rotation_degrees.y = 90.0  # face +X direction
	var truck_path := "res://assets/vehicles/truck.glb"
	if ResourceLoader.exists(truck_path):
		var packed := load(truck_path) as PackedScene
		if packed != null:
			truck_node.add_child(packed.instantiate())
	scene_root.add_child(truck_node)
	var exit_x: float = GridManager.GRID_WIDTH * GridManager.CELL_SIZE + 12.0
	var exit_pos := Vector3(exit_x, 0.0, position.z)
	var dist: float = truck_node.position.distance_to(exit_pos)
	var tw := create_tween()
	tw.tween_property(truck_node, "position", exit_pos, dist / 12.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(truck_node.queue_free)

func _on_worker_arrived_home() -> void:
	if _pending_output.is_empty():
		return
	# Delivery should have happened via _worker_road_delivery_cycle before returning home.
	# If Gold is still pending (Garage), deposit it now.
	# Anything else still pending means delivery failed → keep in local_stock (max_stock) or discard.
	for res in _pending_output.keys():
		var amt: int = _pending_output[res]
		if _resource_manager != null and _resource_manager._amounts.has(res):
			_resource_manager.add_resource(res, amt)
		elif data != null and data.max_stock > 0:
			_local_stock[res] = _local_stock.get(res, 0) + amt
		# else: discard (no storage and delivery already failed)
	_pending_output.clear()
	_update_trough_visual()
	_update_stock_label()
	if data != null and data.max_stock > 0:
		var cap: int = data.max_stock
		_update_indicator(Color(0.55, 0.90, 0.20) if get_local_stock_total() < cap else Color(0.85, 0.10, 0.10))
	else:
		_update_indicator(Color(0.1, 0.9, 0.2))

func _flash_discard() -> void:
	if _mat == null:
		return
	var tween := create_tween()
	tween.tween_property(_mat, "albedo_color", Color(1.0, 0.2, 0.2), 0.08)
	tween.tween_property(_mat, "albedo_color", data.color, 0.30)

func _create_field_bar() -> void:
	_field_bar_bg = MeshInstance3D.new()
	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(_FIELD_BAR_W, _FIELD_BAR_H, 0.01)
	_field_bar_bg.mesh = bg_box
	_field_bar_bg.position = Vector3(0, _FIELD_BAR_Y, 0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_field_bar_bg.material_override = bg_mat
	_field_bar_bg.visible = false
	add_child(_field_bar_bg)
	_field_bar_fill = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(_FIELD_BAR_W, _FIELD_BAR_H, 0.02)
	_field_bar_fill.mesh = fill_box
	_field_bar_fill.position = Vector3(-_FIELD_BAR_W * 0.5, _FIELD_BAR_Y, 0)
	_field_bar_mat = StandardMaterial3D.new()
	_field_bar_mat.albedo_color = Color(0.2, 0.7, 1.0)
	_field_bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_field_bar_fill.material_override = _field_bar_mat
	_field_bar_fill.visible = false
	add_child(_field_bar_fill)

func _update_field_progress() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null or not is_instance_valid(_field_bar_bg):
		return
	if not gm.is_field_growing(origin_cell):
		_field_bar_bg.visible = false
		_field_bar_fill.visible = false
		return
	var remaining: float = gm.get_field_remaining(origin_cell)
	var progress: float = 1.0 - clampf(remaining / data.grow_time, 0.0, 1.0)
	_field_bar_bg.visible = true
	_field_bar_fill.visible = true
	var w: float = maxf(_FIELD_BAR_W * progress, 0.01)
	var mesh = _field_bar_fill.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(w, _FIELD_BAR_H, 0.02)
	_field_bar_fill.position = Vector3(-_FIELD_BAR_W * 0.5 + w * 0.5, _FIELD_BAR_Y, 0)
	if progress < 0.4:
		_field_bar_mat.albedo_color = Color(0.2, 0.5, 1.0)
	elif progress < 0.75:
		_field_bar_mat.albedo_color = Color(0.3, 0.85, 0.25)
	else:
		_field_bar_mat.albedo_color = Color(1.0, 0.82, 0.1)

func get_time_remaining() -> float:
	if _prod_timer != null and is_instance_valid(_prod_timer) and not _prod_timer.is_stopped():
		return _prod_timer.time_left
	return 0.0

func get_production_status() -> String:
	if not _is_active:
		return "Building"
	if data.grow_time > 0.0:
		var gm = get_tree().get_first_node_in_group("grid_manager")
		if gm != null:
			if gm.is_field_growing(origin_cell):
				var remaining: float = gm.get_field_remaining(origin_cell)
				return "🌱 Growing ⏳%ds" % [ceili(remaining)]
			elif gm.is_field_harvest_ready(origin_cell):
				return "✅ Ready to harvest"
		return "Waiting for conditions"
	var has_prod: bool = data.id == "garage" or data.recipes.size() > 0 or data.produces.size() > 0 or data.consumes.size() > 0
	if not has_prod or data.production_time <= 0:
		return ""
	if not _has_worker:
		return "No worker"
	if data.worker_domain == BuildingData.WorkerDomain.LIVESTOCK and get_local_stock_total() > 0:
		return "⏳ รอ Rancher มาเก็บ"
	if data.electricity_needed > 0 and _resource_manager != null:
		if not _resource_manager.has_resources({"Battery": data.electricity_needed}):
			return "🔋 รอแบตเตอรี่"
	if not _pending_output.is_empty():
		if _resource_manager != null and not _resource_manager.has_storage_for(1):
			return "🗑 Storage full"
		return "🚶 Waiting to deposit"
	var active_consumes: Dictionary = data.consumes
	if data.recipes.size() > 0:
		var recipe: Dictionary = data.recipes[_current_recipe % data.recipes.size()]
		active_consumes = recipe.get("consumes", {})
	if active_consumes.size() > 0:
		if is_factory_building():
			for res in active_consumes:
				if _input_stock.get(res, 0) < active_consumes.get(res, 0):
					return "Waiting for materials"
		elif _resource_manager != null:
			if not _resource_manager.has_resources(active_consumes):
				return "Waiting for materials"
	return "Producing"

func get_worker_info() -> Dictionary:
	if _worker == null or not is_instance_valid(_worker):
		return {"activity": "ไม่มีคนงาน", "details": ""}
	var activity: String = _worker.get_activity_text()
	var details := ""
	if data != null and data.id == "farm_house":
		if _farmer_carrying != "":
			details = "กำลังถือ: %s %s" % [_RES_ICON.get(_farmer_carrying, "📦"), _farmer_carrying]
		elif not _farmer_job_queue.is_empty():
			var harvest_count: int = 0
			var supply_count: int = 0
			for j in _farmer_job_queue:
				if j["type"] == "harvest": harvest_count += 1
				else: supply_count += 1
			var parts: Array = []
			if harvest_count > 0: parts.append("เก็บเกี่ยว %d" % harvest_count)
			if supply_count > 0: parts.append("จัดส่ง %d" % supply_count)
			details = "คิว: " + ", ".join(parts)
		else:
			details = "รอการมอบหมาย..."
	elif data != null and data.id == "woodcutter_house":
		if _woodcutter_has_wood:
			details = "กำลังถือไม้ — กำลังส่ง"
		elif not _woodcutter_delivery_queue.is_empty():
			details = "โกดังเต็ม — กำลังหาพื้นที่"
	return {"activity": activity, "details": details}

func get_local_stock_total() -> int:
	var total: int = 0
	for v in _local_stock.values():
		total += v
	return total

func set_recipe(idx: int) -> void:
	if data == null or data.recipes.is_empty(): return
	_current_recipe = idx % data.recipes.size()
	_input_stock.clear()
	_update_produce_icon()

func _update_stock_label() -> void:
	var cap: int = data.max_stock if data != null else 0
	if cap <= 0 and data != null and data.storage_bonus > 0:
		cap = data.storage_bonus
	if cap <= 0 or _status_label == null or not is_instance_valid(_status_label):
		return
	var total: int = get_local_stock_total()
	var res_icon: String = ""
	if data != null:
		if not data.produces.is_empty():
			res_icon = _RES_ICON.get(data.produces.keys()[0], "")
		elif data.storage_bonus > 0:
			res_icon = "📦"
	_status_label.text = "%s %d/%d" % [res_icon, total, cap]
	_status_label.visible = true

func _spawn_worker() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	var work_pos: Vector3 = _get_work_target(gm)
	_worker = Worker.new()
	gm.add_child(_worker)
	_worker.setup(_get_exit_world_pos(), work_pos, data.production_time, data.id, data.worker_model)
	if is_factory_building():
		_worker.set_cycle_callback(_factory_worker_cycle)
	else:
		_worker.set_cycle_callback(_worker_road_delivery_cycle)
	_worker.arrived_home.connect(_on_worker_arrived_home)

func _factory_worker_cycle() -> Array:
	# Priority 1: deliver pending output
	if not _pending_output.is_empty():
		var wps: Array = _worker_road_delivery_cycle()
		if not wps.is_empty():
			return wps
	# Priority 2: fetch missing inputs
	return _carrier_get_trip_waypoints()

func _find_nearest_warehouse(gm, near_cell: Vector2i) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist: float = 1e9
	for cell in gm.get_all_building_cells("warehouse"):
		var d: float = (Vector2(cell) - Vector2(near_cell)).length_squared()
		if d < best_dist:
			best_dist = d
			best_cell = cell
	return best_cell

func _worker_road_delivery_cycle() -> Array:
	if _pending_output.is_empty(): return []
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null: return []

	# Buildings with their own local storage (max_stock > 0) → return home and let _on_worker_arrived_home handle deposit
	if data != null and data.max_stock > 0:
		return []

	var building_ref := self

	# Gold (from Garage): deposit immediately to resource_manager, no walking needed
	var only_gold: bool = true
	for res in _pending_output:
		if res != "Gold":
			only_gold = false
			break
	if only_gold:
		for res in _pending_output:
			if _resource_manager != null: _resource_manager.add_resource(res, _pending_output[res])
		_pending_output.clear()
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
		return []

	# Physical goods: Feed → silo; everything else → warehouse
	var wpos: Vector3 = _worker.position if (_worker != null and is_instance_valid(_worker)) else position
	var wcell: Vector2i = gm.world_to_cell(wpos)
	var sto_cell: Vector2i
	if _pending_output.has("Feed"):
		sto_cell = _find_nearest_silo(gm, wcell)
		if sto_cell == Vector2i(-1, -1):
			sto_cell = _find_nearest_warehouse(gm, wcell)
	else:
		sto_cell = _find_nearest_warehouse(gm, wcell)

	if sto_cell == Vector2i(-1, -1):
		# No storage → currency goes to pool, physical goods are discarded
		for res in _pending_output.keys():
			if _resource_manager != null and _resource_manager._amounts.has(res):
				_resource_manager.add_resource(res, _pending_output[res])
		_pending_output.clear()
		if _worker != null and is_instance_valid(_worker): _worker.set_carrying(false)
		var road_cell: Vector2i = gm.get_nearest_road_cell(wcell)
		if road_cell != Vector2i(-1, -1):
			var road_pos: Vector3 = gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
			_worker.set_waypoints([{"pos": road_pos, "pause": 0.3}])
		return []

	var sto_bld = gm.get_building_node_at(sto_cell)
	var sto_pos: Vector3 = gm.cell_to_world(sto_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	var cap_sto: Building = sto_bld as Building
	var _do_deposit := func():
		if not is_instance_valid(building_ref): return
		for res in building_ref._pending_output.keys():
			var amt: int = building_ref._pending_output[res]
			# Currency resources (Gold, Gasoline, Battery) go to global pool
			if building_ref._resource_manager != null and building_ref._resource_manager._amounts.has(res):
				building_ref._resource_manager.add_resource(res, amt)
			elif is_instance_valid(cap_sto):
				cap_sto.receive_resource(res, amt)
		building_ref._pending_output.clear()
		building_ref._update_trough_visual()
		if building_ref._worker != null and is_instance_valid(building_ref._worker):
			building_ref._worker.set_carrying(false)
	return [{"pos": sto_pos, "pause": 0.5, "on_arrive": _do_deposit}]

# fallback delivery target (no longer used for _spawn_worker — road is used instead)
func _get_delivery_target(gm):
	var road_cell: Vector2i = gm.get_nearest_road_cell(origin_cell)
	if road_cell != Vector2i(-1, -1):
		return gm.cell_to_world(road_cell) + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	return position

func _get_work_target(gm):
	if data.id == "lumberyard":
		var forest_cell = gm.get_nearest_terrain_cell(origin_cell, _GM_FOREST)
		_lumberyard_target = forest_cell
		if forest_cell == Vector2i(-1, -1):
			return position + Vector3(0.0, 0.0, _GM_CELL * 0.6)
		var forest_world = gm.cell_to_world(forest_cell)
		return forest_world + Vector3(_GM_CELL * 0.5, 0.0, _GM_CELL * 0.5)
	elif data.worker_domain == BuildingData.WorkerDomain.CROP_FIELD or data.id == "tree_farm":
		return position + Vector3(0.0, 0.0, data.size.y * _GM_CELL * 0.4)
	elif data.id == "garage":
		return position + Vector3(_GM_CELL * 3.0, 0.0, 0.0)
	else:
		return position + Vector3(0.0, 0.0, _GM_CELL * 0.6)

# ---- Glow / Flash ----

func _set_glow(active: bool) -> void:
	if _mat == null:
		return
	_mat.emission_enabled = active
	_mat.emission = data.color * 0.5 if active else Color.BLACK
	_mat.emission_energy_multiplier = 1.5

func _flash() -> void:
	if _mat == null:
		return
	var tween := create_tween()
	tween.tween_property(_mat, "albedo_color", Color.WHITE, 0.08)
	tween.tween_property(_mat, "albedo_color", data.color, 0.18)

# ---- Indicator ----

func _create_indicator(label_y: float) -> void:
	_indicator = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_indicator.mesh = sphere
	_indicator.position = Vector3(0.5, label_y - 0.4, 0.0)
	_indicator.visible = false
	add_child(_indicator)

func _update_indicator(color: Color) -> void:
	if _indicator == null:
		return
	var has_prod: bool = data.id == "garage" or data.recipes.size() > 0 or data.produces.size() > 0 or data.consumes.size() > 0
	if data.production_time <= 0 or not has_prod:
		return
	_indicator.visible = true
	var ind_mat := _indicator.material_override as StandardMaterial3D
	if ind_mat == null:
		ind_mat = StandardMaterial3D.new()
		_indicator.material_override = ind_mat
	ind_mat.albedo_color = color
	ind_mat.emission_enabled = true
	ind_mat.emission = color * 0.6
	ind_mat.emission_energy_multiplier = 1.2

# ---- Selection Highlight & Info ----

func _create_highlight() -> void:
	if data == null:
		return
	_highlight = MeshInstance3D.new()
	var sz := data.size
	var box := BoxMesh.new()
	box.size = Vector3(sz.x * _GM_CELL - 0.08, 0.05, sz.y * _GM_CELL - 0.08)
	_highlight.mesh = box
	_highlight.position = Vector3(0, 0.025, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.75, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.75, 1.0)
	mat.emission_energy_multiplier = 2.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight.material_override = mat
	_highlight.visible = false
	add_child(_highlight)

func _create_info_label(label_y: float) -> void:
	_info_label = Label3D.new()
	_info_label.font_size = 34
	_info_label.position = Vector3(0, label_y + 0.8, 0)
	_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info_label.modulate = Color(0.75, 1.0, 0.90)
	_info_label.outline_modulate = Color.BLACK
	_info_label.outline_size = 10
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.no_depth_test = true
	_info_label.visible = false
	add_child(_info_label)

func _update_produce_icon() -> void:
	if data == null: return
	var active_produces: Dictionary = data.produces
	if data.recipes.size() > 0:
		var recipe: Dictionary = data.recipes[_current_recipe % data.recipes.size()]
		active_produces = recipe.get("produces", {})
	if active_produces.is_empty() or data.production_time <= 0.0:
		if _produce_icon_label != null: _produce_icon_label.visible = false
		return
	var icon: String = ""
	for res in active_produces:
		var ic: String = _RES_ICON.get(res, "")
		if ic != "":
			icon = ic
			break
	if icon == "": icon = "📦"
	if _produce_icon_label == null:
		_produce_icon_label = Label3D.new()
		_produce_icon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_produce_icon_label.no_depth_test = true
		_produce_icon_label.font_size = 52
		_produce_icon_label.outline_size = 8
		_produce_icon_label.outline_modulate = Color.BLACK
		_produce_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_produce_icon_label.position = Vector3(0, _label_y + 0.7, 0)
		add_child(_produce_icon_label)
	_produce_icon_label.text = icon
	_produce_icon_label.visible = true

func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _highlight != null:
		_highlight.visible = selected
	if _info_label != null:
		_info_label.visible = false

func _get_info_text() -> String:
	if data == null:
		return ""
	# Storage buildings: show local stock
	if data.storage_bonus > 0:
		var used: int = get_local_stock_total()
		var cap: int = data.storage_bonus
		var parts: Array = []
		for res in _local_stock.keys():
			if res == "Gold":
				continue
			var amt: int = _local_stock.get(res, 0)
			if amt > 0:
				parts.append("%s%d" % [_RES_ICON.get(res, "📦"), amt])
		var header: String = "📦 %d/%d" % [used, cap]
		if parts.is_empty():
			return header + "\nEmpty"
		return header + "\n" + " ".join(parts)
	var status := get_production_status()
	var lines: Array = [status]
	var active_produces: Dictionary = data.produces
	var active_consumes: Dictionary = data.consumes
	if data.recipes.size() > 0 and _current_recipe < data.recipes.size():
		var recipe: Dictionary = data.recipes[_current_recipe]
		active_produces = recipe.get("produces", {})
		active_consumes = recipe.get("consumes", {})
	if active_produces.size() > 0:
		var parts: Array = []
		for res in active_produces:
			parts.append("%s×%d" % [_RES_ICON.get(res, ""), active_produces[res]])
		lines.append("→ " + " ".join(parts))
	if active_consumes.size() > 0:
		var parts: Array = []
		for res in active_consumes:
			var have: int
			if is_factory_building():
				have = _input_stock.get(res, 0)
			elif _resource_manager != null:
				have = _resource_manager.get_amount(res)
			else:
				have = 0
			parts.append("%s %d/%d" % [_RES_ICON.get(res, ""), have, active_consumes[res]])
		lines.append("← " + " ".join(parts))
	return "\n".join(lines)
