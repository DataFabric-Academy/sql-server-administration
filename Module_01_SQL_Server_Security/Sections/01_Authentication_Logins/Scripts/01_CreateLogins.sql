-- 01_CreateLogins.sql
-- สร้าง/จัดการ logins ตามหัวข้อ 1.3-1.4 ของ Section 1 (Module 1)
-- แก้ชื่อเครื่อง (MACHINE) เป็นชื่อจริงของคุณก่อนรัน

USE [master];
GO

-- 1) Windows Authentication login — local group ของเครื่อง
--    แทน MACHINE ด้วย hostname ของเครื่องนี้ (รัน hostname เพื่อดูชื่อ)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'MACHINE\WebUsers')
    CREATE LOGIN [MACHINE\WebUsers] FROM WINDOWS
        WITH DEFAULT_DATABASE = [AdventureWorks2025];
GO

-- 2) SQL Server Authentication login
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Web_Application')
    CREATE LOGIN [Web_Application] WITH PASSWORD = N'Pa$$w0rd2025',
        DEFAULT_DATABASE = [AdventureWorks2025],
        CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
GO

-- 3) จัดการ login ที่มีอยู่
ALTER LOGIN [Web_Application] DISABLE;
SELECT name, is_disabled FROM sys.server_principals WHERE name = N'Web_Application';

ALTER LOGIN [Web_Application] ENABLE;
ALTER LOGIN [Web_Application] WITH PASSWORD = N'Pa$$w0rd2026';
GO

-- 4) ตรวจดู login ทั้งหมดที่เราสร้าง
SELECT name, sid, type_desc, is_disabled, create_date
FROM sys.server_principals
WHERE name IN (N'MACHINE\WebUsers', N'Web_Application')
ORDER BY name;
GO

-- 5) เปลี่ยน default database ให้ตรงเครื่องที่มี AdventureWorks2025
ALTER LOGIN [Web_Application] WITH DEFAULT_DATABASE = [AdventureWorks2025];
GO
-- หมายเหตุ: ถ้าจะทดสอบ error 4064 (default database หาย) ให้
-- ALTER LOGIN [Web_Application] WITH DEFAULT_DATABASE = [NotExistingDB]; แล้ว login ด้วย Web_Application
