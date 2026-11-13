/* =============================================================================
   01_CompleteRestore_RecoveryModes.sql
   Module 07 - Section 2: สถานการณ์กู้แบบเต็ม — จาก full เดียว และ
   full + differential (บนชื่อ DB สำเนา เพื่อไม่กระทบตัวจริง)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง + ชุด backup: full + diff
   --------------------------------------------------------------- */
IF DB_ID(N'LabScen') IS NOT NULL
BEGIN
    ALTER DATABASE [LabScen] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabScen];
END
GO
CREATE DATABASE [LabScen];
ALTER DATABASE [LabScen] SET RECOVERY FULL;
GO
USE [LabScen];
GO
CREATE TABLE dbo.Archive (id INT IDENTITY, note NVARCHAR(60));
INSERT INTO dbo.Archive (note) VALUES (N'ก่อน full');
USE master;
GO
BACKUP DATABASE [LabScen] TO DISK = N'C:\SQLBackups\Scen.bak'
WITH FORMAT, INIT, NAME = N'scen full', CHECKSUM, COMPRESSION;
GO
USE [LabScen];
GO
INSERT INTO dbo.Archive (note) VALUES (N'หลัง full ก่อน diff');
USE master;
GO
BACKUP DATABASE [LabScen] TO DISK = N'C:\SQLBackups\Scen.bak'
WITH DIFFERENTIAL, NAME = N'scen diff', CHECKSUM;
GO
USE [LabScen];
GO
INSERT INTO dbo.Archive (note) VALUES (N'หลัง diff — ไม่มีทางอยู่ถ้าไม่มี log');
USE master;
GO

/* ---------------------------------------------------------------
   2) สถานการณ์ A — กู้จาก full เดียว บนชื่อใหม่ (กู้เพื่อดึงข้อมูลย้อน)
   --------------------------------------------------------------- */
RESTORE DATABASE [LabScen_A]
FROM DISK = N'C:\SQLBackups\Scen.bak'
WITH FILE = 1, RECOVERY,
     MOVE N'LabScen'     TO N'C:\SQLBackups\LabScen_A.mdf',
     MOVE N'LabScen_log' TO N'C:\SQLBackups\LabScen_A_log.ldf',
     STATS = 10;
GO
USE [LabScen_A];
GO
SELECT COUNT(*) AS rows_in_full_only, MAX(note) AS last_note FROM dbo.Archive;
GO
/* Expected: 1 แถว 'ก่อน full' — full backup เดียวให้ข้อมูลจุดนั้นเท่านั้น */
USE master;
GO

/* ---------------------------------------------------------------
   3) สถานการณ์ B — full + differential บนชื่อใหม่
   --------------------------------------------------------------- */
RESTORE DATABASE [LabScen_B]
FROM DISK = N'C:\SQLBackups\Scen.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabScen'     TO N'C:\SQLBackups\LabScen_B.mdf',
     MOVE N'LabScen_log' TO N'C:\SQLBackups\LabScen_B_log.ldf';
RESTORE DATABASE [LabScen_B]
FROM DISK = N'C:\SQLBackups\Scen.bak'
WITH FILE = 2, RECOVERY;      -- diff
GO
USE [LabScen_B];
GO
SELECT COUNT(*) AS rows_with_diff, MAX(note) AS last_note FROM dbo.Archive;
GO
/* Expected: 2 แถว — diff นำงานระหว่าง full ถึง diff กลับมาทั้งหมด
   แถวที่สาม (หลัง diff) จะกลับมาได้ด้วย log/tail ดู 02_DiffLogChain_Restore.sql */
USE master;
GO

/* ---------------------------------------------------------------
   4) RESTRICTED_USER — กู้เสร็จแล้วปล่อยเฉพาะ DBA เช็กก่อน
   --------------------------------------------------------------- */
RESTORE DATABASE [LabScen_C]
FROM DISK = N'C:\SQLBackups\Scen.bak'
WITH FILE = 1, RECOVERY, RESTRICTED_USER,
     MOVE N'LabScen'     TO N'C:\SQLBackups\LabScen_C.mdf',
     MOVE N'LabScen_log' TO N'C:\SQLBackups\LabScen_C_log.ldf';
GO
SELECT name, user_access_desc FROM sys.databases WHERE name = N'LabScen_C';
GO
-- เช็กเสร็จแล้วปล่อย user ทั้งหมด:
ALTER DATABASE [LabScen_C] SET MULTI_USER;
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabScen]     SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabScen];
ALTER DATABASE [LabScen_A]   SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabScen_A];
ALTER DATABASE [LabScen_B]   SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabScen_B];
ALTER DATABASE [LabScen_C]   SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabScen_C];
GO
-- ลบไฟล์ C:\SQLBackups\Scen.bak, LabScen_*.mdf/_log.ldf ทีหลัง
GO
