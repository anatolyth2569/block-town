extends Node

# รันฉากนี้หนึ่งครั้งจาก Godot Editor เพื่อ render รูปตัวอย่างอาคารทั้งหมด
# แล้วบันทึกเป็น PNG ลงใน res://assets/building_previews/
# เมื่อเสร็จแล้วให้เปลี่ยน Main Scene กลับเป็น scenes/main.tscn

const OUTPUT_DIR := "res://assets/building_previews/"
const TRES_DIR := "res://resources/buildings/"

var _label: Label
var _sub_label: Label
var _all_paths: Array = []

func _ready() -> void:
	# สร้าง output directory
	var abs_out := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)

	# UI แสดง progress
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.offset_top = -40.0
	_label.offset_bottom = 40.0
	_label.offset_left = -400.0
	_label.offset_right = 400.0
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "กำลังเตรียม..."
	add_child(_label)

	_sub_label = Label.new()
	_sub_label.set_anchors_preset(Control.PRESET_CENTER)
	_sub_label.offset_top = 30.0
	_sub_label.offset_bottom = 80.0
	_sub_label.offset_left = -400.0
	_sub_label.offset_right = 400.0
	_sub_label.add_theme_font_size_override("font_size", 16)
	_sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub_label)

	# รวบรวม .tres ทั้งหมดใน resources/buildings/
	var dir := DirAccess.open(TRES_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				_all_paths.append(TRES_DIR + fname)
			fname = dir.get_next()
	_all_paths.sort()

	await get_tree().process_frame
	_generate_all()

func _generate_all() -> void:
	var total := _all_paths.size()
	var saved := 0
	var skipped := 0

	for i in total:
		var path: String = _all_paths[i]
		var bd := load(path) as BuildingData
		if bd == null:
			skipped += 1
			continue

		_label.text = "[%d/%d]  %s" % [i + 1, total, bd.id]
		_sub_label.text = "บันทึกแล้ว %d รูป" % saved
		await get_tree().process_frame

		if bd.model_path == "" or not ResourceLoader.exists(bd.model_path):
			skipped += 1
			continue

		var out_path := OUTPUT_DIR + bd.id + ".png"
		await _render_and_save(bd, out_path)
		saved += 1

	_label.text = "เสร็จแล้ว! บันทึก %d รูป (%d ข้าม)" % [saved, skipped]
	_sub_label.text = "บันทึกที่: %s\n\nตอนนี้ไปที่ Project → Project Settings → Application → Run\nเปลี่ยน Main Scene กลับเป็น res://scenes/main.tscn" % OUTPUT_DIR
	_sub_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))

func _render_and_save(bd: BuildingData, out_path: String) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(280, 200)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)

	# สภาพแวดล้อมเหมือนใน store preview
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.92, 0.90, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.72)
	env.ambient_light_energy = 0.20
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.80
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	# แสงหลัก (เหมือน store)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -38, 0)
	key.light_energy = 0.90
	key.shadow_enabled = false
	sv.add_child(key)

	# กล้อง isometric (เหมือน store)
	var ms: float = bd.model_scale
	var center := Vector3(0.0, 1.4 * ms, 0.0)
	var cam := Camera3D.new()
	cam.position = center + Vector3(1.0, 1.0, 1.0).normalized() * 5.5
	cam.look_at_from_position(cam.position, center, Vector3.UP)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(3.2, 5.2 * ms)
	sv.add_child(cam)

	# โมเดลอาคาร
	var packed := load(bd.model_path) as PackedScene
	if packed:
		var inst := packed.instantiate()
		inst.scale = Vector3.ONE * ms
		sv.add_child(inst)

	# รอให้ render เสร็จ (5 frames ให้ชัวร์)
	for _i in 5:
		await get_tree().process_frame

	# capture และบันทึก
	var img := sv.get_texture().get_image()
	img.save_png(out_path)

	sv.queue_free()
	await get_tree().process_frame
