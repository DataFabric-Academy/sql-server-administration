# Lab 5: Recovery Models และพฤติกรรม Transaction Log (บทที่ 5)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab05** (Planning and Implementing a Backup Strategy) + [Microsoft Learn — Recovery Models](https://learn.microsoft.com/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17) + [The Transaction Log](https://learn.microsoft.com/sql/relational-databases/logs/the-transaction-log-sql-server?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> แล็บเดิมใช้ฐานข้อมูล MarketDev/Research ที่สร้างด้วย path คงที่ — เวอร์ชันนี้ให้ SQL Server จัดการไฟล์เอง (ไม่ต้องแก้ path) และเพิ่มการวัดด้วย DMV สมัยใหม่

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** restore เรียบร้อย (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- บัญชีที่มีสิทธิ์ sysadmin (แล็บนี้ต้องสร้าง/ลบ database และเปลี่ยน server config จำลอง)
- พื้นที่ว่าง disk ~500 MB และโฟลเดอร์ `C:\SQLBackups` (สคริปต์สร้างให้เอง)
- อ่านคู่: [Section 1](../Sections/01_Backup_Strategy/README.md), [Section 2](../Sections/02_Transaction_Log/README.md), [Section 3](../Sections/03_Backup_Types/README.md), [Glossary](../../Glossary.md)

## Scenario

บริษัท Adventure Works มีฐานข้อมูลทีมการตลาด (MarketDev — รื้อโหลดข้อมูลทุกวัน) และทีมวิจัย (Research — บันทึกผลการทดลองที่ขาดแถวเดียวไม่ได้) คุณต้องเลือก recovery model ให้ถูก พิสูจน์ด้วยการวัด log จริง แล้วแนะนำจังหวะ backup ให้ทั้งสองทีม

## Objectives

1. สร้างฐานข้อมูล SIMPLE และ FULL คู่เปรียบเทียบ แล้วตรวจพฤติกรรม log truncation
2. วัด log growth ด้วย `DBCC SQLPERF(LOGSPACE)`, `sys.dm_db_log_space_usage` และ `sys.dm_db_log_stats`
3. ทดสอบผลของ BULK_LOGGED ต่อ log size และข้อจำกัดการกู้คืน (minimal logging)

---

## Exercise 1: SIMPLE vs FULL — log truncation ทำงานอย่างไร (Section 2)

### Step 1 — สร้างฐานข้อมูลคู่เปรียบเทียบ

> **ต้องรู้ก่อน**: `ALTER DATABASE ... SET RECOVERY` เลือกโมเดลทันที (คำสั่งเดิมจาก Lab05 Setup เดิมใช้ `SET RECOVERY SIMPLE/FULL`); SIMPLE ตัด log หลัง CHECKPOINT อัตโนมัติ ส่วน FULL ตัดเฉพาะหลัง BACKUP LOG — อ่าน [Glossary — Recovery Model](../../Glossary.md)

```sql
USE [master];
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'MarketDev') IS NOT NULL
BEGIN
    ALTER DATABASE [MarketDev] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MarketDev];
END
GO
CREATE DATABASE [MarketDev];
ALTER DATABASE [MarketDev] SET RECOVERY SIMPLE;
GO

IF DB_ID(N'Research') IS NOT NULL
BEGIN
    ALTER DATABASE [Research] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [Research];
END
GO
CREATE DATABASE [Research];
ALTER DATABASE [Research] SET RECOVERY FULL;
GO
```

✅ **สังเกต**: ทั้งคู่ระดับ compatibility เดียวกัน ต่างกันเฉพาะ recovery model — ทุกอย่างถัดไปเกิดจากตัวเลือกนี้เท่านั้น

*(สคริปต์ฉบับเต็ม: [Sections/02_Transaction_Log/Scripts/03_Recovery_Models_Compare.sql](../Sections/02_Transaction_Log/Scripts/03_Recovery_Models_Compare.sql))*

### Step 2 — โหลดข้อมูลและวัด log growth

```sql
USE [MarketDev];
GO
CREATE TABLE dbo.MktLoads (id INT IDENTITY, col2 CHAR(200) DEFAULT 'x');
INSERT INTO dbo.MktLoads DEFAULT VALUES;
GO 1000

USE [Research];
GO
CREATE TABLE dbo.ResLoads (id INT IDENTITY, col2 CHAR(200) DEFAULT 'x');
INSERT INTO dbo.ResLoads DEFAULT VALUES;
GO 1000
GO

-- เครื่องมือวัดสองรุ่นคู่กัน
DBCC SQLPERF(LOGSPACE);
GO
SELECT d.name, l.used_log_space_in_percent,
       l.log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage AS l
CROSS JOIN sys.databases AS d
WHERE d.database_id = DB_ID() AND l.database_id = DB_ID();
GO
-- (รันคำถามแยกใน MarketDev และ Research แต่ละ database)

SELECT * FROM sys.dm_db_log_stats(DB_ID(N'MarketDev'));
SELECT * FROM sys.dm_db_log_stats(DB_ID(N'Research'));
GO
```

**Expected:** ตัวเลข log space ขยับขึ้นในทั้งสอง DB แต่ `log_reuse_wait_desc` ต่างกัน — MarketDev = `NOTHING` (SIMPLE), Research = `LOG_BACKUP` (ยังไม่มี log backup)

### Step 3 — CHECKPOINT แล้ววัดซ้ำ

```sql
CHECKPOINT;   -- ตัด log ของ MarketDev ทันที แต่ไม่แตะ Research
GO
DBCC SQLPERF(LOGSPACE);
GO
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases WHERE name IN (N'MarketDev', N'Research');
GO
```

✅ **สังเกต**: Log Space Used (%) ของ MarketDev ลดลง — Research ยังคงสูงเพราะ FULL รอ log backup เท่านั้น

### Step 4 — BACKUP LOG ต้องมี full ก่อน (กติกา chain)

```sql
BACKUP DATABASE [Research]
TO DISK = N'C:\SQLBackups\Research.bak'
WITH FORMAT, INIT, NAME = N'Research full 1', CHECKSUM, COMPRESSION;
GO
BACKUP LOG [Research]
TO DISK = N'C:\SQLBackups\Research.trn'
WITH FORMAT, INIT, NAME = N'Research log 1', CHECKSUM;
GO
DBCC SQLPERF(LOGSPACE);
GO
```

**Expected:** log space ของ Research ลดลงหลัง log backup — ยืนยันว่า log backup คือกลไก truncation ใน FULL

### Step 5 — BACKUP LOG บน SIMPLE จะ fail

```sql
BACKUP LOG [MarketDev] TO DISK = N'C:\SQLBackups\MarketDev.trn' WITH INIT;
GO
```

✅ **สังเกต**: `Msg 4208` — ฐานข้อมูล SIMPLE ไม่มี log backup และไม่มี point-in-time recovery เป็นข้อจำกัดที่ตกลงกันด้วยโมเดล

---

## Exercise 2: วัด RPO จากจังหวะ log backup (Section 1 + 3)

### Step 1 — ทำจังหวะ backup จำลอง production

> **ต้องรู้ก่อน**: ใน production จังหวะเหล่านี้คือ Agent job — ตรวจ interval จริงจาก `msdb.dbo.backupset` ได้เสมอ

```sql
USE [Research];
GO
INSERT INTO dbo.ResLoads DEFAULT VALUES;
GO 500
WAITFOR DELAY '00:00:05';
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO
INSERT INTO dbo.ResLoads DEFAULT VALUES;
GO 500
WAITFOR DELAY '00:00:05';
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO
```

### Step 2 — คำนวณ RPO ประมาณจาก history

```sql
SELECT database_name,
       MAX(backup_finish_date) AS last_log_backup,
       DATEDIFF(SECOND,
                (SELECT TOP 1 b2.backup_finish_date FROM msdb.dbo.backupset AS b2
                 WHERE b2.database_name = b.database_name AND b2.type = 'L'
                 ORDER BY b2.backup_finish_date DESC OFFSET 1 ROWS),
                MAX(backup_finish_date)) AS approx_RPO_sec
FROM msdb.dbo.backupset AS b
WHERE b.type = 'L' AND b.database_name = N'Research'
GROUP BY b.database_name;
GO
```

**Expected:** `approx_RPO_sec ≈ 5` — ตรงกับค่า WAITFOR; ในระบบจริงคือระยะห่าง job log backup

*(สคริปต์เดโม RPO/RTO ฉบับเต็ม: [Sections/01_Backup_Strategy/Scripts/01_RPO_RTO_BackupInterval.sql](../Sections/01_Backup_Strategy/Scripts/01_RPO_RTO_BackupInterval.sql))*

---

## Exercise 3: BULK_LOGGED — minimal logging แลกกับอะไร (Section 2)

### Step 1 — เตรียมไฟล์ CSV ด้วย PowerShell

> **ต้องรู้ก่อน**: BULK INSERT อ่านไฟล์ฝั่ง SQL Server เท่านั้น — เขียนไฟล์ล่วงหน้าด้วย PowerShell คำสั่งเดียว

```powershell
powershell -Command "1..20000 | ForEach-Object { \"$($_),Item$($_),$($_)\" } | Out-File C:\SQLBackups\BulkData.csv -Encoding ascii"
```

### Step 2 — BULK INSERT + TABLOCK ใน FULL recovery (full logging)

```sql
USE [Research];
GO
CREATE TABLE dbo.BulkLoads (id INT, name NVARCHAR(50), value DECIMAL(10,2));
GO
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
BULK INSERT dbo.BulkLoads
FROM N'C:\SQLBackups\BulkData.csv'
WITH (FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, ROWS_PER_BATCH = 20000);
GO
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
```

**Expected:** log โตขึ้นระดับขนาดข้อมูล (~ครึ่งถึงเท่าของไฟล์ CSV ใน FULL) — ทุกแถวถูกบันทึกเต็มรูปแบบ

### Step 3 — สลับ BULK_LOGGED แล้วทดสอบซ้ำ

```sql
USE [master];
GO
ALTER DATABASE [Research] SET RECOVERY BULK_LOGGED;
GO
TRUNCATE TABLE [Research].dbo.BulkLoads;
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO
USE [Research];
GO
BULK INSERT dbo.BulkLoads
FROM N'C:\SQLBackups\BulkData.csv'
WITH (FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, ROWS_PER_BATCH = 20000);
GO
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
```

✅ **สังเกต**: log เพิ่มน้อยมากเทียบ Exercise 3 Step 2 — minimal logging จันทึกเฉพาะ extent allocation

### Step 4 — ราคาที่ต้องจ่าย: จุดกู้คืนตัดกลางไม่ได้

```sql
-- ช่วงนี้ถ้ามี backup ลง log แล้ว STOPAT กลางช่วง BULK INSERT จะไม่ตัดได้ละเอียด
-- (SQL Server ให้กู้ถึง "จุดที่ bulk operation เสร็จ" เท่านั้น)
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO
ALTER DATABASE [Research] SET RECOVERY FULL;   -- กลับโมเดลปกติ (ไม่หัก chain)
GO
```

**Expected:** เข้าใจว่า BULK_LOGGED เร็วและประหยัด log จริง แต่เสียการตัดจุด (point-in-time granularity) ภายในช่วง minimal-logged — ใช้เฉพาะช่วง bulk load ที่ยอมรับได้

---

## 🧹 Clean-up

```sql
USE [master];
GO
ALTER DATABASE [MarketDev] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [MarketDev];
ALTER DATABASE [Research] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [Research];
GO
```

```powershell
# ลบไฟล์ที่เก็บไว้ระหว่างแล็บ
Remove-Item C:\SQLBackups\Research*.bak, C:\SQLBackups\Research*.trn, `
            C:\SQLBackups\MarketDev*.trn, C:\SQLBackups\BulkData.csv -ErrorAction SilentlyContinue
```

---

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม CHECKPOINT ตัด log ของ MarketDev ได้แต่ Research ไม่ตัด?</b></summary>
SIMPLE ตัด log อัตโนมัติหลัง checkpoint (log ไม่ถูกเก็บ) ส่วน FULL ต้อง log backup จึงตัด เพราะ engine สงวน log record เพื่อ point-in-time recovery — ดู [Section 2 หัวข้อ 2.5](../Sections/02_Transaction_Log/README.md)
</details>

<details>
<summary><b>2. สมมติ Research หายทั้ง disk ตอน 14:07 และ log backup ตัวล่าสุดจบ 14:05 — เราจะเสียข้อมูลเท่าไรหากดำเนินการถูกต้อง?</b></summary>
ถ้าทำ tail-log backup ได้ (DB ยังเข้าถึง log ได้แม้ data เสีย) จะไม่เสียเลย — กู้ full + log ทุกอัน + tail กลับถึง 14:07; ถ้า log file เสียหายจน tail ไม่ได้ จะเสียงาน 14:05–14:07 (RPO ที่ทำได้จริง) — ดู [Section 1](../Sections/01_Backup_Strategy/README.md)
</details>

<details>
<summary><b>3. BULK_LOGGED ทำ log เล็กลงอย่างไร และเสียความสามารถอะไร?</b></summary>
Minimal logging บันทึกแค่ extent ที่จัดสรร (ไม่ใช่ทุกแถว) เมื่อ bulk op ใช้ TABLOCK ใน BULK_LOGGED/SIMPLE — เสียการตัดจุดกลางช่วงนั้นในการกู้ (point-in-time granularity) และ log backup ครอบคลุมช่วงนั้นต้องเก็บ extent ข้อมูลจริง — ดู [Exercise 3](#exercise-3-bulk_logged--minimal-logging-แลกกับอะไร-section-2)
</details>
