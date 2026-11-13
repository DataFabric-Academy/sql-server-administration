-- ============================================================================
-- Section 01 — Demo 04: SQL Trace ถูก deprecated — ทางใหม่คือ Extended Events
-- ฐานข้อมูล: master + AdventureWorks2025
-- สคริปต์นี้: (1) แสดง deprecated features ของ trace ที่ห้ามเริ่มงานใหม่ด้วย
--            (2) สาธิต XE session จับ failed login (แทน Trace "Login Audit")
--            (3) อ่านผลและ cleanup
-- ============================================================================
USE master;
GO

-- ---------- ขั้น 1: ตรวจ deprecated features ที่ instance ใช้อยู่ ----------
-- SQL Trace procs (sp_trace_*) อยู่ในรายการ deprecated — ถ้า instance มี trace
-- เก่ารันอยู่ จะเห็นค่า usage > 0 และต้องวางแผนย้ายไป XE
SELECT instance_name, cntr_value AS usage_count
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Deprecated Features%'
  AND instance_name IN ('SQL Trace', 'sp_trace_create', 'SQL Server Profiler')
ORDER BY instance_name;
GO

-- ---------- ขั้น 2: เตรียม path สำหรับไฟล์ .xel ----------
-- แก้ path ตามเครื่องของคุณ (SQL Server service account ต้องเขียนได้)
-- ตัวอย่างใช้ C:\XELogs\ — สร้างโฟลเดอร์ก่อนรัน
-- บน Linux: /var/opt/mssql/xelogs (ให้ mssql เป็นเจ้าของ)

-- ---------- ขั้น 3: สร้าง XE session จับ failed login ----------
-- ทดแทน SQL Trace แบบคลาสสิก "Login Audit" ที่เคยใช้ event 14 (Audit Login Failed)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'Lab_FailedLogins')
    DROP EVENT SESSION Lab_FailedLogins ON SERVER;
GO
CREATE EVENT SESSION Lab_FailedLogins ON SERVER
ADD EVENT sqlserver.error_reported
(
    -- เก็บฟิลด์ที่ต้องการเทียบกับ trace columns เดิม
    ACTION (sqlserver.client_hostname, sqlserver.username, sqlserver.session_id)
    WHERE severity = 14                            -- login failed = severity 14
      AND error_number = 18456                     -- "Login failed for user"
)
ADD TARGET package0.event_file
(
    SET filename = N'C:\XELogs\Lab_FailedLogins.xel',
        max_file_size = 10,                      -- MB ต่อไฟล์
        max_rollover_files = 5                   -- หมุนวนได้สูงสุด 5 ไฟล์
)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS)
GO
-- หมายเหตุ: SQL Server 2025 มี "time-bound XE sessions" — option ให้ session
-- หยุดเองเมื่อหมดเวลา ใช้กัน session ถูกลืมไว้ค้าง; อ่านรายละเอียดในเอกสาร
-- Extended Events sessions

ALTER EVENT SESSION Lab_FailedLogins ON SERVER
    STATE = START;
GO

-- ---------- ขั้น 4: สร้างเหตุการณ์ failed login ----------
-- ลอง login ผิดพาสเวิร์ด (จาก sqlcmd หรือ SSMS ด้วย password ผิด)
-- ตัวอย่าง command line:
--   sqlcmd -S localhost -U Lab03WebApp -P WrongPassword
-- (Lab03WebApp เป็น login จาก Module 03 lab — ถ้าไม่มีให้ใช้ login ใด ๆ ที่มีอยู่)

-- ---------- ขั้น 5: อ่านผลจากไฟล์ .xel ----------
SELECT
    event_data.value('(event/@timestamp)[1]', 'datetime2')   AS event_time,
    event_data.value('(event/data[@name="error_number"]/value)[1]', 'int') AS error_number,
    event_data.value('(event/action[@name="username"]/value)[1]', 'sysname') AS attempted_user,
    event_data.value('(event/action[@name="client_hostname"]/value)[1]', 'sysname') AS client
FROM (
    SELECT CAST(event_data AS xml) AS event_data
    FROM sys.fn_xe_file_target_read_file
         (N'C:\XELogs\Lab_FailedLogins*.xel', NULL, NULL, NULL)
) AS x
ORDER BY event_time;
GO
-- คาดหวัง: แถวจากการล็อกอินที่ล้มเหลว (error 18456) พร้อม user/client

-- ---------- ขั้น 6: อ่าน session ในตัว system_health เมื่อเกิดปัญหา ----------
-- (ไม่ต้องสร้าง — SQL Server มีให้แล้ว ดู error รุนแรง/deadlock จาก ring buffer)
SELECT CAST(target_data AS xml).value(
    'count(/RingBufferTarget/event)', 'int') AS system_health_events
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
WHERE s.name = 'system_health' AND t.target_name = 'ring_buffer';
GO

-- ---------- Cleanup ----------
ALTER EVENT SESSION Lab_FailedLogins ON SERVER STATE = STOP;
DROP EVENT SESSION Lab_FailedLogins ON SERVER;
GO
-- ไฟล์ .xel ต้องลบเองในระบบไฟล์ถ้าต้องการ
-- จบสคริปต์
