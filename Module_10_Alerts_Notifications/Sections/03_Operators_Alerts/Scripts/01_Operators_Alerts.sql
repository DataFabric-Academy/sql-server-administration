-- ============================================================================
-- Module 10, Section 3 — Operators + Alerts (event / performance / WMI)
-- ปรับจาก Old/Demofiles/Mod10 (Demo 3 - operators.sql, Demo 4 - alerts.sql):
--   ลด notification ให้เหลือ email-only (pager/net send กำลังถูกถอด) และแทน
--   การจำลอง log full ด้วย while-loop ให้เป็นการทดสอบด้วย RAISERROR + perf counter
-- ต้องมี: sysadmin; Database Mail พร้อม (รัน Scripts/01_DatabaseMail_Setup.sql ก่อน)
-- idempotent — ลบของเดิมก่อนสร้างใหม่
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) Operator — ผู้รับ notification (email เท่านั้นในงานใหม่)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_delete_operator @name = N'Fabrikam DBA Team';

EXEC dbo.sp_add_operator
    @name          = N'Fabrikam DBA Team',
    @enabled       = 1,
    @email_address = N'dba-team@fabrikam.example';
-- หมายเหตุ: พารามิเตอร์ pager (@pager_address, @pager_days ...) และ
-- @netsend_address มีใน syntax แต่กลไกจะถูกลบในเวอร์ชันอนาคต — ไม่ใช้
GO

/* ----------------------------------------------------------------------------
   2) ทดสอบช่องทางอีเมลถึง operator (ต้องตั้ง Database Mail + Agent profile แล้ว)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_notify_operator
    @operator_name       = N'Fabrikam DBA Team',
    @notification_method = 1,                       -- 1 = email
    @subject             = N'Test: operator channel works',
    @body                = N'ถ้าเห็นอีเมลนี้ ช่องทาง Agent -> Database Mail พร้อมใช้';
GO

/* ----------------------------------------------------------------------------
   3) Event alert — จับ severity 17 ทั้งหมด (รวม log full 9002)
      สำคัญ: alert จับได้เฉพาะข้อความที่ถึง Windows Application Log
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Severity 17')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Severity 17';

EXEC dbo.sp_add_alert
    @name                         = N'Fabrikam - Severity 17',
    @severity                     = 17,
    @enabled                      = 1,
    @delay_between_responses      = 120,    -- วินาที — กันเมลล้นเมื่อ error ซ้ำถี่
    @notification_message         = N'Fabrikam: severity 17 error — ตรวจ error log ทันที',
    @include_event_description_in = 1;      -- 1 = ใส่ description ในอีเมล (email only)

-- (เทียบ) alert เจาะเฉพาะ error number 9002 "transaction log full":
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Log Full (9002)')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Log Full (9002)';

EXEC dbo.sp_add_alert
    @name                         = N'Fabrikam - Log Full (9002)',
    @message_id                   = 9002,   -- ใช้ message_id => severity = 0 อัตโนมัติ
    @enabled                      = 1,
    @delay_between_responses      = 180,
    @include_event_description_in = 1;
GO

/* ----------------------------------------------------------------------------
   4) Performance condition alert — จับ "ก่อนพัง": log ของ AW2025 เตือน 90%
      รูปแบบ: Object|Counter|Instance|Comparator Value
      (บน named instance ใช้ object MSSQL$<InstanceName>:Databases)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - AW2025 Log Used > 90%')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - AW2025 Log Used > 90%';

EXEC dbo.sp_add_alert
    @name                   = N'Fabrikam - AW2025 Log Used > 90%',
    @enabled                = 1,
    @delay_between_responses = 300,
    @performance_condition  = N'SQLServer:Databases|Percent Log Used|AdventureWorks2025|> 90';
GO

/* ----------------------------------------------------------------------------
   5) WMI alert (ย่อ) — จับ DEADLOCK_GRAPH (ตัวอย่างทางการของ Microsoft)
      ต้อง: Agent service account มีสิทธิ์ WMI ของ namespace + msdb Service Broker เปิด
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Deadlock graph (WMI)')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Deadlock graph (WMI)';

EXEC dbo.sp_add_alert
    @name          = N'Fabrikam - Deadlock graph (WMI)',
    @enabled       = 0,   -- ปิดไว้เป็นตัวอย่าง (เปิด = 1 เมื่อต้องการใช้จริง)
    @wmi_namespace = N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER',
    @wmi_query     = N'SELECT * FROM DEADLOCK_GRAPH';
GO

/* ----------------------------------------------------------------------------
   6) Response: แจ้ง operator + (ตัวเลือก) รัน job เมื่อ alert ยิง
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_notification
    @alert_name          = N'Fabrikam - Severity 17',
    @operator_name       = N'Fabrikam DBA Team',
    @notification_method = 1;      -- 1 = email

EXEC dbo.sp_add_notification
    @alert_name          = N'Fabrikam - Log Full (9002)',
    @operator_name       = N'Fabrikam DBA Team',
    @notification_method = 1;

-- (ตัวเลือก) ให้ alert "Log Used > 90%" รัน job ตอบสนอง — เช่น backup log ทันที
-- EXEC dbo.sp_update_alert
--     @name = N'Fabrikam - AW2025 Log Used > 90%',
--     @job_name = N'Daily Backup';   -- job จาก Lab 8

-- ตรวจระบบทั้งหมด: alert + notification + operator
SELECT a.name AS alert_name, a.enabled, a.delay_between_responses,
       a.severity, a.message_id, a.performance_condition, a.wmi_query,
       o.name AS notified_operator, o.email_address
FROM dbo.sysalerts AS a
LEFT JOIN dbo.sysnotifications AS n ON n.alert_id = a.id
LEFT JOIN dbo.sysoperators AS o ON o.id = n.operator_id
ORDER BY a.name;
-- Expected: 4 alerts (1 ปิด) + ผูก operator แล้ว 2 ตัวแรก
GO

/* ----------------------------------------------------------------------------
   7) ทดสอบให้ alert ยิงจริง — RAISERROR severity 17 WITH LOG
      (ต้อง sysadmin หรือ ALTER TRACE) — ภายในไม่กี่วินาที Agent จะจับและส่งเมล
   ---------------------------------------------------------------------------- */
RAISERROR (N'Fabrikam: test severity 17 for alert.', 17, 1) WITH LOG;
GO
-- รอ 10-15 วินาที แล้วตรวจ:
--   a) อีเมลใน smtp4dev / กล่องจริง
--   b) Database Mail log:
SELECT TOP 10 log_id, event_type, description, log_date
FROM dbo.sysmail_event_log
ORDER BY log_id DESC;

--   c) Agent log บันทึกการจับ alert:
EXEC xp_readerrorlog 0, 2, N'Fabrikam - Severity 17';
-- Expected: Agent log มีบรรทัดบอกว่า alert ถูก raise + notification ถูกส่ง

/* ----------------------------------------------------------------------------
   Clean-up — ลบ alerts + operator (คง Database Mail ไว้ใช้โมดูลต่อไป)
   ----------------------------------------------------------------------------
   USE msdb;
   EXEC dbo.sp_delete_alert @name = N'Fabrikam - Severity 17';
   EXEC dbo.sp_delete_alert @name = N'Fabrikam - Log Full (9002)';
   EXEC dbo.sp_delete_alert @name = N'Fabrikam - AW2025 Log Used > 90%';
   EXEC dbo.sp_delete_alert @name = N'Fabrikam - Deadlock graph (WMI)';
   EXEC dbo.sp_delete_operator @name = N'Fabrikam DBA Team';
   GO
*/
