-- =============================================================================
-- 05_Page_Splits_Histogram.sql - ตาม mid-page splits ด้วย event transaction_log
-- + histogram target นับต่อ alloc_unit_id แล้วเชื่อมกลับเป็นชื่อ index
-- เหตุที่ใช้ transaction_log: ไม่มี event "page_splits" ใน XE - split แบบกลาง page
--   ปรากฏใน log เป็น operation = 'LOP_DELETE_SPLIT' (แถวถูกย้ายออกจาก page เดิม)
--   split ท้าย page (append-only) ไม่ก่อ fragmentation จึงไม่สนใจ
-- ปรับจาก Old/Labfiles/Lab12/Solution/.../Exercise 02 - page splits.sql (20764D)
--   (เดิมใช้ database AdventureWorks/ADVENTUREWORKS domain -> AdventureWorks2025)
-- =============================================================================

USE master;
GO

-- Task 1: สร้าง session (histogram นับ count ต่อ alloc_unit_id โดยไม่เก็บ event เต็ม)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'TrackPageSplits')
    DROP EVENT SESSION [TrackPageSplits] ON SERVER;
GO

CREATE EVENT SESSION [TrackPageSplits] ON SERVER
ADD EVENT sqlserver.transaction_log (
    WHERE operation        = N'LOP_DELETE_SPLIT'          -- mid-page split
      AND sqlserver.database_name = N'AdventureWorks2025' -- กรองที่ predicate เลย - เบา
)
ADD TARGET package0.histogram (
    SET filtering_event_name = N'sqlserver.transaction_log',
        source               = N'alloc_unit_id',         -- field ของ event
        source_type          = 0,                        -- 0 = event field (1 = action)
        slots                = 64                        -- จำนวนช่องนับ
)
WITH ( MAX_MEMORY           = 4 MB,
       EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
       MAX_DISPATCH_LATENCY = 10 SECONDS,
       STARTUP_STATE        = OFF );
GO

-- Task 2: เตรียมตารางทดลองที่ก่อ mid-split ง่าย (random key)
USE AdventureWorks2025;
GO
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
GO
IF OBJECT_ID('Lab.SplitDemo', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.SplitDemo
    (
        SplitId  int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_SplitDemo PRIMARY KEY,
        RandomKey int              NOT NULL,
        Payload  nvarchar(200)     NOT NULL CONSTRAINT DF_SplitDemo_Payload DEFAULT REPLICATE(N'x', 120)
    );
    -- index แคบที่รับ key สุ่ม - แถวใหม่ตกกลาง page ที่เต็ม -> mid-split
    CREATE NONCLUSTERED INDEX IX_SplitDemo_RandomKey ON Lab.SplitDemo (RandomKey);
END
GO

-- Task 3: เริ่ม session แล้วยิง workload (แทรก key สุ่ม 5,000 แถว)
ALTER EVENT SESSION [TrackPageSplits] ON SERVER
STATE = START;
GO

INSERT Lab.SplitDemo (RandomKey)
SELECT CAST(RAND(CHECKSUM(NEWID())) * 100000 AS int)
FROM sys.all_columns AS c1
CROSS JOIN (SELECT TOP (50) 1 AS x FROM sys.all_columns) AS c2;
GO

-- ยิงซ้ำอีกชุดถ้า histogram ยังไม่มีข้อมูล (สัดส่วน split ขึ้นกับว่า page เต็มแค่ไหน)
INSERT Lab.SplitDemo (RandomKey)
SELECT CAST(RAND(CHECKSUM(NEWID())) * 100000 AS int)
FROM sys.all_columns AS c1
CROSS JOIN (SELECT TOP (50) 1 AS x FROM sys.all_columns) AS c2;
GO

-- Task 4: อ่าน histogram (รอ dispatch ก่อน - MAX_DISPATCH_LATENCY = 10 วินาที)
SELECT CAST(xt.target_data AS XML) AS histogram_xml
FROM sys.dm_xe_session_targets AS xt
JOIN sys.dm_xe_sessions AS s ON s.address = xt.event_session_address
WHERE s.name = N'TrackPageSplits'
  AND xt.target_name = 'histogram';
GO

-- Task 5: shred histogram -> alloc_unit_id + count
WITH hist AS (
    SELECT CAST(xt.target_data AS XML) AS histogram_xml
    FROM sys.dm_xe_session_targets AS xt
    JOIN sys.dm_xe_sessions AS s ON s.address = xt.event_session_address
    WHERE s.name = N'TrackPageSplits'
      AND xt.target_name = 'histogram'
)
SELECT h.slot.value('(value)[1]', 'bigint')     AS alloc_unit_id,
       h.slot.value('(@count)[1]', 'bigint')    AS split_count
FROM hist
CROSS APPLY histogram_xml.nodes('HistogramTarget/Slot') AS h(slot)
ORDER BY split_count DESC;
GO

-- Task 6: ตบแต่งเป็นรายงาน - join กลับไปหา schema.table.index
WITH hist AS (
    SELECT CAST(xt.target_data AS XML) AS histogram_xml
    FROM sys.dm_xe_session_targets AS xt
    JOIN sys.dm_xe_sessions AS s ON s.address = xt.event_session_address
    WHERE s.name = N'TrackPageSplits'
      AND xt.target_name = 'histogram'
), slots AS (
    SELECT h.slot.value('(value)[1]', 'bigint')  AS alloc_unit_id,
           h.slot.value('(@count)[1]', 'bigint') AS split_count
    FROM hist
    CROSS APPLY histogram_xml.nodes('HistogramTarget/Slot') AS h(slot)
)
SELECT OBJECT_SCHEMA_NAME(p.object_id) AS SchemaName,
       OBJECT_NAME(p.object_id)        AS TableName,
       i.name                          AS IndexName,
       SUM(s.split_count)              AS TotalSplits
FROM slots AS s
JOIN sys.allocation_units AS au ON au.allocation_unit_id = s.alloc_unit_id
JOIN sys.partitions AS p ON p.partition_id = au.container_id
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
GROUP BY OBJECT_SCHEMA_NAME(p.object_id), OBJECT_NAME(p.object_id), i.name
ORDER BY TotalSplits DESC;
GO

-- Expected: IX_SplitDemo_RandomKey ครองอันดับหนึ่ง - workload เรายิงมันโดยตรง
-- บนระบบจริง: รายงานนี้คือ "index ไหนถูกทำ split บ่อย" โดยทั่วไปมาจาก
--   random key insert/update หรือ payload ใหญ่ที่บีบแถวเพื่อนข้างหน้า (fillfactor)

-- Task 7: หยุด/ลบ session และตารางทดลอง (จบทดลอง)
ALTER EVENT SESSION [TrackPageSplits] ON SERVER
STATE = STOP;
GO

DROP EVENT SESSION [TrackPageSplits] ON SERVER;
GO

DROP TABLE IF EXISTS Lab.SplitDemo;
GO

-- ทดลองเอง
-- 1) เพิ่ม FILLFACTOR = 70 ให้ index แล้วรัน workload ซ้ำ เทียบจำนวน split
-- 2) สลับ target เป็น event_file แล้วดู event เต็มของ split (มี page_id อ่านได้)
-- 3) ร่วมกับ workload จาก 07_Workload_Generator.sql ที่ยิง split ต่อเนื่อง (##stopload)
