# Design Reference — วิธีใช้โฟลเดอร์นี้

โฟลเดอร์นี้เก็บ HTML design ของแต่ละอาคาร
เพื่อเปรียบเทียบกับ .tscn ที่สร้างจริงใน Godot

---

## โครงสร้าง

```
design_reference/
└── buildings/
    ├── slaughterhouse.html       ← design HTML ของโรงฆ่าสัตว์
    ├── slaughterhouse_notes.md   ← โน้ตการแปลง (optional)
    ├── bakery.html
    └── ...
```

ไฟล์ .tscn จริงอยู่ที่:
```
scenes/buildings/{ชื่ออาคาร}.tscn
```

---

## วิธีใช้

1. ออกแบบอาคารเป็น HTML ก่อน → บันทึกไว้ที่ `design_reference/buildings/`
2. ส่งชื่อไฟล์ให้ Claude → Claude จะแปลงเป็น .tscn ให้
3. .tscn จะถูกบันทึกที่ `scenes/buildings/` อัตโนมัติ

---

## ตัวอย่างชื่อไฟล์

| HTML (design)                        | tscn (Godot)                            |
|--------------------------------------|-----------------------------------------|
| `buildings/slaughterhouse.html`      | `scenes/buildings/slaughterhouse.tscn`  |
| `buildings/market.html`              | `scenes/buildings/market.tscn`          |
| `buildings/advanced_bakery.html`     | `scenes/buildings/advanced_bakery.tscn` |

---

## สิ่งที่ต้องบอก Claude ตอนแปลง

- ชื่อ HTML ไฟล์ที่ต้องการแปลง
- ขนาดอาคาร (1×1, 2×2, ฯลฯ)
- `model_scale` ใน .tres ของอาคารนั้น (ถ้ารู้)
