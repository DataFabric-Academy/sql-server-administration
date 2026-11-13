/* =============================================================================
   03_PageRestore.sql
   Module 07 - Section 3: page restore — จำลอง page เสีย (สร้างเองใน sandbox)
   → เจอ error 824 → บันทึกใน msdb.dbo.suspect_pages → กู้เฉพาะ page
   รันได้บน SQL Server 2025 — idempotent
   ⚠️ แล็บนี้ "แก้ไขไฟล์ .mdf จริง" ด้วย PowerShell บนฐานข้อมูลทดลองเท่านั้น
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลองเฉพาะกิจ (ห้ามใช้กับ AdventureWorks หรือ DB จริง!)
   --------------------------------------------------------------- */
IF DB_ID(N'PageDemo') IS NOT NULL
BEGIN
    ALTER DATABASE [PageDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PageDemo];
END
GO
CREATE DATABASE [PageDemo]
ON  PRIMARY ( NAME = N'PageDemo_data', FILENAME = N'C:\SQLBackups\PageDemo.mdf' )
LOG ON      ( NAME = N'PageDemo_log',  FILENAME = N'C:\SQLBackups\PageDemo_log.ldf' );
GO
ALTER DATABASE [PageDemo] SET RECOVERY FULL;
ALTER DATABASE [PageDemo] SET PAGE_VERIFY CHECKSUM;   -- ทำให้เห็น error 824
GO

USE [PageDemo];
GO
CREATE TABLE dbo.Bill (id INT IDENTITY, payload CHAR(4000) DEFAULT 'x');
INSERT INTO dbo.Bill DEFAULT VALUES;
GO 200     -- ~50 pages ข้อมูล เพื่อให้ตารางไม่ใช่ page เดียว
GO

/* ---------------------------------------------------------------
   2) Backup ครบ: full + log (จำเป็นสำหรับ page restore)
   --------------------------------------------------------------- */
USE master;
GO
BACKUP DATABASE [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo.bak'
WITH FORMAT, INIT, NAME = N'PageDemo full', CHECKSUM;
GO
USE [PageDemo];
GO
INSERT INTO dbo.Bill DEFAULT VALUES;
GO 50
USE master;
GO
BACKUP LOG [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo_log.trn'
WITH FORMAT, INIT, NAME = N'PageDemo log 1', CHECKSUM;
GO

/* ---------------------------------------------------------------
   3) หา page ของตาราง (จะนำไปทำลาย 1 หน้า)
   --------------------------------------------------------------- */
SELECT TOP 1 allocated_page_page_id AS page_to_corrupt
FROM sys.dm_db_database_page_allocations
     (DB_ID(N'PageDemo'), OBJECT_ID(N'PageDemo.dbo.Bill'), NULL, NULL, 'DETAILED')
WHERE is_allocated = 1 AND page_type_desc = N'DATA_PAGE';
GO
/* จดตัวเลข page_to_corrupt ที่ได้ (เช่น 9) — ใช้ใน PowerShell ขั้นถัดไป */

/* ---------------------------------------------------------------
   4) [PowerShell] ทำลาย page จำลอง disk พัง — DB ต้อง OFFLINE ก่อน!
      รันใน T-SQL: ALTER DATABASE [PageDemo] SET OFFLINE;
      แล้วใน PowerShell (แทน <PAGE_ID> ด้วยเลขจากขั้น 3):

      $path = 'C:\SQLBackups\PageDemo.mdf'
      $page = <PAGE_ID>
      $zeros = New-Object byte[] 8192
      $fs = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'ReadWrite')
      $fs.Seek($page * 8192, 'Begin') | Out-Null
      $fs.Write($zeros, 0, 8192)
      $fs.Close()
      "corrupted page $page"

      จากนั้นกลับมา T-SQL: ALTER DATABASE [PageDemo] SET ONLINE;
   --------------------------------------------------------------- */
ALTER DATABASE [PageDemo] SET OFFLINE;
GO
/* → รัน PowerShell ข้างบนตรงนี้ (offline ปลดล็อกไฟล์) → ค่อยเซ็ต ONLINE กลับ */
-- ALTER DATABASE [PageDemo] SET ONLINE;
-- GO

/* ---------------------------------------------------------------
   5) เหตุการณ์เกิด: SELECT ตาราง → error 824 (checksum mismatch)
      รันหลังขั้น 4 ครบ (offline → corrupt → online) แล้วเท่านั้น:
   --------------------------------------------------------------- */
-- USE [PageDemo];
-- GO
-- SELECT COUNT(*) FROM dbo.Bill;
-- GO
/* Expected: Msg 824 — "SQL Server detected a logical consistency-based
   I/O error... incorrect checksum" — บาง query ที่ไม่แตะ page นั้นยังทำงานได้
   (หน้าเสียเฉพาะจุด = DB ยังใช้งานได้ส่วนใหญ่) */

/* ---------------------------------------------------------------
   6) ตรวจบันทึกใน msdb.dbo.suspect_pages
   --------------------------------------------------------------- */
SELECT database_id, file_id, page_id, event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages
WHERE database_id = DB_ID(N'PageDemo');
GO
/* Expected: 1 แถว — file_id = 1, page_id = เลขที่ทำลาย,
   event_type = 2 (bad checksum — ค่า default ของ page ที่ถูกเขียนศูนย์ทับ)
   ค่าอื่น ๆ: 1 = 823/disk หรือ 824 อื่น ๆ, 3 = torn page, 4 = restored, 5 = repaired */

/* ---------------------------------------------------------------
   7) Page restore — กู้เฉพาะหน้านั้นจาก full + log
      แทน <PAGE_ID> ด้วยเลขจริง เช่น PAGE = N'1:9'
   --------------------------------------------------------------- */
-- USE master;
-- GO
-- RESTORE DATABASE [PageDemo]
--     PAGE = N'1:<PAGE_ID>'
-- FROM DISK = N'C:\SQLBackups\PageDemo.bak'
-- WITH FILE = 1, NORECOVERY;
-- RESTORE LOG [PageDemo]
-- FROM DISK = N'C:\SQLBackups\PageDemo_log.trn'
-- WITH RECOVERY;
-- GO
-- /* Expected: "Successfully restored processing 1 pages" — DB ยัง online ตลอด */

/* ---------------------------------------------------------------
   8) ยืนยันว่าข้อมูลกลับมา + เคลียร์ suspect_pages
   --------------------------------------------------------------- */
-- USE [PageDemo];
-- GO
-- SELECT COUNT(*) FROM dbo.Bill;   -- Expected: 250 แถว ไม่มี error อีก
-- GO
-- DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
-- GO
-- BACKUP LOG [PageDemo] TO DISK = N'C:\SQLBackups\PageDemo_log.trn'
--     WITH NOINIT, NAME = N'log หลัง page restore', CHECKSUM;
-- GO
/* ข้อควรจำ: หลัง page restore สั่ง BACKUP LOG ใหม่เสมอ เพิ่มบันทึก
   ว่าการซ่อมแล้วเสร็จ กัน restore ซ้ำชนข้อมูลเก่า */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
IF DB_ID(N'PageDemo') IS NOT NULL
BEGIN
    ALTER DATABASE [PageDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PageDemo];
END
GO
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
GO
-- ลบไฟล์ C:\SQLBackups\PageDemo* ทีหลัง
GO
