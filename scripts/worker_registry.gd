# worker_registry.gd
# Worker registry: every building has its own assigned worker type.
# Columns: job_id (used for worker_states lookup), notes
#
# Building               | job_id
# --------------------------------------------------------
# farm_house             | farm_house        — harvests crops and waters fields
# woodcutter_house       | woodcutter_house  — chops trees, delivers wood to road
# builder_house          | builder_house     — constructs waiting buildings
# house                  | house             — provides population
#
# Production buildings (workers_needed > 0, delivers to road)
# lumberyard             | lumberyard        — saws wood near the yard
# mill                   | mill              — grinds wheat into flour
# bakery                 | bakery            — bakes bread
# advanced_bakery        | advanced_bakery   — bakes premium pastries
# cake_bakery            | cake_bakery       — bakes cakes
# dairy_bakery           | dairy_bakery      — makes milk-based desserts
# pie_shop               | pie_shop          — makes pies
# cookie_chain           | cookie_chain      — bakes cookies
# sugar_mill             | sugar_mill        — processes sugarcane
# feed_mill              | feed_mill         — grinds animal feed
# dairy                  | dairy             — processes milk
# animal_barn            | animal_barn       — milks cows
# chicken_coop           | chicken_coop      — collects eggs
# sheep_pen              | sheep_pen         — shears sheep
# oil_pump               | oil_pump          — pumps crude oil
# power_plant            | power_plant       — generates electricity
# refinery               | refinery          — refines oil
# garage                 | garage            — delivers goods by truck
# well                   | well              — draws water from the well
# wind_pump              | wind_pump         — pumps water with wind
# water_facility         | water_facility    — produces water
#
# Buildings with a carrier (non-Water consumes)
# Every building with non-Water consumes gets a carrier worker.
# carrier = material transport — walks to storage, picks up materials, delivers to building
#
# Important notes:
# - Every production worker delivers only to the nearest road cell
# - If road is removed, buildings not adjacent to road will stop; workers walk home
# - Crops/farms/livestock do not need roads — can be placed anywhere on grass

extends Node

const BUILDING_TO_WORKER: Dictionary = {
	"farm_house":       {"job": "farm_house"},
	"woodcutter_house": {"job": "woodcutter_house"},
	"builder_house":    {"job": "builder_house"},
	"ranch_house":      {"job": "ranch_house"},
	"lumberyard":       {"job": "lumberyard"},
	"mill":             {"job": "mill"},
	"bakery":           {"job": "bakery"},
	"advanced_bakery":  {"job": "advanced_bakery"},
	"cake_bakery":      {"job": "cake_bakery"},
	"dairy_bakery":     {"job": "dairy_bakery"},
	"pie_shop":         {"job": "pie_shop"},
	"cookie_chain":     {"job": "cookie_chain"},
	"sugar_mill":       {"job": "sugar_mill"},
	"feed_mill":        {"job": "feed_mill"},
	"dairy":            {"job": "dairy"},
	"animal_barn":      {"job": "animal_barn"},
	"chicken_coop":     {"job": "chicken_coop"},
	"sheep_pen":        {"job": "sheep_pen"},
	"oil_pump":         {"job": "oil_pump"},
	"power_plant":      {"job": "power_plant"},
	"refinery":         {"job": "refinery"},
	"garage":           {"job": "garage"},
	"well":             {"job": "well"},
	"wind_pump":        {"job": "wind_pump"},
	"water_facility":   {"job": "water_facility"},
	"carrier":          {"job": "carrier"},
}

func get_worker_name(building_id: String) -> String:
	var lm = Engine.get_singleton("LocaleManager") if Engine.has_singleton("LocaleManager") else get_node_or_null("/root/LocaleManager")
	if lm != null:
		return lm.worker(building_id)
	return "Worker"

func get_job_id(building_id: String) -> String:
	if BUILDING_TO_WORKER.has(building_id):
		return BUILDING_TO_WORKER[building_id].get("job", building_id)
	return building_id
