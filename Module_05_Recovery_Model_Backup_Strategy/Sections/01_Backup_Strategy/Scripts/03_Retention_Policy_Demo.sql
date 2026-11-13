/* =============================================================================
   03_Retention_Policy_Demo.sql
   Module 05 - Section 1: นโยบายเก็บรักษา — RETAINDAYS / EXPIREDATE
   และการอ่าน expiration จาก msdb
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO

IF DB_ID(N'LabRetention') IS NOT NULL
BEGIN
    ALTER DATABASE [LabRetention] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabRetention];
END
GO
CREATE DATABASE [LabRetention];
GO

/* ---------------------------------------------------------------
   1) Backup พร้อม RETAINDAYS — ห้ามเขียนทับภายใน 7 วัน
      (RETAINDAYS มีลำดับความสำคัญสูงกว่า EXPIREDATE เมื่อใช้พร้อมกัน)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabRetention]
TO DISK = N'C:\SQLBackups\LabRetention.bak'
WITH FORMAT, INIT,
     RETAINDAYS = 7,                     -- ห้าม overwrite ภายใน 7 วัน
     NAME = N'LabRetention weekly full';
GO

/* ---------------------------------------------------------------
   2) ทดสอบว่า INIT ถูก block เพราะ backup set ยังไม่หมดอายุ
      → คำสั่งถัดไปควร FAIL ด้วย error 2611/4035 เกี่ยวกับ expiration
      (รันเพื่อดู error แล้วกดแก้ให้เป็น SKIP)
   --------------------------------------------------------------- */
-- BACKUP DATABASE [LabRetention]
-- TO DISK = N'C:\SQLBackups\LabRetention.bak'
-- WITH INIT, NAME = N'attempt overwrite within retention';
-- GO
-- Expected: "The backup set on file 1 expires on <วันที่>" — ห้าม overwrite
-- เมื่อใช้ WITH SKIP แทน INIT จะ bypass การตรวจ expiration:

BACKUP DATABASE [LabRetention]
TO DISK = N'C:\SQLBackups\LabRetention.bak'
WITH SKIP, INIT, NAME = N'forced overwrite with SKIP (demo)';
GO

/* ---------------------------------------------------------------
   3) อ่าน expiration จาก msdb.dbo.backupset (คอลัมน์ expiration_date)
      — เครื่องมือวางแผน retention ที่ใช้จริงใน Agent job
   --------------------------------------------------------------- */
SELECT
    database_name,
    name AS backup_set_name,
    type,                              -- D = full, I = diff, L = log
    backup_start_date,
    backup_finish_date,
    expiration_date,
    DATEDIFF(DAY, backup_start_date, expiration_date) AS retain_days
FROM msdb.dbo.backupset
WHERE database_name = N'LabRetention'
ORDER BY backup_start_date;
GO

/* ---------------------------------------------------------------
   4) ตัวเลือก retention ระดับ server (media retention)
      default 0 วัน — ถ้าไม่กำหนด RETAINDAYS/EXPIREDATE engine ใช้ค่านี้
   --------------------------------------------------------------- */
SELECT name, value_in_use
FROM sys.configurations
WHERE name = N'media retention';
GO

/* Expected: ตารางแสดง expiration_date = backup_start_date + 7 วัน
   (แถวล่าสุดถูกเขียนทับด้วย SKIP จะมี expiration ใหม่ตามค่า media retention = 0) */

/* ---------------------------------------------------------------
   ข้อควรจำ: EXPIREDATE/RETAINDAYS กันเฉพาะการเขียนทับโดย SQL Server
   ไม่กันการลบไฟล์ที่ OS — นโยบายจริงต้องควบคุมด้วย process ฝั่ง storage
   (เช่น lifecycle policy ของ blob storage หรือ script ลบไฟล์)
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabRetention] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabRetention];
GO
-- ลบไฟล์ C:\SQLBackups\LabRetention.bak ทีหลัง
GO
