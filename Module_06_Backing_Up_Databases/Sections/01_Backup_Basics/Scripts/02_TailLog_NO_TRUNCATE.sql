/* =============================================================================
   02_TailLog_NO_TRUNCATE.sql
   Module 06 - Section 1: BACKUP LOG WITH NO_TRUNCATE — เก็บ tail-log
   เมื่อฐานข้อมูลเสียหาย (จำลองเหตุการณ์ใน sandbox ของตัวเอง)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) สร้าง DB + ชุด backup ครบ (full + log)
   --------------------------------------------------------------- */
IF DB_ID(N'LabTailLog') IS NOT NULL
BEGIN
    ALTER DATABASE [LabTailLog] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabTailLog];
END
GO
CREATE DATABASE [LabTailLog]
ON  PRIMARY ( NAME = N'LabTailLog_data', FILENAME = N'C:\SQLBackups\LabTailLog.mdf' )
LOG ON       ( NAME = N'LabTailLog_log',  FILENAME = N'C:\SQLBackups\LabTailLog_log.ldf' );
GO
ALTER DATABASE [LabTailLog] SET RECOVERY FULL;
GO

USE [LabTailLog];
GO
CREATE TABLE dbo.Orders (id INT IDENTITY PRIMARY KEY, note NVARCHAR(50));
INSERT INTO dbo.Orders (note) VALUES (N'ก่อน full');
USE master;
GO
BACKUP DATABASE [LabTailLog] TO DISK = N'C:\SQLBackups\TailLog.bak'
WITH FORMAT, INIT, NAME = N'tail demo full', CHECKSUM;
GO
USE [LabTailLog];
GO
INSERT INTO dbo.Orders (note) VALUES (N'หลัง full ก่อน log backup');
USE master;
GO
BACKUP LOG [LabTailLog] TO DISK = N'C:\SQLBackups\TailLog.bak'
WITH NAME = N'tail demo log 1', CHECKSUM;
GO

/* ---------------------------------------------------------------
   2) งานล่าสุดที่ "ยังไม่มีใคร backup" — จะรอดชีวิตด้วย tail-log
   --------------------------------------------------------------- */
USE [LabTailLog];
GO
INSERT INTO dbo.Orders (note) VALUES (N'งานหลัง log backup — ต้องรอดชีวิต');
GO
SELECT COUNT(*) AS row_count, MAX(note) AS last_note FROM dbo.Orders;
GO
USE master;
GO

/* ---------------------------------------------------------------
   3) จำลอง data file เสียหาย: เปลี่ยนชื่อไฟล์ .mdf ชั่วคราวให้ engine อ่านไม่ได้
      (เป็น sandbox ที่ปลอดภัยกว่าการทุบไบต์ในไฟล์จริง)
      NOTE: ต้องหยุด SQL Server สั้น ๆ หรือใช้ DB OFFLINE เพื่อปลดล็อกไฟล์
   --------------------------------------------------------------- */
ALTER DATABASE [LabTailLog] SET OFFLINE;
GO
-- รันใน SSMS: EXEC master..xp_cmdshell ... อย่าใช้ — เราใช้ PowerShell แยกแทน:
--   Rename-Item C:\SQLBackups\LabTailLog.mdf LabTailLog.mdf.broken
-- กลับมาทำ SQL ต่อ:
-- ALTER DATABASE [LabTailLog] SET ONLINE;   -- จะ FAIL เพราะไฟล์หาย
/* Expected: Msg 5120 "Unable to open the physical file..." — DB อยู่สถานะ RECOVERY_PENDING */

/* ---------------------------------------------------------------
   4) Tail-log backup ด้วย NO_TRUNCATE — จะยังทำงานได้
      เพราะ log file ยังอยู่และ engine ยอมให้ backup ทั้งที่ DB เสีย
   --------------------------------------------------------------- */
-- หลัง rename ไฟล์จริงด้วย PowerShell แล้ว ให้รัน:
-- BACKUP LOG [LabTailLog]
--     TO DISK = N'C:\SQLBackups\TailLog_tail.trn'
--     WITH NO_TRUNCATE, CHECKSUM;
/* Expected: ทำงานสำเร็จ (มี warning เรื่อง metadata) — ไฟล์ .trn เก็บ
   งานถึงวินาทีสุดท้ายรวมแถว "งานหลัง log backup" */

/* ---------------------------------------------------------------
   5) กู้คืนจริง: rename .mdf กลับ → DROP/RESTORE ตาม chain
      (full + log1 + tail ต้อง restore ตามลำดับ NORECOVERY จนตัวสุดท้าย)
   --------------------------------------------------------------- */
-- ใน PowerShell:
--   Rename-Item C:\SQLBackups\LabTailLog.mdf.broken LabTailLog.mdf   (คืนไฟล์เดิม)
-- แล้ว restore เต็มสายเพื่อเห็นว่าข้อมูลล่าสุดกลับมา:
-- RESTORE DATABASE [LabTailLog]
--     FROM DISK = N'C:\SQLBackups\TailLog.bak'
--     WITH FILE = 1, REPLACE, NORECOVERY;
-- RESTORE LOG [LabTailLog]
--     FROM DISK = N'C:\SQLBackups\TailLog.bak'
--     WITH FILE = 2, NORECOVERY;
-- RESTORE LOG [LabTailLog]
--     FROM DISK = N'C:\SQLBackups\TailLog_tail.trn'
--     WITH RECOVERY;
-- USE [LabTailLog];
-- SELECT COUNT(*) AS row_count, MAX(note) AS last_note FROM dbo.Orders;
/* Expected: last_note = N'งานหลัง log backup — ต้องรอดชีวิต'
   — tail-log ช่วยให้ไม่เสียงานถึงวินาทีสุดท้าย */

/* ---------------------------------------------------------------
   ข้อจำกัดที่ต้องรู้: NO_TRUNCATE ทำงานได้เมื่อ DB อยู่ SUSPENDED /
   RECOVERY_PENDING แต่ทำไม่ได้ถ้า DB OFFLINE / EMERGENCY
   ในกรณีที่ NO_TRUNCATE fail ให้ลอง WITH CONTINUE_AFTER_ERROR แทน
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
IF DB_ID(N'LabTailLog') IS NOT NULL
BEGIN
    ALTER DATABASE [LabTailLog] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IF EXISTS [LabTailLog];
END
GO
-- ลบไฟล์ C:\SQLBackups\TailLog* และ LabTailLog* ทีหลัง
GO
