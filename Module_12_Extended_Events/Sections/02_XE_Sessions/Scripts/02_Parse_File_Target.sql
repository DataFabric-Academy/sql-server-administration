-- =============================================================================
-- 02_Parse_File_Target.sql - อ่านผลจาก event_file (.xel) ด้วย sys.fn_xe_file_target_read_file
-- แล้ว shred XML เป็นตารางที่อ่านได้ (ทักษะหลักของการใช้ XE จริง)
-- ข้อกำหนด: มีไฟล์จาก 01_Long_Query_Session.sql (C:\SQLBackups\XE\LongQueries*.xel)
-- แก้ path ในพารามิเตอร์ของ fn_xe_file_target_read_file ให้ตรงเครื่องคุณ
-- หมายเหตุ: สำหรับไฟล์ .trc ของ SQL Trace เก่าใช้ sys.fn_trace_gettable - ซึ่ง DEPRECATED
--           ให้แปลง workflow ทั้งหมดมาที่ .xel + fn_xe_file_target_read_file
-- =============================================================================

USE master;
GO

-- Task 1: ดูไฟล์ดิบ (แต่ละแถว = event หนึ่งเป็น XML + ที่มาของไฟล์)
SELECT CAST(event_data AS XML) AS event_data_xml,
       file_name,
       file_offset
FROM sys.fn_xe_file_target_read_file(
         N'C:\SQLBackups\XE\LongQueries*.xel',   -- wildcard หมุนอ่านทุก rollover file
         NULL, NULL, NULL);
GO

-- Task 2: shred เป็นตารางที่วิเคราะห์ได้
WITH raw AS (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file(
             N'C:\SQLBackups\XE\LongQueries*.xel', NULL, NULL, NULL)
)
SELECT c.value('(@name)[1]', 'nvarchar(60)')                          AS event_name,
       c.value('(@timestamp)[1]', 'datetime2(3)')                     AS event_time,
       c.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0  AS duration_ms,
       c.value('(data[@name="cpu_time"]/value)[1]', 'bigint') / 1000.0  AS cpu_ms,
       c.value('(data[@name="logical_reads"]/value)[1]', 'bigint')    AS logical_reads,
       c.value('(action[@name="session_id"]/value)[1]', 'int')        AS session_id,
       c.value('(action[@name="client_hostname"]/value)[1]', 'nvarchar(60)') AS client_hostname,
       c.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM raw
CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
ORDER BY duration_ms DESC;
GO

-- อ่านโครง query:
--   @name / @timestamp      = attribute บน element <event>
--   data[@name="..."]/value  = event field (duration, cpu_time, logical_reads)
--   action[@name="..."]/value = action ที่ session เพิ่ม (sql_text, session_id, ...)
--   CROSS APPLY ...nodes('/event') = คลาย XML หนึ่งแถวต่อ event หนึ่งตัว

-- Task 3: สรุปแบบ "รายงาน" - top statement ที่กินเวลามากสุดรวมกัน
WITH raw AS (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file(
             N'C:\SQLBackups\XE\LongQueries*.xel', NULL, NULL, NULL)
), events AS (
    SELECT c.value('(@timestamp)[1]', 'datetime2(3)')                     AS event_time,
           c.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0 AS duration_ms,
           c.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
    FROM raw
    CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
)
SELECT TOP (10)
       LEFT(REPLACE(REPLACE(sql_text, CHAR(13), ' '), CHAR(10), ' '), 80) AS StatementHead,
       COUNT(*)           AS Occurrences,
       MAX(duration_ms)   AS MaxDurationMs,
       SUM(duration_ms)   AS TotalDurationMs
FROM events
GROUP BY LEFT(REPLACE(REPLACE(sql_text, CHAR(13), ' '), CHAR(10), ' '), 80)
ORDER BY TotalDurationMs DESC;
GO

-- Task 4: เทียบผ่าน PowerShell (ทางเลือกนอก SQL Server)
-- cmdlet Read-SqlXEvent ของ SqlServer module อ่านไฟล์ .xel ได้โดยตรง:
--   Read-SqlXEvent -FileName C:\SQLBackups\XE\LongQueries.xel |
--       Select-Object -First 5 name, timestamp
-- เหมาะกับงานประมวลผล/เก็บประวัติฝั่ง client (ดู Module 11)

-- Task 5: ทดลองเอง
-- 1) อ่านเฉพาะไฟล์รอบใหม่: รัน 01 ซ้ำจนมี LongQueries_0_*.xel แล้วสังเกต file_name ต่างกัน
-- 2) เพิ่มคอลัมน์ database_id: c.value('(data[@name="database_id"]/value)[1]', 'int')
-- 3) อ่านไฟล์ system_health: FROM sys.fn_xe_file_target_read_file('system_health*.xel', ...)
--    (relative path resolve ที่โฟลเดอร์ LOG ของ instance - เจาะต่อใน Script 04)
