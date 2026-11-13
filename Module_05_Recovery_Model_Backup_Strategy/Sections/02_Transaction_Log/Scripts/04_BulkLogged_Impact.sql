/* =============================================================================
   04_BulkLogged_Impact.sql
   Module 05 - Section 2: ทดสอบผลของ BULK_LOGGED + minimal logging
   (BULK INSERT ... WITH TABLOCK) ต่อขนาด log และข้อจำกัดการกู้คืน
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง FULL recovery + full backup เปิด chain
   --------------------------------------------------------------- */
IF DB_ID(N'LabBulk') IS NOT NULL
BEGIN
    ALTER DATABASE [LabBulk] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabBulk];
END
GO
CREATE DATABASE [LabBulk] ( SIZE = 16MB, FILEGROWTH = 64MB );
ALTER DATABASE [LabBulk] SET RECOVERY FULL;
GO
BACKUP DATABASE [LabBulk] TO DISK = N'C:\SQLBackups\LabBulk.bak'
WITH FORMAT, INIT, NAME = N'LabBulk full 1', CHECKSUM, COMPRESSION;
GO
USE [LabBulk];
GO
CREATE TABLE dbo.BulkTarget (
    id INT NOT NULL,
    name NVARCHAR(50),
    value DECIMAL(10,2)
);
GO

/* ---------------------------------------------------------------
   2) เตรียมไฟล์ CSV สำหรับ BULK INSERT
      รันคำสั่ง PowerShell นี้ใน terminal (ครั้งเดียว):

      powershell -Command "1..20000 | ForEach-Object { \"$($_),Item$($_),$($_)\" } | Out-File C:\SQLBackups\BulkData.csv -Encoding ascii"

   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   3) วัด baseline ของ log (ส่วนที่ใช้นับตั้งแต่ log backup ล่าสุด)
   --------------------------------------------------------------- */
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO

/* ---------------------------------------------------------------
   4) BULK INSERT ใน FULL recovery พร้อม TABLOCK — log เขียนเต็มรูปแบบ
      (TABLOCK ใน FULL ไม่ทำ minimal logging)
   --------------------------------------------------------------- */
BULK INSERT dbo.BulkTarget
FROM N'C:\SQLBackups\BulkData.csv'
WITH ( FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, ROWS_PER_BATCH = 20000 );
GO

SELECT N'FULL + TABLOCK' AS scenario,
       used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
/* Expected: log โตขึ้นระดับขนาดข้อมูล (หรือมากกว่า) — full logging */

/* ---------------------------------------------------------------
   5) เคลียร์ + ลบ log backlog ด้วย log backup แล้วเริ่มวัดใหม่
   --------------------------------------------------------------- */
DELETE FROM dbo.BulkTarget;
BACKUP LOG [LabBulk] TO DISK = N'C:\SQLBackups\LabBulk.trn' WITH INIT, CHECKSUM;
GO

/* ---------------------------------------------------------------
   6) สลับเป็น BULK_LOGGED แล้ว BULK INSERT ซ้ำ — minimal logging
   --------------------------------------------------------------- */
ALTER DATABASE [LabBulk] SET RECOVERY BULK_LOGGED;
GO
BULK INSERT dbo.BulkTarget
FROM N'C:\SQLBackups\BulkData.csv'
WITH ( FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK, ROWS_PER_BATCH = 20000 );
GO

SELECT N'BULK_LOGGED + TABLOCK' AS scenario,
       used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
/* Expected: log โตขึ้นน้อยมากเทียบกับข้อ 4 — minimal logging จันทึกเฉพาะ
   extent การจัดสรร ไม่บันทึกทุกแถว */

/* ---------------------------------------------------------------
   7) ราคาที่ต้องจ่าย: ช่วง minimal-logged ทำให้ point-in-time restore
      ไม่สามารถตัดกลางช่วง BULK INSERT ได้ (ต้องกู้ทั้งก้อน)
      BACKUP LOG ตอนนี้จะกลายเป็น "มีหรือไม่มี" ของ bulk operation
   --------------------------------------------------------------- */
BACKUP LOG [LabBulk] TO DISK = N'C:\SQLBackups\LabBulk2.trn' WITH INIT, CHECKSUM;
GO
SELECT log_backup_lsn, log_since_last_log_backup_mb
FROM sys.dm_db_log_stats(DB_ID(N'LabBulk'));
GO

/* ---------------------------------------------------------------
   8) กลับสู่ FULL — สลับจาก BULK_LOGGED กลับไม่หัก chain
      (FULL <-> BULK_LOGGED ยังคง chain เดิม, SIMPLE เท่านั้นที่หัก)
   --------------------------------------------------------------- */
ALTER DATABASE [LabBulk] SET RECOVERY FULL;
GO
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases WHERE name = N'LabBulk';
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabBulk] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabBulk];
GO
-- ลบไฟล์ C:\SQLBackups\LabBulk* และ BulkData.csv ทีหลัง
GO
