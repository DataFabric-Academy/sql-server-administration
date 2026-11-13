-- 01_CreateUsers.sql
-- แมป login เป็น user ตามหัวข้อ 2.1-2.2 ของ Section 2 (Module 1)
-- แก้ MACHINE และ path ของ login ให้ตรงเครื่องของคุณ

USE [master];
GO
-- เตรียม logins ที่จะใช้ (idempotent)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Superman')
    CREATE LOGIN [Superman] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE [AdventureWorks2025];
GO

-- 1) SQL login → SQL user
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Superman')
    CREATE USER [Superman] FOR LOGIN [Superman];

-- 2) Windows login → Windows user (แก้ MACHINE ให้ตรงเครื่อง)
-- IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Sales_Asia')
--     CREATE USER [Sales_Asia] FOR LOGIN [MACHINE\Sales_Asia]
--         WITH DEFAULT_SCHEMA = [Sales];

-- 3) เปิด guest ชั่วคราวเพื่อสาธิต (ห้ามใช้ production)
GRANT CONNECT TO guest;
GO

-- 4) ตรวจดู user ที่สร้าง
SELECT name, sid, type_desc, default_schema_name, authentication_type_desc
FROM sys.database_principals
WHERE name IN (N'Superman', N'guest')
ORDER BY name;
GO
