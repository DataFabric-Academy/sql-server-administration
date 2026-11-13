/* =============================================================================
   03_Recovery_Models_Compare.sql
   Module 05 - Section 2: เทียบ SIMPLE vs FULL ต่อ log truncation และความสามารถ
   กู้คืน — ปรับจาก 20764D Lab05 Setup (MarketDev / Research)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) สร้างฐานข้อมูลคู่เปรียบ — MarketDev (SIMPLE) / Research (FULL)
      (จาก Setup.sql เดิม ตัด FILENAME เฉพาะที่ออกให้ใช้ data dir ปกติ)
   --------------------------------------------------------------- */
IF DB_ID(N'MarketDev') IS NOT NULL
BEGIN
    ALTER DATABASE [MarketDev] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [MarketDev];
END
GO
CREATE DATABASE [MarketDev] ( SIZE = 16MB, FILEGROWTH = 32MB );
ALTER DATABASE [MarketDev] SET RECOVERY SIMPLE;
GO

IF DB_ID(N'Research') IS NOT NULL
BEGIN
    ALTER DATABASE [Research] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [Research];
END
GO
CREATE DATABASE [Research] ( SIZE = 16MB, FILEGROWTH = 32MB );
ALTER DATABASE [Research] SET RECOVERY FULL;
GO

/* ---------------------------------------------------------------
   2) ข้อมูลเริ่มต้นเหมือนกันทั้งสอง
   --------------------------------------------------------------- */
USE [MarketDev];
GO
CREATE TABLE dbo.Experiments (id INT IDENTITY PRIMARY KEY, name NVARCHAR(100), results DECIMAL(10,2));
INSERT INTO dbo.Experiments (name, results) VALUES (N'ทดลอง A', 88.5), (N'ทดลอง B', 92.1);
GO

USE [Research];
GO
CREATE TABLE dbo.Experiments (id INT IDENTITY PRIMARY KEY, name NVARCHAR(100), results DECIMAL(10,2));
INSERT INTO dbo.Experiments (name, results) VALUES (N'ทดลอง A', 88.5), (N'ทดลอง B', 92.1);
GO

/* ---------------------------------------------------------------
   3) เทียบ truncation หลัง checkpoint
   --------------------------------------------------------------- */
CHECKPOINT;   -- global checkpoint ทั้ง instance
GO
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases
WHERE name IN (N'MarketDev', N'Research');
GO
/* Expected: MarketDev (SIMPLE) log_reuse_wait_desc = NOTHING (ตัดแล้ว)
             Research (FULL)     log_reuse_wait_desc = LOG_BACKUP (ค้างเพราะยังไม่มี log backup
             และยังไม่เคยทำ full backup — เปิด chain ด้วย full ก่อน) */

/* ---------------------------------------------------------------
   4) ลอง BACKUP LOG บน SIMPLE — จะ fail
   --------------------------------------------------------------- */
BACKUP LOG [MarketDev] TO DISK = N'C:\SQLBackups\MarketDev.trn' WITH INIT;
GO
/* Expected: Msg 4208 — "The statement BACKUP LOG is not allowed
   while the recovery model is SIMPLE" */

/* ---------------------------------------------------------------
   5) เปิด log chain ของ Research ด้วย full แล้ว BACKUP LOG ได้ปกติ
   --------------------------------------------------------------- */
BACKUP DATABASE [Research]
TO DISK = N'C:\SQLBackups\Research.bak'
WITH FORMAT, INIT, NAME = N'Research full 1', CHECKSUM, COMPRESSION;
GO
INSERT INTO [Research].dbo.Experiments (name, results) VALUES (N'ทดลอง C', 75.0);
GO
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO
SELECT name, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases WHERE name = N'Research';
GO
/* Expected: log_reuse_wait_desc = NOTHING หลัง log backup สำเร็จ */

/* ---------------------------------------------------------------
   6) สลับ FULL → SIMPLE → FULL ทำลาย chain
      Research จะ BACKUP LOG ไม่ได้จนกว่าได้ full/diff ใหม่
   --------------------------------------------------------------- */
ALTER DATABASE [Research] SET RECOVERY SIMPLE;
ALTER DATABASE [Research] SET RECOVERY FULL;
GO
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research2.trn' WITH INIT;
GO
/* Expected: Msg 4214 — BACKUP LOG cannot be performed because there is no
   current database backup. วิธีแก้: BACKUP DATABASE ... WITH INIT ก่อน แล้ว
   BACKUP LOG จะทำงานได้อีกครั้ง */

BACKUP DATABASE [Research]     -- เปิด chain ใหม่ (ไม่เขียนโค้ดรันให้เพราะตัวอย่างแล้ว)
TO DISK = N'C:\SQLBackups\Research.bak' WITH INIT, NAME = N'Research full 2', CHECKSUM;
BACKUP LOG [Research] TO DISK = N'C:\SQLBackups\Research.trn' WITH INIT, CHECKSUM;
GO

/* ---------------------------------------------------------------
   Cleanup — ทำตามแนวคิด "ล้างของหลังแล็บ"
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [MarketDev] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [MarketDev];
ALTER DATABASE [Research] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [Research];
GO
-- ลบไฟล์ C:\SQLBackups\MarketDev* / Research* ทีหลัง
GO
