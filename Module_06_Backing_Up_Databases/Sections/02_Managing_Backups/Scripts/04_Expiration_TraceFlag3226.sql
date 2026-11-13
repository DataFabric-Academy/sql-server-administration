/* =============================================================================
   04_Expiration_TraceFlag3226.sql
   Module 06 - Section 2: RETAINDAYS / EXPIREDATE และ trace flag 3226
   (ปิดข้อความ successful backup ใน error log)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'LabExpire') IS NOT NULL
BEGIN
    ALTER DATABASE [LabExpire] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabExpire];
END
GO
CREATE DATABASE [LabExpire];
GO

/* ---------------------------------------------------------------
   1) Backup พร้อม RETAINDAYS แล้วอ่าน expiration จาก msdb
   --------------------------------------------------------------- */
BACKUP DATABASE [LabExpire]
TO DISK = N'C:\SQLBackups\Exp.bak'
WITH FORMAT, INIT, RETAINDAYS = 14, NAME = N'keep 14 days', CHECKSUM;
GO
SELECT database_name, name, backup_start_date, expiration_date,
       DATEDIFF(DAY, backup_start_date, expiration_date) AS retained_days
FROM msdb.dbo.backupset
WHERE database_name = N'LabExpire';
GO
/* Expected: expiration_date = backup_start_date + 14 วัน */

/* ---------------------------------------------------------------
   2) ทดสอบ: INIT จะโดนขวางเพราะยังไม่หมดอายุ / SKIP ผ่าน
   --------------------------------------------------------------- */
BEGIN TRY
    BACKUP DATABASE [LabExpire]
    TO DISK = N'C:\SQLBackups\Exp.bak'
    WITH INIT, NAME = N'overwrite attempt';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED: ' + ERROR_MESSAGE();
END CATCH
GO
BACKUP DATABASE [LabExpire]
TO DISK = N'C:\SQLBackups\Exp.bak'
WITH SKIP, INIT, NAME = N'forced with SKIP', CHECKSUM;
GO
/* Expected: ครั้งแรก fail (backup set ยังไม่หมดอายุ), ครั้งที่สองผ่านด้วย SKIP */

/* ---------------------------------------------------------------
   3) ค่า media retention ระดับ server (default 0 — ใช้เมื่อไม่ระบุตัวเลือก)
   --------------------------------------------------------------- */
SELECT name, value_in_use FROM sys.configurations
WHERE name = N'media retention';
GO

/* ---------------------------------------------------------------
   4) Trace flag 3226 — ปิด "successful backup" ใน error log
      สังเกตผลผ่าน sys.dm_os_ring_buffers หรืออ่าน ERRORLOG หลังรัน
   --------------------------------------------------------------- */
DBCC TRACEON (3226);
DBCC TRACESTATUS (3226);
GO
BACKUP DATABASE [LabExpire]
TO DISK = N'C:\SQLBackups\Exp_quiet.bak'
WITH FORMAT, INIT, CHECKSUM;
GO
DBCC TRACEOFF (3226);
GO
/* Expected: ระหว่าง TRACEON ข้อความ "Database backed up..." ไม่ถูกเขียนลง error log
   (ตรวจด้วย EXEC sys.xp_readerrorlog 0, 1, N'Database backed up')
   ใน production ตั้งถาวรผ่าน startup parameter -T3226 หรือหลัง restart ด้วย
   DBCC TRACEON (3226, -1)  — เขียนที่ startup ให้ปลอดภัยที่สุด */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabExpire] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabExpire];
GO
-- ลบไฟล์ C:\SQLBackups\Exp*.bak ทีหลัง
GO
