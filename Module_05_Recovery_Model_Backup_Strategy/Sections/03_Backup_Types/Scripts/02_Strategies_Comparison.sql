/* =============================================================================
   02_Strategies_Comparison.sql
   Module 05 - Section 3: เปรียบเทียบ strategy แบบจับเวลา — restore แบบ
   (a) full เดียว   (b) full + diff + log  — ดูผลต่อเวลาและขั้นตอน
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) สร้าง DB + ข้อมูลสามชุดช่วงเวลา (T1, T2, T3)
   --------------------------------------------------------------- */
IF DB_ID(N'LabStrategy') IS NOT NULL
BEGIN
    ALTER DATABASE [LabStrategy] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabStrategy];
END
GO
CREATE DATABASE [LabStrategy];
ALTER DATABASE [LabStrategy] SET RECOVERY FULL;
GO
USE [LabStrategy];
GO
CREATE TABLE dbo.Sales (id INT IDENTITY PRIMARY KEY, amount DECIMAL(10,2), batch NVARCHAR(20));
GO

-- T1: ก่อน full backup
INSERT INTO dbo.Sales (amount, batch) VALUES (100.00, N'T1');
BACKUP DATABASE [LabStrategy] TO DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH FORMAT, INIT, NAME = N'Strategy full', CHECKSUM, COMPRESSION;
GO

-- T2: หลัง full ก่อน diff
INSERT INTO dbo.Sales (amount, batch) VALUES (200.00, N'T2');
BACKUP DATABASE [LabStrategy] TO DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH DIFFERENTIAL, NAME = N'Strategy diff', CHECKSUM;
GO

-- T3: หลัง diff — จะถูกกู้ด้วย log
INSERT INTO dbo.Sales (amount, batch) VALUES (300.00, N'T3');
BACKUP LOG [LabStrategy] TO DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH NAME = N'Strategy log', CHECKSUM;
GO
SELECT batch, COUNT(*) AS rows_count, SUM(amount) AS total FROM dbo.Sales GROUP BY batch;
GO
/* Expected: T1+T2+T3 ครบทั้งสามชุด */

/* ---------------------------------------------------------------
   2) Scenario A — restore ด้วย full อย่างเดียว (RPO = จนถึง T1)
   --------------------------------------------------------------- */
RESTORE DATABASE [LabStrategy_A]
FROM DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH FILE = 1, RECOVERY,
     MOVE N'LabStrategy'     TO N'C:\SQLBackups\LabStrategy_A.mdf',
     MOVE N'LabStrategy_log' TO N'C:\SQLBackups\LabStrategy_A_log.ldf',
     STATS = 10;
GO
USE [LabStrategy_A];
GO
SELECT batch, COUNT(*) AS restored_rows FROM dbo.Sales GROUP BY batch;
GO
/* Expected: เห็นเฉพาะ T1 — full backup จุดเดียว = RPO เท่าระยะห่าง full */
USE master;
GO

/* ---------------------------------------------------------------
   3) Scenario B — restore เต็ม chain: full + diff + log (ถึง T3)
      restore ตามลำดับ: มี RECOVERY เฉพาะตัวสุดท้ายเสมอ
   --------------------------------------------------------------- */
RESTORE DATABASE [LabStrategy_B]
FROM DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabStrategy'     TO N'C:\SQLBackups\LabStrategy_B.mdf',
     MOVE N'LabStrategy_log' TO N'C:\SQLBackups\LabStrategy_B_log.ldf',
     STATS = 10;
RESTORE DATABASE [LabStrategy_B]
FROM DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH FILE = 2, NORECOVERY;          -- differential
RESTORE LOG [LabStrategy_B]
FROM DISK = N'C:\SQLBackups\LabStrategy.bak'
WITH FILE = 3, RECOVERY;            -- log — อันสุดท้ายใช้ RECOVERY
GO
USE [LabStrategy_B];
GO
SELECT batch, COUNT(*) AS restored_rows, SUM(amount) AS total FROM dbo.Sales GROUP BY batch;
GO
/* Expected: T1 + T2 + T3 ครบ — chain สมบูรณ์คือความสามารถของ FULL recovery */

/* ---------------------------------------------------------------
   4) ทดสอบความผิดพลาดที่พบบ่อย: ลืม NORECOVERY ก่อนตัวสุดท้าย
      คลอง restore ถูก RECOVERY ปิดไปแล้ว ต่อ log ต่อไม่ได้
      (คอมเมนต์ไว้ ลองรันบน A เพื่อเห็น error ครั้งแรกได้)
   --------------------------------------------------------------- */
-- RESTORE LOG [LabStrategy_A] FROM DISK = N'C:\SQLBackups\LabStrategy.bak'
-- WITH FILE = 3, RECOVERY;
/* Expected: Msg 4306 — file 3 ไม่สามารถต่อบน database ที่ recovered แล้ว
   กฎ: NORECOVERY ทุกขั้น ยกเว้นขั้นสุดท้าย */

/* ---------------------------------------------------------------
   5) ดู LSN เพื่อเข้าใจลำดับ restore (เครื่องมือตรวจตอนเกิดเหตุจริง)
   --------------------------------------------------------------- */
SELECT
    CASE type WHEN 'D' THEN N'Full' WHEN 'I' THEN N'Diff' WHEN 'L' THEN N'Log' END AS backup_type,
    first_lsn, last_lsn, checkpoint_lsn, differential_base_lsn, backup_finish_date
FROM msdb.dbo.backupset
WHERE database_name = N'LabStrategy'
ORDER BY backup_finish_date;
GO
/* Expected: first_lsn/last_lsn ของ log อันถัดไปต่อจาก last_lsn อันก่อน —
   restore ผิดลำดับจะโดน engine ตรวจสาย LSN เตือนทันที */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabStrategy_A] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabStrategy_A];
ALTER DATABASE [LabStrategy_B] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabStrategy_B];
ALTER DATABASE [LabStrategy] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabStrategy];
GO
-- ลบไฟล์ C:\SQLBackups\LabStrategy* ทีหลัง
GO
