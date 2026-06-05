extends Control

var _res_mgr = null
var _gm = null
var _res_labels: Dictionary = {}
var _res_panels: Dictionary = {}
var _gas_blink_tween: Tween = null
var _notify_label: Label
var _demolish_btn: Button
var _population_label: Label

# Store UI state
var _store_panel: PanelContainer = null
var _store_open: bool = false
var _store_category: int = -1  # -1 = all
var _store_cards_container: Container = null
var _store_backdrop: Control = null

# Active popup (trade only)
var _active_popup: Control = null
var _backdrop: Control = null

# Bottom action bar (building selected / empty cell)
var _action_bar: PanelContainer = null
var _action_bar_content: HBoxContainer = null
var _selected_building = null  # Building instance — untyped to avoid hard dep

# Tooltip world anchor — updated in _process to follow building in 3D
var _tooltip_world_pos: Vector3 = Vector3.ZERO

# Cell action mini-popup (grass / road click)
var _cell_popup: Control = null
var _cell_popup_world_pos: Vector3 = Vector3.ZERO

# Production status bubbles — floating above active buildings
var _prod_overlays: Dictionary = {}   # Building -> {panel, name_lbl, sub_lbl, time_lbl}


var _exit_build_btn: Button = null
var _confirm_place_btn: Button = null
var _place_actions: HBoxContainer = null
var _building_placer_node: Node = null

# Minimap
var _minimap_panel: Control = null
var _minimap_backdrop: ColorRect = null
var _minimap_draw = null
var _minimap_open: bool = false

# Building info panel (shown on left side during placement mode)
var _build_info_panel: Control = null

# Resource display names are now loaded from LocaleManager (locale/th.json).
# This list drives which resources appear in the top bar.
const RESOURCE_DISPLAY: Array = [
	"Gold", "Score", "Battery", "Wood", "Wheat", "Flour", "Bread", "Planks", "Gasoline",
	"Sugarcane", "Cotton", "Pumpkin", "Corn", "Tomato",
	"Sugar", "Milk", "Egg", "Butter", "Cake", "Power", "Tools", "Salt",
	"PumpkinPie", "DairyCake", "Cookie", "Feed", "Wool",
	"Oil", "Plastic", "Chemical", "Stone", "IronOre", "Coal", "Iron",
	"Chili", "Basil", "Lemongrass", "Galangal", "Garlic", "Lime", "SpringOnion",
	"PadKrapao", "Somtam", "TomYum", "PickledGarlic",
	"Fabric",
	"Pig", "Pork",
]

func _res_name(key: String) -> String:
	var lm = get_node_or_null("/root/LocaleManager")
	return lm.resource(key) if lm != null else key

func _status_text(s: String) -> String:
	var lm = get_node_or_null("/root/LocaleManager")
	if lm == null: return s
	if s.begins_with("🌱 Growing"):
		return "🌱 กำลังเติบโต" + s.substr("🌱 Growing".length())
	if s.begins_with("✅ Ready to harvest"):
		return "✅ พร้อมเก็บเกี่ยว"
	if s.begins_with("🗑 "):
		return "🗑 " + lm.status(s.substr(3).strip_edges())
	if s.begins_with("🚶 "):
		return "🚶 " + lm.status(s.substr(3).strip_edges())
	var translated: String = lm.status(s)
	return translated if translated != s else s

const RES_ICON: Dictionary = {
	"Gold": "🪙", "Score": "⭐", "Wood": "🪵", "Water": "💧",
	"Wheat": "🌾", "Flour": "🌀", "Bread": "🍞", "Planks": "📋",
	"Gasoline": "⛽", "Battery": "🔋",
	"Sugarcane": "🌿", "Cotton": "🌸", "Pumpkin": "🎃",
	"Corn": "🌽", "Tomato": "🍅",
	"Sugar": "🍬", "Milk": "🥛", "Egg": "🥚",
	"Butter": "🧈", "Cake": "🎂", "Power": "⚡",
	"Tools": "🔧", "Salt": "🧂",
	"PumpkinPie": "🥧", "DairyCake": "🍰", "Cookie": "🍪",
	"Feed": "🌾", "Wool": "🧶",
	"Oil": "🛢️", "Plastic": "🧴", "Chemical": "⚗️",
	"Stone": "🪨", "IronOre": "⛏️", "Coal": "🖤", "Iron": "⚙️",
	"Chili": "🌶️", "Basil": "🍃", "Lemongrass": "🎋",
	"Galangal": "🌱", "Garlic": "🧄", "Lime": "🍋", "SpringOnion": "🧅",
	"PadKrapao": "🍛", "Somtam": "🥗", "TomYum": "🍲", "PickledGarlic": "🫙",
	"Fabric": "🧵",
	"Pig": "🐷", "Pork": "🥩",
}

const STORAGE_FILTER: Dictionary = {
	"silo":      ["Wheat", "Corn", "Sugarcane", "Cotton", "Pumpkin",
				  "Tomato", "Salt", "Feed", "Wool", "Milk", "Egg",
				  "Chili", "Basil", "Lemongrass", "Galangal", "Garlic", "Lime", "SpringOnion", "Pig"],
	"warehouse": ["Wood", "Planks", "Flour", "Sugar", "Bread", "Butter",
				  "Cake", "PumpkinPie", "DairyCake", "Cookie",
				  "Tools", "Gasoline", "Oil", "Plastic", "Chemical",
				  "Water", "Power", "Iron",
				  "PadKrapao", "Somtam", "TomYum", "PickledGarlic", "Fabric", "Pork"],
	"ore_depot": ["Stone", "IronOre", "Coal", "Iron"],
	"fuel_tank": ["Gasoline", "Oil"],
}

const CAT_COLOR: Array = [
	Color(0.15, 0.55, 0.12),   # FARM
	Color(0.55, 0.32, 0.08),   # RANCH
	Color(0.28, 0.52, 0.22),   # PROCESSING
	Color(0.45, 0.22, 0.08),   # INDUSTRIAL
	Color(0.22, 0.42, 0.80),   # HOUSING
	Color(0.38, 0.38, 0.42),   # TRADE
]

const CAT_LABEL: Array = ["all", "farm", "ranch", "processing", "industrial", "housing", "trade", "road"]
const CAT_EMOJI: Dictionary = {
	"all": "🏪", "farm": "🌾", "ranch": "🐄",
	"processing": "🏗️", "industrial": "⚙️", "housing": "🏠", "trade": "📦", "road": "🛤️"
}
const BUILDING_ICON: Dictionary = {
	"farm": "🌾", "sugarcane_field": "🌿",
	"pumpkin_patch": "🎃", "corn_field": "🌽", "cotton_field": "🌸", "tomato_field": "🍅",
	"salt_field": "🧂", "tree_farm": "🌲", "mill": "🌀",
	"feed_mill": "🐾", "bakery": "🍞", "kitchen": "🍳", "weaving_house": "🧵",
	"dairy": "🥛",
	"lumberyard": "🪵", "well": "💧", "small_pond": "🪷", "large_pond": "🏞️", "wind_pump": "💨",
	"water_facility": "🚰", "silo": "🏚️", "warehouse": "📦",
	"power_plant": "⚡", "refinery": "🛢️",
	"oil_pump": "⛽", "fuel_tank": "⛽",
	"farm_house": "🏡", "woodcutter_house": "🪓",
	"builder_house": "🔨",
	"animal_barn": "🐄", "chicken_coop": "🐔", "sheep_pen": "🐑", "pig_pen": "🐷",
	"chili_field": "🌶️", "basil_garden": "🍃",
	"lime_orchard": "🍋", "spring_onion_field": "🌿",
	"kitchen": "🍛",
	"garlic_field": "🧄", "ranch_house": "🏘️",
	"garage": "🚚",
	"slaughterhouse": "🔪", "sawmill": "🪚", "workshop": "🔨", "engineer_house": "⚙️",
	"solar_panel": "☀️", "house": "🏠",
}

# Mapping from store tab index → BuildingData.Category values
# 0=all, 1=FARM(0), 2=RANCH(1), 3=PROCESSING(2), 4=INDUSTRIAL(3), 5=HOUSING(4), 6=TRADE(5), 7=roads
const CAT_MAP: Array = [[], [0], [1], [2], [3], [4], [5], []]

const BUILDING_PATHS: Array = [
	"res://resources/buildings/lumberyard.tres",
	"res://resources/buildings/well.tres",
	"res://resources/buildings/small_pond.tres",
	"res://resources/buildings/large_pond.tres",
	"res://resources/buildings/farm.tres",
	"res://resources/buildings/sugarcane_field.tres",
	"res://resources/buildings/pumpkin_patch.tres",
	"res://resources/buildings/corn_field.tres",
	"res://resources/buildings/cotton_field.tres",
	"res://resources/buildings/tomato_field.tres",
	"res://resources/buildings/tree_farm.tres",
	"res://resources/buildings/salt_field.tres",
	"res://resources/buildings/wind_pump.tres",
	"res://resources/buildings/animal_barn.tres",
	"res://resources/buildings/chicken_coop.tres",
	"res://resources/buildings/sheep_pen.tres",
	"res://resources/buildings/pig_pen.tres",
	"res://resources/buildings/feed_mill.tres",
	"res://resources/buildings/silo.tres",
	"res://resources/buildings/dairy.tres",
	"res://resources/buildings/weaving_house.tres",
	"res://resources/buildings/water_facility.tres",
	"res://resources/buildings/power_plant.tres",

	"res://resources/buildings/refinery.tres",

	"res://resources/buildings/farm_house.tres",
	"res://resources/buildings/mill.tres",
	"res://resources/buildings/bakery.tres",
	"res://resources/buildings/oil_pump.tres",
	"res://resources/buildings/woodcutter_house.tres",
	"res://resources/buildings/builder_house.tres",
	"res://resources/buildings/warehouse.tres",
	"res://resources/buildings/fuel_tank.tres",
	"res://resources/buildings/chili_field.tres",
	"res://resources/buildings/basil_garden.tres",
	"res://resources/buildings/spring_onion_field.tres",
	"res://resources/buildings/lime_orchard.tres",
	"res://resources/buildings/kitchen.tres",
	"res://resources/buildings/garlic_field.tres",
	"res://resources/buildings/ranch_house.tres",
	"res://resources/buildings/slaughterhouse.tres",
	"res://resources/buildings/sawmill.tres",
	"res://resources/buildings/workshop.tres",
	"res://resources/buildings/garage.tres",
	"res://resources/buildings/engineer_house.tres",
	"res://resources/buildings/solar_panel.tres",
	"res://resources/buildings/house.tres",
]

func _ready() -> void:
	_res_mgr = get_node_or_null("/root/ResourceManager")
	_gm = get_node_or_null("/root/GameManager")
	if _res_mgr == null or _gm == null:
		push_error("HUD: autoloads not found")
		return
	_res_mgr.resource_changed.connect(_on_resource_changed)
	_res_mgr.population_changed.connect(_on_population_changed)
	_res_mgr.gold_depleted.connect(func(): _show_notify("⚠ ทองหมด! คนงานหยุดรับค่าจ้าง"))
	_gm.state_changed.connect(_on_state_changed)
	_gm.building_info_requested.connect(_show_building_info)
	_gm.building_data_selected.connect(_show_build_info)
	_gm.empty_cell_clicked.connect(_on_empty_cell_clicked)
	_gm.pond_cell_clicked.connect(_on_pond_cell_clicked)
	_gm.forest_cell_clicked.connect(_on_forest_cell_clicked)
	_gm.grass_cell_clicked.connect(_on_grass_cell_clicked)
	_gm.road_cell_clicked.connect(_on_road_cell_clicked)
	_build_top_bar()
	_build_bottom_bar()
	_build_action_bar()
	_build_notify_label()
	var _poll := Timer.new()
	_poll.wait_time = 0.3
	_poll.autostart = true
	_poll.timeout.connect(_refresh_top_bar)
	add_child(_poll)
	_refresh_top_bar()
	_add_save_controls()
	_build_minimap()
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm._auto_save_timer != null:
		if not sm._auto_save_timer.timeout.is_connected(show_save_flash):
			sm._auto_save_timer.timeout.connect(show_save_flash)

# --- Top Bar ---

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 68)
	_apply_panel_style(panel, Color(0.98, 0.98, 1.0, 0.96), Color(0.65, 0.60, 0.82), false)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 4)
	margin.add_child(outer_hbox)

	# Scrollable resource chips — fills available width, scrolls horizontally when overflow
	var res_scroll := ScrollContainer.new()
	res_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	res_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	res_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(res_scroll)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 4)
	res_scroll.add_child(hbox)

	for res in RESOURCE_DISPLAY:
		var card := _make_resource_card(res as String)
		card.visible = false
		_res_panels[res] = card
		hbox.add_child(card)

	_population_label = Label.new()
	_population_label.text = "👷 0/0"
	_population_label.add_theme_font_size_override("font_size", 16)
	_population_label.add_theme_color_override("font_color", Color(0.10, 0.10, 0.15))
	_population_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_population_label.add_theme_constant_override("outline_size", 4)
	_population_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_population_label.custom_minimum_size = Vector2(70, 44)
	_population_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_hbox.add_child(_population_label)

	var gold_btn := Button.new()
	gold_btn.text = "+500🪙"
	gold_btn.custom_minimum_size = Vector2(84, 44)
	gold_btn.focus_mode = Control.FOCUS_NONE
	_style_button(gold_btn, Color(0.6, 0.45, 0.0, 0.85), Color(1.0, 0.88, 0.2))
	gold_btn.pressed.connect(_on_add_gold)
	outer_hbox.add_child(gold_btn)

	# Divider
	var div := VSeparator.new()
	div.custom_minimum_size = Vector2(2, 36)
	div.add_theme_color_override("separator_color", Color(0.55, 0.50, 0.72, 0.50))
	outer_hbox.add_child(div)

	# Profile button (👤 + province name)
	var profile_btn := Button.new()
	var gm_tp = get_node_or_null("/root/GameManager")
	var prov_name: String = _province_display(gm_tp.selected_province if gm_tp != null else "")
	profile_btn.text = "👤  " + prov_name
	profile_btn.custom_minimum_size = Vector2(110, 44)
	profile_btn.focus_mode = Control.FOCUS_NONE
	profile_btn.name = "ProfileBtn"
	_style_button(profile_btn, Color(0.22, 0.28, 0.48, 0.88), Color(0.80, 0.88, 1.0))
	profile_btn.pressed.connect(_open_settings_popup)
	outer_hbox.add_child(profile_btn)

	# Settings gear
	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.custom_minimum_size = Vector2(44, 44)
	settings_btn.focus_mode = Control.FOCUS_NONE
	_style_button(settings_btn, Color(0.22, 0.28, 0.48, 0.88), Color(0.80, 0.88, 1.0))
	settings_btn.pressed.connect(_open_settings_popup)
	outer_hbox.add_child(settings_btn)

func _province_display(id: String) -> String:
	var names: Dictionary = {
		"chiang_mai": "เชียงใหม่", "chiang_rai": "เชียงราย", "nan": "น่าน",
		"khon_kaen": "ขอนแก่น",  "ubon": "อุบลราชธานี", "korat": "นครราชสีมา",
		"ayutthaya": "อยุธยา",   "bangkok": "กรุงเทพฯ",  "chonburi": "ชลบุรี",
		"phetchaburi": "เพชรบุรี","surat": "สุราษฎร์ธานี","phuket": "ภูเก็ต",
		"songkhla": "สงขลา",
	}
	return names.get(id, "เลือกพื้นที่")

func _open_settings_popup() -> void:
	# Close if already open
	var existing := get_node_or_null("SettingsPopup")
	if existing != null:
		existing.queue_free()
		return

	var popup := PanelContainer.new()
	popup.name = "SettingsPopup"
	popup.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	popup.offset_left   = -310.0
	popup.offset_right  = -4.0
	popup.offset_top    = 68.0
	popup.offset_bottom = 68.0 + 220.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.22, 0.97)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.border_width_top  = 2
	style.border_color      = Color(0.35, 0.48, 0.80, 0.75)
	popup.add_theme_stylebox_override("panel", style)
	add_child(popup)

	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header
	var gm_sp := get_node_or_null("/root/GameManager")
	var pname := _province_display(gm_sp.selected_province if gm_sp != null else "")
	var header := Label.new()
	header.text = "⚙  ตั้งค่า — " + pname
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.78, 0.86, 1.0))
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Move province button
	var move_btn := Button.new()
	move_btn.text = "🗺  ย้ายพื้นที่ / เปลี่ยนจังหวัด"
	move_btn.custom_minimum_size = Vector2(0, 46)
	move_btn.focus_mode = Control.FOCUS_NONE
	_style_button(move_btn, Color(0.55, 0.28, 0.08, 0.90), Color(1.0, 0.78, 0.42))
	move_btn.pressed.connect(_confirm_move_province.bind(popup))
	vbox.add_child(move_btn)

	var move_hint := Label.new()
	move_hint.text = "ลบโครงการนี้และเริ่มสร้างในจังหวัดใหม่\nความคืบหน้าทั้งหมดจะหายไป"
	move_hint.add_theme_font_size_override("font_size", 11)
	move_hint.add_theme_color_override("font_color", Color(0.70, 0.60, 0.45))
	move_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(move_hint)

	vbox.add_child(HSeparator.new())

	# Close button
	var close_btn := Button.new()
	close_btn.text = "✕  ปิด"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.focus_mode = Control.FOCUS_NONE
	_style_button(close_btn, Color(0.25, 0.22, 0.35, 0.85), Color(0.75, 0.72, 0.90))
	close_btn.pressed.connect(popup.queue_free)
	vbox.add_child(close_btn)

func _confirm_move_province(settings_popup: Control) -> void:
	settings_popup.queue_free()

	var confirm := PanelContainer.new()
	confirm.name = "ConfirmMovePopup"
	confirm.set_anchors_preset(Control.PRESET_CENTER)
	confirm.offset_left  = -200.0
	confirm.offset_right =  200.0
	confirm.offset_top   = -100.0
	confirm.offset_bottom = 100.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.06, 0.06, 0.98)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top  = 2
	style.border_color      = Color(0.75, 0.22, 0.12)
	confirm.add_theme_stylebox_override("panel", style)

	# Backdrop
	var bd := ColorRect.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.color = Color(0, 0, 0, 0.55)
	bd.z_index = 10
	add_child(bd)
	confirm.z_index = 11
	add_child(confirm)

	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	confirm.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "⚠  ยืนยันการย้ายพื้นที่?"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "เมืองและความคืบหน้าทั้งหมดจะถูกลบ\nไม่สามารถกู้คืนได้ ต้องการดำเนินการต่อ?"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.85, 0.72, 0.65))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "ยกเลิก"
	cancel_btn.custom_minimum_size = Vector2(110, 40)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	_style_button(cancel_btn, Color(0.22, 0.22, 0.35, 0.90), Color(0.80, 0.80, 1.0))
	cancel_btn.pressed.connect(func(): bd.queue_free(); confirm.queue_free())
	btn_row.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.text = "🗺  ย้ายพื้นที่"
	ok_btn.custom_minimum_size = Vector2(130, 40)
	ok_btn.focus_mode = Control.FOCUS_NONE
	_style_button(ok_btn, Color(0.55, 0.08, 0.08, 0.92), Color(1.0, 0.55, 0.45))
	ok_btn.pressed.connect(_do_move_province)
	btn_row.add_child(ok_btn)

func _do_move_province() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.delete_save()
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")

func _make_resource_card(res: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(82, 0)
	_apply_panel_style(panel, Color(1.0, 1.0, 1.0, 0.92), Color(0.68, 0.64, 0.82))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "%s %s" % [RES_ICON.get(res, ""), _res_name(res)]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.28, 0.24, 0.42))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var amt_lbl := Label.new()
	amt_lbl.text = "0"
	amt_lbl.add_theme_font_size_override("font_size", 26)
	amt_lbl.add_theme_color_override("font_color", Color(0.10, 0.08, 0.15))
	amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(amt_lbl)
	_res_labels[res] = amt_lbl

	return panel

# --- Bottom Bar (Store) ---

func _build_bottom_bar() -> void:
	# STORE toggle button — bottom-right
	var store_toggle := Button.new()
	store_toggle.text = "🏪 STORE"
	store_toggle.custom_minimum_size = Vector2(130, 56)
	store_toggle.focus_mode = Control.FOCUS_NONE
	store_toggle.anchor_left = 1.0
	store_toggle.anchor_right = 1.0
	store_toggle.anchor_top = 1.0
	store_toggle.anchor_bottom = 1.0
	store_toggle.offset_left = -138.0
	store_toggle.offset_right = -4.0
	store_toggle.offset_top = -62.0
	store_toggle.offset_bottom = -4.0
	_style_button(store_toggle, Color(0.88, 0.92, 0.98, 0.92), Color(0.15, 0.30, 0.60))
	store_toggle.pressed.connect(_on_store_toggle)
	add_child(store_toggle)

	# Placement action bar — centered at bottom, holds ✕ and ✓ buttons
	_place_actions = HBoxContainer.new()
	_place_actions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_place_actions.offset_left = 132.0
	_place_actions.offset_right = -142.0
	_place_actions.offset_top = -62.0
	_place_actions.offset_bottom = -4.0
	_place_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_place_actions.add_theme_constant_override("separation", 8)
	_place_actions.visible = false
	add_child(_place_actions)

	_exit_build_btn = Button.new()
	_exit_build_btn.text = "✕ ยกเลิก"
	_exit_build_btn.custom_minimum_size = Vector2(148, 54)
	_exit_build_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_exit_build_btn, Color(0.58, 0.12, 0.10, 0.92), Color.WHITE)
	_exit_build_btn.pressed.connect(func(): _gm.cancel_placement())
	_place_actions.add_child(_exit_build_btn)

	# MAP toggle button — bottom-left corner
	var map_btn := Button.new()
	map_btn.text = "🗺 MAP"
	map_btn.custom_minimum_size = Vector2(120, 56)
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.anchor_left = 0.0
	map_btn.anchor_right = 0.0
	map_btn.anchor_top = 1.0
	map_btn.anchor_bottom = 1.0
	map_btn.offset_left = 4.0
	map_btn.offset_right = 128.0
	map_btn.offset_top = -62.0
	map_btn.offset_bottom = -4.0
	_style_button(map_btn, Color(0.12, 0.32, 0.58, 0.92), Color(0.80, 0.90, 1.0))
	map_btn.pressed.connect(_toggle_minimap)
	add_child(map_btn)

	# Store panel — centered popup, hidden by default
	_store_panel = PanelContainer.new()
	_store_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_store_panel.offset_left = 4.0
	_store_panel.offset_right = -4.0
	_store_panel.offset_top = 72.0
	_store_panel.offset_bottom = -4.0
	_apply_panel_style(_store_panel, Color(0.98, 0.97, 1.0, 0.97), Color(0.60, 0.54, 0.80), false)
	_store_panel.visible = false
	add_child(_store_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 8)
	outer_margin.add_theme_constant_override("margin_right", 8)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	_store_panel.add_child(outer_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	outer_margin.add_child(vbox)

	# Header row
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var title_lbl := Label.new()
	title_lbl.text = "🏪 ร้านค้า"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.18, 0.15, 0.32))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_row.add_child(title_lbl)

	var store_close := Button.new()
	store_close.text = "✕"
	store_close.custom_minimum_size = Vector2(44, 44)
	store_close.focus_mode = Control.FOCUS_NONE
	_style_button(store_close, Color(0.70, 0.68, 0.80, 0.90), Color(0.20, 0.18, 0.35))
	store_close.pressed.connect(_close_store)
	header_row.add_child(store_close)

	# Category tabs
	var tab_hbox := HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_hbox)

	var _lm_tabs = get_node_or_null("/root/LocaleManager")
	for i in range(CAT_LABEL.size()):
		var tab_btn := Button.new()
		var cat_key: String = CAT_LABEL[i]
		var th_cat: String = _lm_tabs.category(cat_key) if _lm_tabs != null else cat_key
		var emoji: String = CAT_EMOJI.get(cat_key, "")
		tab_btn.text = "%s %s" % [emoji, th_cat]
		tab_btn.custom_minimum_size = Vector2(72, 40)
		tab_btn.focus_mode = Control.FOCUS_NONE
		_style_button(tab_btn, Color(0.88, 0.86, 0.95, 0.92), Color(0.20, 0.18, 0.38))
		tab_btn.pressed.connect(_on_store_category.bind(i))
		tab_hbox.add_child(tab_btn)

	# Scroll container — vertical scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_store_cards_container = grid

	_refresh_store_cards()

# --- Action Bar (bottom strip, context-sensitive) ---

func _build_action_bar() -> void:
	_action_bar = PanelContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_bar.offset_top = -72.0
	_action_bar.offset_bottom = 0.0
	_action_bar.visible = false
	_apply_panel_style(_action_bar, Color(0.97, 0.97, 1.0, 0.97), Color(0.48, 0.62, 0.90), true)
	add_child(_action_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_action_bar.add_child(margin)

	_action_bar_content = HBoxContainer.new()
	_action_bar_content.add_theme_constant_override("separation", 8)
	_action_bar_content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_action_bar_content)

func _hide_action_bar() -> void:
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.set_selected(false)
	_selected_building = null
	if _action_bar == null:
		return
	_action_bar.visible = false
	if _action_bar_content != null:
		for child in _action_bar_content.get_children():
			child.queue_free()

func _populate_action_bar_building(bld: Building) -> void:
	for child in _action_bar_content.get_children():
		child.queue_free()

	# Color swatch
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(8, 50)
	swatch.color = bld.data.color if bld.data != null else Color.GRAY
	_action_bar_content.add_child(swatch)

	# Info section
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_bar_content.add_child(info_vbox)

	var title := Label.new()
	if bld.data != null:
		var lm_ab = get_node_or_null("/root/LocaleManager")
		var th_ab: String = lm_ab.building(bld.data.id) if lm_ab != null else ""
		title.text = th_ab if th_ab != bld.data.id else bld.data.display_name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.18, 0.15, 0.32))
	info_vbox.add_child(title)

	var status_str: String = bld.get_production_status()
	var s_lbl := Label.new()
	s_lbl.text = _status_text(status_str)
	s_lbl.add_theme_font_size_override("font_size", 12)
	var s_color: Color
	match status_str:
		"Producing": s_color = Color(0.3, 1.0, 0.4)
		"Waiting for materials": s_color = Color(1.0, 0.85, 0.2)
		_: s_color = Color(0.70, 0.70, 0.75)
	s_lbl.add_theme_color_override("font_color", s_color)
	info_vbox.add_child(s_lbl)

	# Action buttons
	var refund_amt: int = bld.data.build_cost.get("Gold", 0) / 2 if bld.data != null else 0
	var remove_btn := Button.new()
	remove_btn.text = "💣 รื้อถอน  +%d🪙" % refund_amt
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.custom_minimum_size = Vector2(140, 48)
	_style_button(remove_btn, Color(0.38, 0.08, 0.08, 0.9), Color(1.0, 0.45, 0.35))
	remove_btn.pressed.connect(func(): _on_demolish_building(bld))
	_action_bar_content.add_child(remove_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(40, 48)
	_style_button(close_btn, Color(0.72, 0.70, 0.82, 0.90), Color(0.20, 0.18, 0.35))
	close_btn.pressed.connect(_hide_action_bar)
	_action_bar_content.add_child(close_btn)

	_action_bar.visible = true

func _refresh_store_cards() -> void:
	if _store_cards_container == null:
		return
	for child in _store_cards_container.get_children():
		child.queue_free()

	# Road + terrain — special category (index 7)
	if _store_category == 7:
		_store_cards_container.add_child(_make_road_card("ถนนดิน\nDirt Road", 0, false))
		_store_cards_container.add_child(_make_road_card("ถนนลาดยาง\nPaved Road", 50, true))
		_store_cards_container.add_child(_make_pond_card("🪷 บ่อน้ำเล็ก\nSmall Pond", 80, false))
		_store_cards_container.add_child(_make_pond_card("🏞️ บ่อน้ำใหญ่\nLarge Pond", 150, true))
		return

	var filtered: Array = []
	for path in BUILDING_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var bd: BuildingData = load(path) as BuildingData
		if bd == null:
			continue
		if _store_category > 0:
			var allowed: Array = CAT_MAP[_store_category]
			if not (int(bd.category) in allowed):
				continue
		filtered.append(bd)
	filtered.sort_custom(func(a, b): return a.build_cost.get("Gold", 0) < b.build_cost.get("Gold", 0))
	for bd in filtered:
		_store_cards_container.add_child(_make_store_card(bd))

func _make_road_card(label: String, cost: int, is_paved: bool) -> Control:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 150)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_col := Color(0.90, 0.84, 0.68) if not is_paved else Color(0.84, 0.80, 0.72)
	var cost_txt := "Free" if cost == 0 else "%d🪙" % cost
	btn.text = "%s\n%s" % [label, cost_txt]
	_style_button(btn, bg_col, Color(0.35, 0.28, 0.08))
	btn.pressed.connect(func() -> void:
		var paid: bool = cost == 0 or _res_mgr == null or _res_mgr.pay({"Gold": cost})
		if not paid: _show_notify("ทองไม่พอ! ต้องการ %d🪙" % cost)
		if not paid: return
		if _gm != null: _gm.start_road_placing(is_paved)
		_close_store()
	)
	return btn

func _make_pond_card(label: String, cost: int, big: bool) -> Control:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 150)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_col := Color(0.62, 0.80, 0.92) if big else Color(0.72, 0.88, 0.96)
	var cost_txt := "%d🪙" % cost
	var water_bonus := "+2💧/ข้างเคียง" if big else "+1💧/ข้างเคียง"
	btn.text = "%s\n%s\n%s" % [label, cost_txt, water_bonus]
	_style_button(btn, bg_col, Color(0.05, 0.25, 0.45))
	btn.pressed.connect(func() -> void:
		var paid: bool = _res_mgr == null or _res_mgr.pay({"Gold": cost})
		if not paid:
			_show_notify("ทองไม่พอ! ต้องการ %d🪙" % cost)
			return
		if _gm != null: _gm.start_pond_placing(big)
		_close_store()
		_show_notify("คลิกเพื่อวางสระน้ำ  คลิกขวาเพื่อยกเลิก")
	)
	return btn

func _make_building_preview(bd: BuildingData, _bg_col: Color) -> Control:
	# ถ้ามี PNG pre-rendered → ใช้เลย (ไม่ต้อง render 3D)
	var png_path := "res://assets/building_previews/" + bd.id + ".png"
	if ResourceLoader.exists(png_path):
		var tex := load(png_path) as Texture2D
		if tex != null:
			var rect := TextureRect.new()
			rect.texture = tex
			rect.custom_minimum_size = Vector2(0, 100)
			rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return rect

	# Fallback: emoji (ยังไม่ได้ generate หรือไม่มีโมเดล)
	var lbl := Label.new()
	lbl.text = BUILDING_ICON.get(bd.id, "🏗️")
	lbl.add_theme_font_size_override("font_size", 38)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size = Vector2(0, 50)
	return lbl

func _make_store_card(bd: BuildingData) -> Control:
	var cat: int = bd.category if bd.category < CAT_COLOR.size() else 0
	var bg_col: Color = CAT_COLOR[cat]

	# ── Outer card container ──
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_st := StyleBoxFlat.new()
	card_st.bg_color = bg_col.lightened(0.50)
	card_st.corner_radius_top_left = 10
	card_st.corner_radius_top_right = 10
	card_st.corner_radius_bottom_left = 10
	card_st.corner_radius_bottom_right = 10
	card_st.border_width_left = 2
	card_st.border_width_right = 2
	card_st.border_width_top = 2
	card_st.border_width_bottom = 2
	card_st.border_color = bg_col
	card_st.shadow_size = 3
	card_st.shadow_color = Color(0, 0, 0, 0.15)
	card.add_theme_stylebox_override("panel", card_st)
	card.mouse_entered.connect(func():
		card_st.bg_color = bg_col.lightened(0.65)
		card_st.border_width_left = 3; card_st.border_width_right = 3
		card_st.border_width_top = 3; card_st.border_width_bottom = 3
	)
	card.mouse_exited.connect(func():
		card_st.bg_color = bg_col.lightened(0.50)
		card_st.border_width_left = 2; card_st.border_width_right = 2
		card_st.border_width_top = 2; card_st.border_width_bottom = 2
	)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_on_build_button(bd)
				card.get_viewport().set_input_as_handled()
	)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	mg.add_theme_constant_override("margin_top", 10)
	mg.add_theme_constant_override("margin_bottom", 10)
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(mg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mg.add_child(vbox)

	# ── Preview (SubViewport 3D ถ้ามีโมเดล, emoji ถ้าไม่มี) ──
	vbox.add_child(_make_building_preview(bd, bg_col))

	# ── ชื่ออาคาร ──
	var lm := get_node_or_null("/root/LocaleManager")
	var th_name: String = lm.building(bd.id) if lm != null else ""
	var display_name: String = th_name if th_name != bd.id else bd.display_name
	var name_lbl := Label.new()
	name_lbl.text = display_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.10, 0.08, 0.18))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# ── เส้นคั่น ──
	var sep := HSeparator.new()
	sep.modulate = bg_col.darkened(0.1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# ── สร้างอะไร (produces) ──
	var all_produces: Dictionary = {}
	if bd.produces.size() > 0:
		all_produces.merge(bd.produces)
	for recipe in bd.recipes:
		var rp: Dictionary = recipe.get("produces", {})
		all_produces.merge(rp)
	if all_produces.size() > 0:
		var prod_parts: Array = []
		for res in all_produces:
			var icon_r: String = RES_ICON.get(res, "▫️")
			var res_name: String = lm.resource(res) if lm != null else res
			prod_parts.append("%s%s" % [icon_r, res_name])
		var prod_lbl := Label.new()
		prod_lbl.text = "▶ " + "  ".join(prod_parts)
		prod_lbl.add_theme_font_size_override("font_size", 12)
		prod_lbl.add_theme_color_override("font_color", Color(0.10, 0.32, 0.12))
		prod_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prod_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(prod_lbl)

	# ── ผลกระทบบวก ──
	if bd.water_radius > 0:
		var eff := Label.new()
		eff.text = "💧 น้ำ %d ช่อง" % bd.water_radius
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.08, 0.30, 0.78))
		eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(eff)
	if bd.population_bonus > 0:
		var eff := Label.new()
		eff.text = "👥 +%d คน" % bd.population_bonus
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.10, 0.20, 0.62))
		eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(eff)

	# ── ผลกระทบลบ ──
	if bd.pollution_radius > 0:
		var eff := Label.new()
		eff.text = "☣️ มลพิษ %d ช่อง" % bd.pollution_radius
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.70, 0.20, 0.05))
		eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(eff)
	if bd.shadow_radius > 0:
		var eff := Label.new()
		eff.text = "🌑 เงา %d ช่อง" % bd.shadow_radius
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.35, 0.32, 0.38))
		eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(eff)

	# ── ขนาด + ราคา ──
	var size_lbl := Label.new()
	size_lbl.text = "⬛ %dx%d" % [bd.size.x, bd.size.y]
	size_lbl.add_theme_font_size_override("font_size", 11)
	size_lbl.add_theme_color_override("font_color", Color(0.40, 0.38, 0.45))
	size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(size_lbl)

	var cost_parts: Array = []
	for res in bd.build_cost:
		cost_parts.append("%d%s" % [bd.build_cost[res], RES_ICON.get(res, "")])
	var cost_lbl := Label.new()
	cost_lbl.text = ", ".join(cost_parts)
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(0.30, 0.22, 0.02))
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cost_lbl)

	return card

func _on_store_toggle() -> void:
	if _store_panel == null:
		return
	_store_open = not _store_open
	_store_panel.visible = _store_open
	if _store_open:
		_store_backdrop = Control.new()
		_store_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_store_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_store_backdrop.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed: _close_store()
		)
		add_child(_store_backdrop)
		move_child(_store_backdrop, _store_panel.get_index())
	else:
		if _store_backdrop != null and is_instance_valid(_store_backdrop):
			_store_backdrop.queue_free()
		_store_backdrop = null

func _close_store() -> void:
	_store_open = false
	if _store_panel != null:
		_store_panel.visible = false
	if _store_backdrop != null and is_instance_valid(_store_backdrop):
		_store_backdrop.queue_free()
	_store_backdrop = null

func _on_store_category(cat_index: int) -> void:
	_store_category = cat_index
	_refresh_store_cards()

# --- Notify ---

func _build_notify_label() -> void:
	_notify_label = Label.new()
	_notify_label.set_anchors_preset(Control.PRESET_CENTER)
	_notify_label.position = Vector2(0, -130)
	_notify_label.add_theme_font_size_override("font_size", 34)
	_notify_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_notify_label.add_theme_constant_override("outline_size", 6)
	_notify_label.modulate = Color(1, 0.35, 0.25, 0)
	_notify_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notify_label)

# --- Orders Panel ---

# --- Building Info Popup ---

func _show_building_info(building: Node) -> void:
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.set_selected(false)
	_selected_building = null
	_close_active_popup()
	_hide_action_bar()

	var bld: Building = building as Building
	if bld == null or bld.data == null:
		return

	if bld.data.id == "garage":
		_show_garage_sell_ui(bld)
		return

	_selected_building = bld
	bld.set_selected(true)
	_remove_prod_overlay(bld)  # hide bubble while tooltip is open
	_show_building_popup(bld)

func _field_conditions_active(bld: Building, grid_mgr) -> bool:
	# Conditions are only relevant while field is idle (waiting for inputs)
	# When growing or harvest-ready → conditions are irrelevant, hide them
	if bld.data == null or bld.data.grow_time <= 0.0 or grid_mgr == null: return false
	return not grid_mgr.is_field_growing(bld.origin_cell) and not grid_mgr.is_field_harvest_ready(bld.origin_cell)

func _get_res_have(bld: Building, res: String, need: int, grid_mgr) -> int:
	if bld.data != null and bld.data.grow_time > 0.0 and grid_mgr != null:
		# Field building — conditions display only while idle
		if not _field_conditions_active(bld, grid_mgr):
			return need  # growing or harvest-ready = show as satisfied
		var have: int = grid_mgr.get_field_input(bld.origin_cell, res)
		if res == "Water": have += grid_mgr.get_water_bonus(bld.origin_cell)
		return have
	if res == "Water" and grid_mgr != null:
		return grid_mgr.get_water_bonus(bld.origin_cell)
	if bld.is_factory_building():
		return bld.get_input_stock_amount(res)
	return _res_mgr.get_amount(res) if _res_mgr != null else 0

func _make_res_row_ref(icon: String, res_name: String, have: int, need: int) -> Array:
	var ok: bool = have >= need
	var row := PanelContainer.new()
	var row_st := StyleBoxFlat.new()
	row_st.bg_color = Color(0.96, 0.96, 0.96)
	row_st.corner_radius_top_left = 6
	row_st.corner_radius_top_right = 6
	row_st.corner_radius_bottom_left = 6
	row_st.corner_radius_bottom_right = 6
	row.add_theme_stylebox_override("panel", row_st)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	row.add_child(inner)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(5, 28)
	bar.color = Color(0.20, 0.75, 0.35) if ok else Color(0.95, 0.52, 0.18)
	inner.add_child(bar)
	var amt_lbl := Label.new()
	amt_lbl.text = "%d / %d" % [have, need]
	amt_lbl.custom_minimum_size = Vector2(54, 0)
	amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt_lbl.add_theme_font_size_override("font_size", 14)
	amt_lbl.add_theme_color_override("font_color", Color(0.15, 0.12, 0.10))
	inner.add_child(amt_lbl)
	var name_lbl := Label.new()
	name_lbl.text = "  %s %s" % [icon, res_name]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.22, 0.20, 0.18))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(name_lbl)
	return [row, amt_lbl, bar]

func _show_building_popup(bld: Building) -> void:
	_tooltip_world_pos = bld.position + Vector3(0, 2.5, 0)
	_backdrop = _make_backdrop()

	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(270, 0)
	popup.visible = false  # hide until layout computes size, avoids frame-1 misposition
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1.0, 1.0, 1.0, 0.98)
	st.corner_radius_top_left = 14
	st.corner_radius_top_right = 14
	st.corner_radius_bottom_left = 14
	st.corner_radius_bottom_right = 14
	st.shadow_size = 6
	st.shadow_color = Color(0, 0, 0, 0.25)
	st.shadow_offset = Vector2(0, 3)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_active_popup = popup
	await get_tree().process_frame
	if is_instance_valid(popup): popup.visible = true

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	popup.add_child(outer)

	# ── Colored header ──────────────────────────────────────
	var cat_idx: int = bld.data.category if bld.data != null else 0
	var cat_col: Color = CAT_COLOR[cat_idx] if cat_idx < CAT_COLOR.size() else Color(0.35, 0.55, 0.35)
	var hdr := PanelContainer.new()
	var hdr_st := StyleBoxFlat.new()
	hdr_st.bg_color = cat_col
	hdr_st.corner_radius_top_left = 14
	hdr_st.corner_radius_top_right = 14
	hdr.add_theme_stylebox_override("panel", hdr_st)
	outer.add_child(hdr)

	var hdr_mg := MarginContainer.new()
	hdr_mg.add_theme_constant_override("margin_left", 14)
	hdr_mg.add_theme_constant_override("margin_right", 8)
	hdr_mg.add_theme_constant_override("margin_top", 10)
	hdr_mg.add_theme_constant_override("margin_bottom", 10)
	hdr.add_child(hdr_mg)

	var hdr_row := HBoxContainer.new()
	hdr_mg.add_child(hdr_row)

	var hdr_text := VBoxContainer.new()
	hdr_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_text.add_theme_constant_override("separation", 1)
	hdr_row.add_child(hdr_text)

	var name_lbl := Label.new()
	if bld.data != null:
		var lm_n = get_node_or_null("/root/LocaleManager")
		var th_name: String = lm_n.building(bld.data.id) if lm_n != null else ""
		name_lbl.text = th_name if th_name != bld.data.id else bld.data.display_name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	hdr_text.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = _status_text(bld.get_production_status())
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.80))
	hdr_text.add_child(status_lbl)

	# Timer pill — yellow, shows time remaining while producing/growing
	var time_pill := PanelContainer.new()
	var pill_st := StyleBoxFlat.new()
	pill_st.bg_color = Color(0.98, 0.82, 0.18)
	pill_st.corner_radius_top_left = 20
	pill_st.corner_radius_top_right = 20
	pill_st.corner_radius_bottom_left = 20
	pill_st.corner_radius_bottom_right = 20
	time_pill.add_theme_stylebox_override("panel", pill_st)
	time_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_text.add_child(time_pill)
	var pill_mg := MarginContainer.new()
	pill_mg.add_theme_constant_override("margin_left", 10)
	pill_mg.add_theme_constant_override("margin_right", 10)
	pill_mg.add_theme_constant_override("margin_top", 3)
	pill_mg.add_theme_constant_override("margin_bottom", 3)
	time_pill.add_child(pill_mg)
	var time_lbl := Label.new()
	time_lbl.add_theme_font_size_override("font_size", 14)
	time_lbl.add_theme_color_override("font_color", Color(0.15, 0.10, 0.02))
	pill_mg.add_child(time_lbl)

	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.flat = true
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.custom_minimum_size = Vector2(28, 28)
	x_btn.add_theme_color_override("font_color", Color.WHITE)
	x_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.6, 0.6))
	x_btn.pressed.connect(_close_active_popup)
	hdr_row.add_child(x_btn)

	# ── Body ───────────────────────────────────────────────
	var body_mg := MarginContainer.new()
	body_mg.add_theme_constant_override("margin_left", 12)
	body_mg.add_theme_constant_override("margin_right", 12)
	body_mg.add_theme_constant_override("margin_top", 10)
	body_mg.add_theme_constant_override("margin_bottom", 12)
	outer.add_child(body_mg)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body_mg.add_child(body)

	var grid_mgr := get_tree().get_first_node_in_group("grid_manager")

	var active_produces: Dictionary = bld.data.produces if bld.data != null else {}
	var active_consumes: Dictionary = bld.data.consumes if bld.data != null else {}
	if bld.data != null and bld.data.recipes.size() > 0 and bld._current_recipe < bld.data.recipes.size():
		var recipe: Dictionary = bld.data.recipes[bld._current_recipe]
		active_produces = recipe.get("produces", {})
		active_consumes = recipe.get("consumes", {})

	# Description
	if bld.data != null and bld.data.description != "":
		var desc_lbl := Label.new()
		desc_lbl.text = bld.data.description
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.34))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(220, 0)
		body.add_child(desc_lbl)
		body.add_child(_make_thin_sep())

	# Recipe picker — shown when building has multiple selectable recipes
	if bld.data != null and bld.data.recipes.size() > 1:
		var picker_lbl := Label.new()
		picker_lbl.text = "⚙️ เลือกสูตรการผลิต" if not bld._recipe_confirmed else "🔄 เปลี่ยนการผลิต"
		picker_lbl.add_theme_font_size_override("font_size", 12)
		picker_lbl.add_theme_color_override("font_color",
			Color(0.75, 0.30, 0.10) if not bld._recipe_confirmed else Color(0.45, 0.40, 0.34))
		body.add_child(picker_lbl)
		var picker_row := HBoxContainer.new()
		picker_row.add_theme_constant_override("separation", 5)
		body.add_child(picker_row)
		# pending[0] tracks which recipe is highlighted but not yet confirmed
		var pending: Array = [bld._current_recipe]
		var recipe_btns: Array = []
		for ri in bld.data.recipes.size():
			var r: Dictionary = bld.data.recipes[ri]
			var rbtn := Button.new()
			var rname: String = r.get("name", "")
			if rname == "":
				var rp: Dictionary = r.get("produces", {})
				var parts: Array = []
				for res in rp:
					parts.append(RES_ICON.get(res, "") + " " + _res_name(res))
				rname = "  ".join(parts)
			rbtn.text = rname
			rbtn.focus_mode = Control.FOCUS_NONE
			rbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			recipe_btns.append(rbtn)
			picker_row.add_child(rbtn)
		var refresh_recipe_btns := func():
			for bi in recipe_btns.size():
				_style_button(recipe_btns[bi],
					Color(0.18, 0.48, 0.80) if bi == pending[0] else Color(0.72, 0.72, 0.74),
					Color.WHITE)
		for ri in bld.data.recipes.size():
			var cap_ri := ri
			recipe_btns[ri].pressed.connect(func():
				pending[0] = cap_ri
				refresh_recipe_btns.call()
			)
		refresh_recipe_btns.call()
		var confirm_recipe_btn := Button.new()
		confirm_recipe_btn.text = "✓ ยืนยัน"
		confirm_recipe_btn.focus_mode = Control.FOCUS_NONE
		confirm_recipe_btn.custom_minimum_size = Vector2(90, 34)
		_style_button(confirm_recipe_btn, Color(0.18, 0.55, 0.22), Color.WHITE)
		var cap_bld_r := bld
		confirm_recipe_btn.pressed.connect(func():
			if not is_instance_valid(cap_bld_r): return
			cap_bld_r.confirm_recipe(pending[0])
			_show_building_info(cap_bld_r)
		)
		body.add_child(confirm_recipe_btn)
		body.add_child(_make_thin_sep())

	# Produces rows (output info)
	var produce_labels: Dictionary = {}
	for res in active_produces:
		if bld.data != null and bld.data.max_stock > 0:
			var stock: int = bld.get_local_stock_total()
			var ref_result: Array = _make_res_row_ref(RES_ICON.get(res, ""), _res_name(res), stock, bld.data.max_stock)
			body.add_child(ref_result[0])
			produce_labels[res] = {"amt": ref_result[1], "bar": ref_result[2]}
		else:
			var out_lbl := Label.new()
			out_lbl.text = "→  %s %s  ×%d" % [RES_ICON.get(res, ""), _res_name(res), active_produces[res]]
			out_lbl.add_theme_font_size_override("font_size", 14)
			out_lbl.add_theme_color_override("font_color", Color(0.15, 0.42, 0.72))
			body.add_child(out_lbl)

	# Consumes rows — live update (hidden while field is growing)
	var consume_row_refs: Dictionary = {}
	var is_field: bool = bld.data != null and bld.data.grow_time > 0.0
	for res in active_consumes:
		var need: int = active_consumes[res]
		var have: int = _get_res_have(bld, res, need, grid_mgr)
		var ref_result: Array = _make_res_row_ref(RES_ICON.get(res, ""), _res_name(res), have, need)
		body.add_child(ref_result[0])
		if is_field and not _field_conditions_active(bld, grid_mgr):
			ref_result[0].visible = false
		consume_row_refs[res] = {"row": ref_result[0], "amt": ref_result[1], "bar": ref_result[2]}

	# ── Environment effects section ──────────────────────────────────────
	var is_affectable: bool = bld.data != null and bld.data.grow_time > 0.0
	var eff_water_lbl: Label = null
	var eff_shadow_lbl: Label = null
	var eff_pollution_lbl: Label = null
	var eff_speed_lbl: Label = null
	var elec_status_lbl: Label = null

	if is_affectable and grid_mgr != null:
		body.add_child(_make_thin_sep())
		var eff_title := Label.new()
		eff_title.text = "ผลกระทบต่อการผลิต"
		eff_title.add_theme_font_size_override("font_size", 12)
		eff_title.add_theme_color_override("font_color", Color(0.50, 0.45, 0.38))
		body.add_child(eff_title)

		var eff_grid := GridContainer.new()
		eff_grid.columns = 2
		eff_grid.add_theme_constant_override("h_separation", 10)
		eff_grid.add_theme_constant_override("v_separation", 3)
		body.add_child(eff_grid)

		if bld.data.grow_time > 0.0:
			var wk := Label.new()
			wk.text = "💧 น้ำ"
			wk.add_theme_font_size_override("font_size", 13)
			wk.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
			wk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			eff_grid.add_child(wk)
			eff_water_lbl = Label.new()
			eff_water_lbl.add_theme_font_size_override("font_size", 13)
			eff_water_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			eff_grid.add_child(eff_water_lbl)
			_set_eff_lbl(eff_water_lbl, grid_mgr.get_water_bonus(bld.origin_cell), true)

		var sk := Label.new()
		sk.text = "🌑 เงา"
		sk.add_theme_font_size_override("font_size", 13)
		sk.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
		sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_grid.add_child(sk)
		eff_shadow_lbl = Label.new()
		eff_shadow_lbl.add_theme_font_size_override("font_size", 13)
		eff_shadow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		eff_grid.add_child(eff_shadow_lbl)
		_set_eff_lbl(eff_shadow_lbl, grid_mgr.get_shadow_count(bld.origin_cell), false)

		var pk := Label.new()
		pk.text = "☁ มลพิษ"
		pk.add_theme_font_size_override("font_size", 13)
		pk.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
		pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_grid.add_child(pk)
		eff_pollution_lbl = Label.new()
		eff_pollution_lbl.add_theme_font_size_override("font_size", 13)
		eff_pollution_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		eff_grid.add_child(eff_pollution_lbl)
		_set_eff_lbl(eff_pollution_lbl, grid_mgr.get_pollution_count(bld.origin_cell), false)

		var spk := Label.new()
		spk.text = "⏱ ความเร็ว"
		spk.add_theme_font_size_override("font_size", 13)
		spk.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
		spk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff_grid.add_child(spk)
		eff_speed_lbl = Label.new()
		eff_speed_lbl.add_theme_font_size_override("font_size", 13)
		eff_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		eff_grid.add_child(eff_speed_lbl)
		_set_speed_lbl(eff_speed_lbl, grid_mgr.get_production_modifier(bld.origin_cell))

	# ── Electricity status (for buildings that need power) ───────────────
	if bld.data != null and bld.data.electricity_needed > 0 and grid_mgr != null:
		body.add_child(_make_thin_sep())
		var elec_row := HBoxContainer.new()
		elec_row.add_theme_constant_override("separation", 8)
		body.add_child(elec_row)
		var elec_key := Label.new()
		elec_key.text = "⚡ ไฟฟ้า"
		elec_key.add_theme_font_size_override("font_size", 13)
		elec_key.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
		elec_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elec_row.add_child(elec_key)
		elec_status_lbl = Label.new()
		elec_status_lbl.add_theme_font_size_override("font_size", 13)
		elec_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		elec_row.add_child(elec_status_lbl)
		var elec_lvl: int = grid_mgr.get_electricity_count(bld.origin_cell)
		elec_status_lbl.text = "มี (Lv%d)" % elec_lvl if elec_lvl >= bld.data.electricity_needed else "ไม่มี"
		elec_status_lbl.add_theme_color_override("font_color",
			Color(0.10, 0.60, 0.15) if elec_lvl >= bld.data.electricity_needed else Color(0.80, 0.15, 0.10))

	# Storage inventory (warehouse / silo)
	var storage_vbox: VBoxContainer = null
	var storage_filter: Array = STORAGE_FILTER.get(bld.data.id if bld.data != null else "", [])
	if bld.data != null and bld.data.storage_bonus > 0 and _res_mgr != null:
		storage_vbox = VBoxContainer.new()
		storage_vbox.add_theme_constant_override("separation", 4)
		body.add_child(storage_vbox)
		_rebuild_storage_rows(bld, storage_filter, storage_vbox)

	# (growth status shown in header status_lbl — no duplicate label needed)

	# Worker house status
	const WORKER_HOUSE_IDS: Array = ["farm_house", "woodcutter_house", "builder_house"]
	var worker_activity_lbl: Label = null
	var worker_detail_lbl: Label = null
	if bld.data != null and bld.data.id in WORKER_HOUSE_IDS:
		body.add_child(_make_thin_sep())
		var wi: Dictionary = bld.get_worker_info()
		worker_activity_lbl = Label.new()
		worker_activity_lbl.text = "👷 " + wi.get("activity", "")
		worker_activity_lbl.add_theme_font_size_override("font_size", 15)
		worker_activity_lbl.add_theme_color_override("font_color", Color(0.18, 0.25, 0.52))
		body.add_child(worker_activity_lbl)
		worker_detail_lbl = Label.new()
		worker_detail_lbl.text = wi.get("details", "")
		worker_detail_lbl.add_theme_font_size_override("font_size", 13)
		worker_detail_lbl.add_theme_color_override("font_color", Color(0.42, 0.38, 0.32))
		worker_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		worker_detail_lbl.custom_minimum_size = Vector2(220, 0)
		body.add_child(worker_detail_lbl)

	body.add_child(_make_thin_sep())

	# ── Upgrade section ─────────────────────────────────────────────────
	if bld.is_upgradeable() or (bld.data != null and bld.upgrade_level > 0 and bld.data.production_time > 0.0):
		var upg_row := HBoxContainer.new()
		upg_row.add_theme_constant_override("separation", 6)
		body.add_child(upg_row)

		var upg_key := Label.new()
		upg_key.text = "⬆ อัปเกรด"
		upg_key.add_theme_font_size_override("font_size", 13)
		upg_key.add_theme_color_override("font_color", Color(0.30, 0.28, 0.24))
		upg_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upg_row.add_child(upg_key)

		# Level dots: ● filled, ○ empty
		const MAX_LVL: int = 2
		var dots: String = ""
		for di in MAX_LVL:
			dots += ("● " if di < bld.upgrade_level else "○ ")
		var dot_lbl := Label.new()
		dot_lbl.text = dots.strip_edges()
		dot_lbl.add_theme_font_size_override("font_size", 14)
		dot_lbl.add_theme_color_override("font_color", Color(0.20, 0.55, 0.20))
		upg_row.add_child(dot_lbl)

		var speed_pct: String = "%d%%" % int(Building.UPGRADE_SPEED_MULT[bld.upgrade_level] * 100.0)
		var speed_lbl := Label.new()
		speed_lbl.text = "  ×%s" % speed_pct
		speed_lbl.add_theme_font_size_override("font_size", 13)
		speed_lbl.add_theme_color_override("font_color", Color(0.18, 0.48, 0.18))
		upg_row.add_child(speed_lbl)

		if bld.is_upgradeable():
			var upg_btn := Button.new()
			var upg_cost: int = bld.get_upgrade_cost()
			upg_btn.text = "🪙 %d  ↑" % upg_cost
			upg_btn.focus_mode = Control.FOCUS_NONE
			upg_btn.custom_minimum_size = Vector2(90, 30)
			var can_upg: bool = _res_mgr != null and _res_mgr.get_amount("Gold") >= upg_cost
			if can_upg:
				_style_button(upg_btn, Color(0.55, 0.35, 0.02), Color.WHITE)
			else:
				upg_btn.disabled = true
				var ds2 := StyleBoxFlat.new()
				ds2.bg_color = Color(0.55, 0.53, 0.50)
				ds2.corner_radius_top_left = 5
				ds2.corner_radius_top_right = 5
				ds2.corner_radius_bottom_left = 5
				ds2.corner_radius_bottom_right = 5
				upg_btn.add_theme_stylebox_override("normal", ds2)
				upg_btn.add_theme_stylebox_override("disabled", ds2)
				upg_btn.add_theme_color_override("font_color", Color(0.78, 0.76, 0.74))
				upg_btn.add_theme_color_override("font_disabled_color", Color(0.78, 0.76, 0.74))
			upg_btn.add_theme_font_size_override("font_size", 13)
			var bld_upg := bld
			upg_btn.pressed.connect(func():
				if not is_instance_valid(bld_upg): return
				if bld_upg.perform_upgrade():
					_show_building_info(bld_upg)
				else:
					_show_notify("ทองไม่พอ! ต้องการ 🪙%d" % bld_upg.get_upgrade_cost())
			)
			upg_row.add_child(upg_btn)

		body.add_child(_make_thin_sep())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	body.add_child(btn_row)

	# Rotate button
	var bld_ref := bld
	var rot_btn := Button.new()
	rot_btn.text = "🔄 หมุน"
	rot_btn.focus_mode = Control.FOCUS_NONE
	rot_btn.custom_minimum_size = Vector2(90, 36)
	_style_button(rot_btn, Color(0.18, 0.42, 0.75), Color.WHITE)
	rot_btn.pressed.connect(func():
		if not is_instance_valid(bld_ref): return
		bld_ref.facing = (bld_ref.facing + 1) % 4
		bld_ref.rotation_degrees.y = bld_ref.facing * 90.0
		_show_building_info(bld_ref)
	)
	btn_row.add_child(rot_btn)

	var refund: int = bld.data.build_cost.get("Gold", 0) / 2 if bld.data != null else 0
	var rem_btn := Button.new()
	rem_btn.text = "💣 ทุบ  +%d🪙" % refund
	rem_btn.focus_mode = Control.FOCUS_NONE
	rem_btn.custom_minimum_size = Vector2(120, 36)
	_style_button(rem_btn, Color(0.72, 0.16, 0.10), Color.WHITE)
	rem_btn.pressed.connect(func(): _on_demolish_building(bld))
	btn_row.add_child(rem_btn)

	# Init timer pill on open
	var gm_init = get_tree().get_first_node_in_group("grid_manager")
	var t_init: float = 0.0
	if bld.data != null and bld.data.grow_time > 0.0 and gm_init != null:
		t_init = gm_init.get_field_remaining(bld.origin_cell)
	else:
		t_init = bld.get_time_remaining()
	var ts_init: String = _format_time(t_init)
	var init_status: String = bld.get_production_status()
	var show_init: bool = init_status == "Producing" or init_status.begins_with("🌱 Growing")
	time_lbl.text = "🕐  " + ts_init
	time_pill.visible = ts_init != "" and show_init

	# Live refresh timer
	var refresh := Timer.new()
	refresh.wait_time = 0.5
	refresh.autostart = true
	refresh.timeout.connect(func():
		if not is_instance_valid(bld): return
		var cur_status: String = bld.get_production_status()
		if is_instance_valid(status_lbl): status_lbl.text = _status_text(cur_status)
		# Update timer pill
		var gm_ref = get_tree().get_first_node_in_group("grid_manager")
		if is_instance_valid(time_pill) and is_instance_valid(time_lbl):
			var t_left: float = 0.0
			if bld.data != null and bld.data.grow_time > 0.0 and gm_ref != null:
				t_left = gm_ref.get_field_remaining(bld.origin_cell)
			else:
				t_left = bld.get_time_remaining()
			var ts: String = _format_time(t_left)
			var show_pill: bool = cur_status == "Producing" or cur_status.begins_with("🌱 Growing")
			time_lbl.text = "🕐  " + ts
			time_pill.visible = ts != "" and show_pill
		var show_conditions: bool = not is_field or _field_conditions_active(bld, gm_ref)
		for res in consume_row_refs:
			var refs: Dictionary = consume_row_refs[res]
			if is_instance_valid(refs["row"]): refs["row"].visible = show_conditions
			if not show_conditions: continue
			var need: int = active_consumes.get(res, 0)
			var have: int = _get_res_have(bld, res, need, grid_mgr)
			var ok: bool = have >= need
			if is_instance_valid(refs["amt"]): refs["amt"].text = "%d / %d" % [have, need]
			if is_instance_valid(refs["bar"]): refs["bar"].color = Color(0.20, 0.75, 0.35) if ok else Color(0.95, 0.52, 0.18)
		for res in produce_labels:
			var refs: Dictionary = produce_labels[res]
			var stock: int = bld.get_local_stock_total()
			var max_s: int = bld.data.max_stock if bld.data != null else 0
			var ok: bool = stock >= max_s
			if is_instance_valid(refs["amt"]): refs["amt"].text = "%d / %d" % [stock, max_s]
			if is_instance_valid(refs["bar"]): refs["bar"].color = Color(0.20, 0.75, 0.35) if ok else Color(0.95, 0.52, 0.18)
		if is_affectable and gm_ref != null:
			if eff_water_lbl != null and is_instance_valid(eff_water_lbl):
				_set_eff_lbl(eff_water_lbl, gm_ref.get_water_bonus(bld.origin_cell), true)
			if eff_shadow_lbl != null and is_instance_valid(eff_shadow_lbl):
				_set_eff_lbl(eff_shadow_lbl, gm_ref.get_shadow_count(bld.origin_cell), false)
			if eff_pollution_lbl != null and is_instance_valid(eff_pollution_lbl):
				_set_eff_lbl(eff_pollution_lbl, gm_ref.get_pollution_count(bld.origin_cell), false)
			if eff_speed_lbl != null and is_instance_valid(eff_speed_lbl):
				_set_speed_lbl(eff_speed_lbl, gm_ref.get_production_modifier(bld.origin_cell))
		if elec_status_lbl != null and is_instance_valid(elec_status_lbl) and gm_ref != null and bld.data != null:
			var elec_lvl: int = gm_ref.get_electricity_count(bld.origin_cell)
			var has_power: bool = elec_lvl >= bld.data.electricity_needed
			elec_status_lbl.text = "มี (Lv%d)" % elec_lvl if has_power else "ไม่มี"
			elec_status_lbl.add_theme_color_override("font_color",
				Color(0.10, 0.60, 0.15) if has_power else Color(0.80, 0.15, 0.10))
		if storage_vbox != null and is_instance_valid(storage_vbox): _rebuild_storage_rows(bld, storage_filter, storage_vbox)
		if worker_activity_lbl != null and is_instance_valid(worker_activity_lbl):
			var wi: Dictionary = bld.get_worker_info()
			worker_activity_lbl.text = "👷 " + wi.get("activity", "")
			if worker_detail_lbl != null and is_instance_valid(worker_detail_lbl):
				worker_detail_lbl.text = wi.get("details", "")
	)
	popup.add_child(refresh)

# ── Production status bubbles ──────────────────────────────────────────

func _setup_prod_overlays() -> void:
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_scan_prod_overlays)
	add_child(t)

func _format_time(secs: float) -> String:
	var s: int = ceili(secs)
	if s <= 0: return ""
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s

func _prod_overlay_status(bld: Building) -> String:
	if bld.data == null: return ""
	if bld.data.grow_time > 0.0:
		var gm = get_tree().get_first_node_in_group("grid_manager")
		if gm != null and gm.is_field_growing(bld.origin_cell):
			var crop: String = bld.data.produces.keys()[0] if not bld.data.produces.is_empty() else ""
			return "🌱 %s %s" % [RES_ICON.get(crop, ""), _res_name(crop)]
	if bld.data.production_time > 0.0 and bld.get_production_status() == "Producing":
		var active_p: Dictionary = bld.data.produces
		if bld.data.recipes.size() > 0:
			var rec: Dictionary = bld.data.recipes[bld._current_recipe % bld.data.recipes.size()]
			active_p = rec.get("produces", {})
		var out: String = active_p.keys()[0] if not active_p.is_empty() else ""
		return "⚙️ %s %s" % [RES_ICON.get(out, ""), _res_name(out)]
	return ""

func _scan_prod_overlays() -> void:
	if _gm == null: return
	var grid := get_tree().get_first_node_in_group("grid_manager")
	if grid == null: return
	var seen: Array = []
	for cell in grid._buildings:
		var node = grid._buildings[cell]
		if not (node is Building): continue
		var bld: Building = node as Building
		if seen.has(bld): continue
		seen.append(bld)
		if bld == _selected_building: continue
		var sub: String = _prod_overlay_status(bld)
		if sub == "":
			_remove_prod_overlay(bld)
			continue
		var gm = get_tree().get_first_node_in_group("grid_manager")
		var t_left: float = 0.0
		if bld.data != null and bld.data.grow_time > 0.0 and gm != null:
			t_left = gm.get_field_remaining(bld.origin_cell)
		else:
			t_left = bld.get_time_remaining()
		if not _prod_overlays.has(bld) or not is_instance_valid(_prod_overlays[bld]["panel"]):
			_prod_overlays[bld] = _make_prod_overlay(bld.data.display_name, sub, t_left)
		else:
			var refs: Dictionary = _prod_overlays[bld]
			if is_instance_valid(refs["sub_lbl"]): refs["sub_lbl"].text = sub
			if is_instance_valid(refs["time_lbl"]):
				var ts: String = _format_time(t_left)
				refs["time_lbl"].text = "🕐  " + ts if ts != "" else ""
				refs["time_pill"].visible = ts != ""
	# Remove overlays for buildings no longer tracked
	for bld in _prod_overlays.keys():
		if not is_instance_valid(bld) or not seen.has(bld):
			_remove_prod_overlay(bld)

func _remove_prod_overlay(bld) -> void:
	if _prod_overlays.has(bld):
		var refs: Dictionary = _prod_overlays[bld]
		if is_instance_valid(refs.get("panel")):
			refs["panel"].queue_free()
		_prod_overlays.erase(bld)

func _make_prod_overlay(bld_name: String, subtitle: String, time_left: float) -> Dictionary:
	var panel := PanelContainer.new()
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(1.0, 1.0, 1.0, 0.92)
	pst.corner_radius_top_left = 10
	pst.corner_radius_top_right = 10
	pst.corner_radius_bottom_left = 10
	pst.corner_radius_bottom_right = 10
	pst.shadow_size = 5
	pst.shadow_color = Color(0, 0, 0, 0.22)
	pst.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", pst)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 12)
	mg.add_theme_constant_override("margin_right", 12)
	mg.add_theme_constant_override("margin_top", 8)
	mg.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(mg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	mg.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = bld_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.10, 0.08, 0.06))
	vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.50, 0.47, 0.44))
	vbox.add_child(sub_lbl)

	# Yellow timer pill
	var time_pill := PanelContainer.new()
	var pill_st := StyleBoxFlat.new()
	pill_st.bg_color = Color(0.98, 0.82, 0.18)
	pill_st.corner_radius_top_left = 20
	pill_st.corner_radius_top_right = 20
	pill_st.corner_radius_bottom_left = 20
	pill_st.corner_radius_bottom_right = 20
	time_pill.add_theme_stylebox_override("panel", pill_st)
	vbox.add_child(time_pill)

	var pill_mg := MarginContainer.new()
	pill_mg.add_theme_constant_override("margin_left", 10)
	pill_mg.add_theme_constant_override("margin_right", 10)
	pill_mg.add_theme_constant_override("margin_top", 3)
	pill_mg.add_theme_constant_override("margin_bottom", 3)
	time_pill.add_child(pill_mg)

	var time_lbl := Label.new()
	var ts: String = _format_time(time_left)
	time_lbl.text = "🕐  " + ts if ts != "" else ""
	time_lbl.add_theme_font_size_override("font_size", 15)
	time_lbl.add_theme_color_override("font_color", Color(0.18, 0.12, 0.02))
	pill_mg.add_child(time_lbl)
	time_pill.visible = ts != ""

	return {"panel": panel, "name_lbl": name_lbl, "sub_lbl": sub_lbl,
			"time_lbl": time_lbl, "time_pill": time_pill}

func _make_res_chip(icon: String, amount_text: String, bg: Color) -> Control:
	var pc := PanelContainer.new()
	var chip_st := StyleBoxFlat.new()
	chip_st.bg_color = bg
	chip_st.corner_radius_top_left = 16
	chip_st.corner_radius_top_right = 16
	chip_st.corner_radius_bottom_left = 16
	chip_st.corner_radius_bottom_right = 16
	pc.add_theme_stylebox_override("panel", chip_st)
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 8)
	inner.add_theme_constant_override("margin_right", 8)
	inner.add_theme_constant_override("margin_top", 4)
	inner.add_theme_constant_override("margin_bottom", 4)
	pc.add_child(inner)
	var lbl := Label.new()
	lbl.text = "%s %s" % [icon, amount_text]
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.10, 0.08, 0.15))
	inner.add_child(lbl)
	return pc

func _format_storage_text(filter: Array = []) -> String:
	if _res_mgr == null:
		return "📦 Empty"
	var used: int = _res_mgr.get_total_stored()
	var parts: Array = []
	var res_list: Array = filter if filter.size() > 0 else RESOURCE_DISPLAY
	for res in res_list:
		if res == "Gold":
			continue
		var amt: int = _res_mgr.get_amount(res)
		if amt > 0:
			parts.append("%s%s×%d" % [RES_ICON.get(res, ""), _res_name(res), amt])
	var header: String = "📦 %d/%d" % [used, _res_mgr.get_amount("Gold")]
	if parts.is_empty():
		return header + "\nEmpty"
	return header + "\n" + "  ".join(parts)

func _rebuild_storage_rows(bld, filter: Array, container: VBoxContainer) -> void:
	for c in container.get_children():
		c.queue_free()
	if not is_instance_valid(bld):
		return
	var cap: int = 0
	if bld.data != null:
		cap = bld.data.storage_bonus if bld.data.storage_bonus > 0 else bld.data.max_stock
	var used: int = bld.get_local_stock_total()
	var header_lbl := Label.new()
	header_lbl.text = "📦 %d/%d ช่อง" % [used, cap]
	header_lbl.add_theme_font_size_override("font_size", 14)
	header_lbl.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18))
	container.add_child(header_lbl)
	var res_list: Array = filter if filter.size() > 0 else RESOURCE_DISPLAY
	var has_any: bool = false
	for res in res_list:
		if res == "Gold": continue
		var amt: int = bld._local_stock.get(res, 0)
		if amt <= 0: continue
		has_any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_lbl := Label.new()
		name_lbl.text = "%s %s" % [RES_ICON.get(res, ""), _res_name(res)]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var amt_lbl := Label.new()
		amt_lbl.text = "×%d" % amt
		amt_lbl.add_theme_font_size_override("font_size", 13)
		amt_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.32))
		row.add_child(amt_lbl)
		var del_btn := Button.new()
		del_btn.text = "🗑"
		del_btn.flat = true
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(28, 24)
		var bld_ref: Node = bld
		var res_key: String = res
		var vbox_ref: VBoxContainer = container
		var filter_ref: Array = filter
		del_btn.pressed.connect(func():
			if not is_instance_valid(bld_ref): return
			bld_ref._local_stock.erase(res_key)
			bld_ref._update_stock_label()
			if is_instance_valid(vbox_ref):
				_rebuild_storage_rows(bld_ref, filter_ref, vbox_ref)
		)
		row.add_child(del_btn)
		container.add_child(row)
	if not has_any:
		var empty_lbl := Label.new()
		empty_lbl.text = "— ว่างเปล่า —"
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.55, 0.48))
		container.add_child(empty_lbl)

func _format_storage_text_bld(bld, filter: Array = []) -> String:
	if bld == null or not is_instance_valid(bld):
		return "📦 Empty"
	var cap: int = 0
	if bld.data != null:
		cap = bld.data.storage_bonus if bld.data.storage_bonus > 0 else bld.data.max_stock
	var used: int = bld.get_local_stock_total()
	var parts: Array = []
	var res_list: Array = filter if filter.size() > 0 else RESOURCE_DISPLAY
	for res in res_list:
		if res == "Gold":
			continue
		var amt: int = bld._local_stock.get(res, 0)
		if amt > 0:
			parts.append("%s%s×%d" % [RES_ICON.get(res, ""), _res_name(res), amt])
	var header: String = "📦 %d/%d" % [used, cap]
	if parts.is_empty():
		return header + "\nEmpty"
	return header + "\n" + "  ".join(parts)

func _set_eff_lbl(lbl: Label, value: int, positive_good: bool) -> void:
	if positive_good:
		if value > 0:
			lbl.text = "+%d" % value
			lbl.add_theme_color_override("font_color", Color(0.15, 0.60, 0.28))
		else:
			lbl.text = "–"
			lbl.add_theme_color_override("font_color", Color(0.60, 0.55, 0.48))
	else:
		if value > 0:
			lbl.text = "-%d" % value
			lbl.add_theme_color_override("font_color", Color(0.80, 0.30, 0.14))
		else:
			lbl.text = "–"
			lbl.add_theme_color_override("font_color", Color(0.60, 0.55, 0.48))

func _set_speed_lbl(lbl: Label, modifier: float) -> void:
	if modifier <= 1.0:
		lbl.text = "ปกติ"
		lbl.add_theme_color_override("font_color", Color(0.15, 0.60, 0.28))
	else:
		lbl.text = "ช้า %.0f×" % modifier
		lbl.add_theme_color_override("font_color", Color(0.80, 0.20, 0.10))

func _make_thin_sep() -> Control:
	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(0, 1)
	var sep_st := StyleBoxFlat.new()
	sep_st.bg_color = Color(0.78, 0.75, 0.70)
	sep.add_theme_stylebox_override("panel", sep_st)
	return sep

func _on_demolish_building(bld: Building) -> void:
	_hide_action_bar()
	_close_active_popup()
	var grid_mgr := get_tree().get_first_node_in_group("grid_manager") as GridManager
	if grid_mgr == null or bld == null or not is_instance_valid(bld):
		return
	var refund: int = 0
	if bld.data != null:
		refund = bld.data.build_cost.get("Gold", 0) / 2
	grid_mgr.remove_building_at(bld.origin_cell)
	if _res_mgr != null and refund > 0:
		_res_mgr.add_resource("Gold", refund)
		_show_notify("รื้อถอนแล้ว! ได้คืน +%d🪙" % refund)
	else:
		_show_notify("รื้อถอนแล้ว")

func _on_empty_cell_clicked() -> void:
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.set_selected(false)
	_selected_building = null
	_close_active_popup()
	_hide_action_bar()

func _on_grass_cell_clicked(cell: Vector2i) -> void:
	_close_active_popup()
	_hide_action_bar()
	var gm := get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm == null:
		return
	var wp := gm.cell_to_world(cell)
	_cell_popup_world_pos = Vector3(wp.x + GridManager.CELL_SIZE * 0.5, 2.8, wp.z + GridManager.CELL_SIZE * 0.5)

	var popup := PanelContainer.new()
	popup.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	st.corner_radius_top_left = 12
	st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12
	st.corner_radius_bottom_right = 12
	st.shadow_size = 5
	st.shadow_color = Color(0, 0, 0, 0.22)
	st.shadow_offset = Vector2(0, 2)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_cell_popup = popup

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 14)
	mg.add_theme_constant_override("margin_right", 14)
	mg.add_theme_constant_override("margin_top", 10)
	mg.add_theme_constant_override("margin_bottom", 10)
	popup.add_child(mg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	mg.add_child(vbox)

	var title := Label.new()
	title.text = "🌿 ที่ดินว่าง"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.18, 0.38, 0.12))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var build_btn := Button.new()
	build_btn.text = "🏗️  สร้าง"
	build_btn.custom_minimum_size = Vector2(130, 38)
	build_btn.focus_mode = Control.FOCUS_NONE
	_style_button(build_btn, Color(0.18, 0.52, 0.18), Color.WHITE)
	build_btn.pressed.connect(func() -> void:
		_close_cell_popup()
		_on_store_toggle()
	)
	vbox.add_child(build_btn)

	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.visible = true

func _on_road_cell_clicked(cell: Vector2i) -> void:
	_close_active_popup()
	_hide_action_bar()
	var gm := get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm == null:
		return
	var wp := gm.cell_to_world(cell)
	_cell_popup_world_pos = Vector3(wp.x + GridManager.CELL_SIZE * 0.5, 2.8, wp.z + GridManager.CELL_SIZE * 0.5)

	var terrain := gm.get_terrain(cell)
	var is_paved: bool = (terrain == GridManager.Terrain.PAVED_ROAD)

	var popup := PanelContainer.new()
	popup.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	st.corner_radius_top_left = 12
	st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12
	st.corner_radius_bottom_right = 12
	st.shadow_size = 5
	st.shadow_color = Color(0, 0, 0, 0.22)
	st.shadow_offset = Vector2(0, 2)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_cell_popup = popup

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 14)
	mg.add_theme_constant_override("margin_right", 14)
	mg.add_theme_constant_override("margin_top", 10)
	mg.add_theme_constant_override("margin_bottom", 10)
	popup.add_child(mg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	mg.add_child(vbox)

	var title := Label.new()
	title.text = "🛤️ ถนนลาดยาง" if is_paved else "🛤️ ถนนดิน"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.28, 0.22, 0.10))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var demo_btn := Button.new()
	demo_btn.text = "🔨  รื้อถนน"
	demo_btn.custom_minimum_size = Vector2(130, 38)
	demo_btn.focus_mode = Control.FOCUS_NONE
	_style_button(demo_btn, Color(0.72, 0.20, 0.10), Color.WHITE)
	demo_btn.pressed.connect(func() -> void:
		gm.remove_road_at(cell)
		_close_cell_popup()
		_show_notify("รื้อถนนแล้ว")
	)
	vbox.add_child(demo_btn)

	await get_tree().process_frame
	if is_instance_valid(popup):
		popup.visible = true

func _on_forest_cell_clicked(cell: Vector2i) -> void:
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.set_selected(false)
	_selected_building = null
	_close_active_popup()
	_hide_action_bar()

	var gm := get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm == null:
		return
	var info: Dictionary = gm.get_tree_harvest_info(cell)
	if info.is_empty():
		return

	var is_big: bool = info.get("is_big", false)
	var remaining: int = info.get("remaining", 0)
	var max_h: int = info.get("max", 0)

	_backdrop = _make_backdrop()

	var popup := PanelContainer.new()
	popup.position = Vector2(10, 68)
	popup.custom_minimum_size = Vector2(260, 0)

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.96, 0.92, 0.98)
	st.corner_radius_top_left = 14
	st.corner_radius_top_right = 14
	st.corner_radius_bottom_left = 14
	st.corner_radius_bottom_right = 14
	st.border_width_left = 5
	st.border_color = Color(0.18, 0.42, 0.12)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_active_popup = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🌲 Large Tree" if is_big else "🌳 Small Tree"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.10, 0.30, 0.08))
	vbox.add_child(title)

	# Row showing remaining harvest count
	var harvest_row := HBoxContainer.new()
	harvest_row.add_theme_constant_override("separation", 6)
	vbox.add_child(harvest_row)

	var harvest_lbl := Label.new()
	harvest_lbl.text = "🪓 Harvests left  %d / %d" % [remaining, max_h]
	harvest_lbl.add_theme_font_size_override("font_size", 16)
	harvest_lbl.add_theme_color_override("font_color", Color(0.38, 0.25, 0.08))
	harvest_row.add_child(harvest_lbl)

	# Update harvest count real-time every 0.5 seconds
	var harvest_refresh := Timer.new()
	harvest_refresh.wait_time = 0.5
	harvest_refresh.autostart = true
	harvest_refresh.timeout.connect(func():
		if not is_instance_valid(harvest_lbl): return
		var updated_info: Dictionary = gm.get_tree_harvest_info(cell)
		if updated_info.is_empty(): harvest_lbl.text = "🪓 All harvested"
		if updated_info.is_empty(): return
		harvest_lbl.text = "🪓 Harvests left  %d / %d" % [updated_info.get("remaining", 0), updated_info.get("max", max_h)]
	)
	popup.add_child(harvest_refresh)

	var sub := Label.new()
	sub.text = "Must be cleared before building"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.42, 0.30))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(220, 0)
	vbox.add_child(sub)

	vbox.add_child(_make_thin_sep())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var clear_cost: int = 20 if is_big else 10
	var clear_btn := Button.new()
	clear_btn.text = "🪓 โค่นทิ้ง  %d 🪙" % clear_cost
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.custom_minimum_size = Vector2(160, 38)
	_style_button(clear_btn, Color(0.48, 0.26, 0.08), Color.WHITE)
	var cap_cell_f := cell
	var cap_cost_f := clear_cost
	clear_btn.pressed.connect(func():
		var rm_f = get_node_or_null("/root/ResourceManager")
		if rm_f == null or not rm_f.has_resources({"Gold": cap_cost_f}):
			_show_notify("⚠ ทองไม่พอ")
			return
		rm_f.remove_resource("Gold", cap_cost_f)
		var gm_f := get_tree().get_first_node_in_group("grid_manager") as GridManager
		if gm_f != null: gm_f.clear_tree_immediately(cap_cell_f)
		_close_active_popup()
	)
	btn_row.add_child(clear_btn)

	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.custom_minimum_size = Vector2(38, 38)
	_style_button(x_btn, Color(0.60, 0.58, 0.54), Color.WHITE)
	x_btn.pressed.connect(_close_active_popup)
	btn_row.add_child(x_btn)

func _on_pond_cell_clicked(cell: Vector2i) -> void:
	_close_active_popup()
	_hide_action_bar()
	var gm := get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm == null:
		return
	var origin: Vector2i = gm.get_pond_at(cell)
	if origin == Vector2i(-1, -1):
		return
	var coverage: int = int(gm._pond_origins.get(origin, 1))
	var cost: int = 15 if coverage == 1 else 30
	_show_clear_pond_popup(origin, cost)

func _show_clear_pond_popup(origin: Vector2i, cost: int) -> void:
	_backdrop = _make_backdrop()

	var popup := PanelContainer.new()
	popup.position = Vector2(10, 68)
	popup.custom_minimum_size = Vector2(270, 0)

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.96, 0.92, 0.98)
	st.corner_radius_top_left = 14
	st.corner_radius_top_right = 14
	st.corner_radius_bottom_left = 14
	st.corner_radius_bottom_right = 14
	st.border_width_left = 5
	st.border_color = Color(0.25, 0.55, 0.85)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_active_popup = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ล้างบ่อน้ำ?"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "บ่อน้ำจะถูกเอาออก สามารถสร้างอาคารได้"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.42, 0.40, 0.38))
	vbox.add_child(sub)

	vbox.add_child(_make_thin_sep())

	# Cost chip
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cost_row)
	cost_row.add_child(_make_res_chip("🪙", "%d" % cost, Color(0.98, 0.90, 0.62)))

	vbox.add_child(_make_thin_sep())

	# Yes / No buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = "ยืนยัน"
	yes_btn.focus_mode = Control.FOCUS_NONE
	yes_btn.custom_minimum_size = Vector2(110, 42)
	_style_button(yes_btn, Color(0.18, 0.52, 0.18), Color.WHITE)
	yes_btn.pressed.connect(func():
		var can: bool = _res_mgr != null and _res_mgr.can_afford({"Gold": cost})
		if not can: _close_active_popup()
		if not can: _show_notify("ทองไม่พอ! ต้องการ %d🪙" % cost)
		if not can: return
		_res_mgr.pay({"Gold": cost})
		var gm := get_tree().get_first_node_in_group("grid_manager") as GridManager
		if gm != null: gm.clear_pond(origin)
		_close_active_popup()
		_show_notify("เคลียร์บ่อแล้ว!")
	)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "ยกเลิก"
	no_btn.focus_mode = Control.FOCUS_NONE
	no_btn.custom_minimum_size = Vector2(110, 42)
	_style_button(no_btn, Color(0.72, 0.16, 0.10), Color.WHITE)
	no_btn.pressed.connect(_close_active_popup)
	btn_row.add_child(no_btn)

func _on_recipe_select(bld: Building, recipe_index: int) -> void:
	bld._current_recipe = recipe_index
	_show_building_info(bld)

func _make_backdrop() -> Control:
	var bd := Control.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_STOP
	bd.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed: _close_active_popup()
	)
	add_child(bd)
	return bd

func _close_cell_popup() -> void:
	if _cell_popup != null and is_instance_valid(_cell_popup):
		_cell_popup.queue_free()
	_cell_popup = null
	for bp in get_tree().get_nodes_in_group("building_placer"):
		if bp.has_method("hide_selection"):
			bp.hide_selection()

func _close_active_popup() -> void:
	_close_cell_popup()
	if _active_popup != null and is_instance_valid(_active_popup):
		_active_popup.queue_free()
	_active_popup = null
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = null
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.set_selected(false)
	_selected_building = null

# --- Trade UI ---

func _show_garage_sell_ui(garage_bld: Building) -> void:
	_close_active_popup()

	var om: Node = get_node_or_null("/root/OrderManager")
	if om == null:
		_show_notify("ระบบคำสั่งซื้อไม่พร้อม")
		return

	var gm = get_tree().get_first_node_in_group("grid_manager")
	var gas_have: int = _res_mgr.get_amount("Gasoline") if _res_mgr != null else 0

	_backdrop = _make_backdrop()
	var popup := PanelContainer.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	popup.custom_minimum_size = Vector2(360, 0)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.97, 0.95, 0.91, 0.98)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.border_width_top = 3
	panel_style.border_color = Color(0.75, 0.44, 0.08)
	popup.add_theme_stylebox_override("panel", panel_style)
	add_child(popup)
	_active_popup = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# --- Header row: title + gasoline counter ---
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var title_lbl := Label.new()
	title_lbl.text = "🚚  โรงรถ — คำสั่งซื้อ"
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", Color(0.22, 0.14, 0.04))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_lbl)

	var gas_col: Color = Color(0.60, 0.32, 0.04) if gas_have >= 1 else Color(0.72, 0.12, 0.08)
	var gas_badge := Label.new()
	gas_badge.text = "⛽ ×%d" % gas_have
	gas_badge.add_theme_font_size_override("font_size", 13)
	gas_badge.add_theme_color_override("font_color", gas_col)
	header_row.add_child(gas_badge)

	# Divider
	var hdiv := ColorRect.new()
	hdiv.color = Color(0.75, 0.44, 0.08, 0.28)
	hdiv.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(hdiv)

	# --- 3 Order cards ---
	var slots: Array = om.get_slots()
	var stock: Dictionary = om.get_available_stock(gm)

	var time_labels: Array = []
	var send_buttons: Array = []

	for i in 3:
		var card_data: Dictionary = _make_order_card(i, slots[i], stock, gas_have, garage_bld, om)
		vbox.add_child(card_data["panel"])
		time_labels.append(card_data["time_lbl"])
		send_buttons.append(card_data["send_btn"])

	# --- Tick timer: update countdowns + button states every 1s ---
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	popup.add_child(tick)
	tick.timeout.connect(func():
		if not is_instance_valid(popup):
			return
		var cur_slots: Array = om.get_slots()
		var new_gas: int = _res_mgr.get_amount("Gasoline") if _res_mgr != null else 0
		var new_stock: Dictionary = om.get_available_stock(gm)
		for j in 3:
			var secs: int = int(cur_slots[j]["remaining"])
			time_labels[j].text = "⏱ %d:%02d" % [secs / 60, secs % 60]
			var can_f: bool = om.can_fulfill(j, new_stock)
			send_buttons[j].disabled = not (can_f and new_gas >= 1)
	)

	# Close popup when an order auto-rotates (order expired mid-session)
	var _on_changed: Callable
	_on_changed = func():
		if is_instance_valid(popup):
			_close_active_popup()
			_show_notify("คำสั่งซื้อเปลี่ยนแปลง!")
	om.orders_changed.connect(_on_changed, CONNECT_ONE_SHOT)
	popup.tree_exiting.connect(func():
		if om.orders_changed.is_connected(_on_changed):
			om.orders_changed.disconnect(_on_changed)
	)

	# --- Bottom row: close + demolish ---
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom_row)

	var close_btn := Button.new()
	close_btn.text = "ปิด"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.custom_minimum_size = Vector2(0, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	_style_button(close_btn, Color(0.46, 0.46, 0.50), Color.WHITE)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(_close_active_popup)
	bottom_row.add_child(close_btn)

	var refund: int = garage_bld.data.build_cost.get("Gold", 0) / 2 if garage_bld.data != null else 0
	var demolish_btn := Button.new()
	demolish_btn.text = "💣 ทุบ  +%d🪙" % refund
	demolish_btn.custom_minimum_size = Vector2(120, 34)
	demolish_btn.focus_mode = Control.FOCUS_NONE
	_style_button(demolish_btn, Color(0.58, 0.12, 0.08), Color.WHITE)
	demolish_btn.add_theme_font_size_override("font_size", 13)
	demolish_btn.pressed.connect(func(): _on_demolish_building(garage_bld))
	bottom_row.add_child(demolish_btn)


func _make_order_card(idx: int, slot: Dictionary, stock: Dictionary,
		gas_have: int, garage_bld: Building, om: Node) -> Dictionary:
	const TIER_COLORS: Array = [
		Color(0.18, 0.52, 0.18),
		Color(0.70, 0.38, 0.04),
		Color(0.44, 0.10, 0.56),
	]
	var tier: int = slot.get("tier", 1)
	var border_col: Color = TIER_COLORS[clampi(tier - 1, 0, 2)]
	var can_fulfill: bool = om.can_fulfill(idx, stock)
	var can_send: bool = can_fulfill and gas_have >= 1

	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.93, 0.90, 0.86)
	cs.corner_radius_top_left = 7
	cs.corner_radius_top_right = 7
	cs.corner_radius_bottom_left = 7
	cs.corner_radius_bottom_right = 7
	cs.border_width_left = 3
	cs.border_color = border_col
	card.add_theme_stylebox_override("panel", cs)

	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 10)
	cm.add_theme_constant_override("margin_right", 10)
	cm.add_theme_constant_override("margin_top", 8)
	cm.add_theme_constant_override("margin_bottom", 8)
	card.add_child(cm)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	cm.add_child(cv)

	# Top row: tier badge + countdown
	var top_row := HBoxContainer.new()
	cv.add_child(top_row)

	var tier_lbl := Label.new()
	tier_lbl.text = "Tier %d" % tier
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", border_col)
	tier_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(tier_lbl)

	var secs: int = int(slot.get("remaining", 0.0))
	var time_lbl := Label.new()
	time_lbl.text = "⏱ %d:%02d" % [secs / 60, secs % 60]
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.add_theme_color_override("font_color", Color(0.40, 0.30, 0.10))
	top_row.add_child(time_lbl)

	# Time progress bar
	var pbar := ProgressBar.new()
	pbar.custom_minimum_size = Vector2(0, 4)
	pbar.max_value = slot.get("ttl", 90.0)
	pbar.value = slot.get("remaining", 0.0)
	pbar.show_percentage = false
	cv.add_child(pbar)

	# Goods list
	for res in slot["goods"]:
		var qty_need: int = slot["goods"][res]
		var qty_have: int = stock.get(res, 0)
		var enough: bool = qty_have >= qty_need

		var grow := HBoxContainer.new()
		cv.add_child(grow)

		var icon_lbl := Label.new()
		icon_lbl.text = "%s %s" % [RES_ICON.get(res, "📦"), _res_name(res)]
		icon_lbl.add_theme_font_size_override("font_size", 13)
		icon_lbl.add_theme_color_override("font_color", Color(0.18, 0.12, 0.06))
		icon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grow.add_child(icon_lbl)

		var qty_lbl := Label.new()
		qty_lbl.text = "×%d" % qty_need
		qty_lbl.add_theme_font_size_override("font_size", 13)
		qty_lbl.add_theme_color_override("font_color", Color(0.18, 0.12, 0.06))
		grow.add_child(qty_lbl)

		var have_lbl := Label.new()
		have_lbl.text = "  (%d)" % qty_have
		have_lbl.add_theme_font_size_override("font_size", 11)
		have_lbl.add_theme_color_override("font_color",
			Color(0.12, 0.48, 0.12) if enough else Color(0.70, 0.12, 0.08))
		grow.add_child(have_lbl)

	# Reward + send button row
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 6)
	cv.add_child(bot_row)

	var reward_lbl := Label.new()
	reward_lbl.text = "🪙 %d" % slot.get("reward", 0)
	reward_lbl.add_theme_font_size_override("font_size", 15)
	reward_lbl.add_theme_color_override("font_color", Color(0.58, 0.36, 0.00))
	reward_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(reward_lbl)

	var send_btn := Button.new()
	send_btn.text = "🚚 ส่ง"
	send_btn.custom_minimum_size = Vector2(80, 30)
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.disabled = not can_send
	if can_send:
		_style_button(send_btn, Color(0.12, 0.44, 0.16), Color.WHITE)
	else:
		var ds := StyleBoxFlat.new()
		ds.bg_color = Color(0.55, 0.53, 0.50)
		ds.corner_radius_top_left = 5
		ds.corner_radius_top_right = 5
		ds.corner_radius_bottom_left = 5
		ds.corner_radius_bottom_right = 5
		send_btn.add_theme_stylebox_override("normal", ds)
		send_btn.add_theme_stylebox_override("disabled", ds)
		send_btn.add_theme_color_override("font_color", Color(0.78, 0.76, 0.74))
		send_btn.add_theme_color_override("font_disabled_color", Color(0.78, 0.76, 0.74))
	send_btn.add_theme_font_size_override("font_size", 13)

	var reward: int = slot.get("reward", 0)
	send_btn.pressed.connect(func():
		if garage_bld.trigger_truck_delivery(idx):
			_close_active_popup()
			_show_notify("🚚 ส่งแล้ว!  +🪙 %d" % reward)
		else:
			_show_notify("ส่งไม่ได้ — สินค้าไม่พอหรือ ⛽ Gasoline หมด")
	)
	bot_row.add_child(send_btn)

	return {"panel": card, "time_lbl": time_lbl, "send_btn": send_btn}

# --- Callbacks ---

func _on_build_button(bd: BuildingData) -> void:
	if _res_mgr == null or _gm == null:
		return
	var gold_cost: int = bd.build_cost.get("Gold", 0)
	if gold_cost > 0 and _res_mgr.get_amount("Gold") < gold_cost:
		_show_notify("ทองไม่พอ! ต้องการ 🪙%d" % gold_cost)
		return
	_gm.select_for_placement(bd)
	_close_store()

func _show_recipe_picker(bd: BuildingData) -> void:
	_close_active_popup()
	_backdrop = _make_backdrop()

	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(280, 0)
	popup.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.97, 0.95, 0.90)
	st.corner_radius_top_left = 12; st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
	st.set_content_margin_all(14)
	popup.add_theme_stylebox_override("panel", st)
	add_child(popup)
	_active_popup = popup
	await get_tree().process_frame
	if not is_instance_valid(popup): return
	popup.visible = true
	popup.set_anchors_preset(Control.PRESET_CENTER)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	popup.add_child(vbox)

	# Header
	var hdr := Label.new()
	hdr.text = "%s — เลือกสูตรการผลิต" % bd.display_name
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", Color(0.20, 0.16, 0.10))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.72, 0.68, 0.60, 0.5))
	vbox.add_child(sep)

	# Recipe buttons row
	var recipe_row := HBoxContainer.new()
	recipe_row.add_theme_constant_override("separation", 6)
	recipe_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(recipe_row)

	var chosen_recipe: int = 0
	var recipe_btns: Array = []

	for ri in bd.recipes.size():
		var r: Dictionary = bd.recipes[ri]
		var rbtn := Button.new()
		rbtn.focus_mode = Control.FOCUS_NONE
		var rname: String = r.get("name", "")
		if rname == "":
			var rp: Dictionary = r.get("produces", {})
			var parts: Array = []
			for res in rp:
				parts.append(RES_ICON.get(res, "") + " " + _res_name(res))
			rname = "\n".join(parts)
		# Show produce icons in the button
		var rp_btn: Dictionary = r.get("produces", {})
		var icons: String = ""
		for res in rp_btn:
			icons += RES_ICON.get(res, "")
		rbtn.text = "%s\n%s" % [icons, rname]
		rbtn.custom_minimum_size = Vector2(100, 64)
		recipe_btns.append(rbtn)
		recipe_row.add_child(rbtn)

	var confirm_btn := Button.new()
	confirm_btn.focus_mode = Control.FOCUS_NONE

	var _refresh_btns := func():
		for bi in recipe_btns.size():
			var b: Button = recipe_btns[bi]
			_style_button(b,
				Color(0.18, 0.48, 0.80) if bi == chosen_recipe else Color(0.72, 0.72, 0.74),
				Color.WHITE)

	for ri in bd.recipes.size():
		var cap_ri := ri
		recipe_btns[ri].pressed.connect(func():
			chosen_recipe = cap_ri
			_refresh_btns.call()
		)
	_refresh_btns.call()

	# Cost reminder
	var cost_lbl := Label.new()
	var cost_parts: Array = []
	for res in bd.build_cost:
		cost_parts.append("%s%d %s" % [RES_ICON.get(res, ""), bd.build_cost[res], res])
	cost_lbl.text = "ค่าก่อสร้าง: " + "  ".join(cost_parts)
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.add_theme_color_override("font_color", Color(0.40, 0.36, 0.28))
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)

	# Confirm / Cancel
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_style_button(confirm_btn, Color(0.18, 0.55, 0.22), Color.WHITE)
	confirm_btn.text = "✓ ยืนยัน"
	confirm_btn.focus_mode = Control.FOCUS_NONE
	confirm_btn.custom_minimum_size = Vector2(110, 40)
	var cap_bd := bd
	confirm_btn.pressed.connect(func():
		if _gm == null: return
		_gm.select_for_placement(cap_bd, chosen_recipe)
		_close_active_popup()
		_close_store()
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	_style_button(cancel_btn, Color(0.60, 0.22, 0.18), Color.WHITE)
	cancel_btn.text = "ยกเลิก"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size = Vector2(90, 40)
	cancel_btn.pressed.connect(_close_active_popup)
	btn_row.add_child(cancel_btn)

func _on_demolish_button() -> void:
	if _gm == null:
		return
	if _gm.is_demolishing():
		_gm.cancel_placement()
	else:
		_gm.start_demolish()
		_show_notify("คลิกอาคารเพื่อรื้อถอน  คลิกขวาเพื่อยกเลิก")

func _on_road_button() -> void:
	if _gm == null:
		return
	if _gm.is_placing_road():
		_gm.cancel_placement()
	else:
		_gm.start_road_placing()
		_show_notify("คลิกเพื่อวางถนน  คลิกขวาเพื่อยกเลิก")

func _on_add_gold() -> void:
	if _res_mgr == null:
		return
	_res_mgr.add_resource("Gold", 500)
	_show_notify("+500 🪙")

func _refresh_top_bar() -> void:
	if _res_mgr == null:
		return
	var totals: Dictionary = {}
	# Gold and Gasoline come from resource_manager (currency)
	for res in ["Gold", "Gasoline"]:
		var amt: int = _res_mgr.get_amount(res)
		if amt > 0: totals[res] = amt
	# All other resources: aggregate from buildings' local_stock
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm != null:
		var seen := {}
		for cell in gm._buildings.keys():
			var bld = gm._buildings[cell]
			if not is_instance_valid(bld): continue
			var uid: int = bld.get_instance_id()
			if seen.has(uid): continue
			seen[uid] = true
			for res in bld._local_stock:
				totals[res] = totals.get(res, 0) + bld._local_stock.get(res, 0)
	for res in RESOURCE_DISPLAY as Array:
		if not _res_panels.has(res):
			continue
		var amt: int = totals.get(res, 0)
		# Always show Gasoline so the player sees the 0-warning even when empty
		_res_panels[res].visible = amt > 0 or res == "Gasoline"
		if _res_labels.has(res) and (amt > 0 or res == "Gasoline"):
			_res_labels[res].text = str(amt)
	_update_gasoline_warning(totals.get("Gasoline", 0))

func _update_gasoline_warning(amount: int) -> void:
	var panel: PanelContainer = _res_panels.get("Gasoline") as PanelContainer
	var lbl: Label = _res_labels.get("Gasoline")
	if panel == null:
		return
	if _gas_blink_tween != null and _gas_blink_tween.is_valid():
		_gas_blink_tween.kill()
		_gas_blink_tween = null
	panel.modulate = Color.WHITE
	if amount == 0:
		_apply_panel_style(panel, Color(0.35, 0.04, 0.04, 0.97), Color(0.92, 0.10, 0.10))
		if lbl != null:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.30, 0.22))
		_gas_blink_tween = create_tween().set_loops()
		_gas_blink_tween.tween_property(panel, "modulate", Color(1.0, 0.45, 0.45, 0.7), 0.45)
		_gas_blink_tween.tween_property(panel, "modulate", Color.WHITE, 0.45)
	elif amount < 20:
		_apply_panel_style(panel, Color(0.52, 0.26, 0.02, 0.97), Color(0.88, 0.46, 0.04))
		if lbl != null:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35))
	else:
		_apply_panel_style(panel, Color(1.0, 1.0, 1.0, 0.92), Color(0.68, 0.64, 0.82))
		if lbl != null:
			lbl.add_theme_color_override("font_color", Color(0.10, 0.08, 0.15))

func _on_resource_changed(_res_name: String, _new_amount: int) -> void:
	_refresh_top_bar()

func _on_population_changed(available: int, used: int) -> void:
	if _population_label == null:
		return
	_population_label.text = "👷%d/%d" % [used, available]

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _active_popup != null and is_instance_valid(_active_popup) and _selected_building != null:
		var screen_pos: Vector2 = cam.unproject_position(_tooltip_world_pos)
		var vp := get_viewport_rect().size
		var px: float = clampf(screen_pos.x - _active_popup.size.x * 0.5, 4.0, vp.x - _active_popup.size.x - 4.0)
		var py: float = clampf(screen_pos.y - _active_popup.size.y - 16.0, 4.0, vp.y - _active_popup.size.y - 4.0)
		_active_popup.position = Vector2(px, py)
	if _cell_popup != null and is_instance_valid(_cell_popup):
		var sp: Vector2 = cam.unproject_position(_cell_popup_world_pos)
		var vp2 := get_viewport_rect().size
		var cpx: float = clampf(sp.x - _cell_popup.size.x * 0.5, 4.0, vp2.x - _cell_popup.size.x - 4.0)
		var cpy: float = clampf(sp.y - _cell_popup.size.y - 12.0, 4.0, vp2.y - _cell_popup.size.y - 4.0)
		_cell_popup.position = Vector2(cpx, cpy)
	for bld in _prod_overlays.keys():
		if not is_instance_valid(bld):
			continue
		var refs: Dictionary = _prod_overlays[bld]
		if not is_instance_valid(refs["panel"]):
			continue
		var sp: Vector2 = cam.unproject_position((bld as Node3D).position + Vector3(0, 2.8, 0))
		var panel: Control = refs["panel"]
		panel.position = sp - Vector2(panel.size.x * 0.5, panel.size.y)
	if _minimap_open and _minimap_draw != null and is_instance_valid(_minimap_draw):
		_minimap_draw.queue_redraw()


func _on_state_changed(new_state: int) -> void:
	var placing: bool = (new_state == 1)  # State.PLACING_BUILDING
	if _place_actions != null:
		_place_actions.visible = placing
	if not placing and _build_info_panel != null and is_instance_valid(_build_info_panel):
		_build_info_panel.visible = false
	if placing:
		_show_confirm_place_btn()
	else:
		_hide_confirm_place_btn()

func _get_building_placer() -> Node:
	if _building_placer_node == null or not is_instance_valid(_building_placer_node):
		_building_placer_node = get_tree().get_first_node_in_group("building_placer")
	return _building_placer_node

func _show_confirm_place_btn() -> void:
	_hide_confirm_place_btn()
	var bp := _get_building_placer()
	if bp == null:
		return
	if not bp.touch_cell_locked.is_connected(_on_touch_cell_locked):
		bp.touch_cell_locked.connect(_on_touch_cell_locked)
	if not bp.touch_cell_unlocked.is_connected(_on_touch_cell_unlocked):
		bp.touch_cell_unlocked.connect(_on_touch_cell_unlocked)

	if _place_actions == null:
		return
	_confirm_place_btn = Button.new()
	_confirm_place_btn.text = "✓ วางที่นี่"
	_confirm_place_btn.custom_minimum_size = Vector2(148, 54)
	_confirm_place_btn.focus_mode = Control.FOCUS_NONE
	_confirm_place_btn.disabled = true
	_style_button(_confirm_place_btn, Color(0.12, 0.45, 0.12, 0.92), Color.WHITE)
	_confirm_place_btn.pressed.connect(func():
		var placer := _get_building_placer()
		if placer != null and is_instance_valid(placer):
			placer.confirm_place()
	)
	_place_actions.add_child(_confirm_place_btn)

func _hide_confirm_place_btn() -> void:
	if _confirm_place_btn != null and is_instance_valid(_confirm_place_btn):
		_confirm_place_btn.queue_free()
	_confirm_place_btn = null

func _on_touch_cell_locked(is_valid: bool) -> void:
	if _confirm_place_btn == null or not is_instance_valid(_confirm_place_btn):
		return
	_confirm_place_btn.disabled = not is_valid

func _on_touch_cell_unlocked() -> void:
	if _confirm_place_btn == null or not is_instance_valid(_confirm_place_btn):
		return
	_confirm_place_btn.disabled = true

func _show_notify(msg: String) -> void:
	_notify_label.text = msg
	var tween := create_tween()
	tween.tween_property(_notify_label, "modulate", Color(1, 0.35, 0.25, 1), 0.1)
	tween.tween_interval(1.5)
	tween.tween_property(_notify_label, "modulate", Color(1, 0.35, 0.25, 0), 0.4)

# --- Minimap ---

func _build_minimap() -> void:
	const MAP_PX: int = 20 * 18  # 360 px
	const PAD:    int = 10

	# Dark backdrop (click to close)
	_minimap_backdrop = ColorRect.new()
	_minimap_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_backdrop.color = Color(0.0, 0.0, 0.0, 0.62)
	_minimap_backdrop.visible = false
	_minimap_backdrop.gui_input.connect(_on_backdrop_input)
	_minimap_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_minimap_backdrop)

	# Centered popup panel
	_minimap_panel = PanelContainer.new()
	_minimap_panel.set_anchors_preset(Control.PRESET_CENTER)
	_minimap_panel.offset_left   = -(MAP_PX * 0.5 + PAD + 2)
	_minimap_panel.offset_right  =   MAP_PX * 0.5 + PAD + 2
	_minimap_panel.offset_top    = -(MAP_PX * 0.5 + 30 + PAD + 20)
	_minimap_panel.offset_bottom =   MAP_PX * 0.5 + 26 + PAD
	_minimap_panel.visible       = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.14, 0.97)
	bg.corner_radius_top_left     = 10
	bg.corner_radius_top_right    = 10
	bg.corner_radius_bottom_left  = 10
	bg.corner_radius_bottom_right = 10
	bg.border_width_top   = 2
	bg.border_color       = Color(0.32, 0.52, 0.85, 0.85)
	_minimap_panel.add_theme_stylebox_override("panel", bg)
	add_child(_minimap_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   PAD)
	margin.add_theme_constant_override("margin_right",  PAD)
	margin.add_theme_constant_override("margin_top",    PAD)
	margin.add_theme_constant_override("margin_bottom", PAD)
	_minimap_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "🗺  แผนที่เมือง"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕  ปิด"
	close_btn.custom_minimum_size = Vector2(70, 28)
	close_btn.focus_mode = Control.FOCUS_NONE
	_style_button(close_btn, Color(0.32, 0.10, 0.10, 0.88), Color(1.0, 0.55, 0.45))
	close_btn.pressed.connect(_toggle_minimap)
	header.add_child(close_btn)

	# Map canvas
	_minimap_draw = load("res://scripts/minimap_draw.gd").new()
	_minimap_draw.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	vbox.add_child(_minimap_draw)

	# Legend row
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	vbox.add_child(legend)

	for entry in [
		[Color(0.28, 0.65, 0.20), "หญ้า"],
		[Color(0.12, 0.40, 0.82), "น้ำ/แม่น้ำ"],
		[Color(0.08, 0.30, 0.10), "ป่า"],
		[Color(0.72, 0.58, 0.40), "ถนน"],
		[Color(0.48, 0.48, 0.52), "ถนนลาดยาง"],
		[Color(1.00, 0.82, 0.18), "อาคาร"],
	]:
		var dot := ColorRect.new()
		dot.color = entry[0]
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(dot)
		var lbl := Label.new()
		lbl.text = entry[1]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
		legend.add_child(lbl)

func _toggle_minimap() -> void:
	_minimap_open = not _minimap_open
	_minimap_backdrop.visible = _minimap_open
	_minimap_panel.visible    = _minimap_open
	if _minimap_open:
		if _minimap_draw.grid_manager == null:
			_minimap_draw.grid_manager = get_tree().get_first_node_in_group("grid_manager")
		_minimap_draw.queue_redraw()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_toggle_minimap()

# --- Save Controls ---

func _add_save_controls() -> void:
	# Save status label (top center)
	var save_lbl := Label.new()
	save_lbl.name = "SaveStatusLabel"
	save_lbl.text = ""
	save_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	save_lbl.add_theme_font_size_override("font_size", 14)
	save_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	save_lbl.position = Vector2(-60, 8)
	add_child(save_lbl)

func show_save_flash() -> void:
	var lbl := get_node_or_null("SaveStatusLabel") as Label
	if lbl == null:
		return
	lbl.text = "✓ Saved"
	var t := Timer.new()
	t.wait_time = 2.0
	t.one_shot = true
	t.timeout.connect(func(): if is_instance_valid(lbl): lbl.text = "")
	add_child(t)
	t.start()

# --- Helpers ---

func _apply_panel_style(panel: PanelContainer, bg: Color, border: Color, top: bool = true) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	if top:
		style.border_width_bottom = 2
		style.border_color = border
	else:
		style.border_width_top = 2
		style.border_color = border
	panel.add_theme_stylebox_override("panel", style)

func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.corner_radius_top_left = 5
	normal.corner_radius_top_right = 5
	normal.corner_radius_bottom_left = 5
	normal.corner_radius_bottom_right = 5
	normal.border_width_bottom = 2
	normal.border_color = fg.darkened(0.1)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.18)
	hover.corner_radius_top_left = 5
	hover.corner_radius_top_right = 5
	hover.corner_radius_bottom_left = 5
	hover.corner_radius_bottom_right = 5
	hover.border_width_bottom = 2
	hover.border_color = fg
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_sb := StyleBoxFlat.new()
	pressed_sb.bg_color = bg.darkened(0.15)
	pressed_sb.corner_radius_top_left = 5
	pressed_sb.corner_radius_top_right = 5
	pressed_sb.corner_radius_bottom_left = 5
	pressed_sb.corner_radius_bottom_right = 5
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)

# --- Build Info Panel ---

func _show_build_info(data) -> void:
	if _build_info_panel != null and is_instance_valid(_build_info_panel):
		_build_info_panel.queue_free()
		_build_info_panel = null
	if data == null:
		return
	_build_info_panel = _create_build_info_panel(data)
	add_child(_build_info_panel)

func _create_build_info_panel(data) -> Control:
	var lm = get_node_or_null("/root/LocaleManager")

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(230, 0)
	outer.anchor_left = 0.0
	outer.anchor_right = 0.0
	outer.anchor_top = 0.0
	outer.anchor_bottom = 0.0
	outer.position = Vector2(10, 70)

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.09, 0.15, 0.95)
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.border_width_left = 1
	st.border_width_right = 1
	st.border_width_top = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.45, 0.48, 0.72, 0.55)
	outer.add_theme_stylebox_override("panel", st)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	outer.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# Building name
	var th_name: String = lm.building(data.id) if lm != null else data.display_name
	var name_lbl := Label.new()
	name_lbl.text = th_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(206, 0)
	vbox.add_child(name_lbl)

	if data.display_name != th_name:
		var en_lbl := Label.new()
		en_lbl.text = data.display_name
		en_lbl.add_theme_font_size_override("font_size", 11)
		en_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.80))
		vbox.add_child(en_lbl)

	vbox.add_child(_info_sep())

	# Size + cost + workers
	_info_row(vbox, "ขนาด", "%d×%d ช่อง" % [data.size.x, data.size.y])

	if not data.build_cost.is_empty():
		var parts: Array = []
		for res in data.build_cost:
			parts.append("%s %d" % [RES_ICON.get(res, res), data.build_cost[res]])
		_info_row(vbox, "ราคา", "  ".join(parts))

	if data.workers_needed > 0:
		_info_row(vbox, "👷 คนงาน", "%d คน" % data.workers_needed)

	if data.population_bonus > 0:
		_info_row(vbox, "👥 ประชากร", "+%d" % data.population_bonus)

	# Timing
	if data.grow_time > 0.0:
		_info_row(vbox, "⏱ เติบโต", "%.0f วิ" % data.grow_time)
	elif data.production_time > 0.0 and (not data.produces.is_empty() or not data.recipes.is_empty()):
		_info_row(vbox, "⏱ ผลิต/รอบ", "%.0f วิ" % data.production_time)

	# Produces
	if not data.produces.is_empty():
		vbox.add_child(_info_sep())
		_info_header(vbox, "📤 ผลผลิต")
		for res in data.produces:
			_info_row(vbox, "   %s %s" % [RES_ICON.get(res, ""), _res_name(res)], "×%d" % data.produces[res])

	# Consumes
	if not data.consumes.is_empty():
		vbox.add_child(_info_sep())
		_info_header(vbox, "📥 วัตถุดิบ")
		for res in data.consumes:
			_info_row(vbox, "   %s %s" % [RES_ICON.get(res, ""), _res_name(res)], "×%d" % data.consumes[res])

	# Recipes
	if not data.recipes.is_empty():
		vbox.add_child(_info_sep())
		_info_header(vbox, "📋 สูตร (%d)" % data.recipes.size())
		for recipe in data.recipes:
			var rname: String = recipe.get("name", "?")
			var prod: Dictionary = recipe.get("produces", {})
			var prod_str: String = ""
			for r in prod:
				prod_str += "%s×%s " % [RES_ICON.get(r, r), prod[r]]
			_info_row(vbox, "   " + rname, prod_str.strip_edges())

	# Passive bonuses
	if data.storage_bonus > 0:
		vbox.add_child(_info_sep())
		_info_row(vbox, "📦 พื้นที่เก็บ", "+%d" % data.storage_bonus)
	if data.water_radius > 0:
		_info_row(vbox, "💧 รัศมีน้ำ", "%d ช่อง" % data.water_radius)
	if data.shadow_radius > 0:
		_info_row(vbox, "🌑 เงา", "%d ช่อง" % data.shadow_radius)
	if data.pollution_radius > 0:
		_info_row(vbox, "☁ มลพิษ", "%d ช่อง" % data.pollution_radius)

	# Description
	if data.description != "":
		vbox.add_child(_info_sep())
		var desc := Label.new()
		desc.text = data.description
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.72, 0.72, 0.85))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(206, 0)
		vbox.add_child(desc)

	return outer

func _info_sep() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.45, 0.45, 0.6, 0.3))
	return sep

func _info_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 1.0, 0.9))
	parent.add_child(lbl)

func _info_row(parent: VBoxContainer, left: String, right: String) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var left_lbl := Label.new()
	left_lbl.text = left
	left_lbl.add_theme_font_size_override("font_size", 13)
	left_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.90))
	left_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_lbl)
	var right_lbl := Label.new()
	right_lbl.text = right
	right_lbl.add_theme_font_size_override("font_size", 13)
	right_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.80))
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(right_lbl)
