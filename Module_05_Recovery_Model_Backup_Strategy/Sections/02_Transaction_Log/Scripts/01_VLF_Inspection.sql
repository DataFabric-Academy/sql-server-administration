/* =============================================================================
   01_VLF_Inspection.sql
   Module 05 - Section 2: ตรวจ VLF ด้วย sys.dm_db_log_info (แทน DBCC LOGINFO)
   รันได้บน SQL Server 2016 SP2+ / 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';   -- โฟลเดอร์สำหรับไฟล์ DB ทดลองด้านล่าง
GO

/* ---------------------------------------------------------------
   1) สำรวจ VLF ของทุกฐานข้อมูล — เจอตัวที่มีมากกว่า 100 อัน
   --------------------------------------------------------------- */
SELECT [name], COUNT(l.database_id) AS vlf_count
FROM sys.databases AS s
CROSS APPLY sys.dm_db_log_info(s.database_id) AS l
GROUP BY [name]
HAVING COUNT(l.database_id) > 100
ORDER BY vlf_count DESC;
GO
-- Expected: ฐานข้อมูลที่เคย grow ทีละน้อยบ่อย ๆ จะมี vlf_count สูง

/* ---------------------------------------------------------------
   2) รายละเอียด VLF ของ AdventureWorks2025
   --------------------------------------------------------------- */
SELECT file_id, vlf_size_mb, vlf_active, vlf_status, vlf_first_lsn
FROM sys.dm_db_log_info(DB_ID(N'AdventureWorks2025'));
GO

-- ข้อมูลเทียบกันระดับ DB ในมุมมองเดียว (รวม total_vlf_count)
SELECT database_id, total_vlf_count, active_vlf_count,
       total_log_size_mb, active_log_size_mb,
       log_truncation_holdup_reason
FROM sys.dm_db_log_stats(DB_ID(N'AdventureWorks2025'));
GO

/* ---------------------------------------------------------------
   3) เดโม: log ที่ grow ทีละ 1MB สิบครั้ง vs log ที่ grow ครั้งเดียว 10MB
      (SQL Server 2022+ สูตร VLF ใหม่สร้าง VLF น้อยลง แต่ปรากฏการณ์เดียวกัน
       "เล็กบ่อย ๆ" ยังให้ VLF เยอะกว่า "ใหญ่ครั้งเดียว" เสมอ)
   --------------------------------------------------------------- */
IF DB_ID(N'LabVLF') IS NOT NULL
BEGIN
    ALTER DATABASE [LabVLF] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabVLF];
END
GO
CREATE DATABASE [LabVLF]
ON  PRIMARY ( NAME = N'LabVLF_data', FILENAME = N'C:\SQLBackups\LabVLF.mdf',
              SIZE = 8MB, FILEGROWTH = 16MB )
LOG ON ( NAME = N'LabVLF_log', FILENAME = N'C:\SQLBackups\LabVLF_log.ldf',
         SIZE = 4MB, FILEGROWTH = 1MB );      -- growth เล็ก ๆ จงใจ
GO

USE [LabVLF];
GO
CREATE TABLE dbo.T (id INT IDENTITY, filler CHAR(8000) DEFAULT 'x');
-- ใส่ข้อมูลพอให้ log ต้อง grow หลายรอบ (~64MB รวม, แถวละ 8KB)
INSERT INTO dbo.T DEFAULT VALUES;
GO 10
INSERT INTO dbo.T SELECT 'y' FROM sys.all_objects;
GO 10

-- สังเกตจำนวน VLF และขนาดเล็ก ๆ (VLF จิ้มฟิ้วหลักสิบ)
SELECT COUNT(*) AS vlf_count, MIN(vlf_size_mb) AS smallest_vlf_mb,
       MAX(vlf_size_mb) AS largest_vlf_mb
FROM sys.dm_db_log_info(DB_ID(N'LabVLF'));
GO

/* ---------------------------------------------------------------
   4) แก้ปัญหาด้วย pattern ที่ถูกต้อง:
      backup (หรือ truncation) → SHRINKFILE → ตั้งขนาด/growth ใหม่ให้ดี
   --------------------------------------------------------------- */
ALTER DATABASE [LabVLF] SET RECOVERY SIMPLE;    -- ทำให้ truncate ได้ทันทีเพื่อเดโม
CHECKPOINT;
GO
DBCC SHRINKFILE (N'LabVLF_log', 4);             -- รีด log กลับมาเล็ก (ตอนไม่มี workload)
GO
-- ปรับ growth เป็นขนาดคงที่ที่เหมาะสม
ALTER DATABASE [LabVLF]
MODIFY FILE (NAME = N'LabVLF_log', SIZE = 256MB, FILEGROWTH = 256MB);
GO

-- ตรวจซ้ำ: จำนวน VLF ลดลงเหลือไม่กี่อันและ VLF ใหญ่ขึ้น
SELECT COUNT(*) AS vlf_count_after,
       MIN(vlf_size_mb) AS smallest_vlf_mb_after
FROM sys.dm_db_log_info(DB_ID(N'LabVLF'));
GO
/* Expected: vlf_count_after ลดลงเหลือหลักหน่วย (VLF ~64MB หรือใหญ่กว่า)
   หมายเหตุ: เวิร์กโฟลว์ SHRINKFILE ใน production ต้องใช้กับ log backup ก่อน
   ถ้าอยู่ใน FULL recovery (ดู Section 2.5 ของบทเรียน) */

/* ---------------------------------------------------------------
   5) เทียบ DBCC LOGINFO เดิม (ยังรันได้ แต่ถูกแทน — อย่าใช้ในงานใหม่)
   --------------------------------------------------------------- */
DBCC LOGINFO(N'LabVLF');   -- คืนแถวต่อ VLF แบบเดียวกับ dm_db_log_info
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabVLF] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabVLF];
GO
-- ลบไฟล์ C:\SQLBackups\LabVLF*.mdf/.ldf ทีหลัง
GO
