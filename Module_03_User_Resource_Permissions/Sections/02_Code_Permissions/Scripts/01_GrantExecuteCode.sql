-- ============================================================================
-- Section 02 — Demo 01: สิทธิ์บนโค้ด (GRANT EXECUTE)
-- ฐานข้อมูล: AdventureWorks2025
-- ใช้ proc/function มาตรฐานของ AdventureWorks2025:
--   dbo.uspGetManagerEmployees (stored procedure)
--   dbo.ufnGetStock (scalar UDF)
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoCodeUser')
    DROP LOGIN DemoCodeUser;
GO
CREATE LOGIN DemoCodeUser WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoCodeUser')
    DROP USER DemoCodeUser;
GO
CREATE USER DemoCodeUser FOR LOGIN DemoCodeUser;
GO

-- ---------- ขั้น 1: ก่อนมอบสิทธิ์ — เรียก proc ไม่ได้ ----------
EXECUTE AS USER = 'DemoCodeUser';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 2;
-- error 229: The EXECUTE permission was denied on the object 'uspGetManagerEmployees'
REVERT;
GO

-- ---------- ขั้น 2: GRANT EXECUTE บน proc ----------
GRANT EXECUTE ON dbo.uspGetManagerEmployees TO DemoCodeUser;
GO

EXECUTE AS USER = 'DemoCodeUser';
EXEC dbo.uspGetManagerEmployees @BusinessEntityID = 1;   -- ทำงานได้
-- สังเกต: DemoCodeUser ไม่มีสิทธิ์ SELECT บนตารางใด ๆ เลย
-- (ownership chaining ข้ามการตรวจสิทธิ์ของ statement ภายใน proc)
REVERT;
GO

-- ยืนยันว่า user ยังอ่านตารางโดยตรงไม่ได้
EXECUTE AS USER = 'DemoCodeUser';
SELECT TOP 1 * FROM HumanResources.Employee;   -- error 229
REVERT;
GO

-- ---------- ขั้น 3: scalar UDF ใช้สิทธิ์ EXECUTE (ไม่ใช่ SELECT) ----------
EXECUTE AS USER = 'DemoCodeUser';
SELECT dbo.ufnGetStock(1);
-- error 229: The EXECUTE permission was denied on the object 'ufnGetStock'
REVERT;
GO

-- ---------- ขั้น 4: มอบให้ public (ทุก user ใน database) ----------
-- เหมาะกับ generic function ที่ไม่เผยข้อมูลอ่อนไหว
GRANT EXECUTE ON dbo.ufnGetStock TO public;
GO

EXECUTE AS USER = 'DemoCodeUser';
SELECT dbo.ufnGetStock(1);   -- ทำงานได้แล้ว
REVERT;
GO

-- ---------- ขั้น 5: ตรวจสิทธิ์ EXECUTE ที่ user มี ----------
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       OBJECT_NAME(pe.major_id) AS code_object
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 1
  AND OBJECT_NAME(pe.major_id) IN ('uspGetManagerEmployees', 'ufnGetStock')
ORDER BY pr.name;
GO

-- ---------- Cleanup ----------
REVOKE EXECUTE ON dbo.uspGetManagerEmployees FROM DemoCodeUser;
REVOKE EXECUTE ON dbo.ufnGetStock FROM public;
DROP USER DemoCodeUser;
GO
USE master;
GO
DROP LOGIN DemoCodeUser;
GO
-- จบสคริปต์
