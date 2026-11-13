/* =============================================================================
   02_MarkedTransaction_StopAtMark.sql
   Module 07 - Section 4: marked transactions — BEGIN TRAN WITH MARK
   + RESTORE LOG WITH STOPATMARK / STOPBEFOREMARK + msdb.dbo.logmarkhistory
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง + full backup ก่อนเหตุการณ์
   --------------------------------------------------------------- */
IF DB_ID(N'LabMark') IS NOT NULL
BEGIN
    ALTER DATABASE [LabMark] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabMark];
END
GO
CREATE DATABASE [LabMark];
ALTER DATABASE [LabMark] SET RECOVERY FULL;
GO
USE [LabMark];
GO
CREATE TABLE dbo.Batches (id INT IDENTITY, batch NVARCHAR(40), status NVARCHAR(20));
INSERT INTO dbo.Batches (batch, status) VALUES (N'Batch-2025-Q1', N'เก็บถาวร');
GO
USE master;
GO
BACKUP DATABASE [LabMark] TO DISK = N'C:\SQLBackups\Mark.bak'
WITH FORMAT, INIT, NAME = N'full ก่อน mark', CHECKSUM;
GO

/* ---------------------------------------------------------------
   2) ฝัง mark ใน transaction ที่อันตราย แล้วทำงานต่อ
      — mark ถูกเขียนลง log "ตอน COMMIT" เท่านั้น
   --------------------------------------------------------------- */
USE [LabMark];
GO
BEGIN TRANSACTION CleanupOldBatches
    WITH MARK N'ลบ batch เก่าทิ้ง';
GO
DELETE FROM dbo.Batches WHERE status = N'เก็บถาวร';
GO
COMMIT TRANSACTION CleanupOldBatches;
GO
INSERT INTO dbo.Batches (batch, status) VALUES (N'Batch-2026-Q4', N'ทำงานอยู่');
GO

WAITFOR DELAY '00:00:02';
BACKUP LOG [LabMark] TO DISK = N'C:\SQLBackups\Mark_log.trn'
WITH FORMAT, INIT, NAME = N'log ครอบ mark', CHECKSUM;
GO

/* ---------------------------------------------------------------
   3) ตรวจ msdb.dbo.logmarkhistory — ทะเบียนของ mark ทั้งหมด
   --------------------------------------------------------------- */
SELECT mark_name, description, database_name, user_name, mark_time, lsn
FROM msdb.dbo.logmarkhistory
WHERE database_name = N'LabMark'
ORDER BY mark_time;
GO
/* Expected: 1 แถว mark 'CleanupOldBatches' พร้อม LSN — เครื่องมือหาจุดตัดแม่นยำ
   ในเหตุการณ์จริง: หา mark ล่าสุด "ก่อน" เหตุการณ์ที่ต้องการกู้แก้ */

/* ---------------------------------------------------------------
   4) กู้สำเนาชุด A — STOPATMARK (รวม DELETE ที่ mark ด้วย)
      เหมาะกับกรณีที่ transaction ที่ mark "ถูกต้อง" ต้องการกู้ถึงหลังมัน
   --------------------------------------------------------------- */
RESTORE DATABASE [LabMark_A]
FROM DISK = N'C:\SQLBackups\Mark.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabMark'     TO N'C:\SQLBackups\LabMark_A.mdf',
     MOVE N'LabMark_log' TO N'C:\SQLBackups\LabMark_A_log.ldf';
RESTORE LOG [LabMark_A]
FROM DISK = N'C:\SQLBackups\Mark_log.trn'
WITH STOPATMARK = N'CleanupOldBatches', RECOVERY;
GO
USE [LabMark_A];
GO
SELECT * FROM dbo.Batches;
GO
/* Expected: 0 แถว — mark "รวม" transaction (กู้ถึงหลัง commit ของ DELETE) */
USE master;
GO

/* ---------------------------------------------------------------
   5) กู้สำเนาชุด B — STOPBEFOREMARK (ตัด DELETE ทิ้ง)
      เหมาะกับกรณีที่ transaction ที่ mark คือ "ความผิดพลาด" ที่ต้องการย้อน
   --------------------------------------------------------------- */
RESTORE DATABASE [LabMark_B]
FROM DISK = N'C:\SQLBackups\Mark.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabMark'     TO N'C:\SQLBackups\LabMark_B.mdf',
     MOVE N'LabMark_log' TO N'C:\SQLBackups\LabMark_B_log.ldf';
RESTORE LOG [LabMark_B]
FROM DISK = N'C:\SQLBackups\Mark_log.trn'
WITH STOPBEFOREMARK = N'CleanupOldBatches', RECOVERY;
GO
USE [LabMark_B];
GO
SELECT * FROM dbo.Batches;
GO
/* Expected: 1 แถว 'Batch-2025-Q1' — ย้อนกลับก่อน DELETE (แต่แถว Insert หลัง
   DELETE ก็ถูกตัดไปด้วยเพราะ log เดินตามลำดับ) */

/* ---------------------------------------------------------------
   6) mark name ซ้ำ + AFTER — ใช้เมื่อฝัง mark ชื่อเดียวกันทุกคืน
      (เลือกครั้งที่เกิดก่อนเวลาที่ระบุ)
   --------------------------------------------------------------- */
-- RESTORE LOG [LabMark_B] FROM DISK = N'C:\SQLBackups\Mark_log.trn'
--     WITH STOPBEFOREMARK = N'CleanupOldBatches' AFTER N'2026-11-12T15:30:00',
--     RECOVERY;

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabMark]   SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMark];
ALTER DATABASE [LabMark_A] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMark_A];
ALTER DATABASE [LabMark_B] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMark_B];
GO
-- ลบไฟล์ C:\SQLBackups\Mark* และ LabMark_[AB]* ทีหลัง
-- (แถว logmarkhistory ค้างได้ — เก็บไว้ทบทวน หรือเก็บตามนโยบาย msdb)
GO
