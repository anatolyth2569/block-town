extends Node

enum State { IDLE, PLACING_BUILDING, DEMOLISHING, PLACING_ROAD }

signal state_changed(new_state: int)
signal building_data_selected(data)
signal building_info_requested(building)
signal empty_cell_clicked
signal pond_cell_clicked(cell: Vector2i)
signal forest_cell_clicked(cell: Vector2i)
signal grass_cell_clicked(cell: Vector2i)
signal road_cell_clicked(cell: Vector2i)

func show_building_info(building: Node) -> void:
	building_info_requested.emit(building)

var current_state: int = State.IDLE
var selected_building_data = null
var road_is_paved: bool = false

func select_for_placement(data) -> void:
	selected_building_data = data
	current_state = State.PLACING_BUILDING
	state_changed.emit(current_state)
	building_data_selected.emit(data)

func start_demolish() -> void:
	selected_building_data = null
	current_state = State.DEMOLISHING
	state_changed.emit(current_state)

func start_road_placing(paved: bool = false) -> void:
	selected_building_data = null
	road_is_paved = paved
	current_state = State.PLACING_ROAD
	state_changed.emit(current_state)

func cancel_placement() -> void:
	selected_building_data = null
	current_state = State.IDLE
	state_changed.emit(current_state)

func is_placing() -> bool:
	return current_state == State.PLACING_BUILDING

func is_demolishing() -> bool:
	return current_state == State.DEMOLISHING

func is_placing_road() -> bool:
	return current_state == State.PLACING_ROAD
