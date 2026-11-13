-- 02_FixedServerRoles_Demo.sql
-- สาธิต fixed server roles + public + user-defined server role
-- ตามหัวข้อ 1.2-1.3 ของ Section 1 (Module 2)
-- ปรับจาก Microsoft 20764D "Demo 1 - server roles.sql" (Step 2-10)

USE [master];
GO

-- ===== Setup: logins สำหรับสาธิต =====
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'demo_login_1')
    CREATE LOGIN demo_login_1 WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'demo_login_2')
    CREATE LOGIN demo_login_2 WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

-- ===== Step: ทุก login เป็นสมาชิก public โดย default =====
SELECT IS_SRVROLEMEMBER('public', N'demo_login_1') AS is_public_member;  -- 1 = ใช่
GO

-- ===== Step: ดูสิทธิ์เริ่มต้นของ login ใหม่ =====
EXECUTE AS LOGIN = N'demo_login_1'
SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
REVERT;
GO

-- ===== Step: เพิ่มเข้า fixed role (diskadmin) แล้วตรวจ =====
ALTER SERVER ROLE [diskadmin] ADD MEMBER [demo_login_1];
GO

SELECT spr.name AS role_name, spm.name AS member_name
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS spr ON spr.principal_id = rm.role_principal_id
JOIN sys.server_principals AS spm ON spm.principal_id = rm.member_principal_id
WHERE spm.name = N'demo_login_1'
ORDER BY role_name, member_name;
GO

-- ===== Step: สร้าง user-defined server role + ให้สิทธิ์ =====
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'monitoring_role' AND type = 'R')
    DROP SERVER ROLE [monitoring_role];
GO
CREATE SERVER ROLE [monitoring_role] AUTHORIZATION sa;
GO
GRANT VIEW SERVER STATE TO [monitoring_role];     -- ดู DMVs ได้
GRANT VIEW ANY DATABASE TO [monitoring_role];     -- ดูรายการฐานข้อมูลได้
GO
ALTER SERVER ROLE [monitoring_role] ADD MEMBER [demo_login_2];
GO

-- ===== Step: ทดสอบสิทธิ์ที่ได้ =====
EXECUTE AS LOGIN = N'demo_login_2'
SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
REVERT;
GO

-- ===== Cleanup =====
ALTER SERVER ROLE [diskadmin] DROP MEMBER [demo_login_1];
ALTER SERVER ROLE [monitoring_role] DROP MEMBER [demo_login_2];
DROP SERVER ROLE IF EXISTS [monitoring_role];
DROP LOGIN IF EXISTS [demo_login_1];
DROP LOGIN IF EXISTS [demo_login_2];
GO
