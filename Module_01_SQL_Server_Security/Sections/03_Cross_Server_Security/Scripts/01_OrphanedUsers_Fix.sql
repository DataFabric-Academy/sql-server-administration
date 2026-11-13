-- 01_OrphanedUsers_Fix.sql
-- ทดลองสร้าง/แก้ orphaned users ตามหัวข้อ 3.4 ของ Section 3 (Module 1)
-- ปรับจาก Microsoft 20764D "MismatchedIDs.sql" — เปลี่ยน sp_change_users_login (deprecated)
-- เป็นวิธีมาตรฐานปัจจุบัน ALTER USER ... WITH LOGIN

USE master;
GO

-- ===== Setup: จำลองสถานการณ์ orphaned user =====
IF DB_ID(N'LabOrphan') IS NULL
    CREATE DATABASE LabOrphan;
GO

USE LabOrphan;
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'appuser')
    DROP USER [appuser];
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'reportuser')
    DROP USER [reportuser];
GO
CREATE USER [appuser]    WITH PASSWORD = N'Pa$$w0rd2025';   -- contained user ชั่วคราวเพื่อให้มี sid
CREATE USER [reportuser] WITH PASSWORD = N'Pa$$w0rd2025';
GO

-- ===== STEP 1: หา orphaned SQL users (วิธีมาตรฐานปัจจุบัน) =====
SELECT dp.name AS user_in_db, dp.sid
FROM sys.database_principals AS dp
WHERE dp.type = 'S'
  AND dp.sid NOT IN (SELECT sid FROM sys.server_principals)
  AND dp.sid <> 0x0;
GO

-- ===== STEP 2: สร้าง login ใหม่โดยตั้งใจให้ SID ต่างจาก user =====
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'appuser')
    DROP LOGIN [appuser];
GO
CREATE LOGIN [appuser] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE LabOrphan;
GO
-- แปลง user เป็นแบบ instance-auth ที่ชี้ไปที่ login (จะเกิด orphan เพราะ SID ไม่ตรง)
ALTER USER [appuser] WITH LOGIN = [appuser];
GO

-- STEP 3: รายงานอีกครั้ง — appuser ควรโผล่เป็น orphaned
SELECT dp.name AS user_in_db, dp.sid,
       SUSER_SNAME(dp.sid) AS matching_login   -- NULL = ไม่มี login ตรง SID
FROM sys.database_principals AS dp
WHERE dp.type = 'S' AND dp.sid <> 0x0;
GO

-- ===== STEP 4: แก้ด้วย ALTER USER WITH LOGIN (วิธีแนะนำ) =====
-- ใช้เมื่อปลายทางมี login ที่ถูกต้องแล้ว: ALTER USER [user] WITH LOGIN = [login];
-- (สาธิตยกตัวอย่างสั้น ๆ เช่นแก้ให้ชี้ไป login Superman ถ้ามี)
-- ALTER USER [appuser] WITH LOGIN = [Superman];

-- ===== STEP 5: แก้ด้วยการสร้าง login ที่ SID เดียวกับ user =====
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'reportuser')
    DROP LOGIN [reportuser];
GO
DECLARE @sid varbinary(85) =
    (SELECT sid FROM LabOrphan.sys.database_principals WHERE name = N'reportuser');
CREATE LOGIN [reportuser] WITH PASSWORD = N'Pa$$w0rd2025', SID = @sid, CHECK_POLICY = OFF;
GO

-- ===== Cleanup =====
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'appuser')    DROP LOGIN [appuser];
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'reportuser') DROP LOGIN [reportuser];
GO
ALTER DATABASE LabOrphan SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS LabOrphan;
GO
