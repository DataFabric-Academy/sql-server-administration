/* =============================================================================
   01_STOPAT_Restore.sql
   Module 07 - Section 4: point-in-time restore ด้วย STOPAT — จำลอง
   "UPDATE ราดยอดผิดพลาด" แล้วกู้กลับถึงวินาทีก่อนเหตุ (บน DB สำเนา)
   ปรับจากเดโมเดิม "Point-in-Time Restore.sql" (20764D)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง + full backup
   --------------------------------------------------------------- */
IF DB_ID(N'LabSTOPAT') IS NOT NULL
BEGIN
    ALTER DATABASE [LabSTOPAT] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabSTOPAT];
END
GO
CREATE DATABASE [LabSTOPAT];
ALTER DATABASE [LabSTOPAT] SET RECOVERY FULL;
GO
USE [LabSTOPAT];
GO
CREATE TABLE dbo.CustomerBalances (id INT IDENTITY, customer NVARCHAR(40), balance DECIMAL(12,2));
INSERT INTO dbo.CustomerBalances (customer, balance)
VALUES (N'ลูกค้า A', 5000.00), (N'ลูกค้า B', 7500.00), (N'ลูกค้า C', 3200.50);
GO
USE master;
GO
BACKUP DATABASE [LabSTOPAT] TO DISK = N'C:\SQLBackups\STOPAT.bak'
WITH FORMAT, INIT, NAME = N'full ก่อนเหตุการณ์', CHECKSUM;
GO
USE [LabSTOPAT];
GO
INSERT INTO dbo.CustomerBalances (customer, balance) VALUES (N'ลูกค้า D', 1900.00);
GO

/* ---------------------------------------------------------------
   2) บันทึกจุดเวลา "ปลอดภัย" แล้วเกิดเหตุ: UPDATE ราดยอดผิดพลาด
   --------------------------------------------------------------- */
DECLARE @t_safe datetime2 = GETDATE();
PRINT N'จุดปลอดภัย = ' + CONVERT(nvarchar(30), @t_safe, 121);

-- (เก็บเวลาไว้ใน temp table เพื่อใช้ต่อใน batch ถัดไป)
CREATE TABLE #safe_time (t datetime2);
INSERT INTO #safe_time VALUES (@t_safe);

WAITFOR DELAY '00:00:02';

-- เหตุการณ์: script ที่ลืม WHERE ราดทุกยอด
UPDATE dbo.CustomerBalances SET balance = 0;
GO

WAITFOR DELAY '00:00:02';
BACKUP LOG [LabSTOPAT] TO DISK = N'C:\SQLBackups\STOPAT_log.trn'
WITH FORMAT, INIT, NAME = N'log ครอบเหตุการณ์', CHECKSUM;
GO
USE [LabSTOPAT];
GO
SELECT * FROM dbo.CustomerBalances;   -- ยอดถูกล้างเป็นศูนย์แล้ว
GO
USE master;
GO

/* ---------------------------------------------------------------
   3) กู้บนชื่อใหม่ถึงจุดปลอดภัยด้วย STOPAT
      (อ่านเวลาจาก temp table — ในสถานการณ์จริงใช้เวลาจาก job/app log)
   --------------------------------------------------------------- */
DECLARE @t datetime2 = (SELECT t FROM #safe_time);

RESTORE DATABASE [LabSTOPAT_Recovered]
FROM DISK = N'C:\SQLBackups\STOPAT.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabSTOPAT'     TO N'C:\SQLBackups\LabSTOPAT_R.mdf',
     MOVE N'LabSTOPAT_log' TO N'C:\SQLBackups\LabSTOPAT_R_log.ldf';

RESTORE LOG [LabSTOPAT_Recovered]
FROM DISK = N'C:\SQLBackups\STOPAT_log.trn'
WITH RECOVERY, STOPAT = @t;      -- จุดตัด = ก่อน UPDATE ราดยอด
GO
USE [LabSTOPAT_Recovered];
GO
SELECT * FROM dbo.CustomerBalances;
GO
/* Expected: 4 แถวพร้อมยอดเดิม (ไม่มี 0) — ข้อมูลถูกกู้กลับถึงวินาทีก่อนเหตุ
   (temp table อยู่ใน session — ถ้ารันแยก session ให้เลขเวลาจาก PRINT ขั้น 2 แทน) */

/* ---------------------------------------------------------------
   4) กติกา: STOPAT ที่อยู่หลังจบ log ที่มี → ต้องมี tail เพิ่ม
      (ถ้า log backup อันล่าสุดจบก่อนเวลาเป้าหมาย ให้ BACKUP LOG ใหม่ก่อน)
   --------------------------------------------------------------- */
-- BACKUP LOG [LabSTOPAT] TO DISK = N'C:\SQLBackups\STOPAT_tail.trn' WITH NORECOVERY, CHECKSUM;
-- RESTORE LOG [LabSTOPAT_Recovered] FROM DISK = N'C:\SQLBackups\STOPAT_tail.trn'
--     WITH RECOVERY, STOPAT = @t;

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabSTOPAT] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabSTOPAT];
ALTER DATABASE [LabSTOPAT_Recovered] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabSTOPAT_Recovered];
GO
-- ลบไฟล์ C:\SQLBackups\STOPAT* และ LabSTOPAT_R* ทีหลัง
GO
