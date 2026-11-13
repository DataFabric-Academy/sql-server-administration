-- ============================================================================
-- Module 13 - Section 1 - Script 01: ดูกิจกรรมปัจจุบันด้วย DMOs (DMVs/DMFs)
-- ปรับจาก: Microsoft 20764D Mod13 "Demo 1 - DMO.sql"
-- รันได้บน: SQL Server 2019+ (แนะนำ 2025), ฐาน AdventureWorks2025
-- สิทธิ์ที่ต้องมี: VIEW SERVER STATE (sysadmin ผ่านทุกข้อ)
-- ============================================================================
-- เคล็ดลับ: Task 2-6 จะสนุกกว่าถ้ามี workload กำลังรันพื้นหลัง
-- ดู workload ตัวอย่างใน Labs/README.md (Exercise 1)

-- ----------------------------------------------------------------------------
-- Task 1: Request ที่กำลังรันทั้งหมด (ส่วนใหญ่เป็น system/background requests)
-- ----------------------------------------------------------------------------
SELECT * FROM sys.dm_exec_requests;
GO

-- ----------------------------------------------------------------------------
-- Task 2: Session ทั้งหมด - ใช้ is_user_process = 1 กรองกิจกรรมผู้ใช้จริง
-- ----------------------------------------------------------------------------
SELECT * FROM sys.dm_exec_sessions
WHERE is_user_process = 1;
GO

-- ----------------------------------------------------------------------------
-- Task 3: Join requests + sessions = ใคร กำลังรันอะไร รออะไร
-- ----------------------------------------------------------------------------
SELECT s.original_login_name,
       s.program_name,
       r.command,
       r.wait_type,
       r.wait_time,            -- มิลลิวินาทีที่รออยู่ ณ ขณะนี้
       r.blocking_session_id,
       r.sql_handle
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
WHERE s.is_user_process = 1;
GO

-- ----------------------------------------------------------------------------
-- Task 4: ดึงข้อความ batch ที่กำลังรันด้วย sys.dm_exec_sql_text
-- ----------------------------------------------------------------------------
SELECT s.original_login_name,
       s.program_name,
       r.command,
       t.text,                 -- ข้อความ T-SQL ทั้ง batch
       r.wait_type,
       r.wait_time,
       r.blocking_session_id
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1;
GO

-- ----------------------------------------------------------------------------
-- Task 5: ตัดเฉพาะ "statement ปัจจุบัน" ด้วย statement offsets (pattern มาตรฐาน)
-- ----------------------------------------------------------------------------
SELECT s.original_login_name,
       s.program_name,
       r.command,
       (SELECT TOP (1)
               SUBSTRING(t.text,
                         (r.statement_start_offset / 2) + 1,
                         ((CASE r.statement_end_offset
                                WHEN -1 THEN (LEN(CONVERT(nvarchar(max), t.text)) * 2)
                                ELSE r.statement_end_offset
                          END - r.statement_start_offset) / 2) + 1)
       ) AS CurrentStatement,
       r.wait_type,
       r.wait_time,
       r.blocking_session_id
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1;
GO

-- ----------------------------------------------------------------------------
-- Task 6: การเชื่อมต่อระดับ network (เก่าแก่ที่สุดก่อน = เชื่อมต่อนาน)
-- ----------------------------------------------------------------------------
SELECT TOP (20)
       c.session_id,
       c.connect_time,
       DATEDIFF(minute, c.connect_time, SYSDATETIME()) AS ConnectedMinutes,
       c.net_transport,
       c.protocol_type,
       c.client_net_address,
       c.auth_scheme,          -- NTLM / KERBEROS / SQL ...
       s.original_login_name,
       s.program_name
FROM sys.dm_exec_connections AS c
INNER JOIN sys.dm_exec_sessions AS s
        ON c.session_id = s.session_id
WHERE c.net_transport <> 'Session'
ORDER BY c.connect_time;
GO

-- ----------------------------------------------------------------------------
-- Task 7: มุมมองระดับเครื่องจาก sys.dm_os_sys_info
-- ----------------------------------------------------------------------------
SELECT sqlserver_start_time,
       DATEDIFF(day, sqlserver_start_time, SYSDATETIME()) AS UptimeDays,
       cpu_count,
       hyperthread_ratio,
       (cpu_count / hyperthread_ratio) AS LogicalSockets,
       physical_memory_kb / 1024 / 1024      AS PhysicalMemoryGB,
       committed_kb / 1024 / 1024            AS CommittedGB,
       committed_target_kb / 1024 / 1024     AS CommittedTargetGB
FROM sys.dm_os_sys_info;
GO

-- ----------------------------------------------------------------------------
-- Task 8: สรุป plan cache ตามประเภท (เห็นภาระ ad-hoc workload)
-- ----------------------------------------------------------------------------
SELECT cacheobjtype,
       objtype,
       COUNT(*)                    AS CountOfPlans,
       SUM(usecounts)              AS UsageCount,
       SUM(usecounts) / CAST(COUNT(*) AS float) AS AvgUsed,
       SUM(size_in_bytes) / 1024.0 / 1024.0 AS SizeInMB
FROM sys.dm_exec_cached_plans
GROUP BY cacheobjtype, objtype
ORDER BY CountOfPlans DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 9: Top 10 statement แพงเฉลี่ยด้วย logical reads (จาก plan cache)
-- ----------------------------------------------------------------------------
SELECT TOP (10)
       qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
       qs.execution_count,
       SUBSTRING(st.text,
                 (qs.statement_start_offset / 2) + 1,
                 ((CASE qs.statement_end_offset
                        WHEN -1 THEN DATALENGTH(st.text)
                        ELSE qs.statement_end_offset
                   END - qs.statement_start_offset) / 2) + 1) AS StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY AvgLogicalReads DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 10: I/O สถิติของ database files (ค่าสะสมตั้งแต่ restart)
-- ----------------------------------------------------------------------------
SELECT DB_NAME(fs.database_id)                        AS DatabaseName,
       mf.name                                        AS FileName,
       mf.type_desc,
       mf.size * 8 / 1024                             AS SizeMB,
       fs.num_of_reads,
       fs.num_of_writes,
       fs.io_stall_read_ms  / NULLIF(fs.num_of_reads, 0)  AS AvgReadLatency_ms,
       fs.io_stall_write_ms / NULLIF(fs.num_of_writes, 0) AS AvgWriteLatency_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
INNER JOIN sys.master_files AS mf
        ON fs.database_id = mf.database_id
       AND fs.file_id     = mf.file_id
ORDER BY fs.io_stall_read_ms + fs.io_stall_write_ms DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 11: Wait statistics รวมทั้งเซิร์ฟเวอร์ (ค่าสะสมตั้งแต่ restart)
-- ถ้าต้องการเริ่มนับใหม่: DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
-- ----------------------------------------------------------------------------
SELECT TOP (15)
       wait_type,
       waiting_tasks_count,
       wait_time_ms,
       wait_time_ms / 1000.0                                        AS WaitSeconds,
       100.0 * wait_time_ms / SUM(wait_time_ms) OVER ()             AS PctOfTotal,
       signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0
  AND wait_type NOT IN (N'SLEEP_TASK', N'BROKER_TASK_STOP',
                        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'XE_TIMER_EVENT',
                        N'WAITFOR', N'DIRTY_PAGE_POLL',
                        N'DISPATCHER_QUEUE_SEMAPHORE',
                        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
                        N'XE_DISPATCHER_WAIT', N'LOGMGR_QUEUE')
ORDER BY wait_time_ms DESC;
GO
