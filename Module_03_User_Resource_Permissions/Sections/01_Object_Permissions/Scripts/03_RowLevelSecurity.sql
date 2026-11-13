-- ============================================================================
-- Section 01 — Demo 03: Row-Level Security (RLS)
-- ฐานข้อมูล: AdventureWorks2025
-- สาธิต FILTER PREDICATE + BLOCK PREDICATE แบบครบวงจร (idempotent, มี cleanup)
-- รูปแบบอ้างอิงจาก Microsoft Learn — Row-Level Security (example A/C)
-- ============================================================================
USE AdventureWorks2025;
GO

-- ---------- เตรียม schema Security (best practice: แยกวัตถุความปลอดภัย) ----------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Security')
    CREATE SCHEMA Security;
GO

-- ---------- เตรียม user สาธิต (WITHOUT LOGIN — ไม่ต้องมี login จริง) ----------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoRep1')
    DROP USER DemoRep1;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoRep2')
    DROP USER DemoRep2;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoManager')
    DROP USER DemoManager;
GO
CREATE USER DemoRep1 WITHOUT LOGIN;
CREATE USER DemoRep2 WITHOUT LOGIN;
CREATE USER DemoManager WITHOUT LOGIN;
GO

-- ---------- เตรียมตารางทดสอบ ----------
IF OBJECT_ID('Sales.OrdersRepDemo', 'U') IS NOT NULL
    DROP TABLE Sales.OrdersRepDemo;
GO
CREATE TABLE Sales.OrdersRepDemo
(
    OrderId  int NOT NULL PRIMARY KEY,
    SalesRep sysname NOT NULL,
    Product  nvarchar(50) NOT NULL,
    Qty      int NOT NULL
);
GO

INSERT INTO Sales.OrdersRepDemo VALUES
    (1, 'DemoRep1', N'Valve',   5),
    (2, 'DemoRep1', N'Wheel',   2),
    (3, 'DemoRep1', N'Valve',   4),
    (4, 'DemoRep2', N'Bracket', 2),
    (5, 'DemoRep2', N'Wheel',   5),
    (6, 'DemoRep2', N'Seat',    5);
GO

GRANT SELECT ON Sales.OrdersRepDemo TO DemoRep1, DemoRep2, DemoManager;
GO

-- ---------- ขั้น 1: สร้าง predicate function (inline TVF + SCHEMABINDING) ----------
IF OBJECT_ID('Security.fn_repFilter', 'IF') IS NOT NULL
    DROP FUNCTION Security.fn_repFilter;
GO
CREATE FUNCTION Security.fn_repFilter(@SalesRep AS sysname)
RETURNS TABLE
WITH SCHEMABINDING
AS
    RETURN SELECT 1 AS result
    WHERE @SalesRep = USER_NAME() OR USER_NAME() = 'DemoManager';
GO

-- ---------- ขั้น 2: สร้าง security policy (FILTER PREDICATE, STATE = ON) ----------
IF OBJECT_ID('DemoRepFilter', 'SSP') IS NOT NULL
    DROP SECURITY POLICY DemoRepFilter;
GO
CREATE SECURITY POLICY DemoRepFilter
ADD FILTER PREDICATE Security.fn_repFilter(SalesRep)
ON Sales.OrdersRepDemo
WITH (STATE = ON);
GO

-- ---------- ขั้น 3: ทดสอบ filter ----------
EXECUTE AS USER = 'DemoRep1';
SELECT * FROM Sales.OrdersRepDemo;   -- เห็น 3 แถวของ DemoRep1 เท่านั้น
REVERT;

EXECUTE AS USER = 'DemoRep2';
SELECT * FROM Sales.OrdersRepDemo;   -- เห็น 3 แถวของ DemoRep2 เท่านั้น
REVERT;

EXECUTE AS USER = 'DemoManager';
SELECT * FROM Sales.OrdersRepDemo;   -- เห็นทั้ง 6 แถว
REVERT;
GO

-- ---------- ขั้น 4: เพิ่ม BLOCK PREDICATE (AFTER INSERT) ----------
-- ป้องกันการ INSERT แถวของพนักงานคนอื่น — ต้อง ALTER เพิ่ม predicate
ALTER SECURITY POLICY DemoRepFilter
ADD BLOCK PREDICATE Security.fn_repFilter(SalesRep)
ON Sales.OrdersRepDemo AFTER INSERT
WITH (STATE = ON);
GO

EXECUTE AS USER = 'DemoRep1';
-- INSERT แถวของตัวเอง → ได้
INSERT INTO Sales.OrdersRepDemo VALUES (7, 'DemoRep1', N'Gasket', 1);
-- INSERT แถวของคนอื่น → error 33504 ("The attempted insert ... failed ... ")
INSERT INTO Sales.OrdersRepDemo VALUES (8, 'DemoRep2', N'Gear', 3);
REVERT;
GO

-- ---------- ขั้น 5: ปิด policy ชั่วคราว (STATE = OFF) แล้วเห็นทุกแถว ----------
ALTER SECURITY POLICY DemoRepFilter WITH (STATE = OFF);
GO

EXECUTE AS USER = 'DemoRep1';
SELECT * FROM Sales.OrdersRepDemo;   -- เห็นทุกแถว (policy ปิด)
REVERT;
GO

-- เปิดกลับเหมือนเดิม
ALTER SECURITY POLICY DemoRepFilter WITH (STATE = ON);
GO

-- ---------- ขั้น 6: ตรวจ metadata ของ policy ----------
SELECT sp.name AS policy_name, sp.is_enabled,
       spd.predicate_type, OBJECT_NAME(spd.target_object_id) AS target_table,
       OBJECT_NAME(spd.predicate_object_id) AS predicate_fn
FROM sys.security_policies sp
JOIN sys.security_predicates spd ON spd.object_id = sp.object_id;
GO

-- ---------- Cleanup ----------
DROP SECURITY POLICY DemoRepFilter;
DROP FUNCTION Security.fn_repFilter;
DROP TABLE Sales.OrdersRepDemo;
DROP USER DemoRep1;
DROP USER DemoRep2;
DROP USER DemoManager;
GO
-- schema Security ถูกใช้หลาย demo/lab ถ้าต้องการลบด้วย:
-- DROP SCHEMA Security;
-- จบสคริปต์
