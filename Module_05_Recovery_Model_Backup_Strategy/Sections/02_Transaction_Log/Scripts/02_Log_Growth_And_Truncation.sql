/* =============================================================================
   02_Log_Growth_And_Truncation.sql
   Module 05 - Section 2: วัด log growth และทดสอบ log truncation
   (CHECKPOINT vs BACKUP LOG) — ปรับจาก 20764D LogComparisonTest.sql
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   0) DB ทดลอง (จากเดโมเดิม LogTest) — SIMPLE recovery ก่อน
   --------------------------------------------------------------- */
IF DB_ID(N'LogTest') IS NOT NULL
BEGIN
    ALTER DATABASE [LogTest] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LogTest];
END
GO
CREATE DATABASE [LogTest]
LOG ON ( NAME = N'LogTest_log', FILENAME = N'C:\SQLBackups\LogTest_log.ldf',
         SIZE = 8MB, FILEGROWTH = 8MB );
GO
ALTER DATABASE [LogTest] SET RECOVERY SIMPLE;
GO

USE [LogTest];
GO
CREATE TABLE dbo.tLogTest (col1 INT IDENTITY, filler CHAR(200) DEFAULT 'x');
GO

/* ---------------------------------------------------------------
   1) เครื่องมือวัด — คลาสสิก + สมัยใหม่
   --------------------------------------------------------------- */
DBCC SQLPERF(LOGSPACE);    -- คอลัมน์ Log Size (MB) / Log Space Used (%) ของทุก DB
GO
SELECT total_log_size_in_bytes / 1048576.0 AS total_MB,
       used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;    -- รันใน DB เป้าหมาย
GO
-- Expected: log 8MB ใช้ประมาณ 1-3%

/* ---------------------------------------------------------------
   2) เกิด activity ที่เขียน log แล้ววัดซ้ำ
   --------------------------------------------------------------- */
INSERT INTO dbo.tLogTest DEFAULT VALUES;
GO 2000
DBCC SQLPERF(LOGSPACE);
GO
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
-- Expected: % ใช้ขยับขึ้นชัดเจน

/* ---------------------------------------------------------------
   3) ทดสอบ truncation ใน SIMPLE — CHECKPOINT ตัด log ได้จริง
   --------------------------------------------------------------- */
CHECKPOINT;
DBCC SQLPERF(LOGSPACE);
GO
SELECT used_log_space_in_percent FROM sys.dm_db_log_space_usage;
GO
/* Expected: Log Space Used (%) ของ LogTest ลดลงเพราะ SIMPLE
   truncate log ทุกครั้งหลัง checkpoint */

/* ---------------------------------------------------------------
   4) สลับเป็น FULL แล้วทำ full backup ครั้งแรก (เปิด log chain)
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LogTest] SET RECOVERY FULL;
BACKUP DATABASE [LogTest]
TO DISK = N'C:\SQLBackups\LogTest.bak'
WITH FORMAT, INIT, NAME = N'LogTest full', CHECKSUM, COMPRESSION;
GO

/* ---------------------------------------------------------------
   5) เกิด activity ใหม่ → CHECKPOINT → สังเกตว่า log ยังไม่ถูกตัด
   --------------------------------------------------------------- */
USE [LogTest];
GO
INSERT INTO dbo.tLogTest DEFAULT VALUES;
GO 2000
CHECKPOINT;                       -- ใน FULL ไม่ตัด log!
DBCC SQLPERF(LOGSPACE);
GO
SELECT recovery_model, log_reuse_wait_desc FROM sys.databases WHERE name = N'LogTest';
GO
SELECT * FROM sys.dm_db_log_stats(DB_ID(N'LogTest'));
GO
/* Expected: log_reuse_wait_desc = LOG_BACKUP — ทั้ง % ใช้และ
   log_space_in_bytes_since_last_backup ยังคงสูงแม้ checkpoint แล้ว */

/* ---------------------------------------------------------------
   6) BACKUP LOG จึงจะตัด log
   --------------------------------------------------------------- */
BACKUP LOG [LogTest]
TO DISK = N'C:\SQLBackups\LogTest.trn'
WITH FORMAT, INIT, NAME = N'LogTest log 1', CHECKSUM;
GO
DBCC SQLPERF(LOGSPACE);
GO
SELECT used_log_space_in_percent,
       log_space_in_bytes_since_last_backup / 1048576.0 AS used_since_last_log_backup_MB
FROM sys.dm_db_log_space_usage;
GO
/* Expected: Log Space Used (%) ของ LogTest ลดลงเหลือระดับเดิม
   การ truncation เกิดเฉพาะหลัง log backup ใน FULL recovery เท่านั้น */

/* ---------------------------------------------------------------
   7) กติกาการล่องหน: ถ้า "เผลอ" สลับ FULL → SIMPLE → FULL
      log chain หัก — BACKUP LOG จะ fail จนกว่าจะได้ full/diff ใหม่
   --------------------------------------------------------------- */
-- ALTER DATABASE [LogTest] SET RECOVERY SIMPLE;
-- ALTER DATABASE [LogTest] SET RECOVERY FULL;
-- BACKUP LOG [LogTest] TO DISK = N'C:\SQLBackups\LogTest.trn' WITH INIT;
-- Expected: Msg 4214 "No current database backup..." — ต้อง BACKUP DATABASE ก่อน

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LogTest] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LogTest];
GO
-- ลบไฟล์ C:\SQLBackups\LogTest.* ทีหลัง
GO
