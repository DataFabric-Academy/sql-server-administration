/* =============================================================================
   02_Backup_To_Storage_Overview.sql
   Module 05 - Section 1: ภาพรวมปลายทาง backup — disk / Azure Blob / S3
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO

-- โฟลเดอร์ท้องถิ่น
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) Database ทดลองเล็ก ๆ
   --------------------------------------------------------------- */
IF DB_ID(N'LabMedia') IS NOT NULL
BEGIN
    ALTER DATABASE [LabMedia] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabMedia];
END
GO
CREATE DATABASE [LabMedia];
ALTER DATABASE [LabMedia] SET RECOVERY FULL;
GO

USE [LabMedia];
GO
CREATE TABLE dbo.MediaTest (id INT IDENTITY PRIMARY KEY, note NVARCHAR(100));
INSERT INTO dbo.MediaTest (note)
SELECT N'แถวที่ ' + CAST(v.n AS NVARCHAR(10)) FROM (VALUES (1),(2),(3),(4),(5)) AS v(n);
GO

/* ---------------------------------------------------------------
   2) Backup ลง DISK แบบปกติ — ปลายทางพื้นฐานของทุก strategy
   --------------------------------------------------------------- */
BACKUP DATABASE [LabMedia]
TO DISK = N'C:\SQLBackups\LabMedia_Disk.bak'
WITH FORMAT, INIT, NAME = N'LabMedia full to disk', CHECKSUM, COMPRESSION;
GO

/* ---------------------------------------------------------------
   3) Backup ลง DISK แบบ stripe (หลายไฟล์พร้อมกัน)
      ใช้เมื่อไฟล์ใหญ่เกิน volume เดียว หรือกระจาย I/O หลาย disk
   --------------------------------------------------------------- */
BACKUP DATABASE [LabMedia]
TO DISK = N'C:\SQLBackups\LabMedia_Strip1.bak',
   DISK = N'C:\SQLBackups\LabMedia_Strip2.bak'
WITH FORMAT, INIT, NAME = N'LabMedia striped 2 files', CHECKSUM;
GO

/* Expected: ไฟล์สองอันประมาณครึ่งขนาดกัน รวมเท่า backup แบบเดียว
   หมายเหตุ: ชุด stripe ต้องมีไฟล์ครบตอน restore (หายไฟล์เดียวใช้ไม่ได้) */

/* ---------------------------------------------------------------
   4) Azure Blob Storage (TO URL) — ภาพรวมและ template
      ต้องมี credential ก่อน: สร้าง container + SAS token ใน Azure Portal
      แล้วรัน (แก้ placeholder):

      CREATE CREDENTIAL [https://mystorageaccount.blob.core.windows.net/sqlbackups]
          WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
               SECRET = N'<SAS_TOKEN_โดยไม่มีเครื่องหมาย ? นำหน้า>';

      จากนั้น:

      BACKUP DATABASE [LabMedia]
      TO URL = 'https://mystorageaccount.blob.core.windows.net/sqlbackups/LabMedia.bak'
      WITH COMPRESSION, CHECKSUM, STATS = 5;
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   5) S3-compatible object storage (SQL Server 2022+) — template
      สร้าง credential แบบ server-level ที่ชื่อต้องขึ้นต้นด้วย s3://
      ตรงกับ endpoint/bucket แล้ว backup ผ่าน URL = 's3://...'

      USE master;
      CREATE CREDENTIAL [s3://10.10.10.10:8787/sqlbackups]
          WITH IDENTITY = 'S3 Access Key',
               SECRET = N'<AccessKeyID>:<SecretKeyID>';

      BACKUP DATABASE [LabMedia]
      TO URL = 's3://10.10.10.10:8787/sqlbackups/LabMedia.bak'
      WITH FORMAT, COMPRESSION, CHECKSUM;
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   6) SQL Server 2025: immutable blob storage
      ตั้ง immutability policy ที่ระดับ container ใน Azure แล้ว backup ปกติ:
      engine จะเขียนไฟล์แบบ one-pass (ไม่ pre-allocate) เพราะเขียนทับไม่ได้
      ถ้ามี backup ชื่อเดิมแล้ว + WITH FORMAT → BACKUP fail (ป้องกันเขียนทับ)
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   7) ตรวจ credential และตัวเลือกที่เกี่ยวกับสื่อ backup
   --------------------------------------------------------------- */
USE master;
GO
SELECT name, credential_identity FROM sys.credentials;   -- credentials ที่มีอยู่
GO
SELECT name, value_in_use AS current_setting
FROM sys.configurations
WHERE name IN (N'backup compression default', N'backup compression algorithm');
GO

/* ---------------------------------------------------------------
   Cleanup — ลบ DB + แจ้งลบไฟล์ทีหลัง
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabMedia] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMedia];
GO
-- ลบไฟล์ C:\SQLBackups\LabMedia_*.bak ด้วย PowerShell: Remove-Item C:\SQLBackups\LabMedia_*
GO
