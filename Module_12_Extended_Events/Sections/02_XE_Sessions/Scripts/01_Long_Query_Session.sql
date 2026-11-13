-- =============================================================================
-- 01_Long_Query_Session.sql - สร้าง XE session จับ query ที่รันเกิน 5 วินาที
-- (event_file + ring_buffer) รันทดลอง อ่านผล แล้วทำความสะอาด
-- เตรียมก่อน: สร้างโฟลเดอร์เก็บ .xel (แก้ path ให้ตรงเครื่องคุณได้ทุกที่ที่เห็น N'C:\SQLBackups\XE\')
--   PowerShell: New-Item -Path C:\SQLBackups\XE -ItemType Directory -Force
-- ปรับจาก Old/Demofiles/Mod12/Demo/Demo 1 - create xe session.sql
--   (เดิมกรอง server_principal_name = 'ADVENTUREWORKS\Student' - เปลี่ยนเป็นกรอง
--    duration เพื่อไม่พึ่ง AD domain, และเพิ่ม event_file target)
-- =============================================================================

USE master;
GO

-- Task 1: สร้าง session (idempotent - ลบทิ้งก่อนถ้ามีอยู่)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'LongQueries')
    DROP EVENT SESSION [LongQueries] ON SERVER;
GO

CREATE EVENT SESSION [LongQueries] ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    ACTION ( sqlserver.sql_text, sqlserver.client_hostname, sqlserver.session_id )
    WHERE duration > 5000000            -- ไมโครวินาที (5,000,000 = 5 วินาที)
),
ADD EVENT sqlserver.rpc_completed (
    ACTION ( sqlserver.sql_text, sqlserver.session_id )
    WHERE duration > 5000000
)
ADD TARGET package0.event_file (
    SET filename           = N'C:\SQLBackups\XE\LongQueries.xel',
        max_file_size      = 10,        -- MB ต่อไฟล์
        max_rollover_files = 5          -- หมุนวน 5 ไฟล์ (ประมาณ 50 MB สูงสุด)
)
ADD TARGET package0.ring_buffer (
    SET max_memory = 1024               -- KB (คำแนะนำทางการ: <= 1024)
)
WITH ( MAX_MEMORY           = 4 MB,
       EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
       MAX_DISPATCH_LATENCY = 10 SECONDS,
       MAX_EVENT_SIZE       = 0 KB,
       MEMORY_PARTITION_MODE = NONE,
       TRACK_CAUSALITY      = OFF,
       STARTUP_STATE        = OFF );
GO

-- Task 2: ตรวจว่า session ถูกบันทึกใน metadata แต่ยังไม่รัน
SELECT name FROM sys.server_event_sessions WHERE name = N'LongQueries';  -- มีแถว
SELECT name FROM sys.dm_xe_sessions          WHERE name = N'LongQueries';  -- ยังไม่มีแถว (ยังไม่ START)
GO

-- Task 3: เตรียม stored proc ทดลอง (RPC) + เริ่ม session
USE AdventureWorks2025;
GO
IF OBJECT_ID('dbo.uspLongQueryDemo', 'P') IS NULL
BEGIN
    EXEC ('CREATE PROCEDURE dbo.uspLongQueryDemo AS BEGIN SET NOCOUNT ON; END');
END
GO
ALTER PROCEDURE dbo.uspLongQueryDemo
AS
BEGIN
    SET NOCOUNT ON;
    -- จำลอง proc ที่ช้า 6 วินาที (ระบบจริงจะเจอจาก query แพง/lock ฯลฯ)
    WAITFOR DELAY '00:00:06';
    SELECT COUNT(*) AS RowsScanned
    FROM Sales.SalesOrderHeader AS o
    CROSS JOIN Sales.SalesOrderDetail AS d;
END
GO

ALTER EVENT SESSION [LongQueries] ON SERVER
STATE = START;
GO

-- Task 4: ยิง workload ที่ช้าเกินเกณฑ์ (batch + RPC)
WAITFOR DELAY '00:00:06';               -- batch ทั้งก้อนกินเวลา ~6 วินาที
SELECT 'slow batch demo' AS demo;
GO

EXEC AdventureWorks2025.dbo.uspLongQueryDemo;
GO

-- Task 5: อ่านผลจาก ring_buffer (สด - อยู่ใน memory)
-- รอให้ event ถูก dispatch ไป target ก่อน (MAX_DISPATCH_LATENCY = 10 วินาที)
WITH xe AS (
    SELECT CAST(st.target_data AS XML) AS xe_data
    FROM sys.dm_xe_session_targets AS st
    JOIN sys.dm_xe_sessions AS s
      ON st.event_session_address = s.address
    WHERE s.name = N'LongQueries'
      AND st.target_name = 'ring_buffer'
)
SELECT TOP (20)
       x.xe_xml.value('(@name)[1]', 'nvarchar(60)')                AS event_name,
       x.xe_xml.value('(@timestamp)[1]', 'datetime2(3)')           AS event_time,
       x.xe_xml.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0 AS duration_ms,
       x.xe_xml.value('(data[@name="cpu_time"]/value)[1]', 'bigint') / 1000.0 AS cpu_ms,
       x.xe_xml.value('(action[@name="session_id"]/value)[1]', 'int')        AS session_id,
       x.xe_xml.value('(action[@name="client_hostname"]/value)[1]', 'nvarchar(60)') AS client_hostname,
       x.xe_xml.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM xe
CROSS APPLY xe_data.nodes('RingBufferTarget/event') AS x(xe_xml)
ORDER BY event_time;

-- สังเกต: duration เป็นไมโครวินาที -> หาร 1000 = มิลลิวินาที
-- data[@name=...] = event field, action[@name=...] = action ที่ดึงเพิ่ม

-- Task 6: ดูผลใน GUI (เสริม)
-- SSMS > Object Explorer > Management > Extended Events > Sessions > LongQueries
--   - double-click package0.ring_buffer  ดู XML ชุดเดียวกับ Task 5
--   - right-click > Watch Live Data      ดูของสด (แล้วยิง query ซ้ำเพื่อเห็นเหตุการณ์)
--   - right-click > Properties           ดู definition ครบทุกแท็บ

-- Task 7: หยุดและลบ (ตอนจบทดลองเท่านั้น)
ALTER EVENT SESSION [LongQueries] ON SERVER
STATE = STOP;
GO

DROP EVENT SESSION [LongQueries] ON SERVER;
GO

DROP PROCEDURE IF EXISTS AdventureWorks2025.dbo.uspLongQueryDemo;
GO

-- ไฟล์ .xel ยังอยู่ที่ C:\SQLBackups\XE\LongQueries*.xel
-- (อ่านต่อด้วย 02_Parse_File_Target.sql - เดโมอ่านไฟล์จาก target)

-- ทดลองเอง
-- 1) ปรับเกณฑ์เป็น 2 วินาที (2000000) แล้วยิง query ปกติดูว่ามีอะไรติด
-- 2) เพิ่ม action sqlserver.client_app_name แล้วดูว่า app ไหนยิงมา
-- 3) ตั้ง STARTUP_STATE = ON แล้ว restart SQL Server เพื่อเห็น session ฟื้นเอง
--    (ระวังบน production - อ่านหัวข้อ 7 ของ Section README ก่อน)
