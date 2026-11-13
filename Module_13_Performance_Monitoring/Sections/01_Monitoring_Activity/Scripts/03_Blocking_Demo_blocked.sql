-- ============================================================================
-- Module 13 - Section 1 - Script 03: ผู้ถูก BLOCK (blocked) — รันใน SSMS Session 2
-- ปรับจาก: Microsoft 20764D Mod13 "Demo 2b - blocked.sql"
-- เงื่อนไข: รัน 02_Blocking_Demo_blocker.sql ใน Session 1 ค้างไว้ก่อน
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 1: SELECT แถวที่ Session 1 กำลังถือ X lock อยู่
-- query นี้จะค้าง (รอจน timeout 120 วินาที default) — นี่คือ blocking!
-- ----------------------------------------------------------------------------
USE AdventureWorks2025;
GO

SELECT * FROM Lab.BlockingDemo
WHERE Id = 1;
GO

-- ----------------------------------------------------------------------------
-- Task 2 (รันใน Session 3 — หน้าต่างใหม่): จับ blocking ที่กำลังเกิด
-- ----------------------------------------------------------------------------
SELECT r.session_id,
       r.blocking_session_id,
       r.wait_type,
       r.wait_time,
       r.wait_resource,
       s.program_name,
       t.text AS BlockedText
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;
GO

-- ----------------------------------------------------------------------------
-- Task 3: สอบถามตัวการ (head blocker) — แก้ blocking_session_id จาก Task 2
-- ----------------------------------------------------------------------------
SELECT s.session_id,
       s.original_login_name,
       s.program_name,
       s.host_name,
       s.last_request_start_time,
       t.text AS BlockerText
FROM sys.dm_exec_sessions AS s
OUTER APPLY (SELECT * FROM sys.dm_exec_sql_text(
                    (SELECT r.most_recent_sql_handle
                     FROM sys.dm_exec_connections AS r
                     WHERE r.session_id = s.session_id))) AS t
WHERE s.session_id = 55;   -- <<< แก้เป็น blocking_session_id ของคุณ
GO

-- ----------------------------------------------------------------------------
-- Task 4: ดู wait chain แบบละเอียด (ใครรออะไร resource ไหน)
-- ----------------------------------------------------------------------------
SELECT wt.session_id,
       wt.wait_duration_ms,
       wt.wait_type,
       wt.blocking_session_id,
       wt.resource_description
FROM sys.dm_os_waiting_tasks AS wt
WHERE wt.blocking_session_id <> 0;
GO

-- ----------------------------------------------------------------------------
-- Task 5 (จบการทดลอง): กลับไป Session 1 รัน COMMIT; หรือ ROLLBACK;
-- แล้ว Session 2 จะ query สำเร็จทันที
-- หากต้องการ "ยิง" ตัวการจาก session อื่น (ต้องมีสิทธิ์ sysadmin/processadmin):
-- KILL 55;   -- <<< แก้เป็น session id ตัวการ
-- ----------------------------------------------------------------------------
