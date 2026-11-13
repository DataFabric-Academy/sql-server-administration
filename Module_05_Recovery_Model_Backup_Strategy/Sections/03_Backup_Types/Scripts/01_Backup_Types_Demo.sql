/* =============================================================================
   01_Backup_Types_Demo.sql
   Module 05 - Section 3: ประเภท backup ทั้งหมด — full / diff / log / partial
   และการตรวจ differential base ด้วย RESTORE HEADERONLY
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง FULL recovery + ข้อมูล
   --------------------------------------------------------------- */
IF DB_ID(N'LabBackupTypes') IS NOT NULL
BEGIN
    ALTER DATABASE [LabBackupTypes] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabBackupTypes];
END
GO
CREATE DATABASE [LabBackupTypes];
ALTER DATABASE [LabBackupTypes] SET RECOVERY FULL;
GO
USE [LabBackupTypes];
GO
CREATE TABLE dbo.Orders (id INT IDENTITY PRIMARY KEY, qty INT, note NVARCHAR(50));
INSERT INTO dbo.Orders (qty, note) VALUES (10, N'ชุดที่ 1');
GO

/* ---------------------------------------------------------------
   2) Full backup — จุดฐานของ chain (และเป็น differential base)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabBackupTypes]
TO DISK = N'C:\SQLBackups\LabBackupTypes.bak'
WITH FORMAT, INIT, NAME = N'Type demo - full', CHECKSUM, COMPRESSION;
GO

INSERT INTO dbo.Orders (qty, note) VALUES (20, N'ชุดที่ 2');
GO

/* ---------------------------------------------------------------
   3) Differential backup — เก็บเฉพาะที่เปลี่ยนหลัง full
   --------------------------------------------------------------- */
BACKUP DATABASE [LabBackupTypes]
TO DISK = N'C:\SQLBackups\LabBackupTypes.bak'
WITH DIFFERENTIAL, NAME = N'Type demo - diff', CHECKSUM;
GO

INSERT INTO dbo.Orders (qty, note) VALUES (30, N'ชุดที่ 3');
GO

/* ---------------------------------------------------------------
   4) Log backup — เก็บ log ตั้งแต่อันล่าสุด (truncate log ด้วย)
   --------------------------------------------------------------- */
BACKUP LOG [LabBackupTypes]
TO DISK = N'C:\SQLBackups\LabBackupTypes.bak'
WITH NAME = N'Type demo - log 1', CHECKSUM;
GO

/* ---------------------------------------------------------------
   5) Partial backup (READ_WRITE_FILEGROUPS)
      — ตอนนี้ DB มี filegroup เดียว ผลจึงเท่า full;
        แต่ syntax คือหัวใจของ piecemeal restore (Module 7)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabBackupTypes]
READ_WRITE_FILEGROUPS
TO DISK = N'C:\SQLBackups\LabBackupTypes_partial.bak'
WITH FORMAT, INIT, NAME = N'Type demo - partial', CHECKSUM;
GO

/* ---------------------------------------------------------------
   6) COPY_ONLY full — เป็น backup เพิ่มโดยไม่ reset differential base
   --------------------------------------------------------------- */
BACKUP DATABASE [LabBackupTypes]
TO DISK = N'C:\SQLBackups\LabBackupTypes_copyonly.bak'
WITH FORMAT, INIT, COPY_ONLY, NAME = N'Type demo - copy only', CHECKSUM;
GO

/* ---------------------------------------------------------------
   7) ตรวจสิ่งที่ได้ — ลำดับ backup set ในไฟล์เดียว + base ของ diff
   --------------------------------------------------------------- */
RESTORE HEADERONLY
FROM DISK = N'C:\SQLBackups\LabBackupTypes.bak';
GO
/* Expected: 3 แถว (full / diff / log) — สังเกตคอลัมน์:
   BackupType (1=Full, 5=Differential, 2=Log),
   DifferentialBaseLSN (เฉพาะ diff), LastLSN, FirstLSN */

RESTORE HEADERONLY
FROM DISK = N'C:\SQLBackups\LabBackupTypes_copyonly.bak';
GO
/* Expected: BackupType = 1 แต่ DifferentialBaseLSN ไม่เปลี่ยนตรงกับ full ปกติล่าสุด
   (copy-only ไม่เข้าแทน differential base) */

-- differential base ฝั่ง engine (ของฐานข้อมูลปัจจุบัน)
SELECT name AS logical_name, differential_base_lsn, differential_base_guid
FROM sys.master_files
WHERE database_id = DB_ID(N'LabBackupTypes') AND type = 0;
GO

/* ---------------------------------------------------------------
   8) เทียบขนาดจริงของแต่ละประเภทจาก msdb
   --------------------------------------------------------------- */
SELECT type,
       CASE type WHEN 'D' THEN N'Full' WHEN 'I' THEN N'Differential' WHEN 'L' THEN N'Log' END AS type_desc,
       backup_size / 1048576.0 AS size_MB,
       compressed_backup_size / 1048576.0 AS compressed_MB,
       backup_finish_date, name
FROM msdb.dbo.backupset
WHERE database_name = N'LabBackupTypes'
ORDER BY backup_finish_date;
GO
/* Expected: full ใหญ่สุด, diff เล็กเพราะเปลี่ยนแค่ไม่กี่ extent,
   log ตัวแรกหลัง backup จะเล็กมาก (เก็บเฉพาะ insert 2 แถว) */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabBackupTypes] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabBackupTypes];
GO
-- ลบไฟล์ C:\SQLBackups\LabBackupTypes*.bak ทีหลัง
GO
