-- 02_Security_Tokens_Demo.sql
-- ดู login token / user token ตามหัวข้อ 1.6 ของ Section 1 (Module 1)
-- ปรับจาก Microsoft 20764D "Security Tokens Demo.sql" ให้ idempotent + cleanup ในตัว

USE master;
GO

-- ===== Setup =====
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'LabLogin' AND type = 'S')
    DROP LOGIN [LabLogin];
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'LabServerRole' AND type = 'R')
    DROP SERVER ROLE [LabServerRole];
GO

CREATE SERVER ROLE LabServerRole;
CREATE LOGIN LabLogin WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
ALTER SERVER ROLE LabServerRole ADD MEMBER LabLogin;
GO

-- ลบ role/user ระดับ database ของ master ถ้ามีของเดิม
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'LabDatabaseRole' AND type = 'R')
    DROP ROLE [LabDatabaseRole];
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'LabUser' AND type = 'S')
    DROP USER [LabUser];
GO

CREATE ROLE LabDatabaseRole;
CREATE USER LabUser FOR LOGIN LabLogin;
ALTER ROLE LabDatabaseRole ADD MEMBER LabUser;
GO

-- ===== ดู token =====
-- Login token (ระดับ server): LabLogin + LabServerRole + public
EXECUTE AS LOGIN = N'LabLogin';
SELECT * FROM sys.login_token;
REVERT;
GO

-- User token (ระดับ database ใน master): LabUser + LabDatabaseRole + public
EXECUTE AS USER = N'LabUser';
SELECT * FROM sys.user_token;
REVERT;
GO

-- ===== Cleanup =====
ALTER SERVER ROLE LabServerRole DROP MEMBER LabLogin;
DROP ROLE IF EXISTS LabDatabaseRole;
DROP USER IF EXISTS LabUser;
DROP LOGIN IF EXISTS LabLogin;
DROP SERVER ROLE IF EXISTS LabServerRole;
GO
