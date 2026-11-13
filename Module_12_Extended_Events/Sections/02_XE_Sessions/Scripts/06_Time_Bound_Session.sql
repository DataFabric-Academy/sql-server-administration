-- =============================================================================
-- 06_Time_Bound_Session.sql - Time-bound event sessions (SQL Server 2025+)
-- ระบุ MAX_DURATION ใน WITH(...) แล้ว session หยุดเองเมื่อครบเวลา
-- กัน "session ลืมปิด" ที่กิน resource และสร้างไฟล์ .xel ไม่รู้จบ
-- ใช้ได้: SQL Server 2025 (17.x) ขึ้นไป รวมถึง Azure SQL Database / Managed Instance
-- syntax ยืนยันจาก:
--   https://learn.microsoft.com/sql/t-sql/statements/create-event-session-transact-sql
--   https://learn.microsoft.com/sql/relational-databases/extended-events/sql-server-extended-events-sessions
-- =============================================================================

USE master;
GO

-- Task 1: สร้าง session พร้อม MAX_DURATION = 5 นาที
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'LongQueriesTimeBound')
    DROP EVENT SESSION [LongQueriesTimeBound] ON SERVER;
GO

CREATE EVENT SESSION [LongQueriesTimeBound] ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    ACTION ( sqlserver.sql_text )
    WHERE duration > 3000000            -- 3 วินาที
)
ADD TARGET package0.event_file (
    SET filename = N'C:\SQLBackups\XE\LongQueriesTimeBound.xel',
        max_file_size = 10
)
WITH ( MAX_DURATION           = 5 MINUTES,     -- <<< หยุดเองหลังเริ่ม 5 นาที (SQL Server 2025+)
       MAX_MEMORY             = 4 MB,
       EVENT_RETENTION_MODE   = ALLOW_SINGLE_EVENT_LOSS,
       MAX_DISPATCH_LATENCY   = 10 SECONDS,
       TRACK_CAUSALITY        = OFF,
       STARTUP_STATE          = OFF );
GO

-- รูปแบบค่าที่ยอมรับ: MAX_DURATION = <n> SECONDS | MINUTES | HOURS | DAYS | UNLIMITED
-- ขอบเขตสูงสุด: 24 วัน (2,147,483 วินาที); ไม่ระบุ = UNLIMITED

-- Task 2: เริ่ม session แล้วตรวจ metadata
ALTER EVENT SESSION [LongQueriesTimeBound] ON SERVER
STATE = START;
GO

-- max_duration เก็บเป็น "วินาที" (300 = 5 นาที); 0 = ไม่จำกัด
SELECT name, max_duration
FROM sys.server_event_sessions
WHERE name = N'LongQueriesTimeBound';

-- session กำลังรัน (ปรากฏใน DMV)
SELECT name FROM sys.dm_xe_sessions WHERE name = N'LongQueriesTimeBound';
GO

-- Task 3: ยิง query ที่ช้าเกินเกณฑ์ระหว่างที่ session ยังมีเวลาเหลือ
WAITFOR DELAY '00:00:04';
SELECT 'captured while session alive' AS demo;
GO

-- Task 4: หลัง 5 นาทีนับจาก STATE = START - รันซ้ำเพื่อยืนยันว่าหยุดเอง
-- (ในห้องเรียนใช้ WAITFOR รอจนครบ: รันบรรทัดถัดไปแล้วรอ ~5 นาที)
-- WAITFOR DELAY '00:05:10';

-- หลังครบเวลา: หายจาก DMV (หยุดแล้ว) แต่ยังอยู่ใน catalog (metadata คงอยู่)
SELECT name FROM sys.dm_xe_sessions         WHERE name = N'LongQueriesTimeBound';  -- ว่าง = หยุดแล้ว
SELECT name, max_duration FROM sys.server_event_sessions WHERE name = N'LongQueriesTimeBound';
GO

-- อ่านผลที่เก็บได้ก่อนหยุด
SELECT c.value('(@timestamp)[1]', 'datetime2(3)')                AS event_time,
       c.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0 AS duration_ms,
       c.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file(
             N'C:\SQLBackups\XE\LongQueriesTimeBound*.xel', NULL, NULL, NULL)
) AS raw
CROSS APPLY raw.xe_xml.nodes('/event') AS n(c)
ORDER BY event_time;
GO

-- Task 5: แก้ MAX_DURATION ของ session ที่หยุดแล้ว (ได้เฉพาะตอน STOP)
ALTER EVENT SESSION [LongQueriesTimeBound] ON SERVER
WITH ( MAX_DURATION = 10 MINUTES );
GO

SELECT name, max_duration FROM sys.server_event_sessions WHERE name = N'LongQueriesTimeBound';
-- Expected: 600 (10 นาที)

-- ปลดล็อกให้รันไม่จำกัด (ต้องหยุดก่อนเสมอ)
ALTER EVENT SESSION [LongQueriesTimeBound] ON SERVER
WITH ( MAX_DURATION = UNLIMITED );
GO

SELECT name, max_duration FROM sys.server_event_sessions WHERE name = N'LongQueriesTimeBound';
-- Expected: 0 = UNLIMITED

-- Task 6: ทำความสะอาด
DROP EVENT SESSION [LongQueriesTimeBound] ON SERVER;
GO

-- กติกาสรุป (จากเอกสารทางการ):
--  - หยุดก่อนเวลาด้วย ALTER EVENT SESSION ... STATE = STOP ได้ตลอด
--  - เริ่มใหม่ (STATE = START) นับเวลาใหม่ตั้งแต่ต้น
--  - แก้ MAX_DURATION ได้เฉพาะเมื่อ session หยุด
--  - ใช้ MAX_DURATION = UNLIMITED เพื่อเอาข้อจำกัดออก
--  - บนเวอร์ชันเก่ากว่า 2025 คุมอายุด้วย Agent job ที่รัน STATE = STOP ตามตารางแทน

-- ทดลองเอง
-- 1) ตั้ง MAX_DURATION = 2 MINUTES แล้ว START -> รอ -> ยืนยันว่าหยุดเองโดยไม่แตะอะไร
-- 2) START ซ้ำหลังหยุดอัตโนมัติ แล้วสังเกตว่าต้องนับ 5 นาทีใหม่ทั้งหมด
-- 3) ใช้ pattern นี้กับ session จับ deadlocks ชั่วคราวตอนเกิดเหตุ (Agent job เริ่ม session + MAX_DURATION คุม)
