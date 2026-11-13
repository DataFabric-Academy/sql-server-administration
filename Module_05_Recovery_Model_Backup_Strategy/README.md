หัวใจของงาน DBA คือคำสัญญาเดียว: **"ถ้าระบบพัง เรากู้ข้อมูลกลับมาได้เท่าไร ภายในเวลาเท่าไร"** — โมดูลนี้คือรากฐานของคำสัญญานั้น คุณจะเข้าใจว่า **Recovery Model** (SIMPLE / FULL / BULK_LOGGED) กำหนดพฤติกรรม transaction log และตัวเลือกการกู้คืนทั้งหมดอย่างไร แล้วนำมาออกแบบ **กลยุทธ์การ Backup** ที่สอดคล้องกับความต้องการของธุรกิจ (RPO/RTO) ก่อนที่ Module 6–7 จะลงลึกถึงการรัน `BACKUP` และ `RESTORE` จริง

ทุกการตัดสินใจเรื่อง backup เริ่มจาก transaction log — เพราะ SQL Server เก็บทุกการเปลี่ยนแปลงลง log ก่อนเสมอ การเข้าใจว่า log โตเมื่อไร ถูกตัดทิ้ง (truncation) เมื่อไร และ recovery model ตัดสินใจเรื่องนั้นอย่างไร คือความรู้ที่ทำให้คุณเลือก strategy ได้อย่างมีเหตุผล ไม่ใช่ท่องจำแบบครั่ง ๆ

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – เข้าใจพื้นฐาน**: อธิบาย RPO/RTO และเลือก recovery model ให้เหมาะกับลักษณะ workload ได้
- **ระดับ 2 – วินิจฉัย transaction log**: ตรวจ log growth, VLF, log truncation และ `log_reuse_wait_desc` ด้วย DMV ได้
- **ระดับ 3 – ออกแบบกลยุทธ์**: เลือกชุด full + differential + log backup ให้ตอบโจทย์ RPO/RTO และ retention policy ขององค์กรได้
- **ระดับ 4 – นำไปใช้จริง**: กำหนดขนาด log, จัดการ checkpoint และวางแผน backup ไปยัง disk / Azure Blob Storage / S3 ได้

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [กลยุทธ์การ Backup และ RPO/RTO](Sections/01_Backup_Strategy/README.md) |
| 2 | [Transaction Log, VLF และ Recovery Model](Sections/02_Transaction_Log/README.md) |
| 3 | [ประเภท Backup และการเลือก Strategy](Sections/03_Backup_Types/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. RPO กับ RTO ต่างกันอย่างไร และมาจากการตั้งค่าอะไรใน SQL Server?</b></summary>
**RPO (Recovery Point Objective)** = ข้อมูลที่ยอมรับให้สูญหายได้มากแค่ไหน (วัดเป็นเวลา) — ควบคุมโดย **ระยะห่างของ log backup** ใน FULL recovery; **RTO (Recovery Time Objective)** = ระบบต้องกลับมาใช้ได้ภายในเวลาเท่าไร — ควบคุมโดยเวลา restore (ขนาด backup, จำนวน log ที่ต้อง restore ตามลำดับ) — อ่านละเอียด: [Section 1](Sections/01_Backup_Strategy/README.md)
</details>

<details>
<summary><b>2. ฐานข้อมูล SIMPLE กับ FULL ต่างกันตรงไหนที่สำคัญที่สุด?</b></summary>
SIMPLE: log ถูกตัด (truncate) อัตโนมัติหลัง CHECKPOINT → กู้คืนได้เฉพาะจุด backup ล่าสุด ไม่มี point-in-time recovery; FULL: log ถูกเก็บไว้จนกว่าจะได้ **log backup** → กู้คืนถึงวินาทีใดวินาทีหนึ่ง (STOPAT) ได้ แต่ต้องบริหาร log backup เป็นงานประจำ มิฉะนั้น log จะโตจน disk เต็ม — อ่านละเอียด: [Section 2](Sections/02_Transaction_Log/README.md)
</details>

<details>
<summary><b>3. Log เต็มและไม่ยอมเล็กลงแม้รัน CHECKPOINT แล้ว — ตรวจอะไร?</b></summary>
ดูคอลัมน์ `log_reuse_wait_desc` ใน `sys.databases` หรือ `log_truncation_holdup_reason` จาก `sys.dm_db_log_stats(DB_ID())` — สาเหตุที่พบบ่อย: `LOG_BACKUP` (ยังไม่เคยมี log backup ใน FULL), `ACTIVE_TRANSACTION` (ธุรกรรมยาวค้าง), `ACTIVE_BACKUP_OR_RESTORE`, `AVAILABILITY_REPLICA` (secondary ช้า), `REPLICATION` — อ่านละเอียด: [Section 2 หัวข้อ log truncation](Sections/02_Transaction_Log/README.md)
</details>

<details>
<summary><b>4. VLF คืออะไร ทำไม VLF เยอะเกินจึงเป็นปัญหา และตรวจอย่างไร?</b></summary>
**VLF (Virtual Log File)** คือหน่วยย่อยภายในไฟล์ log — VLF จำนวนมากเกิดจากการ growth ทีละน้อยบ่อยครั้ง ทำให้ recovery/restore/startup ช้า — ตรวจด้วย `sys.dm_db_log_info(DB_ID())` (แทน `DBCC LOGINFO` ที่ถูกแทนที่แล้ว) และนับรวมได้จาก `sys.dm_db_log_stats(DB_ID())` คอลัมน์ `total_vlf_count` — อ่านละเอียด: [Section 2 หัวข้อ VLF](Sections/02_Transaction_Log/README.md)
</details>

<details>
<summary><b>5. Differential backup อิงฐาน (base) จากอะไร และ COPY_ONLY เข้ามาเกี่ยวข้องอย่างไร?</b></summary>
Differential สำรองเฉพาะ extent ที่เปลี่ยนหลัง **full backup แบบปกติล่าสุด** (ดูจาก Differential Changed Map) — full backup แบบ `COPY_ONLY` **ไม่ reset** differential base จึงไม่ทำลายลำดับ differential ที่มีอยู่ และ log backup แบบ COPY_ONLY ไม่ truncate log — อ่านละเอียด: [Section 3](Sections/03_Backup_Types/README.md)
</details>

<details>
<summary><b>6. ใช้ BULK_LOGGED เมื่อไร แลกกับอะไร?</b></summary>
ใช้ช่วง bulk load ใหญ่ ๆ (BULK INSERT + TABLOCK, index rebuild ฯลฯ) เพื่อ **minimal logging** ทำให้ log โตน้อยและทำงานเร็วขึ้น — แต่ช่วงที่ minimal-logged ไม่สามารถ point-in-time recovery ภายใน log backup นั้นได้ และ log backup ที่ครอบคลุมช่วงนั้นต้องเก็บ extent ข้อมูลด้วย (ขนาดใหญ่ขึ้น) — อ่านละเอียด: [Section 2 หัวข้อ BULK_LOGGED](Sections/02_Transaction_Log/README.md) และ [Labs](Labs/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **ZSTD backup compression** — อัลกอริทึมบีบอัดใหม่ เร็วกว่าและได้ ratio ดีกว่า MS_XPRESS (`WITH COMPRESSION (ALGORITHM = ZSTD)`) ใช้งานละเอียดใน Module 6
- **Backup to immutable blob storage** — เขียน backup ไปยัง Azure Blob แบบเขียนครั้งเดียวแก้/ลบไม่ได้ กัน ransomware ที่จ้องลบไฟล์ backup
- **Full + differential backup บน secondary replicas ได้** — เดิมทำได้เฉพาะ COPY_ONLY ใน AG เปลี่ยนแนวทาง offload งาน backup ออกจาก primary
- **Backup to URL ด้วย managed identity** (ผ่าน Azure Arc) — ไม่ต้องจัดการ SAS token เอง
- **ADR บน tempdb** — Accelerated Database Recovery ขยายไปครอบครัว transactions ของ tempdb เร่ง rollback/recovery ของงาน temp table
- สูตรการแบ่ง **VLF** ต่อการ grow ถูกปรับให้สร้าง VLF น้อยลงตั้งแต่ SQL Server 2022 — ปัญหา "VLF เยอะจาก auto-growth ทีละเล็ก" เบาลง แต่การวางขนาด log ที่ดียังจำเป็น

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Backup Compression](https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-compression-sql-server?view=sql-server-ver17), [The Transaction Log (SQL Server)](https://learn.microsoft.com/sql/relational-databases/logs/the-transaction-log-sql-server?view=sql-server-ver17), [Recovery Models](https://learn.microsoft.com/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17)
