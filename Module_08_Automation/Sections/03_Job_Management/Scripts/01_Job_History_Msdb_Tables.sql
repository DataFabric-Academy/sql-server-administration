-- ============================================================================
-- Module 08, Section 3 — อ่าน Job History และตาราง msdb ที่สำคัญ
-- ต้องมี: SQL Server Agent รันอยู่, มี job อย่างน้อยหนึ่งตัวรันมาแล้ว
--          (รัน Scripts/01_Create_Job_Steps_Schedule.sql ของ Section 2 ก่อน)
-- อ่านอย่างเดียว (read-only) — รันได้ซ้ำเสมอ
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) อ่าน sysjobhistory พร้อมถอดรหัส run_status / run_date / run_time / run_duration
      run_duration เขียนเป็น HHMMSS ติดกัน (เช่น 10205 = 1 ชม. 2 นาที 5 วินาที)
      หรือเป็นวินาทีล้วนถ้าค่าน้อยกว่า 100
   ---------------------------------------------------------------------------- */
SELECT TOP 20
       j.name            AS job_name,
       s.step_name,
       h.step_id,                      -- 0 = สรุปของทั้ง job
       h.run_date,
       h.run_time,
       h.run_duration,
       /* แปลง run_duration เป็นวินาทีรวม: ถ้า >= 100 ใช้ HHMMSS ถ้าไม่ ใช้วินาทีตรง ๆ */
       CASE
           WHEN h.run_duration >= 100 THEN
               (h.run_duration / 10000) * 3600      -- ชั่วโมง
             + ((h.run_duration % 10000) / 100) * 60 -- นาที
             + (h.run_duration % 100)                 -- วินาที
           ELSE h.run_duration
       END AS duration_seconds,
       CASE h.run_status
            WHEN 0 THEN N'Failed'
            WHEN 1 THEN N'Succeeded'
            WHEN 2 THEN N'Retry'
            WHEN 3 THEN N'Canceled'
            WHEN 4 THEN N'In progress'
            ELSE N'Unknown'
       END AS run_status,
       LEFT(h.message, 200) AS message_head
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
LEFT JOIN dbo.sysjobsteps AS s ON s.job_id = h.job_id AND s.step_id = h.step_id
ORDER BY h.instance_id DESC;
-- Expected: ประวัติล่าสุดก่อน; แถว step_id = 0 คือสรุปทั้ง job

/* ----------------------------------------------------------------------------
   2) หา job ที่ล้มล่าสุดของแต่ละ job (เฉพาะแถว step_id = 0 คือสรุป)
   ---------------------------------------------------------------------------- */
SELECT j.name AS job_name,
       h.run_date, h.run_time,
       CASE h.run_status WHEN 0 THEN N'Failed' WHEN 1 THEN N'Succeeded'
                         WHEN 3 THEN N'Canceled' ELSE N'Other' END AS outcome
FROM dbo.sysjobs AS j
CROSS APPLY (SELECT TOP 1 run_date, run_time, run_status
             FROM dbo.sysjobhistory AS h
             WHERE h.job_id = j.job_id AND h.step_id = 0
             ORDER BY h.instance_id DESC) AS h
WHERE h.run_status <> 1;      -- ยังไม่สำเร็จ (ล้ม/ยกเลิก)
-- Expected: ถ้ามี job ล้มจะแสดง; ถ้าว่าง = ทุก job ล่าสุดสำเร็จ หรือยังไม่เคยรัน

/* ----------------------------------------------------------------------------
   3) sp_help_job — สรุปสถานะราย job (last_run_outcome: 1=สำเร็จ 0=ล้ม 3=ไม่เคยรัน)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_help_job @job_name = N'Fabrikam - Demo Job';
-- คอลัมน์ที่ดูบ่อย: last_run_date/time/outcome, current_execution_status, next_run_date/time

/* ----------------------------------------------------------------------------
   4) sp_help_jobhistory แบบเต็ม (สมมูล View History ใน SSMS)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_help_jobhistory @job_name = N'Fabrikam - Demo Job', @mode = 'FULL';
-- Expected: รายการการรันแต่ละครั้งพร้อมข้อความละเอียดของแต่ละ step

/* ----------------------------------------------------------------------------
   5) สำรวจตาราง msdb สำคัญ — นิยาม + steps + schedules ของทุก job
      (เครื่องมือ audit งาน automation ของ instance ในคำสั่งเดียว)
   ---------------------------------------------------------------------------- */
SELECT j.name AS job_name, j.enabled AS job_enabled,
       j.date_created,
       s.name AS owner_name,
       (SELECT COUNT(*) FROM dbo.sysjobsteps AS js WHERE js.job_id = j.job_id) AS step_count,
       (SELECT COUNT(*) FROM dbo.sysjobschedules AS jsch WHERE jsch.job_id = j.job_id) AS schedule_count
FROM dbo.sysjobs AS j
JOIN sys.server_principals AS s ON s.sid = j.owner_sid
ORDER BY j.name;
-- Expected: รายการ job ทั้งหมด; สังเกต syspolicy_purge_history (job ในตัวของระบบ)

/* ----------------------------------------------------------------------------
   6) นิยาม command จริงของแต่ละ step — อ่านว่า job ทำอะไรโดยไม่เปิด GUI
   ---------------------------------------------------------------------------- */
SELECT j.name AS job_name, js.step_id, js.step_name, js.subsystem,
       js.database_name,
       LEFT(js.command, 150) AS command_head,   -- ตัดให้สั้นพออ่านรวดเดียว
       js.on_success_action, js.on_fail_action, js.retry_attempts
FROM dbo.sysjobsteps AS js
JOIN dbo.sysjobs AS j ON j.job_id = js.job_id
ORDER BY j.name, js.step_id;

/* ----------------------------------------------------------------------------
   7) ตรวจว่า backup จริง ๆ เกิดขึ้นไหม — อย่าเชื่อ job history อย่างเดียว
      (msdb.dbo.backupset เขียนโดย BACKUP DATABASE เอง)
   ---------------------------------------------------------------------------- */
SELECT bs.database_name, bs.type AS backup_type,   -- D=Full, I=Differential, L=Log
       bs.backup_start_date, bs.backup_finish_date,
       DATEDIFF(hour, bs.backup_finish_date, GETDATE()) AS hours_ago,
       bs.is_compressed, bmf.physical_device_name
FROM dbo.backupset AS bs
JOIN dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'AdventureWorks2025'
ORDER BY bs.backup_finish_date DESC;
-- Expected: ถ้ารัน backup job ของ Section 2/Lab มาแล้วจะเห็นแถว type='D' ใหม่ ๆ
