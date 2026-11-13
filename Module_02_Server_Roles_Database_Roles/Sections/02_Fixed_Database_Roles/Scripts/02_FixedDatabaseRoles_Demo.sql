-- 02_FixedDatabaseRoles_Demo.sql
-- สาธิต fixed database roles ตามหัวข้อ 2.2-2.4 ของ Section 2 (Module 2)
-- ปรับจาก Microsoft 20764D "Demo 2 - database roles.sql" (บน AdventureWorks2025 ไม่ใช่ Azure)

USE [master];
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'demo_login_3')
    CREATE LOGIN demo_login_3 WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE [AdventureWorks2025];
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'demo_user_3')
    DROP USER [demo_user_3];
GO
CREATE USER [demo_user_3] FOR LOGIN [demo_login_3];
GO

-- ทุก user เป็นสมาชิก public โดย default
EXECUTE AS USER = N'demo_user_3'
SELECT IS_MEMBER('public') AS is_public_member;
REVERT
GO

-- เพิ่มเข้า db_datareader + db_ddladmin
ALTER ROLE [db_datareader] ADD MEMBER [demo_user_3];
ALTER ROLE [db_ddladmin]  ADD MEMBER [demo_user_3];
GO

-- ดู role memberships
SELECT rdp.name AS role_name, rdm.name AS member_name
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS rdp ON rdp.principal_id = rm.role_principal_id
JOIN sys.database_principals AS rdm ON rdm.principal_id = rm.member_principal_id
WHERE rdm.name = N'demo_user_3'
ORDER BY role_name, member_name;
GO

-- ทดสอบสิทธิ์จริง
EXECUTE AS USER = N'demo_user_3'
SELECT IS_MEMBER('db_datareader') AS is_datareader,
       IS_MEMBER('db_ddladmin')   AS is_ddladmin,
       IS_MEMBER('db_owner')      AS is_owner;
REVERT
GO

-- ===== ทดสอบ database ownership =====
SELECT name, SUSER_SNAME(owner_sid) AS owner_login
FROM sys.databases
WHERE name = N'AdventureWorks2025';
GO

-- ===== Cleanup =====
ALTER ROLE [db_datareader] DROP MEMBER [demo_user_3];
ALTER ROLE [db_ddladmin]  DROP MEMBER [demo_user_3];
DROP USER IF EXISTS [demo_user_3];
GO
USE [master];
GO
DROP LOGIN IF EXISTS [demo_login_3];
GO
