-- ============================================================================
-- Section 01 — Demo 03: Audit ด้วย Temporal Tables (system-versioned)
-- ฐานข้อมูล: AdventureWorks2025 — ปรับจาก demo เดิม 20764D (Manager/ManagerHistory)
-- สาธิต: ประวัติอัตโนมัติ, FOR SYSTEM_TIME, history แก้ไม่ได้, และข้อจำกัด ChangedBy
-- ============================================================================
USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Lab')
    CREATE SCHEMA Lab;
GO

-- ---------- ขั้น 1: สร้าง temporal table ----------
IF OBJECT_ID('Lab.Manager', 'U') IS NOT NULL
BEGIN
    ALTER TABLE Lab.Manager SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE Lab.Manager;
    DROP TABLE Lab.ManagerHistory;
END
GO

CREATE TABLE Lab.Manager
(
    ManagerId     int NOT NULL PRIMARY KEY,
    ManagerName   nvarchar(50) NOT NULL,
    ManagerPassword varbinary(200) NOT NULL,
    ValidFrom datetime2 GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo   datetime2 GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Lab.ManagerHistory));
GO
-- SQL Server สร้าง Lab.ManagerHistory ให้อัตโนมัติ โครงสร้างเหมือนตารางหลัก
-- โดยไม่มี PERIOD + ไม่มี PK

-- ---------- ขั้น 2: ใส่ข้อมูล + แก้ไข + ลบ ----------
INSERT INTO Lab.Manager (ManagerId, ManagerName, ManagerPassword)
VALUES (1, N'superuser',  0x3EED6B62548EC64A90E5D5D186FC9E5C),
       (2, N'PeledYael',  0x19EF561D56A24D42A54169BD3DE23652),
       (3, N'DavisSara',  0xD42025F8D7A67248AC36C5C8E955FA71);
GO

UPDATE Lab.Manager
SET ManagerPassword = 0x3EED6B62548EC64A90E5D5D186FCFFFF,
    ManagerName = N'administrator'
WHERE ManagerId = 1;
GO

DELETE FROM Lab.Manager WHERE ManagerId = 3;
GO

-- ---------- ขั้น 3: เทียบตารางปัจจุบัน vs history ----------
SELECT * FROM Lab.Manager;          -- เห็น 2 แถว (รุ่นล่าสุด)
SELECT * FROM Lab.ManagerHistory;   -- เห็น 3 แถวเก่า (รวมที่ถูก DELETE)
GO

-- ---------- ขั้น 4: query ย้อนเวลาด้วย FOR SYSTEM_TIME ----------
-- 4a) ALL — ทุกเวอร์ชันของทุกแถว
SELECT * FROM Lab.Manager FOR SYSTEM_TIME ALL ORDER BY ManagerId, ValidFrom;

-- 4b) AS OF — สถานะ ณ เวลาที่แถวแรกถูกแก้ (ดูจาก history)
DECLARE @t datetime2 =
    (SELECT TOP (1) ValidFrom FROM Lab.ManagerHistory WHERE ManagerId = 1
     ORDER BY ValidFrom DESC);
SELECT * FROM Lab.Manager FOR SYSTEM_TIME AS OF @t;
GO
-- คาดหวัง: เห็น ManagerId=1 ด้วยค่าเดิม 'superuser' ก่อนถูกแก้

-- ---------- ขั้น 5: history table แก้ไม่ได้ (กัน audit โดนล้าง) ----------
UPDATE Lab.ManagerHistory SET ManagerName = N'hacked';   -- error 13565
INSERT INTO Lab.ManagerHistory (ManagerId, ManagerName, ManagerPassword)
VALUES (99, N'forged', 0x00);                            -- error 13565
GO

-- ---------- ขั้น 6: ข้อจำกัด — temporal table ไม่บอก "ใครแก้" ----------
-- เพิ่มคอลัมน์ ChangedBy เอง (DEFAULT SUSER_SNAME()) ได้ แต่มันเป็นคอลัมน์ธรรมดา:
ALTER TABLE Lab.Manager
ADD ChangedBy sysname NOT NULL CONSTRAINT DF_Manager_ChangedBy DEFAULT (SUSER_SNAME());
GO

UPDATE Lab.Manager SET ManagerName = N'goodChange' WHERE ManagerId = 1;
-- user ที่สิทธิ์พอสามารถ "ปลอม" ค่า ChangedBy ได้โดยระบุชัด:
UPDATE Lab.Manager
SET ManagerName = N'hacked', ChangedBy = N'notMe'
WHERE ManagerId = 1;
GO

SELECT ManagerId, ManagerName, ChangedBy FROM Lab.Manager;
GO
-- สังเกต: ChangedBy ในแถวสุดท้ายเป็น 'notMe' — เหตุผลที่ audit "จริงจัง" ต้องใช้
-- SQL Server Audit (Section 2) หรือ Ledger ที่คุมด้วย cryptographic digest

-- ---------- Cleanup ----------
ALTER TABLE Lab.Manager SET (SYSTEM_VERSIONING = OFF);
DROP TABLE Lab.Manager;
DROP TABLE Lab.ManagerHistory;
GO
-- จบสคริปต์
