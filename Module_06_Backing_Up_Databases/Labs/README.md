# Lab 6: การ Backup ฐานข้อมูล (บทที่ 6)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab06** (Performing Database Backups) + [Microsoft Learn — BACKUP (Transact-SQL)](https://learn.microsoft.com/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver17) + [Create an Encrypted Backup](https://learn.microsoft.com/sql/relational-databases/backup-restore/create-an-encrypted-backup?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> ต้นฉบับแล็บใช้ AdventureWorks 2016 กับ path `D:\Labfiles` — เวอร์ชันนี้ใช้ **AdventureWorks2025** กับ `C:\SQLBackups` (สร้างโฟลเดอร์ให้เอง) และเพิ่มการเปรียบเทียบ **ZSTD compression ของ SQL Server 2025**

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้ — ZSTD ใช้ได้เฉพาะ 2025), database **AdventureWorks2025** restore เรียบร้อย
- บัญชี sysadmin, พื้นที่ว่าง ~1 GB ที่ `C:\SQLBackups`
- SQL Server service account เขียนไฟล์ที่โฟลเดอร์ปลายทางได้ (สคริปต์สร้างโฟลเดอร์เองผ่าน `xp_create_subdir`)
- อ่านคู่: [Section 1](../Sections/01_Backup_Basics/README.md), [Section 2](../Sections/02_Managing_Backups/README.md), [Section 3](../Sections/03_Special_Options/README.md), [Glossary](../../Glossary.md)

## Scenario

ทีม DBA ของ Adventure Works ได้รับแจ้งว่า job backup ประจำวันยังไม่เคยถูกตรวจสอบเลยตั้งแต่ deploy คุณต้อง (1) สร้างชุด backup ครบ chain พร้อม checksum และตรวจสอบ (2) audit ประวัติจริงจาก msdb และล้างของเก่า (3) ประเมิน ZSTD compression และเตรียม encrypted backup สำหรับข้อมูลอ่อนไหว

## Objectives

1. สร้าง full + log + differential backup ของ AdventureWorks2025 พร้อม CHECKSUM และตรวจด้วย RESTORE VERIFYONLY
2. อ่านและจัดการประวัติ backup ใน msdb รวมถึงการล้างประวัติด้วย `sp_delete_database_backuphistory`
3. เปรียบเทียบ compression (MS_XPRESS vs ZSTD) ด้วยตัวเลขจริง และสร้าง encrypted backup พร้อมทดสอบ restore จำลอง

---

## Exercise 1: สร้างชุด Backup ครบ Chain (Section 1)

### Step 1 — เปิด FULL recovery และทำ full backup

> **ต้องรู้ก่อน**: `WITH FORMAT` สร้าง media set ใหม่ (เขียนทับ); `CHECKSUM` ตรวจ page ระหว่างเขียน; `COMPRESSION` ใช้อัลกอริทึม default (`backup compression algorithm`) — อ่าน [Glossary — Backup](../../Glossary.md)

```sql
USE [master];
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO
ALTER DATABASE [AdventureWorks2025] SET RECOVERY FULL;
GO
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW2025_Lab.bak'
WITH FORMAT, INIT, NAME = N'AW2025 lab full', CHECKSUM, COMPRESSION, STATS = 5;
GO
```

✅ **สังเกต**: ข้อความ "Processed ... pages" และเวลาที่ใช้ — จดขนาดไฟล์เทียบกับ Exercise 3

### Step 2 — เกิดการเปลี่ยนแปลง (จากเดโม UpdatePrices เดิม) แล้ว backup log

```sql
USE [AdventureWorks2025];
GO
UPDATE [Production].[Product] SET [ListPrice] = [ListPrice] + 10;
GO
USE [master];
GO
BACKUP LOG [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW2025_Lab.bak'
WITH NAME = N'AW2025 lab log 1', CHECKSUM;
GO
```

### Step 3 — เปลี่ยนแปลงอีกรอบแล้ว backup differential

```sql
USE [AdventureWorks2025];
GO
UPDATE [Production].[Product] SET [ListPrice] = [ListPrice] * 1.05;
GO
USE [master];
GO
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW2025_Lab.bak'
WITH DIFFERENTIAL, NAME = N'AW2025 lab diff', CHECKSUM;
GO
```

### Step 4 — ตรวจทุก backup set ด้วย RESTORE VERIFYONLY

```sql
RESTORE VERIFYONLY
FROM DISK = N'C:\SQLBackups\AW2025_Lab.bak'
WITH CHECKSUM;
GO
RESTORE HEADERONLY
FROM DISK = N'C:\SQLBackups\AW2025_Lab.bak';
GO
```

**Expected:** VERIFYONLY รายงาน valid ทุก set; HEADERONLY แสดง 3 แถว — full (Position 1, BackupType 1), log (2), diff (5) และ `DifferentialBaseLSN` ของ diff ตรงกับ `LastLSN` ของ full

*(สคริปต์ฉบับเต็มของ Section นี้: [Sections/01_Backup_Basics/Scripts/01_MediaSets_Stripe_Mirror.sql](../Sections/01_Backup_Basics/Scripts/01_MediaSets_Stripe_Mirror.sql))*

---

## Exercise 2: อ่านและจัดการประวัติ msdb (Section 2)

### Step 1 — ประวัติ backup ล่าสุดของทุกฐานข้อมูล

> **ต้องรู้ก่อน**: msdb.dbo.backupset คือแหล่งความจริงของ "backup เกิดขึ้นจริง" — ต่างจากที่เขียนไว้ใน job schedule

```sql
SELECT s.database_name, s.type,
       s.backup_start_date, s.backup_finish_date,
       DATEDIFF(SECOND, s.backup_start_date, s.backup_finish_date) AS duration_sec,
       CAST(s.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       f.physical_device_name
FROM msdb.dbo.backupset AS s
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = s.media_set_id
WHERE s.backup_start_date > DATEADD(DAY, -7, GETDATE())
ORDER BY s.backup_start_date DESC;
GO
```

**Expected:** เห็น 3 แถวจาก Exercise 1 พร้อมเวลาจริงที่ใช้ต่อก้อน — ตัวเลขนี้คือวัตถุดิบของ RTO ประมาณการ

### Step 2 — ตรวจ DB ที่พลาด backup เกิน 24 ชั่วโมง

```sql
SELECT d.name, d.recovery_model_desc,
       MAX(s.backup_finish_date) AS last_full_backup,
       DATEDIFF(HOUR, MAX(s.backup_finish_date), GETDATE()) AS hours_since
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS s
       ON s.database_name = d.name AND s.type = 'D'
WHERE d.database_id > 4 AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
HAVING DATEDIFF(HOUR, MAX(s.backup_finish_date), GETDATE()) > 24
    OR MAX(s.backup_finish_date) IS NULL;
GO
```

✅ **สังเกต**: รายการที่ออกมาคือ "โจทย์แรกของเช้า" ที่ DBA ทุกที่ใช้กันจริง

### Step 3 — ล้างประวัติของ DB ทดลองที่ลบไปแล้ว

```sql
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'LabHistory';
GO
```

*(สคริปต์ฉบับเต็ม: [Sections/02_Managing_Backups/Scripts/02_Msdb_BackupHistory.sql](../Sections/02_Managing_Backups/Scripts/02_Msdb_BackupHistory.sql))*

---

## Exercise 3: Compression เทียบตัวเลข + Encrypted Backup (Section 3)

### Step 1 — ทำ backup สามแบบเทียบกัน

> **ต้องรู้ก่อน**: `COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM)` ใช้ได้ตั้งแต่ SQL Server 2025 — บน 2019/2022 ใช้แค่ `WITH COMPRESSION` (MS_XPRESS)

```sql
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_none.bak'
WITH FORMAT, INIT, NO_COMPRESSION, CHECKSUM, NAME = N'benchmark none';
GO
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_xpress.bak'
WITH FORMAT, INIT, COMPRESSION (ALGORITHM = MS_XPRESS), CHECKSUM, NAME = N'benchmark MS_XPRESS';
GO
-- SQL Server 2025 เท่านั้น:
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_zstd.bak'
WITH FORMAT, INIT, COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM), CHECKSUM, NAME = N'benchmark ZSTD';
GO
```

### Step 2 — อ่านตัวเลขเปรียบเทียบจาก msdb

```sql
SELECT name,
       DATEDIFF(SECOND, backup_start_date, backup_finish_date) AS duration_sec,
       CAST(backup_size / 1048576.0 AS DECIMAL(10,2)) AS raw_MB,
       CAST(compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       CAST(backup_size / compressed_backup_size AS DECIMAL(6,2)) AS ratio
FROM msdb.dbo.backupset
WHERE database_name = N'AdventureWorks2025'
  AND name LIKE N'benchmark%'
ORDER BY backup_finish_date;
GO
```

**Expected:** ตารางเทียบ — สิ่งที่วัดได้จริงคือ (1) ratio จากสองคอลัมน์ขนาด (2) เวลาจาก start/finish ตัวเลขจริงขึ้นกับเครื่องของคุณ; แนวที่ Microsoft ประกาศ: ZSTD "เร็วกว่าและได้ผลดีกว่า MS_XPRESS" — ให้จดผลของคุณเองลงตารางด้านล่าง (ตัวอย่างรูปแบบเพื่ออ่านผล ไม่ใช่ benchmark จริง):

| อัลกอริทึม | duration_sec | raw_MB | compressed_MB | ratio |
|:-----------|:-------------|:-------|:--------------|:------|
| ไม่บีบ | *(วัดเอง)* | *(วัดเอง)* | = raw | 1.00 |
| MS_XPRESS | *(วัดเอง)* | *(วัดเอง)* | *(วัดเอง)* | *(วัดเอง)* |
| ZSTD MEDIUM | *(วัดเอง)* | *(วัดเอง)* | *(วัดเอง)* | *(วัดเอง)* |

### Step 3 — สร้าง encrypted backup

```sql
USE [master];
GO
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = N'AWBackupCert')
    CREATE CERTIFICATE AWBackupCert WITH SUBJECT = N'AW backup cert', EXPIRY_DATE = '2030-12-31';
GO
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_encrypted.bak'
WITH FORMAT, INIT,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = AWBackupCert),
     CHECKSUM, COMPRESSION, STATS = 5;
GO
-- Backup certificate ให้ restore ได้บน server อื่น
BACKUP CERTIFICATE AWBackupCert
TO FILE = N'C:\SQLBackups\AWBackupCert.cer'
WITH PRIVATE KEY (FILE = N'C:\SQLBackups\AWBackupCert.pvk',
                  ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO
```

✅ **สังเกต**: `msdb.dbo.backupset.is_encrypted = 1` ยืนยันไฟล์เข้ารหัส

### Step 4 — ทดสอบ restore จำลอง "server ใหม่ที่ไม่มี certificate"

```sql
-- (a) ลบ certificate (มีสำเนา .cer/.pvk แล้วจึงทำได้อย่างปลอดภัย)
USE [master];
GO
DROP CERTIFICATE AWBackupCert;
GO
-- (b) ลอง restore → ควร FAIL
BEGIN TRY
    RESTORE DATABASE [AW_EncTest_NoCert]
    FROM DISK = N'C:\SQLBackups\AW_encrypted.bak'
    WITH FILE = 1,
         MOVE N'AdventureWorks2025'     TO N'C:\SQLBackups\AW_EncTest.mdf',
         MOVE N'AdventureWorks2025_log' TO N'C:\SQLBackups\AW_EncTest_log.ldf';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL: ' + ERROR_MESSAGE();
END CATCH
GO
-- (c) นำเข้า certificate กลับแล้ว restore ผ่าน
CREATE CERTIFICATE AWBackupCert
    FROM FILE = N'C:\SQLBackups\AWBackupCert.cer'
    WITH PRIVATE KEY (FILE = N'C:\SQLBackups\AWBackupCert.pvk',
                      DECRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO
RESTORE DATABASE [AW_EncTest_WithCert]
FROM DISK = N'C:\SQLBackups\AW_encrypted.bak'
WITH FILE = 1,
     MOVE N'AdventureWorks2025'     TO N'C:\SQLBackups\AW_EncTest2.mdf',
     MOVE N'AdventureWorks2025_log' TO N'C:\SQLBackups\AW_EncTest2_log.ldf',
     RECOVERY;
GO
USE [AW_EncTest_WithCert];
GO
SELECT TOP 5 ProductID, ListPrice FROM Production.Product ORDER BY ProductID;
GO
```

**Expected:** (b) fail ด้วยข้อความเรื่อง certificate; (c) restore สำเร็จและ query ข้อมูลได้ — สรุปจำง่าย: **ไฟล์ .bak เดียวกัน อยู่กับ certificate = ข้อมูล, อยู่ที่อื่นโดยไม่มี certificate = ขยะ**

---

## 🧹 Clean-up

```sql
USE [master];
GO
ALTER DATABASE [AW_EncTest_WithCert] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [AW_EncTest_WithCert];
ALTER DATABASE [AdventureWorks2025] SET RECOVERY SIMPLE;   -- คืนค่า (ถ้าเดิมเคยเป็น SIMPLE)
GO
```

```powershell
# ลบไฟล์ทดลอง
Remove-Item C:\SQLBackups\AW2025_Lab.bak, C:\SQLBackups\AW_none.bak, `
            C:\SQLBackups\AW_xpress.bak, C:\SQLBackups\AW_zstd.bak, `
            C:\SQLBackups\AW_encrypted.bak, C:\SQLBackups\AW_EncTest*, `
            C:\SQLBackups\AWBackupCert.* -ErrorAction SilentlyContinue
```

---

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม CHECKSUM ทั้งตอน backup และ VERIFYONLY หลัง backup?</b></summary>
CHECKSUM ตอนเขียนเจอ page เสียของ source database; VERIFYONLY ตรวจความสมบูรณ์ของไฟล์หลังเขียน (จับ media ที่เสียหลังเขียน เช่น disk/network ปัญหา) — ตรวจสองชั้นกันของเสียเงียบ ๆ — ดู [Section 2](../Sections/02_Managing_Backups/README.md)
</details>

<details>
<summary><b>2. ZSTD เปลี่ยนพฤติกรรมอะไรเมื่อตั้ง server config เป็นค่า 3?</b></summary>
`WITH COMPRESSION` ทุกคำสั่งที่ไม่ระบุ ALGORITHM จะใช้ ZSTD ทั้ง instance (SQL Server 2025) — คำสั่งที่ระบุ ALGORITHM เองไม่โดนกระทบ — ดู [Section 3 หัวข้อ 3.2](../Sections/03_Special_Options/README.md)
</details>

<details>
<summary><b>3. ไฟล์ encrypted backup ถูก copy ไปเครื่องอื่นที่มี sysadmin เต็ม ๆ — เปิดอ่านได้ไหม?</b></summary>
ไม่ได้ ตราบใดที่ไม่มี certificate ตัวเดิม (พร้อม private key) ใน master ของเครื่องนั้น — RESTORE fail กลางทาง; นี่คือเหตุผลของการ backup certificate + private key แยกเก็บอย่างปลอดภัย — ดู [Section 3 หัวข้อ 3.3](../Sections/03_Special_Options/README.md)
</details>
