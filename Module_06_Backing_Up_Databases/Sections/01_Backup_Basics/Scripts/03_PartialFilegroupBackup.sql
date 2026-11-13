/* =============================================================================
   03_PartialFilegroupBackup.sql
   Module 06 - Section 1: file/filegroup backup และ partial backup
   (READ_WRITE_FILEGROUPS) — ตั้งต้นสำหรับ piecemeal restore (Module 7)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB สอง filegroup: PRIMARY (งานจริง) + ArchiveFG (read-only)
   --------------------------------------------------------------- */
IF DB_ID(N'LabFGBackup') IS NOT NULL
BEGIN
    ALTER DATABASE [LabFGBackup] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabFGBackup];
END
GO
CREATE DATABASE [LabFGBackup]
ON  PRIMARY ( NAME = N'LabFG_prim', FILENAME = N'C:\SQLBackups\LabFG_prim.mdf',
              SIZE = 8MB, FILEGROWTH = 32MB ),
    FILEGROUP [ArchiveFG]
             ( NAME = N'LabFG_arch', FILENAME = N'C:\SQLBackups\LabFG_arch.ndf',
               SIZE = 8MB, FILEGROWTH = 32MB )
LOG ON       ( NAME = N'LabFG_log',  FILENAME = N'C:\SQLBackups\LabFG_log.ldf',
               SIZE = 8MB, FILEGROWTH = 32MB );
GO
ALTER DATABASE [LabFGBackup] SET RECOVERY FULL;
GO

USE [LabFGBackup];
GO
CREATE TABLE dbo.CurrentOrders (id INT IDENTITY, note NVARCHAR(50)) ON [PRIMARY];
CREATE TABLE dbo.ArchiveOrders (id INT, note NVARCHAR(50)) ON [ArchiveFG];
INSERT INTO dbo.CurrentOrders (note) VALUES (N'งานวิ่ง 1'), (N'งานวิ่ง 2');
INSERT INTO dbo.ArchiveOrders (id, note) VALUES (1, N'ปี 2567'), (2, N'ปี 2568');
GO
-- ล็อก ArchiveFG เป็น read-only (เหมือน warehouse archive)
ALTER DATABASE [LabFGBackup] MODIFY FILEGROUP [ArchiveFG] READ_ONLY;
GO
USE master;
GO

/* ---------------------------------------------------------------
   2) Full backup ครบ (ฐานของ chain) — เอาไว้เทียบขนาด
   --------------------------------------------------------------- */
BACKUP DATABASE [LabFGBackup]
TO DISK = N'C:\SQLBackups\LabFG_full.bak'
WITH FORMAT, INIT, NAME = N'full ทั้ง DB', CHECKSUM, COMPRESSION;
GO

/* ---------------------------------------------------------------
   3) Filegroup backup เฉพาะ ArchiveFG — เก็บครั้งเดียวจนกว่าจะแตะข้อมูล
   --------------------------------------------------------------- */
BACKUP DATABASE [LabFGBackup]
    FILEGROUP = N'ArchiveFG'
TO DISK = N'C:\SQLBackups\LabFG_ArchiveFG.bak'
WITH FORMAT, INIT, NAME = N'archive filegroup (read-only)', CHECKSUM;
GO

/* ---------------------------------------------------------------
   4) Partial backup — READ_WRITE_FILEGROUPS (PRIMARY เท่านั้นตอนนี้)
      ตาราง backup รายวันจริงจะใช้ก้อนนี้ ไม่ต้องดำ archive ซ้ำ
   --------------------------------------------------------------- */
INSERT INTO [LabFGBackup].dbo.CurrentOrders (note) VALUES (N'งานวิ่ง 3');
GO
BACKUP DATABASE [LabFGBackup]
    READ_WRITE_FILEGROUPS
TO DISK = N'C:\SQLBackups\LabFG_partial.bak'
WITH FORMAT, INIT, NAME = N'partial (read-write เท่านั้น)', CHECKSUM;
GO
BACKUP LOG [LabFGBackup] TO DISK = N'C:\SQLBackups\LabFG_log.trn'
WITH FORMAT, INIT, NAME = N'log backup', CHECKSUM;
GO

/* ---------------------------------------------------------------
   5) เทียบขนาดและประเภทที่ได้
   --------------------------------------------------------------- */
SELECT name, type,
       CASE type WHEN 'D' THEN N'Full' WHEN 'P' THEN N'Partial' WHEN 'F' THEN N'File' WHEN 'L' THEN N'Log' END AS type_desc,
       backup_size / 1048576.0 AS size_MB
FROM msdb.dbo.backupset
WHERE database_name = N'LabFGBackup'
ORDER BY backup_finish_date;
GO
/* Expected: partial กับ full ต่างกันเท่าขนาดของ ArchiveFG ที่ถูกตัดออก
   (ใน DB เล็กต่างกันไม่มาก แต่ที่ DB หลายร้อย GB คือตัวเลขใหญ่) */

/* ---------------------------------------------------------------
   ข้อควรจำ:
   - FILEGROUP = '...'  → file backup เฉพาะกลุ่มนั้น
   - READ_WRITE_FILEGROUPS → partial backup (รวม PRIMARY + read/write ทุกกลุ่ม)
   - SIMPLE recovery: file backup ใช้ได้เฉพาะ read-only filegroup
   - restore แบบ piecemeal อยู่ใน Module 7 (WITH PARTIAL, NORECOVERY)
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabFGBackup] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabFGBackup];
GO
-- ลบไฟล์ C:\SQLBackups\LabFG_* ทีหลัง
GO
