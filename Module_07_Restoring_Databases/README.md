Module นี้คือจุดที่ความพยายามทั้งหมดของ Module 5–6 มาพิสูจน์ตัวเอง — **restore คืองานเดียวที่วัดค่า DBA ตรงที่สุด** เพราะเมื่อเกิดเหตุ ผู้บริหารไม่ถามว่าคุณตั้ง job backup ดีแค่ไหน แต่ถามว่า "เมื่อไรข้อมูลกลับมา" และ "เสียไปเท่าไร" คุณจะได้เรียนกลไก restore ทีละขั้น (Copy → Redo → Undo), สถานการณ์การกู้ทั้งเครื่อง (full/diff/log chain), การกู้เฉพาะส่วน (filegroup, page), การกู้ encrypted backup, การกู้ system databases และการกู้กลับ "ถึงวินาทีก่อนความผิดพลาด" ด้วย STOPAT และ marked transactions

ประสบการณ์จริงของแล็บชุดนี้: คุณจะทำผิดอย่างจงใจหลายจุด (restore ทับข้อมูล, ลืม NORECOVERY, กู้โดยไม่มี certificate) เพื่อให้วันเกิดเหตุจริง ทุก error ของคุณคือของที่เคยเห็นมาแล้ว

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – กู้คืนทั้งฐานข้อมูล**: restore จาก full backup ด้วย RECOVERY/NORECOVERY/STANDBY อย่างถูกตำแหน่งได้
- **ระดับ 2 – กู้ตามลำดับ chain**: restore full → diff → log ตามลำดับ LSN และอ่าน metadata เพื่อเลือก backup set ที่ถูกได้
- **ระดับ 3 – กู้เฉพาะจุด**: ทำ tail-log backup, กู้ filegroup แบบ piecemeal, page restore จาก suspect_pages และกู้ system databases ได้
- **ระดับ 4 – กู้ถึงวินาทีก่อนเหตุ**: ใช้ STOPAT/STOPATMARK กู้กลับก่อน DROP/UPDATE อันตราย และออกแบบ recovery playbook ขององค์กรได้

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [กลไก Restore 3 ขั้นและการเตรียมการ](Sections/01_Restore_Mechanics/README.md) |
| 2 | [สถานการณ์การกู้คืน — Full, Differential และ Log Chain](Sections/02_Restore_Scenarios/README.md) |
| 3 | [การกู้แบบพิเศษ — Filegroup, Page, Encrypted และ System Databases](Sections/03_Special_Restores/README.md) |
| 4 | [Point-in-Time Restore — STOPAT และ Marked Transactions](Sections/04_Point_In_Time/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. NORECOVERY, RECOVERY และ STANDBY ต่างกันอย่างไร?</b></summary>
NORECOVERY = ยังรอ restore ต่อ (DB อยู่ RESTORING); RECOVERY = ทำ undo แล้วเปิดใช้งาน (ตัวสุดท้ายเท่านั้น); STANDBY = กลาง ๆ — undo เก็บใน standby file ทำให้ **อ่านได้** แต่ต่อ restore log ต่อได้อีก ใช้บ่อยกับ warm standby/ตรวจข้อมูลกลางทาง — อ่านละเอียด: [Section 1](Sections/01_Restore_Mechanics/README.md)
</details>

<details>
<summary><b>2. ขั้นตอน restore มีกี่ phase และแต่ละ phase ทำอะไร?</b></summary>
3 ขั้น: **Copy** (คัดลอกข้อมูลจาก backup ลงไฟล์), **Redo/Roll Forward** (นำ log จาก backup ขยับงานที่ commit แล้วให้ครบตามเวลา), **Undo/Roll Back** (ถอนธุรกรรมที่ยังไม่ commit — ขั้นนี้เกิดเฉพาะตอน RECOVERY) — อ่านละเอียด: [Section 1](Sections/01_Restore_Mechanics/README.md)
</details>

<details>
<summary><b>3. Restore แล้ว error ขอ tail-log backup — ทำอย่างไร?</b></summary>
FULL/BULK_LOGGED ที่ DB ยังใช้งานได้ต้อง `BACKUP LOG ... WITH NO_TRUNCATE` (หรือ NORECOVERY) ก่อน restore เสมอ; ถ้า DB เสียหายใช้ NO_TRUNCATE; ถ้าต้องการเขียนทับจริง ๆ ให้ใช้ WITH REPLACE — อ่านละเอียด: [Section 1 หัวข้อ 1.4](Sections/01_Restore_Mechanics/README.md)
</details>

<details>
<summary><b>4. STOPAT กับ STOPATMARK ใช้ต่างกันเมื่อไร?</b></summary>
STOPAT ใช้เวลานาฬิกา (ต้องรู้เวลาเหตุการณ์) — STOPATMARK ใช้ "mark" ที่เขียนไว้ล่วงหน้าใน transaction (`BEGIN TRAN ... WITH MARK`) แม่นยำกว่าและใช้กู้หลาย database ให้ตรงจุดเดียวกันได้ (logmarkhistory) — อ่านละเอียด: [Section 4](Sections/04_Point_In_Time/README.md)
</details>

<details>
<summary><b>5. Page restore ต้องมีอะไรครบจึงจะทำได้?</b></summary>
FULL/BULK_LOGGED recovery, ไฟล์ page ที่เสียเฉพาะจุด (จาก msdb.dbo.suspect_pages), full/file backup ที่ครอบ page นั้น + log chain ไม่ขาด; ห้ามมี filegroup ออฟไลน์; restore PAGE ด้วย NORECOVERY แล้วต่อ log จน RECOVERY — อ่านละเอียด: [Section 3 หัวข้อ 3.4](Sections/03_Special_Restores/README.md)
</details>

<details>
<summary><b>6. tempdb กับ resource database ทำไมไม่ต้อง backup?</b></summary>
tempdb ถูกสร้างใหม่ทุกครั้งที่ service เริ่ม (จะไม่ backup); resource database เป็นของไฟล์ executable ที่ติดตั้งมากับ SQL Server — สองตัวนี้จะ backup ไม่ได้และไม่จำเป็น — อ่านละเอียด: [Section 3 หัวข้อ 3.6](Sections/03_Special_Restores/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **ZSTD backup compression (2025)** — restore ไฟล์ ZSTD เร็วขึ้นพร้อมกับการ backup ที่เล็กลง (decompress เร็วกว่า MS_XPRESS)
- **Full/diff backup บน AG secondary (2025)** — เปลี่ยนแนว offload: primary ไม่ต้องรับ load backup เต็มชุด ผลคือไฟล์ backup ใน network เดียวกัน restore ที่ใดก็ได้ตามปกติ
- **Backup/restore to URL ด้วย managed identity (2025, Azure Arc)** — restore จาก cloud storage ไม่ต้องจัดการ credential เพิ่ม
- **Log shipping TLS 1.3 + TDS 8.0** — การเชื่อมต่อ log shipping ใช้ strict encryption ได้ (มี **breaking changes** ที่ควรอ่านก่อน upgrade — ดูลิงก์ breaking changes)
- **ADR บน tempdb (2025)** — redo/undo ระดับ engine เร็วขึ้น รวมถึงงาน temp table; ผลต่อ restore คือ recovery หลัง restart สั้นลง
- **Restore from URL (Azure/S3)** มาตั้งแต่ SQL Server 2016/2022 ตามลำดับ — ทุก command ในโมดูลนี้รันจาก URL ได้เหมือน DISK

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [RESTORE Statements](https://learn.microsoft.com/sql/t-sql/statements/restore-statements-transact-sql?view=sql-server-ver17), [Restore and Recovery Overview](https://learn.microsoft.com/sql/relational-databases/backup-restore/restore-and-recovery-overview-sql-server?view=sql-server-ver17), [Breaking changes in SQL Server 2025](https://learn.microsoft.com/sql/database-engine/breaking-changes-to-database-engine-features-in-sql-server-2025?view=sql-server-ver17)
