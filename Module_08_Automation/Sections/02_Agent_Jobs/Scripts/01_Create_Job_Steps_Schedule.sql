-- ============================================================================
-- Module 08, Section 2 — สร้าง Job + Steps + Schedules ด้วย T-SQL ล้วน
-- ต้องมี: SQL Server Agent รันอยู่, AdventureWorks2025 (ดู Module 00)
-- idempotent — รันซ้ำได้ (ลบ job เดิมก่อนสร้างใหม่ทุกครั้ง)
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) สร้าง Category ของห้องเรียน (idempotent)
   ---------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.syscategories
               WHERE name = N'Fabrikam Maintenance' AND category_class = 1)
    EXEC dbo.sp_add_category
        @class = N'JOB',
        @type  = N'LOCAL',
        @name  = N'Fabrikam Maintenance';
GO

/* ----------------------------------------------------------------------------
   2) ลบ job เดโมเดิม (รันซ้ำได้) แล้วสร้างตัว job
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Demo Job')
    EXEC dbo.sp_delete_job @job_name = N'Fabrikam - Demo Job',
                           @delete_unused_schedule = 1;
GO

DECLARE @jobId BINARY(16);

EXEC dbo.sp_add_job
    @job_name              = N'Fabrikam - Demo Job',
    @enabled               = 1,
    @description           = N'Demo job สร้างใน Module 8 Section 2 — Job/Steps/Schedules',
    @category_name         = N'Fabrikam Maintenance',
    @owner_login_name      = N'sa',
    @notify_level_eventlog = 0,
    @notify_level_email    = 0,
    @delete_level          = 0,
    @job_id                = @jobId OUTPUT;

/* ----------------------------------------------------------------------------
   3) Step 1 (T-SQL) — นับข้อมูลใน AdventureWorks2025
      on_success = 3 (ไป step ถัดไป), on_fail = 2 (จบด้วย fail)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobstep
    @job_id             = @jobId,
    @step_name          = N'Step 1 - นับคำสั่งขาย',
    @step_id            = 1,
    @subsystem          = N'TSQL',
    @database_name      = N'AdventureWorks2025',
    @command            = N'SELECT COUNT(*) AS SalesOrders FROM Sales.SalesOrderHeader;',
    @cmdexec_success_code = 0,
    @on_success_action  = 3,          -- ไป step ถัดไป
    @on_fail_action     = 2,          -- จบด้วยสถานะ fail
    @retry_attempts     = 0,
    @retry_interval     = 0;

/* ----------------------------------------------------------------------------
   4) Step 2 (T-SQL) — จำลองงานบำรุงรักษา: อัปเดตสถิติตารางใหญ่ที่สุด
      แสดงการใช้ multi-statement batch ในหนึ่ง step + retry
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobstep
    @job_id             = @jobId,
    @step_name          = N'Step 2 - อัปเดตสถิติ',
    @step_id            = 2,
    @subsystem          = N'TSQL',
    @database_name      = N'AdventureWorks2025',
    @command            = N'UPDATE STATISTICS Sales.SalesOrderHeader WITH SAMPLE 10 PERCENT;',
    @on_success_action  = 3,          -- ไป step ถัดไป
    @on_fail_action     = 2,
    @retry_attempts     = 2,          -- ลองใหม่ 2 ครั้งเมื่อล้ม (เช่น deadlock)
    @retry_interval     = 5;          -- เว้น 5 นาทีระหว่าง retry

/* ----------------------------------------------------------------------------
   5) Step 3 (T-SQL) — จุดจบของ job: เขียน timestamp ลง msdb ผ่าน dynamic SQL
      on_success = 1 (จบ job แบบสำเร็จ)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobstep
    @job_id             = @jobId,
    @step_name          = N'Step 3 - บันทึกเวลาจบงาน',
    @step_id            = 3,
    @subsystem          = N'TSQL',
    @database_name      = N'msdb',
    @command            = N'SELECT N''Job finished at '' + CONVERT(nvarchar(30), SYSDATETIME(), 120) AS finish_time;',
    @on_success_action  = 1,          -- จบ job แบบสำเร็จ
    @on_fail_action     = 2;

-- กำหนด step เริ่มต้น + ปล่อย job ให้รันได้บน server นี้ (ข้ามแล้ว job รันไม่ได้!)
EXEC dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';
GO

/* ----------------------------------------------------------------------------
   6) Schedule แบบ recurring — ทุกวัน 01:00
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobschedule
    @job_name           = N'Fabrikam - Demo Job',
    @name               = N'Nightly at 01:00',
    @enabled            = 1,
    @freq_type          = 4,          -- Daily
    @freq_interval      = 1,          -- ทุกวัน
    @freq_subday_type   = 1,          -- ครั้งเดียวต่อวัน
    @freq_subday_interval = 0,
    @freq_recurrence_factor = 0,
    @active_start_date  = 20260101,   -- YYYYMMDD — เปลี่ยนเป็นวันที่เริ่มใช้งานได้
    @active_end_date    = 99991231,
    @active_start_time  = 010000,     -- HHMMSS = 01:00:00
    @active_end_time    = 235959;
GO

/* ----------------------------------------------------------------------------
   7) Schedule แบบ weekly — เฉพาะจันทร์ถึงศุกร์ 22:00 (ตัวอย่าง freq_interval แบบบิต)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobschedule
    @job_name           = N'Fabrikam - Demo Job',
    @name               = N'Weekdays at 22:00',
    @enabled            = 0,          -- ปิดไว้เป็นตัวอย่าง (เปิด = 1 เมื่อต้องใช้)
    @freq_type          = 8,          -- Weekly
    @freq_interval      = 62,         -- 2+4+8+16+32 = จันทร์..ศุกร์
    @freq_recurrence_factor = 1,      -- ทุกสัปดาห์
    @freq_subday_type   = 1,
    @active_start_time  = 220000;
GO

/* ----------------------------------------------------------------------------
   8) Schedule แบบ one-off — รันครั้งเดียว (ตัวอย่าง freq_type = 1)
      แก้วันที่เป็นวันที่ในอนาคตก่อนเปิดใช้ ไม่งั้น Agent จะไม่ยิงให้
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobschedule
    @job_name           = N'Fabrikam - Demo Job',
    @name               = N'One-off example',
    @enabled            = 0,
    @freq_type          = 1,          -- One-time
    @active_start_date  = 20261231,
    @active_start_time  = 220000;
GO

/* ----------------------------------------------------------------------------
   9) ตรวจสอบผลลัพธ์ — job, steps, schedules ที่เพิ่งสร้าง
   ---------------------------------------------------------------------------- */
SELECT name, enabled, date_created FROM msdb.dbo.sysjobs
WHERE name = N'Fabrikam - Demo Job';

SELECT js.step_id, js.step_name, js.subsystem, js.on_success_action, js.on_fail_action,
       js.retry_attempts, js.database_name
FROM msdb.dbo.sysjobsteps AS js
JOIN msdb.dbo.sysjobs AS j ON j.job_id = js.job_id
WHERE j.name = N'Fabrikam - Demo Job'
ORDER BY js.step_id;
-- Expected: 3 steps — Step1 on_success_action=3, Step2 retry=2, Step3 on_success_action=1

SELECT s.name AS schedule_name, s.enabled, s.freq_type, s.freq_interval,
       s.freq_subday_type, s.active_start_time
FROM msdb.dbo.sysjobschedules AS jsch
JOIN msdb.dbo.sysjobs AS j ON j.job_id = jsch.job_id
JOIN msdb.dbo.sysschedules AS s ON s.schedule_id = jsch.schedule_id
WHERE j.name = N'Fabrikam - Demo Job'
ORDER BY s.name;
-- Expected: 3 schedules (1 เปิด 2 ปิด)

/* ----------------------------------------------------------------------------
   10) รัน job ทันทีด้วยมือ (ไม่รอ schedule) แล้วดูสถานะ
   ---------------------------------------------------------------------------- */
EXEC msdb.dbo.sp_start_job @job_name = N'Fabrikam - Demo Job';
GO

-- sp_start_job คืนคำสั่งแบบ asynchronous (Agent รันเบื้องหลัง) — รอ 5-10 วินาทีแล้วดูประวัติ
-- รอแล้วรันข้างล่างซ้ำจนเห็นสถานะล่าสุด:
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Fabrikam - Demo Job', @mode = 'FULL';
-- Expected: run_status = 1 (Succeeded) เมื่อ job รันจบ

/* ----------------------------------------------------------------------------
   Clean-up — รันเมื่อต้องการลบของทั้งหมดของ Section นี้
   ----------------------------------------------------------------------------
   IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Fabrikam - Demo Job')
       EXEC msdb.dbo.sp_delete_job @job_name = N'Fabrikam - Demo Job',
                                   @delete_unused_schedule = 1;
   -- (category เก็บไว้ได้ ใช้ต่อใน Section/Lab อื่น)
*/
