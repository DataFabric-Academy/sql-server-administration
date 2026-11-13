# Section 2 — การจัดการ Backup: CHECKSUM, ประวัติ msdb และ Metadata

ไฟล์ backup ที่เขียนไม่สมบูรณ์เป็นอันตรายที่สุดในงาน DBA เพราะมันดู "มีอยู่" จนกว่าวันที่ต้องใช้จริง — การตรวจสอบสองชั้น (`WITH CHECKSUM` ตอนเขียน + `RESTORE VERIFYONLY` หลังเขียน) คือมาตรฐานของงาน production อีกครึ่งหนึ่งของ Section นี้คือ **msdb** — ตารางประวัติการ backup/restore ทุกตัวที่ engine เขียนให้อัตโนมัติ ซึ่งเป็นทั้งเครื่องมือ audit จังหวะจริงของระบบ และแหล่งข้อมูลที่ restore script ใช้ตัดสินใจเลือก backup set

## 2.1 WITH CHECKSUM + STOP_ON_ERROR — ตรวจตั้งแต่ตอนเขียน

- `WITH CHECKSUM` — engine ตรวจ **page checksum** ที่มีอยู่ของทุกหน้า (ถ้า DB ตั้ง PAGE_VERIFY = CHECKSUM — default ตั้งแต่ SQL Server 2008) และคำนวณ checksum ของ backup stream ทั้งหมด
- `STOP_ON_ERROR` (default) — เจอ checksum ผิดให้ backup fail ทันที; เลือกใช้ `CONTINUE_AFTER_ERROR` เฉพาะเหตุการณ์ฉุกเฉิน (เช่น กู้ log ส่วนท้ายจาก DB ที่พัง) โดยยอมรับไฟล์ที่เสียบางส่วน

```sql
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW2025.bak'
WITH FORMAT, INIT, CHECKSUM, STOP_ON_ERROR, COMPRESSION, STATS = 5;
```

ตรวจหา page เสียที่ backup จับได้ ด้วยตาราง `msdb.dbo.suspect_pages` (จำกัด 1,000 แถว):

```sql
SELECT DB_NAME(database_id) AS db_name, file_id, page_id,
       event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages
WHERE event_type IN (1, 2, 3);      -- 1 = 823/824 อื่น ๆ, 2 = bad checksum, 3 = torn page
```

ค่า `event_type` ที่ควรรู้: **1** = 823 (disk error) หรือ 824 อื่น ๆ, **2** = bad checksum, **3** = torn page, **4** = restored (page ถูกกู้หลังเคย suspect), **5** = repaired ด้วย DBCC — ตารางนี้คือแหล่งข้อมูลของ page restore ใน [Module 7](../../../Module_07_Restoring_Databases/Sections/03_Special_Restores/README.md)

## 2.2 RESTORE VERIFYONLY — ตรวจไฟล์โดยไม่กู้จริง

`RESTORE VERIFYONLY` อ่านโครงสร้าง backup ทั้งก้อนและตรวจ checksum โดยไม่ restore — เร็วกว่ากู้จริงหลายเท่า เหมาะเป็น watchdog รายวันใน Agent job:

```sql
RESTORE VERIFYONLY
FROM DISK = N'C:\SQLBackups\AW2025.bak'
WITH CHECKSUM;
GO
-- ✅ "The backup set on file 1 is valid."
-- ❌ "Damage to the backup set was detected." (ต้องวางแผน backup ใหม่ทันที)
```

สำหรับ media set ยังมี `RESTORE LABELONLY` (อ่าน media header อย่างเดียว) — ใช้ตรวจสื่อที่ยืมมาจากรอบอื่น และรัน VERIFYONLY กับชุด stripe ต้องระบุ**ทุกไฟล์**ของ set:

```sql
RESTORE VERIFYONLY
FROM DISK = N'C:\SQLBackups\AW_1.bak',
     DISK = N'E:\SQLBackups\AW_2.bak'
WITH CHECKSUM;
```

> มาตรฐานที่แนะนำ: job backup ทุกตัวรัน `BACKUP ... WITH CHECKSUM` ตามด้วย `RESTORE VERIFYONLY ... WITH CHECKSUM` ใน step ถัดไป — แจ้ง Operator เมื่อ fail มิฉะนั้นไฟล์เสียจะนั่งอยู่เงียบ ๆ จนถึงวันที่ต้องใช้

เดโมรันได้ครบทั้ง CHECKSUM/VERIFYONLY/stripes: [Scripts/01_Verify_Checksum.sql](Scripts/01_Verify_Checksum.sql)

## 2.3 ประวัติ Backup ใน msdb

ทุกครั้งที่ BACKUP/RESTORE สำเร็จ (หรือบางส่วน) engine บันทึกลงตารางใน msdb:

| ตาราง | เก็บอะไร | คอลัมน์ที่ใช้บ่อย |
|:-------|:----------|:-------------------|
| `backupset` | ผลการ backup หนึ่งครั้ง | type (D/I/P/F/L), backup_start/finish_date, backup_size, compressed_backup_size, first_lsn/last_lsn, differential_base_lsn, expiration_date, is_copy_only, is_encrypted |
| `backupfile` | ไฟล์ที่อยู่ใน backup นั้น | logical_name, physical_name, file_type (D=Data/L=Log), file_size |
| `backupmediaset` | media set | name, media_family_count |
| `backupmediafamily` | device แต่ละตัวของ media set | logical_device_name, physical_device_name (path ไฟล์จริง) |
| `restorehistory` | ประวัติการ restore | destination_database_name, restore_date, restore_type |

Query ที่ใช้ทำงานจริง:

```sql
-- (a) "ตัวไหน backup ล่าสุด ของ DB ไหน ที่ไหน เมื่อไร"
SELECT s.database_name,
       CASE s.type WHEN 'D' THEN N'Full' WHEN 'I' THEN N'Diff'
            WHEN 'L' THEN N'Log' WHEN 'P' THEN N'Partial'
            WHEN 'F' THEN N'File' END AS backup_type,
       s.backup_start_date, s.backup_finish_date,
       DATEDIFF(SECOND, s.backup_start_date, s.backup_finish_date) AS duration_sec,
       CAST(s.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       f.physical_device_name
FROM msdb.dbo.backupset AS s
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = s.media_set_id
WHERE s.database_name = N'AdventureWorks2025'
ORDER BY s.backup_finish_date DESC;
```

```sql
-- (b) ตรวจ DB ไหนพลาด full backup เกิน 24 ชั่วโมง (watchdog เช้าวันจันทร์)
SELECT d.name, d.recovery_model_desc,
       MAX(s.backup_finish_date) AS last_full_backup,
       DATEDIFF(HOUR, MAX(s.backup_finish_date), GETDATE()) AS hours_since
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS s
       ON s.database_name = d.name AND s.type = 'D'
WHERE d.database_id > 4 AND d.state_desc = N'ONLINE'
GROUP BY d.name, d.recovery_model_desc
HAVING DATEDIFF(HOUR, MAX(s.backup_finish_date), GETDATE()) > 24
    OR MAX(s.backup_finish_date) IS NULL;
```

```sql
-- (c) แนวโน้มขนาด log backup รายวัน — วัตถุดิบวางแผน storage และจังหวะ backup
SELECT CONVERT(date, backup_start_date) AS backup_day,
       COUNT(*) AS log_backups,
       CAST(SUM(compressed_backup_size) / 1048576.0 AS DECIMAL(10,1)) AS total_MB
FROM msdb.dbo.backupset
WHERE database_name = N'AdventureWorks2025' AND type = 'L'
GROUP BY CONVERT(date, backup_start_date)
ORDER BY backup_day DESC;
```

การอ่านประวัติมีประโยชน์ตรง ๆ สามอย่าง: ตรวจว่า job หลุด (ไม่มี backup ในช่วงคาด), วัดแนวโน้มขนาด (วางแผน storage), และหา backup set ที่ restore ต้องอ้าง (`FILE = position`) โดยไม่ต้องเปิดไฟล์จริง

เดโมอ่านประวัติครบทั้งตาราง (รวม restorehistory): [Scripts/02_Msdb_BackupHistory.sql](Scripts/02_Msdb_BackupHistory.sql)

## 2.4 ล้างประวัติฐานข้อมูลที่ลบไปแล้ว — sp_delete_database_backuphistory

เมื่อ drop database ประวัติใน msdb ยังค้าง — ยิ่ง backup/restore ซ้ำเยอะยิ่งสะสม ทำให้ query ประวัติช้าและเครื่องมือ restore เห็น DB ที่ไม่มีตัวตน:

```sql
-- ลบประวัติทั้งหมดของฐานข้อมูลที่เลิกใช้แล้ว
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'OldAppDB';
```

> จำเป็นก่อน restore ทับ DB ชื่อเดิมในหลาย workflow (เครื่องมือ restore wizard จะเตือน) และเป็นหน้าที่ตามมาของการรื้อโครงการเก่า — เพิ่มเข้าใน runbook "ยกเลิกฐานข้อมูล" ของทีม

การล้างที่มาคู่กันอีกตัวคือประวัติ job ของ Agent:

```sql
-- ลบประวัติ job เก่ากว่า 30 วัน (คู่กับการล้าง backup history)
EXEC msdb.dbo.sp_purge_jobhistory @oldest_date = '2026-10-14';
```

## 2.5 Metadata ของไฟล์ backup — HEADERONLY / FILELISTONLY / LABELONLY

สามคำสั่งอ่านไฟล์ .bak โดยไม่ restore (ต่างจาก VERIFYONLY ที่ตรวจเพื่อความเสียหาย — ตรงนี้คืออ่านข้อมูลเพื่อตัดสินใจ):

| คำสั่ง | คืนอะไร | ใช้ตอนไหน |
|:--------|:--------|:-----------|
| `RESTORE HEADERONLY` | แถวต่อ **backup set** ในไฟล์ — type, LSN เข้า-ออก, base ของ diff, ขนาด | เลือกว่าจะ restore `FILE = n` อันไหน |
| `RESTORE FILELISTONLY` | แถวต่อ **ไฟล์ data/log** ใน backup — logical name, physical name, ขนาด | สร้าง `MOVE` ให้ถูกชื่อ logical ตอน restore ไปที่ใหม่ |
| `RESTORE LABELONLY` | media header — MEDIANAME, จำนวน family | ตรวจสื่อว่าก้อนนี้ของใคร |

```sql
RESTORE HEADERONLY   FROM DISK = N'C:\SQLBackups\AW2025.bak';
RESTORE FILELISTONLY FROM DISK = N'C:\SQLBackups\AW2025.bak';
```

คอลัมน์ที่จำเป็นตอน restore จาก HEADERONLY:

| คอลัมน์ | ใช้ทำอะไร |
|:--------|:----------|
| `Position` | ค่าที่ใส่ใน `RESTORE ... WITH FILE = n` |
| `BackupType` | 1 = Full, 2 = Log, 5 = Differential, 4 = File, 6 = Partial |
| `FirstLSN` / `LastLSN` | ขอบเขต log record ของ backup — ใช้ตรวจลำดับ chain |
| `DifferentialBaseLSN` | LSN ที่ diff นี้เทียบกับ full ที่เป็น base |
| `DatabaseName` / `BackupName` / `BackupFinishDate` | ระบุตัวตนของก้อน |

เดโมอ่านครบพร้อมคำอธิบายคอลัมน์ + กู้จริงตามตำแหน่งที่อ่านได้: [Scripts/03_RestoreMetadata.sql](Scripts/03_RestoreMetadata.sql)

## 2.6 Expiration และ Trace Flag 3226

**Expiration** — กันเขียนทับ backup ก่อนกำหนด:

```sql
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_Month.bak'
WITH FORMAT, INIT, RETAINDAYS = 35,   -- หรือ EXPIREDATE = '2026-12-17'
     NAME = N'AW monthly (เก็บ 35 วัน)';
```

- `RETAINDAYS` ชนะ `EXPIREDATE` เมื่อใช้พร้อมกัน; ถ้าไม่ระบุ engine ใช้ server config `media retention`
- ตรวจ expiration ที่เคยตั้งไว้จาก `msdb.dbo.backupset.expiration_date`
- ข้อจำกัดที่ต้องรู้: กันเฉพาะการเขียนทับโดย SQL Server — ไม่กันการลบไฟล์ที่ OS และ `FORMAT` เขียนทับได้เสมอ (format แถม SKIP ตรวจให้ด้วย)

**Trace flag 3226** — ปิดข้อความ successful backup ใน SQL Server error log:

```sql
DBCC TRACEON (3226);          -- เปิดทดลอง (session นี้)
DBCC TRACESTATUS (3226);      -- ตรวจสถานะ
DBCC TRACEOFF (3226);         -- ปิด
```

ประโยชน์เห็นชัดเมื่อ log backup ถี่ (ทุก 5 นาที = 288 ข้อความ/วัน) — error log จะหมดความหมายเพราะถูก "successful backup" กลืน กลไก alert บน error log ขององค์กรไม่ต้อง filter ขยะ ถ้าต้องการใช้ถาวรให้ตั้งเป็น startup parameter `-T3226` ของ instance หรือ `DBCC TRACEON (3226, -1)` หลัง restart ([BACKUP — Remarks](https://learn.microsoft.com/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver17#remarks))

เดโม expiration + trace flag: [Scripts/04_Expiration_TraceFlag3226.sql](Scripts/04_Expiration_TraceFlag3226.sql)

## 2.7 เชื่อมเข้าสู่งานประจำวัน (Agent job pattern)

| Job step | คำสั่ง | วัตถุประสงค์ |
|:---------|:-------|:--------------|
| 1 — Backup | `BACKUP DATABASE/LOG ... WITH CHECKSUM, COMPRESSION` | สร้างไฟล์ |
| 2 — Verify | `RESTORE VERIFYONLY ... WITH CHECKSUM` | จับไฟล์เสียทันที |
| 3 — Cleanup | PowerShell ลบไฟล์เก่ากว่า retention | ควบคุมพื้นที่ |
| 4 — History hygiene | `sp_delete_database_backuphistory` (DB ที่เลิกใช้) | msdb ไม่บวม |
| 5 — Notify | ผูก Operator กับ `ON FAILURE` | รู้ตัวเร็วเมื่อ chain ขาด |

> อ่านเพิ่มเรื่องการทำ job อัตโนมัติใน [Module 8](../../README.md) (Automation) — Section นี้เตรียมทุกองค์ประกอบที่ job จะเรียกใช้ให้พร้อมแล้ว

### 🚀 SQL Server 2025 & Modern Notes
- **ZSTD compression (2025)** ลดขนาดไฟล์ที่ VERIFYONLY/ลบ/ย้าย — เร็วกว่า MS_XPRESS รายละเอียดใน [Section 3](../03_Special_Options/README.md)
- **Immutable blob storage (2025)** เปลี่ยนแนวเล่นของ retention — ตั้ง policy ฝั่ง Azure container กันลบไฟล์ ตอกย้ำข้อจำกัดว่า `RETAINDAYS` กันเฉพาะ engine ([Backup to URL](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url?view=sql-server-ver17))
- `backup compression algorithm` server config (ค่า 3 = ZSTD) ตั้ง default ให้ WITH COMPRESSION ทุกคำสั่งใน instance — ดูการตั้งค่าใน [Section 3](../03_Special_Options/README.md)
- msdb history tables เป็นระบบเดียวกันตั้งแต่ SQL Server 2005 — สคริปต์ audit ที่เขียนวันนี้ใช้ได้ทั้ง 2019–2025

> อ้างอิง: [Possible Media Errors During Backup and Restore](https://learn.microsoft.com/sql/relational-databases/backup-restore/possible-media-errors-during-backup-and-restore-sql-server?view=sql-server-ver17), [RESTORE VERIFYONLY](https://learn.microsoft.com/sql/t-sql/statements/restore-statements-verifyonly-transact-sql?view=sql-server-ver17), [Backup History and Header Information](https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-history-and-header-information-sql-server?view=sql-server-ver17), [suspect_pages](https://learn.microsoft.com/sql/relational-databases/system-tables/suspect-pages-transact-sql?view=sql-server-ver17)
