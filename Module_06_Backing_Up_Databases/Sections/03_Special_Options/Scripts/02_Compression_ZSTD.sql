/* =============================================================================
   02_Compression_ZSTD.sql
   Module 06 - Section 3: เปรียบเทียบ backup compression
   NO_COMPRESSION vs MS_XPRESS vs ZSTD (SQL Server 2025+)
   รันได้บน SQL Server 2025 (ZSTD ต้อง 17.x; บน 2019/2022 ใช้ส่วน MS_XPRESS ได้)
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'LabZSTD') IS NOT NULL
BEGIN
    ALTER DATABASE [LabZSTD] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabZSTD];
END
GO
CREATE DATABASE [LabZSTD];
GO

USE [LabZSTD];
GO
-- ข้อมูลที่บีบง่าย (ข้อความซ้ำ) เพื่อให้เห็น ratio ชัด
CREATE TABLE dbo.Payload (id INT IDENTITY, text1 NVARCHAR(200), text2 CHAR(80));
INSERT INTO dbo.Payload (text1, text2)
SELECT N'Adventure Works Cargo bike line — รายการที่ ' + CAST(o.n AS NVARCHAR(20)), 'Z'
FROM (SELECT TOP 20000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_objects, sys.all_columns) AS o;
GO
USE master;
GO

/* ---------------------------------------------------------------
   1) NO_COMPRESSION (baseline)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabZSTD]
TO DISK = N'C:\SQLBackups\ZSTD_none.bak'
WITH FORMAT, INIT, NO_COMPRESSION, CHECKSUM, NAME = N'baseline (no compression)';
GO

/* ---------------------------------------------------------------
   2) MS_XPRESS (อัลกอริทึมดั้งเดิม, default ของ WITH COMPRESSION)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabZSTD]
TO DISK = N'C:\SQLBackups\ZSTD_xpress.bak'
WITH FORMAT, INIT, COMPRESSION (ALGORITHM = MS_XPRESS),
     CHECKSUM, NAME = N'MS_XPRESS';
GO

/* ---------------------------------------------------------------
   3) ZSTD (SQL Server 2025+) — เทียบ LOW/MEDIUM/HIGH ได้
   --------------------------------------------------------------- */
BACKUP DATABASE [LabZSTD]
TO DISK = N'C:\SQLBackups\ZSTD_zstd.bak'
WITH FORMAT, INIT, COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM),
     CHECKSUM, NAME = N'ZSTD MEDIUM';
GO

/* ---------------------------------------------------------------
   4) วัดผลจาก msdb — ขนาด + เวลา + ratio
      (สรุปใส่ตารางในเอกสารแล็บของคุณ — ตัวเลขจริงต่างตามฮาร์ดแวร์)
   --------------------------------------------------------------- */
SELECT name,
       backup_start_date, backup_finish_date,
       DATEDIFF(MILLISECOND, backup_start_date, backup_finish_date) AS duration_ms,
       CAST(backup_size / 1048576.0 AS DECIMAL(10,2)) AS raw_MB,
       CAST(compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       CAST(backup_size / compressed_backup_size AS DECIMAL(6,2)) AS ratio
FROM msdb.dbo.backupset
WHERE database_name = N'LabZSTD'
ORDER BY backup_finish_date;
GO
/* Expected รูปแบบผลลัพธ์ (ตัวเลขจริงต่างตามข้อมูล+ฮาร์ดแวร์):
   baseline ใหญ่สุด; MS_XPRESS บีบได้ดี; ZSTD ได้ ratio เท่าหรือดีกว่า
   โดยใช้เวลาไม่มากกว่า — นี่คือประโยคที่ Microsoft ประกาศ: "faster and
   more effective than MS_XPRESS" วัดยืนยันด้วยสองคอลัมน์นี้ได้เสมอ */

/* ---------------------------------------------------------------
   5) ตั้ง default อัลกอริทึมของ instance — config option
      (3 = ZSTD เฉพาะ SQL Server 2025; 0 = MS_XPRESS)
   --------------------------------------------------------------- */
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name = N'backup compression algorithm';
GO
-- EXEC sys.sp_configure N'backup compression algorithm', 3;
-- RECONFIGURE;
-- (เมื่อตั้งแล้ว BACKUP ... WITH COMPRESSION จะใช้ ZSTD ทั้ง instance จนกลับค่า)

/* ---------------------------------------------------------------
   6) ข้อจำกัดสาธิต: compressed + uncompressed รวมกันใน media เดียวไม่ได้
   --------------------------------------------------------------- */
BACKUP DATABASE [LabZSTD]
TO DISK = N'C:\SQLBackups\ZSTD_mix.bak'
WITH NOINIT, NO_COMPRESSION, NAME = N'mix into compressed media';
GO
/* Expected: BACKUP fail — ห้ามผสม compressed และ uncompressed backup sets
   ใน media set เดียว (ข้อจำกัดตามเอกสาร Backup Compression) */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabZSTD] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabZSTD];
GO
-- ลบไฟล์ C:\SQLBackups\ZSTD_* ทีหลัง
GO
