-- ============================================================================
-- Section 03 — Demo 02: แบบฝึกหัดจากสไลด์
-- สร้าง Role + GRANT 4 สิทธิ์ (SELECT, INSERT, UPDATE, DELETE) ทั้ง schema
-- HumanResources เหมือนตัวอย่างในสไลด์ (ปรับจาก Lab03 Exercise 3 เดิม)
-- ฐานข้อมูล: AdventureWorks2025  — ไม่พึ่ง AD (ใช้ SQL auth + WITHOUT LOGIN)
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoHRStaff')
    DROP LOGIN DemoHRStaff;
GO
CREATE LOGIN DemoHRStaff WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoHRStaff')
    DROP USER DemoHRStaff;
GO

-- ---------- ขั้น 1: สร้าง role + user ----------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'HumanResources_Users')
    DROP ROLE HumanResources_Users;
GO
CREATE ROLE HumanResources_Users;
GO

CREATE USER DemoHRStaff FOR LOGIN DemoHRStaff;
GO

-- ---------- ขั้น 2: GRANT 4 สิทธิ์ทั้ง schema ในคำสั่งเดียว (เหมือนสไลด์) ----------
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HumanResources
    TO HumanResources_Users;
GO

-- เพิ่ม user เข้า role
ALTER ROLE HumanResources_Users ADD MEMBER DemoHRStaff;
GO

-- ---------- ขั้น 3: ทดสอบ 4 สิทธิ์จริงใน schema HumanResources ----------
-- ใช้ตาราง Department (มี PK) กับแถวชั่วคราวที่ cleanup ลบทิ้ง
EXECUTE AS USER = 'DemoHRStaff';

-- 3a) SELECT
SELECT TOP 3 DepartmentID, Name FROM HumanResources.Department;

-- 3b) INSERT (id เกินช่วงข้อมูลจริงเพื่อกันชน PK)
INSERT INTO HumanResources.Department (DepartmentID, Name, GroupName)
VALUES (900, N'TestDept-Slide', N'Executive General and Administration');

-- 3c) UPDATE
UPDATE HumanResources.Department
SET Name = N'TestDept-Slide-Updated'
WHERE DepartmentID = 900;

-- 3d) DELETE
DELETE FROM HumanResources.Department WHERE DepartmentID = 900;

-- นอกขอบเขต schema → ยังไม่ได้ (Production เป็น schema อื่น)
SELECT TOP 1 * FROM Production.Product;   -- คาดหวัง error 229

REVERT;
GO

-- ---------- ขั้น 4: เทียบ — role นี้ไม่ครอบ proc (ยังไม่มี EXECUTE) ----------
EXECUTE AS USER = 'DemoHRStaff';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 2;   -- error 229
REVERT;
GO

-- ถ้าต้องการให้ role รัน proc ทั้ง schema ด้วย เพิ่มบรรทัดนี้ (ในคอมเมนต์ไว้):
-- GRANT EXECUTE ON SCHEMA::dbo TO HumanResources_Users;

-- ---------- ขั้น 5: ตรวจผลใน catalog ----------
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       SCHEMA_NAME(pe.major_id) AS schema_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 3
  AND pr.name = 'HumanResources_Users'
ORDER BY pe.permission_name;
GO

SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name = 'HumanResources_Users';
GO

-- ---------- Cleanup ----------
ALTER ROLE HumanResources_Users DROP MEMBER DemoHRStaff;
DROP ROLE HumanResources_Users;
DROP USER DemoHRStaff;
GO
USE master;
GO
DROP LOGIN DemoHRStaff;
GO
-- จบสคริปต์
