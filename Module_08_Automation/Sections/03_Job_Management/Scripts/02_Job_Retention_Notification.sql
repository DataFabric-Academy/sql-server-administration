-- ============================================================================
-- Module 08, Section 3 — ปรับ Job History Retention + ตั้ง Notification ราย job
-- ต้องมี: SQL Server Agent รันอยู่; sysadmin (sp_set_sqlagent_properties เขียนค่าระดับ Agent)
-- idempotent — รันซ้ำได้
-- ข้อควรระวัง: notification ทางอีเมลจะส่งได้จริงเมื่อตั้ง Database Mail แล้ว (Module 10)
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) ปรับ job history retention
      default ของ SQL Server: 1,000 แถวรวม / 100 แถวต่อ job — เล็กเกินสำหรับ
      job ที่รันถี่ (log backup ทุก 15 นาที = 96 แถว/วัน) จึงเพิ่มโควตา
      (สมมูลกับหน้าจอ Agent Properties -> History)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_set_sqlagent_properties
    @jobhistory_max_rows         = 10000,   -- รวมทั้ง instance (NULL = คงค่าเดิม)
    @jobhistory_max_rows_per_job = 1000;    -- ต่อ job
PRINT N'Time: retention ถูกตั้งเป็น 10,000/1,000 แถว';

/* ----------------------------------------------------------------------------
   2) ล้างประวัติแบบ manual (ตัวเลือก)
      sp_purge_jobhistory ใช้ได้สองแบบ: ต่อ job หรือตามอายุทั้ง instance
   ---------------------------------------------------------------------------- */
-- 2a) ลบประวัติของ job เดโมเดิม (ถ้ามี)
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Demo Job')
    EXEC dbo.sp_purge_jobhistory @job_name = N'Fabrikam - Demo Job';

-- 2b) ลบประวัติเก่ากว่า 30 วันของทุก job (คอมเมนต์ไว้ — ให้รันเองเมื่อต้องการ)
-- EXEC dbo.sp_purge_jobhistory @oldest_date = DATEADD(day, -30, GETDATE());

/* ----------------------------------------------------------------------------
   3) สร้าง operator แบบ minimal (notification ต้องมี operator เป็นผู้รับ)
      ลึกเรื่อง operator/Database Mail คือ Module 10 — ตรงนี้แค่เตรียมของ
   ---------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_add_operator
        @name          = N'Fabrikam DBA Team',
        @enabled       = 1,
        @email_address = N'dba-team@fabrikam.example';   -- ที่อยู่ทดลอง (smtp4dev รับได้)
GO

/* ----------------------------------------------------------------------------
   4) ผูก notification เข้ากับ job เดโม — แจ้งอีเมลเมื่อ job ล้ม
      @notify_level_email: 1=เมื่อสำเร็จ, 2=เมื่อล้ม, 3=ทั้งสอง
      (อย่าใช้ @notify_level_netsend/@notify_level_page — กลไกกำลังถูกถอด)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Demo Job')
BEGIN
    EXEC dbo.sp_update_job
        @job_name                   = N'Fabrikam - Demo Job',
        @notify_level_email         = 2,
        @notify_email_operator_name = N'Fabrikam DBA Team';
    PRINT N'Notification ผูกกับ job เรียบร้อย';
END
ELSE
    PRINT N'ยังไม่มี job Fabrikam - Demo Job — รัน Scripts/01_Create_Job_Steps_Schedule.sql ของ Section 2 ก่อน';
GO

/* ----------------------------------------------------------------------------
   5) ตรวจผล — notification ที่ผูกไว้ (sysjobs: notify_level_email + operator)
   ---------------------------------------------------------------------------- */
SELECT j.name AS job_name, j.notify_level_email,
       o.name AS email_operator, o.email_address
FROM dbo.sysjobs AS j
LEFT JOIN dbo.sysoperators AS o ON o.id = j.notify_email_operator_id
WHERE j.name = N'Fabrikam - Demo Job';
-- Expected: notify_level_email = 2, operator = Fabrikam DBA Team

/* ----------------------------------------------------------------------------
   6) ทดสอบส่งอีเมลถึง operator ตรง ๆ (ทางลัดพิสูจน์ช่องทาง Agent -> Mail)
      ต้อง: Database Mail เปิดใช้ + Agent mail profile ตั้งแล้ว (Module 10)
      ถ้ายังไม่ตั้ง Database Mail — สคริปต์จะ error อย่างชัดเจน เป็นเครื่องยืนยันว่า
      ยังขาดชิ้นส่วนไหน ให้ไปทำ Module 10 ก่อน
   ---------------------------------------------------------------------------- */
-- EXEC dbo.sp_notify_operator
--     @operator_name       = N'Fabrikam DBA Team',
--     @notification_method = 1,
--     @subject             = N'Test notification จาก SQL Server',
--     @body                = N'ช่องทาง Agent -> Database Mail ใช้งานได้';
GO

/* ----------------------------------------------------------------------------
   7) จำลอง job ล้มเพื่อดู notification ทำงาน (ตัวเลือก — รันเมื่อพร้อมแล้ว)
      สร้าง step ที่ชัด ๆ พัง แล้วรัน job แล้วอ่าน sysjobhistory
   ---------------------------------------------------------------------------- */
-- EXEC dbo.sp_add_jobstep
--     @job_name = N'Fabrikam - Demo Job', @step_name = N'Bad step',
--     @step_id = 10, @subsystem = N'TSQL', @database_name = N'master',
--     @command = N'BACKUP DATABASE [NoSuchDatabase] TO DISK = N''X:\bad.bak'';',
--     @on_success_action = 1, @on_fail_action = 2;
-- EXEC dbo.sp_start_job @job_name = N'Fabrikam - Demo Job';
-- -- รอ 5-10 วินาที แล้ว:
-- EXEC dbo.sp_help_jobhistory @job_name = N'Fabrikam - Demo Job';
-- -- Expected: run_status = 0 + ข้อความ error 911 ('NoSuchDatabase does not exist')
