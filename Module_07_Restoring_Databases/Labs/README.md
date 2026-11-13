# Lab 7: การ Restore ฐานข้อมูล (บทที่ 7)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab07** (Performing Database Restores) + [Microsoft Learn — Restore and Recovery Overview](https://learn.microsoft.com/sql/relational-databases/backup-restore/restore-and-recovery-overview-sql-server?view=sql-server-ver17) + [Restore a database to a point in time](https://learn.microsoft.com/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> ต้นฉบับใช้ HumanResources/InternetSales/AWDataWarehouse ที่ restore จากไฟล์ .bak สำเร็จรูป — เวอร์ชันนี้ **สร้างทุกอย่างในสคริปต์เอง** (ทำได้บน instance เดียว ไม่ต้องมี AD) และเพิ่ม page restore จำลองจริงด้วย suspect_pages

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้ — ยกเว้น online file restore ของ Exercise 3 ต้อง Enterprise/Developer), database **AdventureWorks2025** restore เรียบร้อย
- บัญชี sysadmin; พื้นที่ว่าง ~1 GB; SSMS 21 (สำหรับ Restore Timeline ใน Exercise 1)
- **รันบนเครื่องทดลองเท่านั้น** — แล็บนี้มีขั้นตอนทำลายข้อมูลจงใจ (และแก้ไขไฟล์ .mdf จำลอง disk พัง)
- อ่านคู่: [Section 1](../Sections/01_Restore_Mechanics/README.md), [Section 2](../Sections/02_Restore_Scenarios/README.md), [Section 3](../Sections/03_Special_Restores/README.md), [Section 4](../Sections/04_Point_In_Time/README.md), [Glossary](../../Glossary.md)

## Scenario

เวลา 14:40 น. นักพัฒนารันสคริปต์ทดลองผิดเซิร์ฟเวอร์ — `DROP TABLE` ตารางยอดขายถูก commit ไปแล้ว คุณต้องกู้ข้อมูลกลับถึงวินาทีก่อนเหตุโดยไม่เสียงานหลังจากนั้น พร้อมกันนี้ต้องซ้อมกู้ encrypted backup และซ่อม page เสียให้ครบเป็น runbook ของทีม

## Objectives

1. กู้คืนจากเหตุ "ลบตารางโดยบังอาจ" ด้วย chain full+log แบบ **point-in-time (STOPAT)** — ครบ 12 ขั้น พร้อมเวลาตัวอย่าง
2. ทดสอบ restore จาก **encrypted backup** ทั้งกรณี fail (ไม่มี certificate) และสำเร็จ (นำเข้า certificate)
3. จำลอง **page corruption** แล้วทำ page restore ด้วยข้อมูลจาก `msdb.dbo.suspect_pages`

---

## Exercise 1: Point-in-Time Restore — กู้กลับก่อน DROP TABLE (12 Steps)

> เวลาตัวอย่างด้านล่างใช้นาฬิกาจริงของเครื่องคุณแทนได้ — สคริปต์จะจดเวลา "จุดปลอดภัย" ให้เองและใช้ตัวแปร ไม่ต้องพิมพ์เวลาเอง

### Step 1 — สร้างฐานข้อมูลสถานการณ์ (เวลาตัวอย่าง 14:00)

> **ต้องรู้ก่อน**: FULL recovery + log chain ครบ = สิทธิ์กู้ถึงทุกวินาที; SIMPLE จะกู้ point-in-time ไม่ได้เลย — อ่าน [Section 1.5](../Sections/01_Restore_Mechanics/README.md)

```sql
USE [master];
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO
IF DB_ID(N'IncidentDB') IS NOT NULL
BEGIN
    ALTER DATABASE [IncidentDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [IncidentDB];
END
GO
CREATE DATABASE [IncidentDB];
ALTER DATABASE [IncidentDB] SET RECOVERY FULL;
GO
USE [IncidentDB];
GO
CREATE TABLE dbo.SalesRecords (id INT IDENTITY, region NVARCHAR(20), amount DECIMAL(12,2));
INSERT INTO dbo.SalesRecords (region, amount)
VALUES (N'กรุงเทพ', 150000.00), (N'เชียงใหม่', 98000.00), (N'ภูเก็ต', 76500.00);
GO
```

### Step 2 — full backup เริ่ม chain (14:02)

```sql
USE [master];
GO
BACKUP DATABASE [IncidentDB] TO DISK = N'C:\SQLBackups\Incident.bak'
WITH FORMAT, INIT, NAME = N'Incident full', CHECKSUM, COMPRESSION;
GO
```

### Step 3 — เกิดงานปกติเพิ่ม (14:05)

```sql
USE [IncidentDB];
GO
INSERT INTO dbo.SalesRecords (region, amount) VALUES (N'ขอนแก่น', 54000.00);
INSERT INTO dbo.SalesRecords (region, amount) VALUES (N'สงขลา', 47500.00);
GO
```

### Step 4 — log backup รอบปกติ (14:10)

```sql
USE [master];
GO
BACKUP LOG [IncidentDB] TO DISK = N'C:\SQLBackups\Incident_log.trn'
WITH FORMAT, INIT, NAME = N'Incident log 14:10', CHECKSUM;
GO
```

### Step 5 — งานใหม่หลัง backup (14:15) — ชุดที่ต้องรอดชีวิตจาก tail

```sql
USE [IncidentDB];
GO
INSERT INTO dbo.SalesRecords (region, amount) VALUES (N'พัทยา', 39000.00);
GO
```

### Step 6 — เหตุการณ์: DROP TABLE โดยบังอาจ (14:20)

```sql
USE [IncidentDB];
GO
-- จดจุดปลอดภัยไว้ในตาราง temp (session เดียวกันทั้งแล็บ)
SELECT GETDATE() AS safe_time_before_drop;
DROP TABLE dbo.SalesRecords;
GO
SELECT * FROM dbo.SalesRecords;   -- ❌ Invalid object name
GO
```

✅ **สังเกต**: `safe_time_before_drop` ที่ PRINT ออกมา — นี่คือ STOPAT เป้าหมายของเรา

### Step 7 — Tail-log backup ก่อนแตะอย่างอื่น (14:21)

> **ต้องรู้ก่อน**: tail = log ตั้งแต่ log backup ล่าสุดถึงวินาทีนี้ — งาน 14:15 (พัทยา) อยู่ในนี้ และไม่ได้อยู่ใน backup อื่นเลย

```sql
USE [master];
GO
BACKUP LOG [IncidentDB] TO DISK = N'C:\SQLBackups\Incident_tail.trn'
WITH NORECOVERY, CHECKSUM;
GO
```

### Step 8 — กู้ full บนชื่อสำเนา (14:23)

```sql
RESTORE DATABASE [IncidentDB_Recovered]
FROM DISK = N'C:\SQLBackups\Incident.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'IncidentDB'     TO N'C:\SQLBackups\IncidentDB_R.mdf',
     MOVE N'IncidentDB_log' TO N'C:\SQLBackups\IncidentDB_R_log.ldf',
     STATS = 10;
GO
```

### Step 9 — กู้ log รอบปกติด้วย STOPAT (14:24)

> เอาเวลาจาก Step 6 (`safe_time_before_drop`) มาใส่แทนที่ตัวอย่างด้านล่าง — กติกาคือระบุ STOPAT **เท่ากัน** ในทุก RESTORE LOG

```sql
RESTORE LOG [IncidentDB_Recovered]
FROM DISK = N'C:\SQLBackups\Incident_log.trn'
WITH NORECOVERY,
     STOPAT = N'2026-11-12T14:20:00.000';   -- ⬅ แก้เป็นเวลาจริงของคุณจาก Step 6
GO
```

**Expected:** ข้อความ restore log — engine กู้ log แต่ยังไม่เปิดใช้ (NORECOVERY)

### Step 10 — กู้ tail จนจุดตัดและเปิดใช้งาน (14:25)

```sql
RESTORE LOG [IncidentDB_Recovered]
FROM DISK = N'C:\SQLBackups\Incident_tail.trn'
WITH RECOVERY,
     STOPAT = N'2026-11-12T14:20:00.000';   -- ⬅ เวลาเดียวกับ Step 9
GO
```

### Step 11 — ตรวจผลลัพธ์

```sql
USE [IncidentDB_Recovered];
GO
SELECT * FROM dbo.SalesRecords;
GO
```

**Expected:** **5 แถวครบ** (กรุงเทพ → พัทยา) — ตารางกลับมาก่อน DROP โดยที่งานทั้งหมดก่อนหน้าไม่หาย เป้าหมายคือ "วินาทีก่อนเหตุ" เป๊ะ

### Step 12 — ดึงข้อมูลกลับตัวจริง (หากต้องการ)

```sql
USE [IncidentDB];
GO
CREATE TABLE dbo.SalesRecords (id INT IDENTITY, region NVARCHAR(20), amount DECIMAL(12,2));
INSERT INTO dbo.SalesRecords (region, amount)
SELECT region, amount FROM [IncidentDB_Recovered].dbo.SalesRecords;
GO
SELECT * FROM dbo.SalesRecords;   -- ตัวจริงกลับมาครบ 5 แถว
GO
```

✅ **สังเกต**: รูปแบบ "กู้บนสำเนา → ยกข้อมูลกลับ" ปลอดภัยกว่ากู้ทับตัวจริงทันที — เหตุผลเดียวกับ playbook ใน [Section 4.4](../Sections/04_Point_In_Time/README.md)

*(สคริปต์ฉบับเต็ม: [Sections/04_Point_In_Time/Scripts/01_STOPAT_Restore.sql](../Sections/04_Point_In_Time/Scripts/01_STOPAT_Restore.sql))*

> **ขั้นเสริม SSMS**: คลิกขวา Databases → Restore Database → Timeline → "Specific date and time" — SSMS เลือกชุด backup ให้เองตามเวลาที่เลือก ลองเทียบกับที่ทำด้วยมือ

---

## Exercise 2: Restore จาก Encrypted Backup (Section 3.2)

### Step 1 — เตรียมคีย์ + certificate และทำ encrypted backup

> **ต้องรู้ก่อน**: `ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = ...)` ต้องมี Database Master Key ของ master — restore ต้องมี certificate ตัวเดิม ไม่ใช่แค่ชื่อเดียวกัน

```sql
USE [master];
GO
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO
IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'Lab7Cert')
    DROP CERTIFICATE Lab7Cert;
GO
CREATE CERTIFICATE Lab7Cert WITH SUBJECT = N'Lab7 encrypted backup', EXPIRY_DATE = '2030-12-31';
GO
BACKUP CERTIFICATE Lab7Cert
TO FILE = N'C:\SQLBackups\Lab7Cert.cer'
WITH PRIVATE KEY (FILE = N'C:\SQLBackups\Lab7Cert.pvk', ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO
BACKUP DATABASE [IncidentDB]
TO DISK = N'C:\SQLBackups\Incident_enc.bak'
WITH FORMAT, INIT, ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = Lab7Cert),
     CHECKSUM, COMPRESSION;
GO
```

### Step 2 — จำลอง server ใหม่: ลบ certificate แล้ว restore (ต้อง FAIL)

```sql
USE [master];
GO
DROP CERTIFICATE Lab7Cert;
GO
BEGIN TRY
    RESTORE DATABASE [IncidentDB_NoCert]
    FROM DISK = N'C:\SQLBackups\Incident_enc.bak'
    WITH FILE = 1,
         MOVE N'IncidentDB'     TO N'C:\SQLBackups\Inc_NoCert.mdf',
         MOVE N'IncidentDB_log' TO N'C:\SQLBackups\Inc_NoCert_log.ldf';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL: ' + ERROR_MESSAGE();
END CATCH
GO
```

✅ **สังเกต**: RESTORE fail ด้วยข้อความว่าหา certificate ไม่เจอ — นี่คือความปลอดภัยที่ทำงานจริง

### Step 3 — นำเข้า certificate จากสำเนาแล้ว restore อีกครั้ง

```sql
USE [master];
GO
CREATE CERTIFICATE Lab7Cert
    FROM FILE = N'C:\SQLBackups\Lab7Cert.cer'
    WITH PRIVATE KEY (FILE = N'C:\SQLBackups\Lab7Cert.pvk',
                      DECRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO
RESTORE DATABASE [IncidentDB_WithCert]
FROM DISK = N'C:\SQLBackups\Incident_enc.bak'
WITH FILE = 1,
     MOVE N'IncidentDB'     TO N'C:\SQLBackups\Inc_WithCert.mdf',
     MOVE N'IncidentDB_log' TO N'C:\SQLBackups\Inc_WithCert_log.ldf',
     RECOVERY;
GO
USE [IncidentDB_WithCert];
GO
SELECT COUNT(*) AS rows_restored FROM dbo.SalesRecords;
GO
```

**Expected:** 5 แถว — encrypted backup กู้ได้เมื่อมี master key + certificate ครบ ยืนยัน runbook ของทีมว่า .cer/.pvk ถูกเก็บอย่างปลอดภัย

---

## Exercise 3: Page Restore จำลองจริงด้วย suspect_pages (Section 3.3)

> ⚠️ ขั้นตอนนี้แก้ไขไฟล์ .mdf จริงเพื่อจำลอง disk พัง — **ทำบน PageDemo DB ที่สร้างเพื่อการทดลองเท่านั้น ห้ามใช้กับ DB จริง**

### Step 1 — สร้าง sandbox + backup ครบ (full + log)

```sql
USE [master];
GO
IF DB_ID(N'PageDemo') IS NOT NULL
BEGIN
    ALTER DATABASE [PageDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PageDemo];
END
GO
CREATE DATABASE [PageDemo]
ON  PRIMARY ( NAME = N'PageDemo_data', FILENAME = N'C:\SQLBackups\PageDemo.mdf' )
LOG ON      ( NAME = N'PageDemo_log',  FILENAME = N'C:\SQLBackups\PageDemo_log.ldf' );
GO
ALTER DATABASE [PageDemo] SET RECOVERY FULL;
ALTER DATABASE [PageDemo] SET PAGE_VERIFY CHECKSUM;
GO
USE [PageDemo];
GO
CREATE TABLE dbo.Bill (id INT IDENTITY, payload CHAR(4000) DEFAULT 'x');
INSERT INTO dbo.Bill DEFAULT VALUES;
GO 200
GO
USE [master];
GO
BACKUP DATABASE [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo.bak'
WITH FORMAT, INIT, NAME = N'PageDemo full', CHECKSUM;
GO
USE [PageDemo];
GO
INSERT INTO dbo.Bill DEFAULT VALUES;
GO 50
USE [master];
GO
BACKUP LOG [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo_log.trn'
WITH FORMAT, INIT, NAME = N'PageDemo log', CHECKSUM;
GO
```

### Step 2 — หา page ที่จะทำให้เสีย

```sql
SELECT TOP 1 allocated_page_page_id AS page_to_corrupt
FROM sys.dm_db_database_page_allocations
     (DB_ID(N'PageDemo'), OBJECT_ID(N'PageDemo.dbo.Bill'), NULL, NULL, 'DETAILED')
WHERE is_allocated = 1 AND page_type_desc = N'DATA_PAGE';
GO
```

**Expected:** ตัวเลขหนึ่ง เช่น `9` — จดไว้

### Step 3 — จำลองความเสียหาย (DB OFFLINE → เขียนศูนย์ทับ 1 page → ONLINE)

```sql
USE [master];
GO
ALTER DATABASE [PageDemo] SET OFFLINE;
GO
```

```powershell
# PowerShell (แทน 9 ด้วยเลขจริงจาก Step 2)
$path = 'C:\SQLBackups\PageDemo.mdf'
$page = 9
$zeros = New-Object byte[] 8192
$fs = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'ReadWrite')
$fs.Seek($page * 8192, 'Begin') | Out-Null
$fs.Write($zeros, 0, 8192)
$fs.Close()
"corrupted page $page"
```

```sql
USE [master];
GO
ALTER DATABASE [PageDemo] SET ONLINE;
GO
USE [PageDemo];
GO
SELECT COUNT(*) FROM dbo.Bill;
GO
```

✅ **สังเกต**: `Msg 824` — checksum mismatch บน page นั้น — DB ที่เหลือยังใช้งานได้ (ความเสียหายเฉพาะจุด)

### Step 4 — ตรวจ suspect_pages

```sql
SELECT database_id, file_id, page_id, event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages
WHERE database_id = DB_ID(N'PageDemo');
GO
```

**Expected:** แถวของ page ที่เสีย (event_type = 2 = bad checksum) — ตารางนี้คือแหล่งข้อมูลจริงของ page restore

### Step 5 — Page restore (แทน 9 ด้วยเลขจริง)

```sql
USE [master];
GO
RESTORE DATABASE [PageDemo]
    PAGE = N'1:9'
FROM DISK = N'C:\SQLBackups\PageDemo.bak'
WITH FILE = 1, NORECOVERY;
GO
RESTORE LOG [PageDemo]
FROM DISK = N'C:\SQLBackups\PageDemo_log.trn'
WITH RECOVERY;
GO
```

### Step 6 — ยืนยันและเคลียร์ของ

```sql
USE [PageDemo];
GO
SELECT COUNT(*) FROM dbo.Bill;    -- Expected: 250 แถว ไม่มี error อีก
GO
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
GO
BACKUP LOG [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo_log.trn'
WITH NOINIT, NAME = N'log หลัง page restore', CHECKSUM;
GO
```

**Expected:** ข้อมูลกลับครบโดยไม่ offline ทั้งฐานข้อมูล — ปิดท้ายด้วย log backup ใหม่เพื่อเขียนจุดซ่อมเสร็จลง chain

---

## 🧹 Clean-up

```sql
USE [master];
GO
-- ปิดท้ายทุก database ที่แล็บสร้าง
DECLARE @db sysname;
DECLARE dbs CURSOR FOR
    SELECT name FROM sys.databases
    WHERE name IN (N'IncidentDB', N'IncidentDB_Recovered', N'IncidentDB_NoCert',
                   N'IncidentDB_WithCert', N'PageDemo');
OPEN dbs;
FETCH NEXT FROM dbs INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sql nvarchar(max) =
        N'IF DB_ID(N''' + @db + N''') IS NOT NULL
          BEGIN ALTER DATABASE [' + @db + N'] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
          DROP DATABASE [' + @db + N']; END';
    EXEC (@sql);
    FETCH NEXT FROM dbs INTO @db;
END
CLOSE dbs; DEALLOCATE dbs;
GO
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
GO
```

```powershell
Remove-Item C:\SQLBackups\Incident*, C:\SQLBackups\Inc_*, C:\SQLBackups\PageDemo*, `
            C:\SQLBackups\Lab7Cert.* -ErrorAction SilentlyContinue
```

---

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไมต้อง tail-log backup ก่อน restore เสมอ?</b></summary>
Tail คืองานตั้งแต่ log backup ตัวล่าสุดถึงวินาทีปัจจุบัน — ไม่มีทางได้กลับจาก backup ตัวอื่น; ข้ามขั้นนี้ = ยอมเสียงานทั้งหมดหลัง backup ล่าสุด (RPO แตกทันที) — ดู [Exercise 1 Step 7](#exercise-1-point-in-time-restore--กู้กลับก่อน-drop-table-12-steps)
</details>

<details>
<summary><b>2. ถ้าใน Step 9 ใส่ STOPAT เป็นเวลาหลัง DROP TABLE — จะเกิดอะไร?</b></summary>
กู้กลับมาแล้วตารางยังถูก drop อยู่ (ผลเท่ากับกู้ tail จนจบ) — จุดตัดต้อง "ก่อน" คำสั่งทำลายเสมอ; ทำแบบเผลอไปแล้วต้องเริ่ม restore ใหม่จาก full — ดู [Section 4.1](../Sections/04_Point_In_Time/README.md)
</details>

<details>
<summary><b>3. STOPBEFOREMARK ต่างจาก STOPATMARK อย่างไร?</b></summary>
STOPATMARK กู้ถึง "หลัง commit ของ mark" (รวม transaction); STOPBEFOREMARK ตัด transaction ที่ mark ทิ้ง (กู้ถึงก่อนมัน) — จึงใช้ STOPBEFOREMARK ย้อน DELETE อันตรายที่ถูกฝัง mark ไว้ — ดู [Section 4.2](../Sections/04_Point_In_Time/README.md)
</details>

<details>
<summary><b>4. Page restore ห้ามใช้กรณีไหน?</b></summary>
page เสียจำนวนมาก (ใช้ restore ทั้ง DB/DBCC CHECKDB repair แทน), recovery model SIMPLE, log chain ขาด, มี minimal-logged operation ใน log ช่วงเสีย (BULK_LOGGED), และ filegroup ที่ page อยู่ต้องไม่ offline — ดู [Section 3.3](../Sections/03_Special_Restores/README.md)
</details>

<details>
<summary><b>5. ลืมเก็บ .cer/.pvk ของ certificate — ไฟล์ encrypted backup ยังมีค่าไหม?</b></summary>
ไม่มีทางกู้ได้อีกเลย — encryption ตั้งใจให้เป็นแบบนั้น; นี่คือเหตุผลที่ runbook ต้องเก็บ certificate+private key แยกที่ (และทดสอบ restore เป็นระยะ) — ดู [Exercise 2](#exercise-2-restore-จาก-encrypted-backup-section-32)
</details>
