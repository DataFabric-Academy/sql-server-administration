/* =============================================================================
   01_RestorePhases_NORECOVERY_STANDBY.sql
   Module 07 - Section 1: เห็น phase จริง — NORECOVERY ค้าง RESTORING,
   STANDBY อ่านได้และต่อ log ได้, RECOVERY ปิดท้าย
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง + สร้าง full + log backup
   --------------------------------------------------------------- */
IF DB_ID(N'LabPhases') IS NOT NULL
BEGIN
    ALTER DATABASE [LabPhases] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabPhases];
END
GO
CREATE DATABASE [LabPhases];
ALTER DATABASE [LabPhases] SET RECOVERY FULL;
GO
USE [LabPhases];
GO
CREATE TABLE dbo.Steps (id INT IDENTITY, note NVARCHAR(60));
INSERT INTO dbo.Steps (note) VALUES (N'ก่อน full backup');
USE master;
GO
BACKUP DATABASE [LabPhases] TO DISK = N'C:\SQLBackups\Phases.bak'
WITH FORMAT, INIT, NAME = N'phases full', CHECKSUM, COMPRESSION;
GO
USE [LabPhases];
GO
INSERT INTO dbo.Steps (note) VALUES (N'หลัง full ก่อน log');
USE master;
GO
BACKUP LOG [LabPhases] TO DISK = N'C:\SQLBackups\Phases.bak'
WITH NAME = N'phases log 1', CHECKSUM;
GO
USE [LabPhases];
GO
INSERT INTO dbo.Steps (note) VALUES (N'งานหลัง log backup ล่าสุด');
USE master;
GO

/* ---------------------------------------------------------------
   2) Restore ด้วย NORECOVERY — ดูสถานะ RESTORING
   --------------------------------------------------------------- */
RESTORE DATABASE [LabPhases]
FROM DISK = N'C:\SQLBackups\Phases.bak'
WITH FILE = 1, NORECOVERY, REPLACE;
GO
SELECT name, state_desc, is_in_standby
FROM sys.databases WHERE name = N'LabPhases';
GO
/* Expected: state_desc = RESTORING — ยังเปิดใช้งานไม่ได้ รอ backup ถัดไป */

/* ---------------------------------------------------------------
   3) STANDBY — เปิดอ่านกลางทางได้และยังต่อ log ต่อได้
   --------------------------------------------------------------- */
RESTORE LOG [LabPhases]
FROM DISK = N'C:\SQLBackups\Phases.bak'
WITH FILE = 2,
     STANDBY = N'C:\SQLBackups\Phases_undo.dat';
GO
SELECT name, state_desc, is_in_standby
FROM sys.databases WHERE name = N'LabPhases';
GO
USE [LabPhases];
GO
SELECT * FROM dbo.Steps;   -- อ่านได้: เห็น 2 แถวแรก
GO
/* Expected: 2 แถว (ก่อน full / หลัง full ก่อน log) — แถวที่สามยังไม่มาเพราะ
   ไม่ได้กู้ tail; DB อ่านได้ (ONLINE + is_in_standby = 1) */

/* ---------------------------------------------------------------
   4) RECOVERY — ปิดท้าย (แถวสุดท้ายจะเข้าเมื่อกู้ tail-log ในแล็บเต็ม)
   สำหรับเดโมนี้ จบด้วย RECOVERY ทันที
   --------------------------------------------------------------- */
RESTORE DATABASE [LabPhases] WITH RECOVERY;
GO
SELECT name, state_desc, is_in_standby
FROM sys.databases WHERE name = N'LabPhases';
GO
/* Expected: ONLINE / is_in_standby = 0 — ขั้น Undo เกิดและ DB ใช้งานได้
   จากนี้ RESTORE LOG ต่อไม่ได้อีก (ต้องเริ่มจาก full) */

/* ---------------------------------------------------------------
   5) พิสูจน์กฎ "RECOVERY แล้วต่อไม่ได้":
      ลอง RESTORE LOG ต่อหลัง RECOVERY → ต้อง fail
   --------------------------------------------------------------- */
BEGIN TRY
    RESTORE LOG [LabPhases] FROM DISK = N'C:\SQLBackups\Phases.bak' WITH FILE = 2;
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (DB recovered แล้ว): ' + ERROR_MESSAGE();
END CATCH
GO
/* Expected: error เพราะ log chain ถูกตัดเมื่อ RECOVERY เกิดขึ้นแล้ว */

/* ---------------------------------------------------------------
   6) ตรวจ progress ของ restore/backups ที่กำลังวิ่ง (มีประโยชน์จริงเวลากู้ใหญ่)
   --------------------------------------------------------------- */
SELECT command, percent_complete, start_time,
       DATEDIFF(SECOND, start_time, GETDATE()) AS elapsed_sec
FROM sys.dm_exec_requests
WHERE command LIKE 'RESTORE%' OR command LIKE 'BACKUP%';
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabPhases] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabPhases];
GO
-- ลบไฟล์ C:\SQLBackups\Phases* ทีหลัง (รวม Phases_undo.dat)
GO
