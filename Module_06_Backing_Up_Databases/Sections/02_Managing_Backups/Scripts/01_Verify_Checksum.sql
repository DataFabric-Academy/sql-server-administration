/* =============================================================================
   01_Verify_Checksum.sql
   Module 06 - Section 2: WITH CHECKSUM + RESTORE VERIFYONLY
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'LabVerify') IS NOT NULL
BEGIN
    ALTER DATABASE [LabVerify] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabVerify];
END
GO
CREATE DATABASE [LabVerify];
GO
-- ตรวจการตั้งค่าการตรวจสอบ page ของฐานข้อมูล (CHECKSUM เป็นค่า default)
SELECT name, page_verify_option_desc FROM sys.databases WHERE name = N'LabVerify';
GO

/* ---------------------------------------------------------------
   1) Backup พร้อม CHECKSUM + STOP_ON_ERROR (default)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabVerify]
TO DISK = N'C:\SQLBackups\LabVerify.bak'
WITH FORMAT, INIT, CHECKSUM, STOP_ON_ERROR, COMPRESSION, STATS = 10,
     NAME = N'checksum demo';
GO

/* ---------------------------------------------------------------
   2) ตรวจสอบไฟล์หลังเขียน — ไม่กู้จริง
   --------------------------------------------------------------- */
RESTORE VERIFYONLY
FROM DISK = N'C:\SQLBackups\LabVerify.bak'
WITH CHECKSUM;
GO
/* Expected: "The backup set on file 1 is valid." */

/* ---------------------------------------------------------------
   3) VERIFYONLY กับ stripe set — ระบุทุกไฟล์
   --------------------------------------------------------------- */
BACKUP DATABASE [LabVerify]
TO DISK = N'C:\SQLBackups\LabVerify_1.bak',
   DISK = N'C:\SQLBackups\LabVerify_2.bak'
WITH FORMAT, INIT, CHECKSUM;
GO
RESTORE VERIFYONLY
FROM DISK = N'C:\SQLBackups\LabVerify_1.bak',
     DISK = N'C:\SQLBackups\LabVerify_2.bak'
WITH CHECKSUM;
GO

/* ---------------------------------------------------------------
   4) ตรวจ suspect_pages — บันทึก page เสีย (ในแล็บปกติจะว่าง)
   --------------------------------------------------------------- */
SELECT TOP 20 database_id, file_id, page_id, event_type, error_count
FROM msdb.dbo.suspect_pages
ORDER BY last_update_date DESC;
GO
/* Expected: 0 แถวบนเครื่องสุขภาพดี — event_type 1/2/3 คือ error ที่เจอจริง (823/824/bad checksum/torn page) */

/* ---------------------------------------------------------------
   5) ลอง NO_CHECKSUM เทียบ (ทำได้ แต่ไม่แนะนำใน production)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabVerify]
TO DISK = N'C:\SQLBackups\LabVerify_nochk.bak'
WITH FORMAT, INIT, NO_CHECKSUM, NAME = N'without checksum (demo)';
GO
/* ข้อแตกต่าง: ไม่มีการตรวจ page checksum ขณะเขียน — page เสียหลุดเข้าไฟล์ได้เงียบ ๆ */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabVerify] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabVerify];
GO
-- ลบไฟล์ C:\SQLBackups\LabVerify* ทีหลัง
GO
