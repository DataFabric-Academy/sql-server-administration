-- ============================================================================
-- Section 01 — Demo 02: Column-Level Permissions
-- ฐานข้อมูล: AdventureWorks2025
-- สาธิตการคุมสิทธิ์ระดับคอลัมน์ + พฤติกรรม SELECT * เมื่อไม่ครบสิทธิ์
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoClerkCol')
    DROP LOGIN DemoClerkCol;
GO
CREATE LOGIN DemoClerkCol WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoClerkCol')
    DROP USER DemoClerkCol;
GO
CREATE USER DemoClerkCol FOR LOGIN DemoClerkCol;
GO

-- ---------- ขั้น 1: GRANT SELECT เฉพาะคอลัมน์ (รูปแบบวงเล็บ) ----------
GRANT SELECT ON Production.ProductInventory (Shelf, Bin) TO DemoClerkCol;
GO

-- ---------- ขั้น 2: ทดสอบจากมุมมอง user ----------
EXECUTE AS USER = 'DemoClerkCol';

-- 2a) อ่านเฉพาะคอลัมน์ที่ได้สิทธิ์ → ทำงานได้ (DISTINCT กันค่าซ้ำรกจอ)
SELECT DISTINCT Shelf, Bin FROM Production.ProductInventory;

-- 2b) SELECT * → error ทีละคอลัมน์ที่ไม่มีสิทธิ์
--     (ข้อความแจ้งชื่อคอลัมน์ที่ห้ามอ่าน — ระวังข้อมูลรั่วผ่าน error)
SELECT * FROM Production.ProductInventory;

REVERT;
GO

-- ---------- ขั้น 3: เพิ่มคอลัมน์ในสิทธิ์เดิม (GRANT ซ้ำเป็นการขยายคอลัมน์) ----------
GRANT SELECT ON Production.ProductInventory (Quantity) TO DemoClerkCol;
GO

EXECUTE AS USER = 'DemoClerkCol';
SELECT DISTINCT Shelf, Bin, Quantity FROM Production.ProductInventory;
REVERT;
GO

-- ---------- ขั้น 4: DENY ระดับคอลัมน์ — ห้ามเห็นจำนวนคงเหลือ ----------
DENY SELECT ON OBJECT::Production.ProductInventory (Quantity) TO DemoClerkCol;
GO

EXECUTE AS USER = 'DemoClerkCol';
SELECT DISTINCT Shelf, Bin FROM Production.ProductInventory;   -- OK
SELECT DISTINCT Quantity FROM Production.ProductInventory;     -- error 229
REVERT;
GO

-- ---------- ขั้น 5: ตรวจสิทธิ์ระดับคอลัมน์ใน catalog ----------
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       c.name AS column_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.columns c
    ON c.object_id = pe.major_id AND c.column_id = pe.minor_id
WHERE pe.class = 1  -- OBJECT
  AND pe.major_id = OBJECT_ID('Production.ProductInventory')
  AND pr.name = 'DemoClerkCol';
GO

-- ---------- Cleanup ----------
REVOKE SELECT ON Production.ProductInventory (Shelf, Bin) FROM DemoClerkCol;
REVOKE SELECT ON Production.ProductInventory (Quantity) FROM DemoClerkCol;
DROP USER DemoClerkCol;
GO
USE master;
GO
DROP LOGIN DemoClerkCol;
GO
-- จบสคริปต์
