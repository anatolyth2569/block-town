# Block-Town — Dev Notes

> อ้างอิงจาก GAME_DESIGN.md สำหรับ design goals และ production chains

---

## สถานะโปรเจกต์ (อัพเดต: 2026-05-18)

โปรเจกต์ใกล้พร้อม playtest แล้ว ระบบหลักทำงานได้ครบ

### ระบบที่ทำงานได้แล้ว
- Production chain (39 buildings, 30+ resources)
- Worker system + Domain system (CROP, LIVESTOCK, etc.)
- Woodcutter / Farmer / Rancher logic
- Pollution effect บน crops
- Gasoline gating trade
- Save / Load system (SaveManager autoload)
- Auto-save ทุก 30 วินาที, บันทึกเมื่อปิดเกม

### ปัญหาที่รู้อยู่
- [ ] **Save system ไม่ขึ้น GitHub** — ต้องตรวจสอบว่า `scripts/save_manager.gd` และไฟล์ script อื่นๆ ถูก commit ขึ้น repo หรือยัง (ไฟล์ save จริง `user://save.json` จะอยู่ใน Godot user data folder ของเครื่อง ไม่ได้อยู่ใน project — ปกติแล้วถูกต้อง)
- [ ] River proximity bonus ถูกถอดออก (เติมน้ำเกิน max)
- [ ] Road speed bonus ยัง partial

### ต้องทำต่อ
1. **Playtest ระบบทั้งหมด** end-to-end
2. Push โค้ดขึ้น GitHub ให้ครบ (รวม scripts ทุกไฟล์)
3. Fix bugs ที่เจอจาก playtest

---

## โครงสร้างสำคัญ

```
scripts/
  save_manager.gd     ← SaveManager autoload (save/load + auto-save)
  resource_manager.gd ← เงิน, resources
  game_manager.gd     ← เวลา, wages
  order_manager.gd    ← orders / trade
  grid_manager.gd     ← grid, placement
  building.gd         ← logic ของอาคาร
  worker.gd           ← NPC worker logic
  worker_registry.gd  ← ลงทะเบียน worker types
  build_queue.gd      ← คิวสร้างอาคาร
  farmer / rancher / woodcutter → อยู่ใน worker.gd

resources/buildings/  ← .tres ไฟล์ 39 อาคาร
scenes/               ← main.tscn + buildings
locale/th.json        ← ข้อความภาษาไทย
```

---

## Save System — วิธีทำงาน

- **Path**: `user://save.json` (อยู่นอก project folder — ใน Godot AppData)
- **Auto-save**: ทุก 30 วินาที (เริ่มหลัง load game)
- **Manual save**: บันทึกอัตโนมัติเมื่อปิดหน้าต่าง
- **Load**: ตรวจสอบว่ามี save ไหม → แสดงปุ่ม Continue / New Game

บันทึก: roads, buildings (รวม stock), fields (harvest timer), trees, resources, orders

---

## วิธี Setup GitHub (ถ้ายังไม่ได้ทำ)

```bash
git init
git add .
git commit -m "initial commit"
git remote add origin <URL>
git push -u origin main
```

สิ่งที่ไม่ต้อง commit (มีใน .gitignore แล้ว):
- `.godot/` folder (cache ของ editor)
- `user://save.json` (save ของผู้เล่น — ไม่อยู่ใน project folder)
