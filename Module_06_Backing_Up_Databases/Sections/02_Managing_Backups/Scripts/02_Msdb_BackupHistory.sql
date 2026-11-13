/* =============================================================================
   02_Msdb_BackupHistory.sql
   Module 06 - Section 2: อ่านประวัติ msdb (backupset / backupfile /
   backupmediaset / backupmediafamily / restorehistory)
   และล้างประวัติด้วย sp_delete_database_backuphistory
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) สร้าง DB + backup หลายแบบให้ msdb มีข้อมูลให้อ่าน
   --------------------------------------------------------------- */
IF DB_ID(N'LabHistory') IS NOT NULL
BEGIN
    ALTER DATABASE [LabHistory] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabHistory];
END
GO
CREATE DATABASE [LabHistory];
ALTER DATABASE [LabHistory] SET RECOVERY FULL;
GO
BACKUP DATABASE [LabHistory] TO DISK = N'C:\SQLBackups\Hist.bak'
WITH FORMAT, INIT, NAME = N'full 1', CHECKSUM, COMPRESSION;
GO
USE [LabHistory];
IF OBJECT_ID(N'dbo.dummy') IS NULL
    CREATE TABLE dbo.dummy (id INT IDENTITY);
GO
INSERT INTO dbo.dummy DEFAULT VALUES;
GO
BACKUP DATABASE [LabHistory] TO DISK = N'C:\SQLBackups\Hist.bak'
WITH DIFFERENTIAL, NAME = N'diff 1', CHECKSUM;
GO
BACKUP LOG [LabHistory] TO DISK = N'C:\SQLBackups\Hist.bak'
WITH NAME = N'log 1', CHECKSUM;
GO

/* ---------------------------------------------------------------
   2) Query อ่านประวัติแบบใช้งานจริง
   --------------------------------------------------------------- */
USE msdb;
GO
-- (a) ประวัติ backup ของ DB หนึ่ง พร้อม path ไฟล์จริง
SELECT s.database_name,
       CASE s.type WHEN 'D' THEN N'Full' WHEN 'I' THEN N'Diff' WHEN 'L' THEN N'Log' END AS backup_type,
       s.backup_start_date, s.backup_finish_date,
       DATEDIFF(SECOND, s.backup_start_date, s.backup_finish_date) AS duration_sec,
       CAST(s.backup_size / 1048576.0 AS DECIMAL(10,2)) AS size_MB,
       CAST(s.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       m.physical_device_name
FROM backupset AS s
JOIN backupmediafamily AS m ON m.media_set_id = s.media_set_id
WHERE s.database_name = N'LabHistory'
ORDER BY s.backup_finish_date;
GO

-- (b) ไฟล์ใดอยู่ใน backup อันล่าสุด (backupfile)
SELECT TOP 5 s.database_name, s.type, f.logical_name, f.file_type,
             CAST(f.file_size / 1048576.0 AS DECIMAL(10,2)) AS file_size_MB
FROM backupfile AS f
JOIN backupset AS s ON s.media_set_id = f.media_set_id
WHERE s.database_name = N'LabHistory'
ORDER BY s.backup_finish_date DESC, f.file_type;
GO

-- (c) media set / family โครงสร้างสื่อ
SELECT ms.media_set_id, ms.name AS media_name, ms.media_family_count,
       mf.logical_device_name, mf.physical_device_name
FROM backupmediaset AS ms
JOIN backupmediafamily AS mf ON mf.media_set_id = ms.media_set_id
WHERE ms.media_set_id IN (SELECT media_set_id FROM backupset WHERE database_name = N'LabHistory');
GO

-- (d) ประวัติ restore (ทำ restore จำลองก่อนหนึ่งครั้งถ้าต้องการดูแถวจริง)
-- RESTORE VERIFYONLY ไม่เขียน restorehistory — ต้อง restore จริง (ยกเว้น WITH LOADHISTORY)
SELECT rh.destination_database_name, rh.restore_date, rh.restore_type,
       rh.restore_history_id
FROM restorehistory AS rh
WHERE rh.destination_database_name LIKE N'%History%';
GO

-- (e) ตรวจจังหวะ backup จริงทั้ง instance — DB ไหนไม่มี backup เกิน 1 วัน
SELECT d.name, d.recovery_model_desc,
       MAX(s.backup_finish_date) AS last_backup,
       DATEDIFF(HOUR, MAX(s.backup_finish_date), GETDATE()) AS hours_since_backup
FROM sys.databases AS d
LEFT JOIN backupset AS s
       ON s.database_name = d.name AND s.type = 'D'
WHERE d.database_id > 4          -- ตัด system DB
GROUP BY d.name, d.recovery_model_desc
ORDER BY hours_since_backup DESC;
GO
USE master;
GO

/* ---------------------------------------------------------------
   3) ล้างประวัติของ DB ที่จะเลิกใช้ — ตัวอย่างจริงของ sp_delete_database_backuphistory
      (เดิม Lab07 Setup.sql ใช้ขั้นตอนนี้ก่อน restore ทับ DB ชื่อเดิม)
   --------------------------------------------------------------- */
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'LabHistory';
GO
-- ยืนยันว่าประวัติหายไป (ควรคืน 0 แถว)
SELECT COUNT(*) AS remaining_rows
FROM msdb.dbo.backupset
WHERE database_name = N'LabHistory';
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabHistory] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabHistory];
GO
-- ลบไฟล์ C:\SQLBackups\Hist.bak ทีหลัง
GO
