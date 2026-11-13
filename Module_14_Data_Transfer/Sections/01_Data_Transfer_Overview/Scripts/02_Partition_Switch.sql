-- ============================================================================
-- Module 14 - Section 1 - Script 02: Partition switching (ALTER TABLE ... SWITCH)
-- ปรับจาก: Microsoft 20764D Mod15 "Demo 02 - partition switch.sql"
-- รันได้บน: SQL Server 2019+ บน AdventureWorks2025 (schema Lab)
-- สิ่งที่สาธิต:
--   A) สลับ partition หนึ่งของตาราง partitioned กับ staging table
--   B) สลับข้อมูลทั้งตารางระหว่างตารางธรรมดา (รูปแบบ load/swap คลาสสิก)
--   C) Cleanup ในตัวไฟล์
-- ============================================================================
USE AdventureWorks2025;
GO

IF SCHEMA_ID('Lab') IS NULL
    EXEC('CREATE SCHEMA Lab;');
GO

-- ----------------------------------------------------------------------------
-- Task A1: สร้าง partition function + scheme (idempotent)
-- หมายเหตุ: partition function/scheme เป็น object ระดับ database (ไม่มี schema)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.RegionScores;
DROP TABLE IF EXISTS Lab.RegionScoresStaging;

IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_lab_regions')
    DROP PARTITION SCHEME ps_lab_regions;

IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_lab_regions')
    DROP PARTITION FUNCTION pf_lab_regions;
GO

-- RANGE LEFT: ค่า 100/200/300 อยู่ใน partition ซ้าย
-- Partition 1: <=100, 2: 101-200, 3: 201-300, 4: >300
CREATE PARTITION FUNCTION pf_lab_regions (int)
    AS RANGE LEFT FOR VALUES (100, 200, 300);
GO

CREATE PARTITION SCHEME ps_lab_regions
    AS PARTITION pf_lab_regions ALL TO ([PRIMARY]);
GO

CREATE TABLE Lab.RegionScores
(
    region_code int          NOT NULL CONSTRAINT PK_RegionScores PRIMARY KEY,
    score_date  date         NOT NULL,
    score       smallint     NOT NULL
)
ON ps_lab_regions (region_code);
GO

-- ดูการกระจาย partition ของตาราง (ยังว่างทั้ง 4 ช่อง)
SELECT p.partition_number,
       p.rows,
       CASE WHEN p.partition_number = 1 THEN N'<= 100'
            WHEN p.partition_number = 2 THEN N'101-200'
            WHEN p.partition_number = 3 THEN N'201-300'
            ELSE N'> 300' END AS RangeLabel
FROM sys.partitions AS p
WHERE p.object_id = OBJECT_ID('Lab.RegionScores')
  AND p.index_id IN (0, 1)
ORDER BY p.partition_number;
GO

-- ----------------------------------------------------------------------------
-- Task A2: สร้าง staging table โครงเหมือนต้นฉบับ + CHECK constraint กันเขต
-- (CHECK ที่ trusted ช่วยให้ engine ยืนยันได้ว่าข้อมูลอยู่ในขอบเขต partition 1)
-- ----------------------------------------------------------------------------
CREATE TABLE Lab.RegionScoresStaging
(
    region_code int          NOT NULL CONSTRAINT PK_RegionScoresStaging PRIMARY KEY,
    score_date  date         NOT NULL,
    score       smallint     NOT NULL
);
GO

ALTER TABLE Lab.RegionScoresStaging
    ADD CONSTRAINT ck_staging_region_le_100 CHECK (region_code <= 100);
GO

INSERT Lab.RegionScoresStaging (region_code, score_date, score)
VALUES (10, '2026-03-01', 50),
       (20, '2026-03-02', 51),
       (30, '2026-03-03', 52);
GO

-- ----------------------------------------------------------------------------
-- Task A3: SWITCH — สลับทั้งก้อนแบบ metadata-only (เร็วระดับมิลลิวินาที)
-- ----------------------------------------------------------------------------
ALTER TABLE Lab.RegionScoresStaging
    SWITCH TO Lab.RegionScores PARTITION 1;
GO

-- Staging ว่างเปล่าทันที
SELECT N'Staging (ควร 0 แถว)' AS TableName, COUNT(*) AS RowsNow
FROM Lab.RegionScoresStaging
UNION ALL
SELECT N'RegionScores partition 1 (ควร 3 แถว)', COUNT(*)
FROM Lab.RegionScores WHERE region_code <= 100;
GO

-- ----------------------------------------------------------------------------
-- Task B: สลับทั้งตารางระหว่างตารางธรรมดาสามใบ (รูปแบบ "load/swap")
--   ShippingRate        = ตารางจริงที่แอปอ่าน
--   ShippingRateStaging = ที่โหลดไฟล์ใหม่เข้าไปนอกระบบ
--   ShippingRateWork    = "ที่ว่าง" รองรับข้อมูลเดิมที่สลับออก
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.ShippingRate;
DROP TABLE IF EXISTS Lab.ShippingRateStaging;
DROP TABLE IF EXISTS Lab.ShippingRateWork;
GO

CREATE TABLE Lab.ShippingRate
       (RateId int PRIMARY KEY, RateCode varchar(10) NOT NULL, RatePerKilo decimal(10,2) NOT NULL);
CREATE TABLE Lab.ShippingRateStaging
       (RateId int PRIMARY KEY, RateCode varchar(10) NOT NULL, RatePerKilo decimal(10,2) NOT NULL);
CREATE TABLE Lab.ShippingRateWork
       (RateId int PRIMARY KEY, RateCode varchar(10) NOT NULL, RatePerKilo decimal(10,2) NOT NULL);
GO

INSERT Lab.ShippingRate (RateId, RateCode, RatePerKilo)
VALUES (1, 'A1', 0.98), (2, 'A2', 1.23), (3, 'B1', 2.34);

-- "ผลโหลดไฟล์ใหม่" เข้า staging
INSERT Lab.ShippingRateStaging (RateId, RateCode, RatePerKilo)
VALUES (1, 'X1', 5.43), (2, 'Y2', 4.32), (3, 'Z1', 3.21);
GO

-- สลับสองจังหวะ: เดิมออกไป Work, ใหม่เข้าตารางจริง
ALTER TABLE Lab.ShippingRate        SWITCH TO Lab.ShippingRateWork;
ALTER TABLE Lab.ShippingRateStaging SWITCH TO Lab.ShippingRate;
GO

SELECT N'ShippingRate (ควรเป็นข้อมูลใหม่)' AS CheckPoint, * FROM Lab.ShippingRate;
SELECT N'ShippingRateWork (ข้อมูลเดิม)'    AS CheckPoint, * FROM Lab.ShippingRateWork;
GO

-- ----------------------------------------------------------------------------
-- Cleanup: ลบทุกอย่างที่สร้าง (รันเมื่อจบการทดลอง — ในตัวไฟล์ตามข้อตกลงโมดูล)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.ShippingRate;
DROP TABLE IF EXISTS Lab.ShippingRateStaging;
DROP TABLE IF EXISTS Lab.ShippingRateWork;
DROP TABLE IF EXISTS Lab.RegionScores;
DROP TABLE IF EXISTS Lab.RegionScoresStaging;

IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_lab_regions')
    DROP PARTITION SCHEME ps_lab_regions;

IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_lab_regions')
    DROP PARTITION FUNCTION pf_lab_regions;
GO
