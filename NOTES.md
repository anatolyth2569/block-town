# Block-Town — Dev Notes

> อ้างอิงจาก GAME_DESIGN.md สำหรับ design goals และ production chains

---

## สถานะโปรเจกต์ (อัพเดต: 2026-05-20)

ระบบหลักทำงานได้ครบ กำลังเพิ่ม content และ polish

### ระบบที่ทำงานได้แล้ว
- Production chain (40+ buildings, 30+ resources)
- Worker system + Domain system (CROP, LIVESTOCK, etc.)
- Woodcutter / Farmer / Rancher logic
- Animal NPCs (วัว ไก่ แกะ หมู) เดินในคอก
- Pollution effect บน crops
- Gasoline gating trade
- Save / Load system (SaveManager autoload)
- Auto-save ทุก 30 วินาที, บันทึกเมื่อปิดเกม
- Store preview system (PNG แทน SubViewport — ต้องรัน generate_previews.tscn)

### ปัญหาที่รู้อยู่
- [ ] **Save system ไม่ขึ้น GitHub** — ตรวจสอบว่า scripts ทุกไฟล์ถูก commit หรือยัง
- [ ] River proximity bonus ถูกถอดออก (เติมน้ำเกิน max)
- [ ] Road speed bonus ยัง partial

---

## สิ่งที่ต้องสร้างเพิ่ม

### โมเดล 3D (tscn) ที่ยังไม่มี
- [ ] **Slaughterhouse** — โรงฆ่าสัตว์ (placeholder ว่างอยู่, รอออกแบบ)
- [ ] อาคารอื่นๆ ที่ยังใช้ box fallback แทน model จริง

### ระบบที่ต้องทำ
- [ ] **Slaughterhouse logic** — รับ Pig → ผลิต Pork (ไฟล์ .tres พร้อมแล้ว รอ model)
- [ ] **Pork / Pig** เพิ่มใน locale/th.json (คำแปลภาษาไทย)
- [ ] River proximity bonus — แก้ให้ไม่ overflow น้ำ แล้ว enable กลับ
- [ ] Road speed bonus — ทำให้ครบ

### Store Preview
- [ ] รัน `scenes/generate_previews.tscn` เพื่อ generate PNG ทุกอาคาร
- [ ] PNG จะบันทึกที่ `assets/building_previews/`
- [ ] หลังรันให้เปลี่ยน Main Scene กลับเป็น `scenes/main.tscn`

### Playtest
- [ ] **Playtest ระบบทั้งหมด** end-to-end ก่อน release
- [ ] Fix bugs ที่เจอจาก playtest

---

## ไอเดีย / Reference

### Townstar — NFT Skins (ไอเดียโมเดลอาคาร)
https://learntownstar.com/category/nfts/nft-skins/
เกมต้นแบบของ Block-Town เปิดดูไอเดีย skin / style อาคารได้

---

## Production Chain — pig / slaughterhouse
```
คอกหมู (pig_pen)
  consumes: Feed
  produces: Pig  ← หมูมีชีวิต ส่งไปโรงฆ่า

โรงฆ่าสัตว์ (slaughterhouse)  ← ยังไม่มีโมเดล
  consumes: Pig
  produces: Pork (×2)
  workers: 1, pollution: 2
```

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
