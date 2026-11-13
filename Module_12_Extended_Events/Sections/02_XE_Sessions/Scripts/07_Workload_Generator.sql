-- =============================================================================
-- 07_Workload_Generator.sql - workload จำลองสำหรับแล็บ Module 12
-- ก่อทั้ง wait (query หนัก CPU/IO) และ mid-page splits (insert key สุ่ม)
-- หยุดด้วย: สร้างตาราง ##stopload จากหน้าต่างอื่น (pattern เดียวกับแล็บ Module 13)
-- ปรับจาก Old/Demofiles/Mod12/Workload/load_script1.sql (20764D)
--   (เดิมเรียก proc เฉพาะของ AdventureWorks2016 -> เขียน query ตรงบน AdventureWorks2025)
-- =============================================================================

USE AdventureWorks2025;
GO

-- Task 0: เคลียร์สัญญาณหยุดเก่า
DROP TABLE IF EXISTS ##stopload;
GO

-- Task 1: เตรียมตารางทดลอง (idempotent - เหมือน Script 05)
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
GO
IF OBJECT_ID('Lab.SplitDemo', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.SplitDemo
    (
        SplitId   int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_SplitDemo PRIMARY KEY,
        RandomKey int              NOT NULL,
        Payload   nvarchar(200)    NOT NULL CONSTRAINT DF_SplitDemo_Payload DEFAULT REPLICATE(N'x', 120)
    );
    CREATE NONCLUSTERED INDEX IX_SplitDemo_RandomKey ON Lab.SplitDemo (RandomKey);
END
GO

-- Task 2: วน workload สูงสุด 60 นาที หรือจนกว่าจะพบ ##stopload
DECLARE @start datetime2 = SYSDATETIME();

WHILE DATEDIFF(ss, @start, SYSDATETIME()) < 3600
  AND OBJECT_ID('tempdb..##stopload') IS NULL
BEGIN
    -- (ก) query รายงานหนัก CPU/IO -> ก่อ SOS_SCHEDULER_YIELD / PAGEIOLATCH_* ฯลฯ
    SELECT c.Name AS Category,
           SUM(d.OrderQty * d.UnitPrice) AS Revenue,
           COUNT_BIG(*)                  AS LineItems
    FROM Sales.SalesOrderHeader AS o
    JOIN Sales.SalesOrderDetail AS d ON d.SalesOrderID = o.SalesOrderID
    JOIN Production.Product AS p ON p.ProductID = d.ProductID
    JOIN Production.ProductSubcategory AS sc ON sc.ProductSubcategoryID = p.ProductSubcategoryID
    JOIN Production.ProductCategory AS c ON c.ProductCategoryID = sc.ProductCategoryID
    GROUP BY c.Name;

    -- (ข) แทรก key สุ่ม 50 แถว -> ก่อ mid-page splits ใน IX_SplitDemo_RandomKey
    INSERT Lab.SplitDemo (RandomKey)
    SELECT CAST(RAND(CHECKSUM(NEWID())) * 100000 AS int)
    FROM sys.all_columns AS c1
    WHERE c1.column_id % 50 = 0;      -- ~100 แถวต่อรอบ (หยิบบางส่วนจาก all_columns)

    WAITFOR DELAY '00:00:01';         -- พัก 1 วินาทีต่อรอบ
END
GO

-- วิธีหยุด workload (รันจากหน้าต่าง SSMS อื่น หรือจาก PowerShell):
--   CREATE TABLE ##stopload (id int);
-- ลูปตรวจเจอแล้วจบเองภายใน 1 วินาที

-- Task 3: หลังจบ workload - ทำความสะอาด
-- DROP TABLE IF EXISTS ##stopload;         -- (ทำที่หน้าต่างอื่นก่อน)
-- DROP TABLE IF EXISTS Lab.SplitDemo;

-- ทดลองเอง
-- 1) ลด WAITFOR เป็น 00:00:00 ให้ workload หนักขึ้น แล้วดู wait_info ใน Script 03 เปลี่ยนเป็นแบบไหน
-- 2) รัน workload 2-3 connection พร้อมกัน (SSMS หลายหน้าต่าง) เพื่อให้ aggregate ต่อ session มีหลาย session_id
-- 3) ตัดส่วน (ข) ออกเพื่อแยกผล "waits ล้วน" จาก "splits" เมื่อเทียบรายงานของสอง session
