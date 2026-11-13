/* =============================================================================
   01_CopyOnly_Backup.sql
   Module 06 - Section 3: COPY_ONLY — พิสูจน์ด้วย DifferentialBaseLSN
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'LabCopyOnly') IS NOT NULL
BEGIN
    ALTER DATABASE [LabCopyOnly] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabCopyOnly];
END
GO
CREATE DATABASE [LabCopyOnly];
ALTER DATABASE [LabCopyOnly] SET RECOVERY FULL;
GO

/* ---------------------------------------------------------------
   1) Full ปกติ (กลายเป็น differential base)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabCopyOnly]
TO DISK = N'C:\SQLBackups\CopyOnly.bak'
WITH FORMAT, INIT, NAME = N'full ปกติ', CHECKSUM;
GO
-- อ่าน differential base ที่ engine เก็บไว้
SELECT name, differential_base_lsn
FROM sys.master_files
WHERE database_id = DB_ID(N'LabCopyOnly') AND type = 0;
GO

/* ---------------------------------------------------------------
   2) COPY_ONLY full — เป็น "สำเนาข้างทาง" ไม่เปลี่ยน base
   --------------------------------------------------------------- */
BACKUP DATABASE [LabCopyOnly]
TO DISK = N'C:\SQLBackups\CopyOnly_copy.bak'
WITH FORMAT, INIT, COPY_ONLY, NAME = N'copy-only full', CHECKSUM;
GO
SELECT name, differential_base_lsn
FROM sys.master_files
WHERE database_id = DB_ID(N'LabCopyOnly') AND type = 0;
GO
/* Expected: differential_base_lsn ไม่เปลี่ยน — ต่างจาก full ปกติที่จะขยับ base */

/* ---------------------------------------------------------------
   3) COPY_ONLY log — ไม่ truncate log, ไม่รบกวน log chain
   --------------------------------------------------------------- */
USE [LabCopyOnly];
GO
IF OBJECT_ID(N'dbo.dummy') IS NULL
    CREATE TABLE dbo.dummy (id INT IDENTITY);
GO
INSERT INTO dbo.dummy DEFAULT VALUES;
GO
USE master;
GO

-- เปรียบเทียบ: log space ก่อน/หลัง COPY_ONLY log backup
USE [LabCopyOnly];
GO
SELECT used_log_space_in_percent FROM sys.dm_db_log_space_usage;   -- ก่อน
BACKUP LOG [LabCopyOnly]
TO DISK = N'C:\SQLBackups\CopyOnly_log.trn'
WITH COPY_ONLY, CHECKSUM;
GO
SELECT used_log_space_in_percent FROM sys.dm_db_log_space_usage;   -- หลัง
GO
/* Expected: % ไม่ลดลง — COPY_ONLY ไม่ truncate log (แต่งานยังถูกเก็บไว้ใน .trn)
   ต่อกัน: log backup ปกติครั้งถัดไปยังตัด log ได้เหมือนเดิม */

BACKUP LOG [LabCopyOnly]
TO DISK = N'C:\SQLBackups\CopyOnly_chain.trn'
WITH CHECKSUM;
GO
SELECT used_log_space_in_percent FROM sys.dm_db_log_space_usage;
GO
/* Expected: ลดลงแล้ว — chain ยังปกติ หลัง COPY_ONLY เสมอ */

/* ---------------------------------------------------------------
   4) ตรวจใน msdb: backup set แบบ copy-only มี is_copy_only = 1
   --------------------------------------------------------------- */
SELECT name, type, is_copy_only, backup_finish_date
FROM msdb.dbo.backupset
WHERE database_name = N'LabCopyOnly'
ORDER BY backup_finish_date;
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabCopyOnly] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabCopyOnly];
GO
-- ลบไฟล์ C:\SQLBackups\CopyOnly* ทีหลัง
GO
