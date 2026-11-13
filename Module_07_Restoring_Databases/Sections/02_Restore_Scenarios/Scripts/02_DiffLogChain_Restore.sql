/* =============================================================================
   02_DiffLogChain_Restore.sql
   Module 07 - Section 2: chain ครบตามลำดับ LSN — full → diff → log → tail
   + แสดง FirstLSN/LastLSN เพื่อเห็นลำดับจริง และ error เมื่อ restore ข้ามอัน
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB + chain: full(F) → log(L1) → diff(D) → log(L2) → tail(T)
   --------------------------------------------------------------- */
IF DB_ID(N'LabChain') IS NOT NULL
BEGIN
    ALTER DATABASE [LabChain] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabChain];
END
GO
CREATE DATABASE [LabChain];
ALTER DATABASE [LabChain] SET RECOVERY FULL;
GO
USE [LabChain];
GO
CREATE TABLE dbo.EventLog (id INT IDENTITY, note NVARCHAR(60));
INSERT INTO dbo.EventLog (note) VALUES (N'ช่วงก่อน full');
USE master;
GO
BACKUP DATABASE [LabChain] TO DISK = N'C:\SQLBackups\Chain.bak'
WITH FORMAT, INIT, NAME = N'F: full', CHECKSUM;
GO
USE [LabChain];
GO
INSERT INTO dbo.EventLog (note) VALUES (N'ช่วง log 1');
USE master;
GO
BACKUP LOG [LabChain] TO DISK = N'C:\SQLBackups\Chain.bak'
WITH NAME = N'L1: log', CHECKSUM;
GO
USE [LabChain];
GO
INSERT INTO dbo.EventLog (note) VALUES (N'ช่วงเข้า diff');
USE master;
GO
BACKUP DATABASE [LabChain] TO DISK = N'C:\SQLBackups\Chain.bak'
WITH DIFFERENTIAL, NAME = N'D: diff', CHECKSUM;
GO
USE [LabChain];
GO
INSERT INTO dbo.EventLog (note) VALUES (N'ช่วง log 2');
USE master;
GO
BACKUP LOG [LabChain] TO DISK = N'C:\SQLBackups\Chain.bak'
WITH NAME = N'L2: log', CHECKSUM;
GO
USE [LabChain];
GO
INSERT INTO dbo.EventLog (note) VALUES (N'งานล่าสุด (tail)');
USE master;
GO
BACKUP LOG [LabChain] TO DISK = N'C:\SQLBackups\Chain_tail.trn'
WITH NAME = N'T: tail', CHECKSUM;
GO

/* ---------------------------------------------------------------
   2) อ่านลำดับ LSN — เห็นตรง ๆ ว่าต้องต่อกันอย่างไร
   --------------------------------------------------------------- */
SELECT s.name, s.type,
       CASE type WHEN 'D' THEN N'Full' WHEN 'I' THEN N'Diff' WHEN 'L' THEN N'Log' END AS type_desc,
       s.first_lsn, s.last_lsn, s.differential_base_lsn
FROM msdb.dbo.backupset AS s
WHERE s.database_name = N'LabChain'
ORDER BY s.backup_finish_date;
GO
/* Expected: first_lsn ของ L1 = last_lsn ของ F; first_lsn ของ L2 = last_lsn ของ L1
   และ differential_base_lsn ของ D = last_lsn ของ F */

/* ---------------------------------------------------------------
   3) กู้ chain ครบ: F → D → L2 → T (ข้าม L1 ได้เพราะ diff ครอบแทน)
      บนชื่อใหม่ LabChain_R
   --------------------------------------------------------------- */
RESTORE DATABASE [LabChain_R]
FROM DISK = N'C:\SQLBackups\Chain.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabChain'     TO N'C:\SQLBackups\LabChain_R.mdf',
     MOVE N'LabChain_log' TO N'C:\SQLBackups\LabChain_R_log.ldf';
RESTORE DATABASE [LabChain_R]
FROM DISK = N'C:\SQLBackups\Chain.bak'
WITH FILE = 3, NORECOVERY;                    -- D (Position 3)
RESTORE LOG [LabChain_R]
FROM DISK = N'C:\SQLBackups\Chain.bak'
WITH FILE = 4, NORECOVERY;                    -- L2 (Position 4)
RESTORE LOG [LabChain_R]
FROM DISK = N'C:\SQLBackups\Chain_tail.trn'
WITH RECOVERY;                                -- T
GO
USE [LabChain_R];
GO
SELECT * FROM dbo.EventLog;
GO
/* Expected: 5 แถวครบรวมงานล่าสุดจาก tail — นี่คือสถานการณ์กู้หลัง disk เสีย */

/* ---------------------------------------------------------------
   4) พิสูจน์ error ลำดับ: ลองกู้ log อันเก่าหลัง diff → fail
      (กู้ DB สำเนาใหม่แล้วใส่ log ผิดตำแหน่งโดยจงใจ)
   --------------------------------------------------------------- */
RESTORE DATABASE [LabChain_Broken]
FROM DISK = N'C:\SQLBackups\Chain.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabChain'     TO N'C:\SQLBackups\LabChain_Broken.mdf',
     MOVE N'LabChain_log' TO N'C:\SQLBackups\LabChain_Broken_log.ldf';
RESTORE DATABASE [LabChain_Broken]
FROM DISK = N'C:\SQLBackups\Chain.bak'
WITH FILE = 3, NORECOVERY;      -- diff
GO
BEGIN TRY
    RESTORE LOG [LabChain_Broken]
    FROM DISK = N'C:\SQLBackups\Chain.bak'
    WITH FILE = 4, NORECOVERY;  -- L2 ปกติ
    -- ต่อด้วย L1 (อันเก่ากว่า) → ต้อง fail
    RESTORE LOG [LabChain_Broken]
    FROM DISK = N'C:\SQLBackups\Chain.bak'
    WITH FILE = 2, NORECOVERY;
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (LSN ย้อนหลัง): ' + ERROR_MESSAGE();
END CATCH
GO
/* Expected: Msg 4305 — "The log in this backup set ... is too late to apply"
   engine ป้องกันการต่อ log ผิดลำดับเสมอ */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabChain]        SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabChain];
ALTER DATABASE [LabChain_R]      SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabChain_R];
ALTER DATABASE [LabChain_Broken] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabChain_Broken];
GO
-- ลบไฟล์ C:\SQLBackups\Chain* และ LabChain_*.mdf/_log.ldf ทีหลัง
GO
