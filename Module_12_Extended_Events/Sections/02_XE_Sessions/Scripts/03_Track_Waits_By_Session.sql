-- =============================================================================
-- 03_Track_Waits_By_Session.sql - ตาม wait ทีละเหตุการณ์ด้วย sqlserver.wait_info
-- แล้ว aggregate "ใครรออะไรนานแค่ไหน" ต่อ session (แตกต่างจาก sys.dm_os_wait_stats
--   ซึ่งเป็นค่าสะสมทั้ง instance ตั้งแต่ restart - ดู Module 13)
-- ปรับจาก Old/Demofiles/Mod12/Demo/Demo 2 - track waits by session.sql
--   (เดิมกรอง login ADVENTUREWORKS\Student ที่พึ่ง AD -> ตัดออก, เก็บลง event_file)
-- ร่วมกับ workload: 07_Workload_Generator.sql (รันไปพร้อมกันเพื่อให้มี wait ให้จับ)
-- =============================================================================

USE master;
GO

-- Task 1: สร้าง session (wait_info เกิดถี่ - ตั้ง predicate ตัด wait สั้นทิ้ง)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'WaitsBySession')
    DROP EVENT SESSION [WaitsBySession] ON SERVER;
GO

CREATE EVENT SESSION [WaitsBySession] ON SERVER
ADD EVENT sqlserver.wait_info (
    ACTION ( sqlserver.sql_text, sqlserver.session_id )
    WHERE duration > 10000                  -- เก็บเฉพาะ wait นานกว่า 10 มิลลิวินาที
)
ADD TARGET package0.event_file (
    SET filename           = N'C:\SQLBackups\XE\WaitsBySession.xel',
        max_file_size      = 10,
        max_rollover_files = 5
)
WITH ( MAX_MEMORY           = 8 MB,        -- wait_info เกิดถี่ ให้ buffer เผื่อ
       EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
       MAX_DISPATCH_LATENCY = 10 SECONDS,
       TRACK_CAUSALITY      = OFF,
       STARTUP_STATE        = OFF );
GO

-- Task 2: เริ่ม session
ALTER EVENT SESSION [WaitsBySession] ON SERVER
STATE = START;
GO

-- Task 3: รัน workload เพื่อให้เกิด wait
-- รันสคริปต์ 07_Workload_Generator.sql จากหน้าต่างใหม่ (วน query หนัก + insert สุ่ม)
-- ระหว่างรอ workload วิ่ง 60-120 วินาที ให้มาทำ Task 4-6 นี้
-- หยุด workload: CREATE TABLE ##stopload (id int); จากหน้าต่างใหม่

WAITFOR DELAY '00:01:00';   -- ให้ workload เก็บ wait เข้าไฟล์ 1 นาที
GO

-- Task 4: aggregate ต่อ session + wait type (จาก event_file)
WITH raw AS (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file(
             N'C:\SQLBackups\XE\WaitsBySession*.xel', NULL, NULL, NULL)
)
SELECT
       c.value('(action[@name="session_id"]/value)[1]', 'int')          AS session_id,
       c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(60)')     AS wait_type,
       COUNT_BIG(*)                                                     AS wait_count,
       SUM(c.value('(data[@name="duration"]/value)[1]', 'bigint')) / 1000.0
                                                                        AS total_wait_ms,
       SUM(c.value('(data[@name="signal_duration"]/value)[1]', 'bigint')) / 1000.0
                                                                        AS signal_wait_ms
FROM raw
CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
GROUP BY c.value('(action[@name="session_id"]/value)[1]', 'int'),
         c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(60)')
HAVING SUM(c.value('(data[@name="duration"]/value)[1]', 'bigint')) > 100000  -- >100 ms รวม
ORDER BY total_wait_ms DESC;
GO

-- สังเกต:
--  wait_type ดึง /text (map type) จึงอ่านเป็นชื่อ เช่น PAGEIOLATCH_SH, CXPACKET, SOS_SCHEDULER_YIELD
--  total_wait_ms - signal_wait_ms = resource wait (รอของจริง ไม่ใช่รอ scheduler)
--  session_id ของ workload ควรโผล่พร้อม wait ของมันเอง (CPU วน query หนัก -> SOS_SCHEDULER_YIELD ฯลฯ)

-- Task 5: รายงานแบบรวม (ทั้ง instance ระหว่างช่วงที่จับ) เทียบ wait stats DMV
WITH raw AS (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file(
             N'C:\SQLBackups\XE\WaitsBySession*.xel', NULL, NULL, NULL)
)
SELECT TOP (10)
       c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(60)') AS wait_type,
       COUNT_BIG(*)                                                 AS events,
       SUM(c.value('(data[@name="duration"]/value)[1]', 'bigint')) / 1000.0 AS total_ms
FROM raw
CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
GROUP BY c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(60)')
ORDER BY total_ms DESC;
GO

-- Task 6: หยุด + ลบ session (และหยุด workload ถ้ายังวนอยู่)
ALTER EVENT SESSION [WaitsBySession] ON SERVER
STATE = STOP;
GO

DROP EVENT SESSION [WaitsBySession] ON SERVER;
GO

-- หยุด workload (ถ้ายังรัน): CREATE TABLE ##stopload (id int);

-- ทดลองเอง
-- 1) ปรับ predicate เป็น duration > 100000 (100 ms) แล้วดูว่าเหลือแค่ wait หนัก ๆ
-- 2) สร้าง blocking จริง (อ้างแล็บ Module 13) แล้วหา LCK_M_S/LCK_M_X ของ session ที่ถูก block
-- 3) เขียนรายงานเทียบสองช่วงเวลา (รอบมี workload vs รอบว่าง) - นี่คือ baseline ระดับเหตุการณ์
