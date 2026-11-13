/* =============================================================================
   02_PrepareRestore_TailLog.sql
   Module 07 - Section 1: ลำดับการเตรียม restore — tail-log backup (NORECOVERY),
   จัดการ user ที่ค้าง (SINGLE_USER), และผลที่ได้เมื่อกู้ด้วย tail ครบ
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB + chain เต็มชุด
   --------------------------------------------------------------- */
IF DB_ID(N'LabPrepare') IS NOT NULL
BEGIN
    ALTER DATABASE [LabPrepare] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabPrepare];
END
GO
CREATE DATABASE [LabPrepare];
ALTER DATABASE [LabPrepare] SET RECOVERY FULL;
GO
USE [LabPrepare];
GO
CREATE TABLE dbo.Data (id INT IDENTITY, note NVARCHAR(60));
INSERT INTO dbo.Data (note) VALUES (N'ก่อน full');
USE master;
GO
BACKUP DATABASE [LabPrepare] TO DISK = N'C:\SQLBackups\Prepare.bak'
WITH FORMAT, INIT, NAME = N'prepare full', CHECKSUM;
GO
USE [LabPrepare];
GO
INSERT INTO dbo.Data (note) VALUES (N'ก่อน log');
USE master;
GO
BACKUP LOG [LabPrepare] TO DISK = N'C:\SQLBackups\Prepare.bak'
WITH NAME = N'prepare log', CHECKSUM;
GO
USE [LabPrepare];
GO
INSERT INTO dbo.Data (note) VALUES (N'งานล่าสุด — อยู่ใน tail');
USE master;
GO

/* ---------------------------------------------------------------
   2) ตรวจว่าใครเชื่อมต่ออยู่ก่อน restore (ปกติ production จะมี)
   --------------------------------------------------------------- */
SELECT session_id, login_name, host_name, program_name
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID(N'LabPrepare') AND is_user_process = 1;
GO

/* ---------------------------------------------------------------
   3) Tail-log backup WITH NORECOVERY — เก็บงานถึงวินาทีสุดท้าย
      และพา DB เข้าสู่ RESTORING (พร้อม restore ต่อทันที)
   --------------------------------------------------------------- */
BACKUP LOG [LabPrepare]
TO DISK = N'C:\SQLBackups\Prepare_tail.trn'
WITH NORECOVERY, CHECKSUM;
GO
SELECT name, state_desc FROM sys.databases WHERE name = N'LabPrepare';
GO
/* Expected: RESTORING — tail ถูกเก็บ, DB อยู่ในโหมดรอ restore */

/* ---------------------------------------------------------------
   4) Restore ตามลำดับ: full → log → tail (NORECOVERY จนตัวสุดท้าย)
   --------------------------------------------------------------- */
RESTORE DATABASE [LabPrepare] FROM DISK = N'C:\SQLBackups\Prepare.bak'
WITH FILE = 1, NORECOVERY, REPLACE;
RESTORE LOG [LabPrepare] FROM DISK = N'C:\SQLBackups\Prepare.bak'
WITH FILE = 2, NORECOVERY;
RESTORE LOG [LabPrepare] FROM DISK = N'C:\SQLBackups\Prepare_tail.trn'
WITH RECOVERY;
GO
USE [LabPrepare];
GO
SELECT * FROM dbo.Data;
GO
/* Expected: 3 แถวครบ — แถว 'งานล่าสุด' มาจาก tail-log backup
   นี่คือแนวคิด RPO ≈ 0 ของ FULL recovery เมื่อ tail ทำได้ */

/* ---------------------------------------------------------------
   5) กลับกัน: ลืม tail แล้ว restore ทับด้วย REPLACE → เสียงานล่าสุด
      (ทำจำลองบน DB สำเนา เพื่อไม่ทำลายของข้างบน)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabPrepare]
TO DISK = N'C:\SQLBackups\Prepare_forget.bak'
WITH FORMAT, INIT, NAME = N'snapshot ก่อนทดสอบ', COPY_ONLY;
GO
USE [LabPrepare];
GO
INSERT INTO dbo.Data (note) VALUES (N'งานล่าสุดหลัง snapshot — จะหายถ้าลืม tail');
USE master;
GO
-- restore ทับโดยไม่มี tail ต้อง REPLACE เพราะ log มีงานที่ไม่เคย backup
RESTORE DATABASE [LabPrepare] FROM DISK = N'C:\SQLBackups\Prepare_forget.bak'
WITH REPLACE, RECOVERY;
GO
USE [LabPrepare];
GO
SELECT * FROM dbo.Data;
GO
/* Expected: 3 แถว — แถวที่สี่หาย เพราะ REPLACE เขียนทับงานที่ไม่เคยถูก backup
   บทเรียน: tail-log backup ก่อน restore ทุกครั้ง เสมอ */

/* ---------------------------------------------------------------
   หมายเหตุ: NO_TRUNCATE (กรณี DB เสียหาย) ดูเดโมฉบับเต็มที่
   Sections/01_Backup_Basics/Scripts/02_TailLog_NO_TRUNCATE.sql ของ Module 6
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabPrepare] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabPrepare];
GO
-- ลบไฟล์ C:\SQLBackups\Prepare* ทีหลัง
GO
