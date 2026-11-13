-- 01_UserDefinedRoles_Demo.sql
-- สาธิต user-defined database role ตามหัวข้อ 3.1 ของ Section 3 (Module 2)
-- ปรับจาก Microsoft 20764D "Demo 3 - user database roles.sql"

USE [master];
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hr_01')
    CREATE LOGIN [hr_01] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hr_02')
    CREATE LOGIN [hr_02] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE [AdventureWorks2025];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'hr_01')
    CREATE USER [hr_01] FOR LOGIN [hr_01];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'hr_02')
    CREATE USER [hr_02] FOR LOGIN [hr_02];
GO

-- ===== Step 1: สร้าง role =====
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'human_resources_reader' AND type = 'R')
    DROP ROLE [human_resources_reader];
GO
CREATE ROLE [human_resources_reader];
GO

-- ===== Step 2: ให้สิทธิ์ SELECT ที่ schema HumanResources =====
GRANT SELECT ON SCHEMA::HumanResources TO [human_resources_reader];
GO

-- ===== Step 3: ตรวจสิทธิ์ของ role =====
SELECT dpr.name AS principal_name, dpe.permission_name,
       dpe.class_desc, sch.name AS schema_name
FROM sys.database_permissions AS dpe
JOIN sys.database_principals AS dpr ON dpr.principal_id = dpe.grantee_principal_id
LEFT JOIN sys.schemas AS sch ON sch.schema_id = dpe.major_id AND dpe.class = 3
WHERE dpr.name = N'human_resources_reader';
GO

-- ===== Step 4: เพิ่มสมาชิก =====
ALTER ROLE [human_resources_reader] ADD MEMBER [hr_01];
ALTER ROLE [human_resources_reader] ADD MEMBER [hr_02];
GO

-- ===== Step 5: ตรวจ membership + ทดสอบ =====
SELECT rdp.name AS role_name, rdm.name AS member_name
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS rdp ON rdp.principal_id = rm.role_principal_id
JOIN sys.database_principals AS rdm ON rdm.principal_id = rm.member_principal_id
WHERE rdp.name = N'human_resources_reader';
GO

EXECUTE AS USER = N'hr_01'
SELECT TOP 3 BusinessEntityID, JobTitle FROM HumanResources.Employee;
REVERT
GO

-- ===== Step 6: Cleanup =====
ALTER ROLE [human_resources_reader] DROP MEMBER [hr_01];
ALTER ROLE [human_resources_reader] DROP MEMBER [hr_02];
DROP ROLE IF EXISTS [human_resources_reader];
DROP USER IF EXISTS [hr_01];
DROP USER IF EXISTS [hr_02];
GO
USE [master];
GO
DROP LOGIN IF EXISTS [hr_01];
DROP LOGIN IF EXISTS [hr_02];
GO
