-- ============================================================================
-- Section 01 — Demo 01: Object Permissions (GRANT / REVOKE / DENY)
-- ฐานข้อมูล: AdventureWorks2025
-- รันบน SQL Server 2025 (17.x) — รันด้วย login ที่มีสิทธิ์ sysadmin หรือ
-- สิทธิ์ ALTER ANY LOGIN / ALTER ANY USER ใน AdventureWorks2025
-- ============================================================================
USE master;
GO

-- ---------- เตรียม login สาธิต (idempotent) ----------
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoSalesClerk')
    DROP LOGIN DemoSalesClerk;
GO
CREATE LOGIN DemoSalesClerk WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

-- ---------- เตรียม user สาธิต ----------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoSalesClerk')
    DROP USER DemoSalesClerk;
GO
CREATE USER DemoSalesClerk FOR LOGIN DemoSalesClerk;
GO

-- ---------- ขั้น 1: default = สิทธิ์เป็นศูนย์ ----------
-- ผลลัพธ์: error 229 "The SELECT permission was denied on object 'Product'"
EXECUTE AS USER = 'DemoSalesClerk';
SELECT TOP 1 Name FROM Production.Product;
REVERT;
GO

-- ---------- ขั้น 2: GRANT SELECT บนตารางเดียว ----------
GRANT SELECT ON Production.Product TO DemoSalesClerk;
GO

EXECUTE AS USER = 'DemoSalesClerk';
SELECT TOP 1 Name FROM Production.Product;      -- ทำงานได้
SELECT TOP 1 LocationID FROM Production.ProductInventory;  -- ยัง error 229 (ตารางอื่น)
REVERT;
GO

-- ---------- ขั้น 3: ดูสิทธิ์ที่มีจริง (effective permissions) ----------
EXECUTE AS USER = 'DemoSalesClerk';
SELECT * FROM sys.fn_my_permissions('Production.Product', 'OBJECT');
REVERT;
GO

-- ---------- ขั้น 4: DENY ชนะ GRANT ----------
-- สมมติ user ได้สิทธิ์ผ่าน role และเราต้องการบล็อกรายบุคคล
CREATE ROLE DemoReaders;
ALTER ROLE DemoReaders ADD MEMBER DemoSalesClerk;
GRANT SELECT ON Production.Product TO DemoReaders;
GO

EXECUTE AS USER = 'DemoSalesClerk';
SELECT TOP 1 Name FROM Production.Product;   -- OK จาก role
REVERT;
GO

DENY SELECT ON Production.Product TO DemoSalesClerk;
GO

EXECUTE AS USER = 'DemoSalesClerk';
SELECT TOP 1 Name FROM Production.Product;   -- error 229 — DENY ชนะ role grant
REVERT;
GO

-- ---------- ขั้น 5: REVOKE เรียกคืน DENY (กลับสู่สถานะ neutral) ----------
REVOKE SELECT ON Production.Product FROM DemoSalesClerk;
GO

EXECUTE AS USER = 'DemoSalesClerk';
SELECT TOP 1 Name FROM Production.Product;   -- OK อีกครั้ง เพราะยังได้จาก role
REVERT;
GO

-- ---------- ขั้น 6: สำรวจ permissions ที่ระบบมีให้ (fn_builtin_permissions) ----------
SELECT class_desc, permission_name, covering_permission_name
FROM sys.fn_builtin_permissions('OBJECT')
WHERE permission_name IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CONTROL')
ORDER BY permission_name;
GO

-- ---------- Cleanup ----------
REVOKE SELECT ON Production.Product FROM DemoReaders;
ALTER ROLE DemoReaders DROP MEMBER DemoSalesClerk;
DROP ROLE DemoReaders;
DROP USER DemoSalesClerk;
GO
USE master;
GO
DROP LOGIN DemoSalesClerk;
GO
-- จบสคริปต์ — ระบบกลับสู่สถานะเริ่มต้น
