-- =============================================================================
-- 04_System_Health_Deadlocks.sql - ดึง deadlock ย้อนหลังจาก session ในตัว system_health
-- system_health เปิดอัตโนมัติ (STARTUP_STATE=ON) เก็บเหตุการณ์เชิงระบบที่สำคัญ:
--   error severity >= 20, xml_deadlock_report, latch wait > 15 วินาที,
--   spinlock wait > 500 ms, และ ring buffer ของ engine ฯลฯ
-- ปรับจาก Old/Labfiles/Lab12/Solution/.../Exercise 01 - system_health.sql (20764D)
-- เอกสาร: https://learn.microsoft.com/sql/relational-databases/extended-events/use-the-system-health-session
-- =============================================================================

USE master;
GO

-- Task 1: ตรวจว่า system_health กำลังรัน และมี target อะไร
SELECT s.name, s.create_time,
       CASE WHEN s.name IN (SELECT name FROM sys.dm_xe_sessions) THEN N'RUNNING' ELSE N'STOPPED' END AS State
FROM sys.server_event_sessions AS s
WHERE s.name = 'system_health';

SELECT xt.target_name
FROM sys.dm_xe_session_targets AS xt
JOIN sys.dm_xe_sessions AS s ON s.address = xt.event_session_address
WHERE s.name = 'system_health';
-- ควรเห็น event_file (ไฟล์อยู่โฟลเดอร์ LOG ของ instance ชื่อ system_health*.xel)
GO

-- Task 2: อ่านไฟล์ system_health ย้อนหลัง (ชื่อ relative resolve ที่โฟลเดอร์ LOG)
-- ถ้าอยากใช้ path เต็ม: หาจาก
--   SELECT SERVERPROPERTY('ErrorLogFileName');   -- ...\LOG\ERRORLOG -> โฟลเดอร์ LOG เดียวกัน
SELECT TOP (50)
       x.c.value('(@name)[1]', 'nvarchar(100)')          AS event_name,
       x.c.value('(@timestamp)[1]', 'datetime2(3)')      AS event_time
FROM (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
) AS raw
CROSS APPLY raw.xe_xml.nodes('/event') AS x(c)
ORDER BY event_time DESC;
GO

-- Task 3: ดึงเฉพาะ deadlock graph (xml_deadlock_report) เรียงเวลา
-- ถ้ายังไม่เคยมี deadlock จะได้ result set ว่าง - ทำแล็บ Exercise 3 เพื่อจำลองเกิด
SELECT x.c.value('(@timestamp)[1]', 'datetime2(3)') AS event_time,
       x.c.query('.') AS deadlock_graph             -- XML ทั้งก้อน (คลิกดูใน SSMS)
FROM (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
) AS raw
CROSS APPLY raw.xe_xml.nodes('/event') AS x(c)
WHERE x.c.value('(@name)[1]', 'varchar(100)') = 'xml_deadlock_report'
ORDER BY event_time;
GO

-- Task 4: อ่าน deadlock ระดับที่ต้องการ - victim, process list, resource list
-- (เลือก event_time ล่าสุดจาก Task 3 แล้วแก้ WHERE ให้ตรง หรือใช้ TOP 1)
WITH deadlocks AS (
    SELECT TOP (1)
           x.c.value('(@timestamp)[1]', 'datetime2(3)') AS event_time,
           x.c.query('./data[@name="xml_report"]/value/deadlock') AS dl
    FROM (
        SELECT CAST(event_data AS XML) AS xe_xml
        FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
    ) AS raw
    CROSS APPLY raw.xe_xml.nodes('/event') AS x(c)
    WHERE x.c.value('(@name)[1]', 'varchar(100)') = 'xml_deadlock_report'
    ORDER BY x.c.value('(@timestamp)[1]', 'datetime2(3)') DESC
)
SELECT event_time,
       dl.value('(victim-list/victimProcess[1]/@id)[1]', 'nvarchar(20)') AS victim_id,
       dl.query('process-list') AS process_list,
       dl.query('resource-list') AS resource_list
FROM deadlocks;
GO

-- แนะนำการอ่าน XML:
--  victim-list    = process ที่ถูกเลือกเป็นเหยื่อ (rollback) - มักกินทรัพยากรน้อยกว่า
--  process-list   = ทุก process ที่เกี่ยว พร้อม query (frame), isolation level, lock mode ที่ร้องขอ
--  resource-list  = resource ที่ถือ/รอ (key/page/object) เชื่อมไปหา process ด้วย hoistid/owner

-- Task 5 (สาธิต): จำลอง deadlock เพื่อให้ system_health เก็บให้
-- สองหน้าต่าง SSMS (Session A / Session B) เทียบกับ AdventureWorks2025:
--   A: BEGIN TRAN; UPDATE Lab.DeadlockA SET Val = 1 WHERE Id = 1;
--   B: BEGIN TRAN; UPDATE Lab.DeadlockB SET Val = 1 WHERE Id = 1;
--   A: UPDATE Lab.DeadlockB SET Val = 2 WHERE Id = 1;   <- รอ B
--   B: UPDATE Lab.DeadlockA SET Val = 2 WHERE Id = 1;   <- รอ A -> DEADLOCK (error 1205)
--   แล้ว COMMIT/ROLLBACK และรัน Task 3 ซ้ำจะเห็น xml_deadlock_report ใหม่
-- (สคริปต์สร้างตาราง Lab.DeadlockA/B รวมคำเฉลยทีละ Step อยู่ใน Labs/README.md)

-- Task 6: ตรวจ error รุนแรงอื่นที่ system_health เก็บไว้ (เสริม)
WITH raw AS (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
)
SELECT TOP (20)
       c.value('(@name)[1]', 'nvarchar(100)')                                  AS event_name,
       c.value('(@timestamp)[1]', 'datetime2(3)')                              AS event_time,
       c.value('(data[@name="severity"]/value)[1]', 'int')                     AS severity,
       c.value('(data[@name="message"]/value)[1]', 'nvarchar(max)')            AS message
FROM raw
CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
WHERE c.value('(@name)[1]', 'nvarchar(100)') = 'error_reported'
  AND c.value('(data[@name="severity"]/value)[1]', 'int') >= 20
ORDER BY event_time DESC;
GO

-- ทดลองเอง
-- 1) จำลอง deadlock ตาม Task 5 แล้ววิเคราะห์ graph: ใครถือ lock อะไร ใครร้องขออะไร ทำไม victim เป็นตัวนั้น
-- 2) ตรวจ how often: สร้างรายงาน count deadlock ต่อวัน (GROUP BY CAST(event_time AS date))
-- 3) สังเกตว่า system_health ใช้ event_file rollover - ข้อมูลเก่าจะหมุนออกเอง (ไม่ใช่คลังถาวร)
