extends Control

const MAP_SCALE  = 0.82
const MAP_OFFSET = Vector2(121.0, 70.0)

# [id, name_th, name_en, raw_x, raw_y, region, terrain]
var PROVINCES: Array = [
	["chiang_rai",  "เชียงราย",     "Chiang Rai",       212, 52,  "north",   "ภูเขา"],
	["chiang_mai",  "เชียงใหม่",    "Chiang Mai",        175, 105, "north",   "ภูเขา"],
	["nan",         "น่าน",         "Nan",               272, 90,  "north",   "ภูเขา"],
	["khon_kaen",   "ขอนแก่น",      "Khon Kaen",         325, 224, "isan",    "ที่ราบ"],
	["ubon",        "อุบลราชธานี",  "Ubon Ratchathani",  364, 262, "isan",    "ริมแม่น้ำ"],
	["korat",       "นครราชสีมา",   "Nakhon Ratchasima", 289, 272, "isan",    "ที่ราบ"],
	["ayutthaya",   "อยุธยา",       "Ayutthaya",         221, 300, "central", "ที่ราบลุ่ม"],
	["bangkok",     "กรุงเทพฯ",     "Bangkok",           234, 332, "central", "ที่ราบลุ่ม"],
	["chonburi",    "ชลบุรี",       "Chonburi",          272, 355, "east",    "ชายทะเล"],
	["phetchaburi", "เพชรบุรี",     "Phetchaburi",       187, 366, "west",    "ชายทะเล"],
	["surat",       "สุราษฎร์ธานี", "Surat Thani",       195, 488, "south",   "ชายทะเล"],
	["phuket",      "ภูเก็ต",       "Phuket",            162, 557, "south",   "เกาะ"],
	["songkhla",    "สงขลา",        "Songkhla",          211, 574, "south",   "ชายทะเล"],
]

var REGION_COLORS: Dictionary = {
	"north":   Color(0.30, 0.72, 0.28),
	"isan":    Color(0.90, 0.62, 0.12),
	"central": Color(0.32, 0.58, 0.95),
	"east":    Color(0.20, 0.72, 0.62),
	"west":    Color(0.45, 0.72, 0.35),
	"south":   Color(0.18, 0.62, 0.88),
}
var REGION_NAMES: Dictionary = {
	"north":   "ภาคเหนือ",
	"isan":    "ภาคอีสาน",
	"central": "ภาคกลาง",
	"east":    "ภาคตะวันออก",
	"west":    "ภาคตะวันตก",
	"south":   "ภาคใต้",
}

var THAILAND_POLY := PackedVector2Array([
	# clockwise from NW corner
	Vector2(150, 68),   # NW — Mae Hong Son (Myanmar border N)
	Vector2(155, 38),   # North apex (Golden Triangle area)
	Vector2(216, 22),   # Chiang Rai N (northernmost point)
	Vector2(260, 30),   # Chiang Rai / Laos border
	Vector2(300, 52),   # Nan / Laos border
	Vector2(342, 92),   # Loei / Mekong NW
	Vector2(375, 142),  # Nong Khai (Mekong)
	Vector2(398, 195),  # Mukdahan (Mekong SE)
	Vector2(412, 252),  # Isan NE tip — rightmost point (near Ubon)
	Vector2(392, 292),  # Isan SE
	Vector2(362, 318),  # Cambodia border NW
	Vector2(340, 340),  # Aranyaprathet
	Vector2(320, 356),  # Gulf of Thailand upper (Chachoengsao)
	Vector2(325, 410),  # East coast Rayong
	Vector2(305, 452),  # Chanthaburi
	Vector2(282, 486),  # Trat — SE corner
	Vector2(262, 525),  # Gulf coast going SW
	Vector2(244, 566),  # Surat Thani E coast
	Vector2(224, 612),  # Nakhon Si Thammarat
	Vector2(213, 652),  # Songkhla
	Vector2(200, 678),  # Malaysia border SE
	Vector2(184, 678),  # Malaysia border S
	Vector2(162, 658),  # Narathiwat W
	Vector2(146, 618),  # Satun W coast
	Vector2(134, 570),  # Phang Nga W (Andaman Sea)
	Vector2(132, 518),  # Ranong W coast
	Vector2(142, 464),  # Prachuap Khiri Khan W
	Vector2(155, 415),  # Hua Hin / Phetchaburi W
	Vector2(170, 374),  # Phetchaburi W coast
	Vector2(180, 338),  # Ratchaburi / Bangkok W
	Vector2(162, 292),  # Kanchanaburi (Three Pagodas area)
	Vector2(148, 250),  # Three Pagodas Pass / Sangkhlaburi
	Vector2(150, 198),  # Tak / Mae Sot W border
	Vector2(150, 145),  # Mae Sariang / Chiang Mai W border
])

var _selected_id:  String = ""
var _hovered_id:   String = ""
var _info_name:    Label  = null
var _info_region:  Label  = null
var _info_terrain: Label  = null
var _info_desc:    Label  = null
var _start_btn:    Button = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Skip map select if a save already exists
	var sm = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_save():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
		return
	_build_ui()

func _to_screen(rx: float, ry: float) -> Vector2:
	return Vector2(rx, ry) * MAP_SCALE + MAP_OFFSET

func _draw() -> void:
	# Ocean
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.16, 0.38))
	# Subtle wave grid
	for i in range(0, int(size.x), 44):
		draw_line(Vector2(i, 0), Vector2(i, size.y), Color(0.10, 0.22, 0.52, 0.18), 1.0)
	for j in range(0, int(size.y), 44):
		draw_line(Vector2(0, j), Vector2(size.x, j), Color(0.10, 0.22, 0.52, 0.18), 1.0)

	# Thailand land polygon
	var pts := PackedVector2Array()
	for pt in THAILAND_POLY:
		pts.append(pt * MAP_SCALE + MAP_OFFSET)
	draw_polygon(pts, PackedColorArray([Color(0.20, 0.50, 0.16)]))
	# Border
	for i in range(pts.size()):
		draw_line(pts[i], pts[(i + 1) % pts.size()], Color(0.38, 0.72, 0.26), 1.5)

	# Province dots
	for prov in PROVINCES:
		var id: String   = prov[0]
		var sp: Vector2  = _to_screen(prov[3], prov[4])
		var col: Color   = REGION_COLORS.get(prov[5], Color.WHITE)
		if id == _selected_id:
			draw_circle(sp, 9.0, Color(1.0, 0.90, 0.0, 0.85))
			draw_circle(sp, 5.5, col)
		elif id == _hovered_id:
			draw_circle(sp, 7.5, Color(1.0, 1.0, 1.0, 0.80))
			draw_circle(sp, 4.5, col)
		else:
			draw_circle(sp, 5.0, col.darkened(0.25))
			draw_circle(sp, 3.0, col)

func _build_ui() -> void:
	# Title
	var title := Label.new()
	title.text = "🗺  เลือกจังหวัดที่จะสร้างเมือง"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.92, 0.90, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(20, 16)
	add_child(title)

	# Province markers (flat buttons over map)
	for prov in PROVINCES:
		_make_marker(prov[0], prov[1], prov[3], prov[4], prov[5])

	# Info + start panel (right side)
	_build_info_panel()

	# Bottom hint
	var hint := Label.new()
	hint.text = "คลิกที่จังหวัดบนแผนที่เพื่อเลือก"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.90, 0.70))
	hint.anchor_left   = 0.0
	hint.anchor_right  = 0.5
	hint.anchor_top    = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top    = -28.0
	hint.offset_bottom = -6.0
	hint.offset_left   = 10.0
	add_child(hint)

func _make_marker(id: String, name_th: String, raw_x: float, raw_y: float, region: String) -> void:
	var sp := _to_screen(raw_x, raw_y)
	var btn := Button.new()
	btn.text = name_th
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = sp + Vector2(6, -8)
	btn.add_theme_color_override("font_color", REGION_COLORS.get(region, Color.WHITE))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.2))
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("outline_size", 3)
	btn.mouse_entered.connect(_on_hover.bind(id))
	btn.mouse_exited.connect(_on_exit)
	btn.pressed.connect(_on_click.bind(id))
	add_child(btn)

func _build_info_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left   = 0.60
	panel.anchor_right  = 0.98
	panel.anchor_top    = 0.08
	panel.anchor_bottom = 0.92

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.16, 0.94)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top   = 2
	style.border_color       = Color(0.28, 0.48, 0.82, 0.75)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "📍 ข้อมูลจังหวัด"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.60, 0.70, 0.92))
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_info_name = Label.new()
	_info_name.text = "—"
	_info_name.add_theme_font_size_override("font_size", 30)
	_info_name.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))
	vbox.add_child(_info_name)

	_info_region = Label.new()
	_info_region.text = ""
	_info_region.add_theme_font_size_override("font_size", 16)
	_info_region.add_theme_color_override("font_color", Color(0.72, 0.85, 0.55))
	vbox.add_child(_info_region)

	_info_terrain = Label.new()
	_info_terrain.text = ""
	_info_terrain.add_theme_font_size_override("font_size", 14)
	_info_terrain.add_theme_color_override("font_color", Color(0.62, 0.72, 0.92))
	vbox.add_child(_info_terrain)

	_info_desc = Label.new()
	_info_desc.text = "คลิกที่จังหวัดบนแผนที่เพื่อดูรายละเอียด\nและเลือกสถานที่สร้างเมือง"
	_info_desc.add_theme_font_size_override("font_size", 13)
	_info_desc.add_theme_color_override("font_color", Color(0.55, 0.62, 0.80))
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Legend
	var legend_lbl := Label.new()
	legend_lbl.text = "ภูมิภาค:"
	legend_lbl.add_theme_font_size_override("font_size", 12)
	legend_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.80))
	vbox.add_child(legend_lbl)
	var legend_grid := GridContainer.new()
	legend_grid.columns = 2
	legend_grid.add_theme_constant_override("h_separation", 8)
	legend_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(legend_grid)
	for region in REGION_COLORS:
		var dot := ColorRect.new()
		dot.color = REGION_COLORS[region]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend_grid.add_child(dot)
		var lbl := Label.new()
		lbl.text = REGION_NAMES.get(region, region)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", REGION_COLORS[region].lightened(0.2))
		legend_grid.add_child(lbl)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_start_btn = Button.new()
	_start_btn.text = "🏙  เริ่มสร้างเมือง"
	_start_btn.custom_minimum_size = Vector2(0, 52)
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	_apply_start_style(false)
	vbox.add_child(_start_btn)

func _apply_start_style(active: bool) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color     = Color(0.12, 0.42, 0.14, 0.92) if active else Color(0.14, 0.14, 0.24, 0.70)
	bg.border_width_bottom = 3
	bg.border_color = Color(0.32, 0.82, 0.35) if active else Color(0.22, 0.22, 0.38)
	bg.corner_radius_top_left     = 7
	bg.corner_radius_top_right    = 7
	bg.corner_radius_bottom_left  = 7
	bg.corner_radius_bottom_right = 7
	var hover := bg.duplicate() as StyleBoxFlat
	hover.bg_color = bg.bg_color.lightened(0.18)
	_start_btn.add_theme_stylebox_override("normal", bg)
	_start_btn.add_theme_stylebox_override("hover", hover)
	_start_btn.add_theme_stylebox_override("pressed", bg.duplicate())
	_start_btn.add_theme_color_override("font_color", Color(0.82, 1.0, 0.82) if active else Color(0.38, 0.38, 0.55))
	_start_btn.add_theme_font_size_override("font_size", 18)

# --- Events ---

func _on_hover(id: String) -> void:
	_hovered_id = id
	_update_info(id)
	queue_redraw()

func _on_exit() -> void:
	_hovered_id = ""
	if _selected_id != "":
		_update_info(_selected_id)
	else:
		_clear_info()
	queue_redraw()

func _on_click(id: String) -> void:
	_selected_id = id
	_update_info(id)
	_start_btn.disabled = false
	_apply_start_style(true)
	queue_redraw()

func _on_start_pressed() -> void:
	if _selected_id.is_empty():
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set("selected_province", _selected_id)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _update_info(id: String) -> void:
	for prov in PROVINCES:
		if prov[0] != id:
			continue
		_info_name.text = prov[1]
		_info_region.text  = "🌏  " + REGION_NAMES.get(prov[5], prov[5])
		_info_terrain.text = "🏔  ภูมิประเทศ: " + prov[6]
		_info_desc.text    = _province_desc(id)
		var col: Color = REGION_COLORS.get(prov[5], Color.WHITE)
		_info_name.add_theme_color_override("font_color", col.lightened(0.25))
		return

func _clear_info() -> void:
	_info_name.text = "—"
	_info_region.text  = ""
	_info_terrain.text = ""
	_info_desc.text = "คลิกที่จังหวัดบนแผนที่เพื่อดูรายละเอียด\nและเลือกสถานที่สร้างเมือง"
	_info_name.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))

func _province_desc(id: String) -> String:
	match id:
		"chiang_mai":   return "เมืองเหนือโอบล้อมด้วยดอย อุดมป่าไม้และทรัพยากรธรรมชาติ ภูมิอากาศเย็นสบาย"
		"chiang_rai":   return "เหนือสุดแดนไทย ชายแดนสามเหลี่ยมทองคำ แหล่งแร่และไม้ป่าอุดมสมบูรณ์"
		"nan":          return "หุบเขาน่านที่สงบงาม แหล่งไม้สักและทรัพยากรป่าเขาคุณภาพสูง"
		"khon_kaen":    return "ศูนย์กลางอีสาน ที่ราบกว้างใหญ่เหมาะเกษตรและอุตสาหกรรม"
		"ubon":         return "ริมฝั่งแม่น้ำมูล–ชี แหล่งน้ำอุดม พื้นที่นาข้าวอีสาน"
		"korat":        return "ประตูอีสาน ที่ราบสูงโคราช เกษตรและอุตสาหกรรมหลักของภาค"
		"ayutthaya":    return "อดีตราชธานี ที่ราบลุ่มแม่น้ำสามสาย ประวัติศาสตร์และเกษตรกรรม"
		"bangkok":      return "เมืองหลวง ศูนย์กลางการค้าและขนส่งใหญ่ที่สุด ประชากรหนาแน่น"
		"chonburi":     return "ชายฝั่งอ่าวไทย ท่าเรือนิคมอุตสาหกรรมระดับนานาชาติ"
		"phetchaburi":  return "ชายฝั่งตะวันตก เมืองประวัติศาสตร์และเกษตรกรรมชายทะเล"
		"surat":        return "ประตูใต้ ท่าเรือและสวนผลไม้เมืองร้อน ศูนย์กลางคมนาคมภาคใต้"
		"phuket":       return "เกาะมุกอันดามัน การท่องเที่ยวและการค้าชายทะเลระดับโลก"
		"songkhla":     return "ชายแดนใต้ริมทะเลสาบสงขลา ประมงและพาณิชย์ชายทะเล"
	return ""
