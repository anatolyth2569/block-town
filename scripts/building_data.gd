class_name BuildingData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var size: Vector2i = Vector2i(1, 1)
@export var build_cost: Dictionary = {}
@export var build_time: float = 8.0   # seconds to build (0 = instant)
@export var population_bonus: int = 0 # population this building provides
@export var color: Color = Color.GRAY

@export_group("Production")
@export var produces: Dictionary = {}
@export var consumes: Dictionary = {}
@export var production_time: float = 5.0
@export var grow_time: float = 0.0   # crop growth time (0 = system not used)
@export var workers_needed: int = 1
@export var recipes: Array = []  # Array of Dictionaries: {name, produces, consumes, time}

@export_group("Passive")
@export var storage_bonus: int = 0
@export var max_stock: int = 0   # > 0 = accumulate stock in building before sending to global storage
@export var shadow_radius: int = 0      # cells this building casts shadow on around it
@export var pollution_radius: int = 0   # cells this building emits pollution on
@export var water_radius: int = 0       # cells this building provides water bonus to
@export var model_path: String = ""
@export var model_scale: float = 2.0

enum Category { FARM, RANCH, INDUSTRIAL, HOUSING, TRADE }
@export var category: Category = Category.FARM

enum WorkerDomain { NONE, CROP_FIELD, LIVESTOCK }
@export var worker_domain: WorkerDomain = WorkerDomain.NONE
