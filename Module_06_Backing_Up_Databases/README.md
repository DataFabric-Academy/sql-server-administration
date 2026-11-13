โมดูลนี้คือ "ประโยคคำสั่ง" ของกลยุทธ์ที่วางไว้ใน Module 5 — คุณจะได้รัน `BACKUP` จริงทุกรูปแบบที่ใช้งานจริง: จากไฟล์เดียวจนถึง stripe/MIRROR, backup log กับ tail-log เมื่อฐานข้อมูลกำลังจะพัง, การอ่านประวัติ backup จาก msdb เพื่อควบคุมจังหวะจริงของระบบ, และตัวเลือกพิเศษที่ทำให้ไฟล์ backup เล็กลง (ZSTD compression ของ SQL Server 2025), ปลอดภัยขึ้น (encryption) และอยู่นอกเครื่องได้ (backup to URL ทั้ง Azure Blob Storage และ S3-compatible storage)

เป้าหมายปลายทางของโมดูลนี้ไม่ใช่แค่ "backup ได้" แต่คือ **backup ที่ตรวจสอบได้ (VERIFYONLY + CHECKSUM), มีบันทึกประวัติ (msdb history), มีนโยบายเก็บรักษา (expiration/retention)** และ restore จริงได้ใน Module 7

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – รัน backup พื้นฐาน**: สร้าง full/diff/log backup ลง disk พร้อม CHECKSUM และตรวจด้วย RESTORE VERIFYONLY ได้
- **ระดับ 2 – จัดการสื่อและประวัติ**: อธิบาย media set/family/backup set, จัดการ expiration และล้างประวัติ msdb ด้วย `sp_delete_database_backuphistory` ได้
- **ระดับ 3 – รับมือสถานการณ์จริง**: ทำ tail-log backup ด้วย NO_TRUNCATE, file/partial backup และอ่าน metadata ด้วย RESTORE HEADERONLY/FILELISTONLY ได้
- **ระดับ 4 – ยกระดับความปลอดภัยและสถาปัตยกรรม**: เลือกอัลกอริทึมบีบอัด (MS_XPRESS vs ZSTD), ตั้ง backup encryption ด้วย certificate และวาง backup to URL/S3 ให้เป็นระบบได้

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [พื้นฐานการ Backup — Media Sets, Stripe, MIRROR และ Tail-Log](Sections/01_Backup_Basics/README.md) |
| 2 | [การจัดการ Backup — CHECKSUM, ประวัติ msdb และ Metadata](Sections/02_Managing_Backups/README.md) |
| 3 | [ตัวเลือกพิเศษ — COPY_ONLY, ZSTD, Encryption และ Backup to URL](Sections/03_Special_Options/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. Media set, media family และ backup set ต่างกันอย่างไร?</b></summary>
**Media set** คือชุดสื่อทั้งหมดที่ backup หนึ่งเขียนลง (เช่น 3 ไฟล์ stripe); **media family** คือข้อมูลที่เขียนลง device หนึ่งของ set นั้น; **backup set** คือผลจากการ BACKUP หนึ่งครั้งที่เก็บใน set — ไฟล์เดียวอาจมีหลาย backup set (NOINIT) — อ่านละเอียด: [Section 1](Sections/01_Backup_Basics/README.md)
</details>

<details>
<summary><b>2. WITH CHECKSUM กับ RESTORE VERIFYONLY ต่างกันตรงไหน?</b></summary>
CHECKSUM ตรวจระหว่าง **เขียน** backup (เห็น page ที่เสียตอนสำรอง) — VERIFYONLY ตรวจโครงสร้างไฟล์ **หลังเขียนเสร็จ** โดยไม่ restore จริง ใช้เป็น watchdog รายวัน; ทั้งคู่ใช้ร่วมกันใน job — อ่านละเอียด: [Section 2](Sections/02_Managing_Backups/README.md)
</details>

<details>
<summary><b>3. Tail-log backup ด้วย NO_TRUNCATE ใช้เมื่อไร และต่างจาก log backup ปกติ?</b></summary>
ใช้เมื่อฐานข้อมูล**เสียหาย** (data file พัง) แต่ยังต้องการกู้ log ส่วนท้ายถึงวินาทีสุดท้าย — NO_TRUNCATE = COPY_ONLY + CONTINUE_AFTER_ERROR โดยพฤติกรรม, ไม่ truncate log และพยายาม backup แม้ DB ออฟไลน์ (ยกเว้น EMERGENCY/ OFFLINE) — อ่านละเอียด: [Section 1](Sections/01_Backup_Basics/README.md)
</details>

<details>
<summary><b>4. COPY_ONLY full backup ต่างจาก full ปกติอย่างไร?</b></summary>
COPY_ONLY ไม่ reset differential base — differential ถัดไปยังเทียบกับ full ก่อนหน้าเหมือนเดิม เหมาะกับ "ทำสำเนาเพิ่มเป็นการชั่วคราว" (เช่นก่อนทดลองเปลี่ยนแปลงใหญ่) โดยไม่รบกวนตาราง backup หลัก — อ่านละเอียด: [Section 3](Sections/03_Special_Options/README.md)
</details>

<details>
<summary><b>5. จะเลือก ZSTD หรือ MS_XPRESS? ปรับ default อย่างไร?</b></summary>
ZSTD (SQL Server 2025+) เร็วกว่าและบีบได้ดีกว่า — กำหนดต่อ backup ด้วย `WITH COMPRESSION (ALGORITHM = ZSTD)` หรือทั้ง instance ด้วย server config `backup compression algorithm` (ค่า 3 = ZSTD) — อ่านละเอียด: [Section 3](Sections/03_Special_Options/README.md)
</details>

<details>
<summary><b>6. ทำไม encrypted backup จึง restore บน server อื่นไม่ได้ทันที?</b></summary>
ข้อมูล encrypt ด้วย certificate ที่อยู่ใน master ของ server ต้นทาง — ปลายทางต้องมี Database Master Key ของ master และ certificate ตัวเดิม (backup/restore certificate พร้อม private key) ก่อน RESTORE จึงจะผ่าน — อ่านละเอียด: [Section 3](Sections/03_Special_Options/README.md) และ [Module 7](../Module_07_Restoring_Databases/Sections/03_Special_Restores/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **ZSTD backup compression** — อัลกอริทึมใหม่ เร็วกว่าและได้ ratio ดีกว่า MS_XPRESS; ระบุระดับได้ (`LEVEL = LOW/MEDIUM/HIGH`)
- **Backup to immutable blob storage** — กัน ransomware แก้/ลบไฟล์ backup; รองรับระดับ container, engine เขียนแบบ one-pass
- **Backup to URL ด้วย managed identity** (ผ่าน Azure Arc) — ไม่ต้องเก็บ SAS token ใน SQL Server อีกต่อไป
- **Full + differential บน AG secondary** — offload งาน backup ออกจาก primary ได้เต็มรูปแบบ (เดิม COPY_ONLY เท่านั้น)
- **Trace flag 3226** — (มีมานานแต่ใช้บ่อยขึ้นในยุค log backup ถี่) ปิดข้อความ successful backup ใน error log กัน log spam
- Backup to S3-compatible storage มาตั้งแต่ SQL Server 2022 — MAXTRANSFERSIZE default 10 MB, stripe สูงสุด 64 URLs

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [BACKUP (Transact-SQL)](https://learn.microsoft.com/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver17), [Backup Compression](https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-compression-sql-server?view=sql-server-ver17), [Backup to URL for Azure Blob Storage](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url?view=sql-server-ver17)
