-- ============================================================================
-- Section 03 — Demo 01: Schema-Level Permissions (GRANT ON SCHEMA::)
-- ฐานข้อมูล: AdventureWorks2025
-- สาธิตตาม demo เดิมของหลักสูตร 20764D (Configuring Permissions at Schema Level)
-- ปรับใหม่: idempotent + AdventureWorks2025 + ไม่ต้องพึ่ง AD
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoSchemaUser')
    DROP LOGIN DemoSchemaUser;
GO
CREATE LOGIN DemoSchemaUser WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoSchemaUser')
    DROP USER DemoSchemaUser;
GO
CREATE USER DemoSchemaUser FOR LOGIN DemoSchemaUser;
GO

-- ---------- ขั้น 1: ก่อนมอบสิทธิ์ — รัน proc ใน dbo ไม่ได้ ----------
EXECUTE AS USER = 'DemoSchemaUser';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 2;   -- error 229
REVERT;
GO

-- ---------- ขั้น 2: GRANT EXECUTE ทั้ง schema dbo ----------
GRANT EXECUTE ON SCHEMA::dbo TO DemoSchemaUser;
GO

EXECUTE AS USER = 'DemoSchemaUser';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 2;   -- ทำงานได้ (รวมทุก proc ใน dbo)
REVERT;
GO

-- ---------- ขั้น 3: DENY ที่ object ชนะ GRANT ที่ schema ----------
-- คำถามจากสไลด์: user มี EXECUTE ระดับ schema แต่โดน DENY ระดับ proc → รันได้ไหม?
DENY EXECUTE ON dbo.uspGetManagerEmployees TO DemoSchemaUser;
GO

EXECUTE AS USER = 'DemoSchemaUser';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 2;
-- error 229 — DENY ชนะ (ระดับลึกกว่า + DENY มีน้ำหนักสูงสุด)
REVERT;
GO

-- ---------- ขั้น 4: GRANT SELECT ทั้ง schema HumanResources ----------
GRANT SELECT ON SCHEMA::HumanResources TO DemoSchemaUser;
GO

EXECUTE AS USER = 'DemoSchemaUser';
SELECT TOP 1 * FROM HumanResources.Employee;          -- OK — ตารางเดิม
SELECT TOP 1 * FROM HumanResources.EmployeePayHistory; -- OK — ตารางอื่นใน schema เดียวกัน
SELECT TOP 1 * FROM Production.Product;               -- error 229 — ต่าง schema
REVERT;
GO

-- ---------- ขั้น 5: ตารางใหม่ใน schema นั้นใช้ได้ทันที (ไม่ต้อง GRANT ใหม่) ----------
CREATE TABLE HumanResources.DemoNewTable (Id int);
GO

EXECUTE AS USER = 'DemoSchemaUser';
SELECT * FROM HumanResources.DemoNewTable;   -- OK โดยไม่แตะ GRANT เพิ่ม
REVERT;
GO

-- ---------- ขั้น 6: ตรวจสิทธิ์ระดับ schema ใน catalog ----------
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       SCHEMA_NAME(pe.major_id) AS schema_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 3                     -- 3 = SCHEMA
  AND pr.name = 'DemoSchemaUser'
ORDER BY pe.permission_name;
GO

-- ---------- ขั้น 7: fn_builtin_permissions — สิทธิ์อะไร "ครอบ" สิทธิ์อะไร ----------
-- (จาก demo เดิม: สำรวจ permission hierarchy ด้วย covering_permission_name)
SELECT permission_name, class_desc, covering_permission_name
FROM sys.fn_builtin_permissions('SCHEMA')
WHERE permission_name IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'EXECUTE', 'CONTROL')
ORDER BY permission_name;
GO

-- ---------- Cleanup ----------
DROP TABLE HumanResources.DemoNewTable;
REVOKE SELECT ON SCHEMA::HumanResources FROM DemoSchemaUser;
REVOKE EXECUTE ON SCHEMA::dbo FROM DemoSchemaUser;
DROP USER DemoSchemaUser;
GO
USE master;
GO
DROP LOGIN DemoSchemaUser;
GO
-- จบสคริปต์
