-- ============================================================================
-- Module 10, Section 2 — ตั้งค่า Database Mail ครบวง (Account/Profile/Principal)
-- ปรับจาก Old/Demofiles/Mod10 (Demo 2 - database mail.sql) ให้สร้างทุกอย่างเอง
--   ทดสอบกับ smtp4dev (fake SMTP ฟรี) หรือเปลี่ยนค่าไปใช้ SMTP จริงได้
-- ต้องมี: sysadmin (sp_configure + จัดการ Database Mail)
-- idempotent — ลบของเดิมก่อนสร้างใหม่ทุกครั้ง
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) เปิดใช้ Database Mail XPs (ปิด default เพื่อความปลอดภัย)
   ---------------------------------------------------------------------------- */
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE;
GO

/* ----------------------------------------------------------------------------
   2) ล้างของเดิม (เรียงลำดับ: principalprofile -> profileaccount -> profile -> account)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysmail_profile    WHERE name = N'Fabrikam DBA Profile')
    EXEC dbo.sysmail_delete_principalprofile_sp @profile_name = N'Fabrikam DBA Profile';
IF EXISTS (SELECT 1 FROM dbo.sysmail_profile    WHERE name = N'Fabrikam DBA Profile')
    EXEC dbo.sysmail_delete_profileaccount_sp   @profile_name = N'Fabrikam DBA Profile';
IF EXISTS (SELECT 1 FROM dbo.sysmail_profile    WHERE name = N'Fabrikam DBA Profile')
    EXEC dbo.sysmail_delete_profile_sp          @profile_name = N'Fabrikam DBA Profile';
IF EXISTS (SELECT 1 FROM dbo.sysmail_account    WHERE name = N'Fabrikam Mail Account')
    EXEC dbo.sysmail_delete_account_sp          @account_name = N'Fabrikam Mail Account';
GO

/* ----------------------------------------------------------------------------
   3) Mail Account — ข้อมูล SMTP จริง
      ตัวอย่างนี้ชี้ smtp4dev (docker: -p 25:25 -p 5000:80 rnwood/smtp4dev)
      ในสภาพแวดล้อมจริง: เปลี่ยน @mailserver_name/@port/@enable_ssl/@username/@password
      ตาม SMTP ขององค์กร (เช่น port 587 + SSL)
   ---------------------------------------------------------------------------- */
EXEC dbo.sysmail_add_account_sp
    @account_name            = N'Fabrikam Mail Account',
    @description             = N'SMTP หลักของห้องเรียน (smtp4dev)',
    @email_address           = N'sqlserver@fabrikam.example',
    @display_name            = N'Fabrikam SQL Server',
    @replyto_address         = N'dba-team@fabrikam.example',
    @mailserver_name         = N'localhost',
    @mailserver_type         = N'SMTP',
    @port                    = 25,
    @username                = NULL,
    @password                = NULL,
    @use_default_credentials = 0,
    @enable_ssl              = 0;

/* ----------------------------------------------------------------------------
   4) Mail Profile + ผูก account (ลำดับ = failover order หลาย account)
   ---------------------------------------------------------------------------- */
EXEC dbo.sysmail_add_profile_sp
    @profile_name = N'Fabrikam DBA Profile',
    @description  = N'Profile สำหรับ Agent notification และ sp_send_dbmail';

EXEC dbo.sysmail_add_profileaccount_sp
    @profile_name    = N'Fabrikam DBA Profile',
    @account_name    = N'Fabrikam Mail Account',
    @sequence_number = 1;

/* ----------------------------------------------------------------------------
   5) มอบ profile ให้ผู้ใช้ — แบบ public (ทุก user ใน DatabaseMailUserRole)
      @principal_name = N'public' => public profile; ถ้าใส่ชื่อ user เฉพาะตัว
      (ต้อง CREATE USER ใน msdb ก่อน) => private profile สำหรับ user นั้น
   ---------------------------------------------------------------------------- */
EXEC dbo.sysmail_add_principalprofile_sp
    @profile_name   = N'Fabrikam DBA Profile',
    @principal_name = N'public',
    @is_default     = 1;
GO

/* ----------------------------------------------------------------------------
   6) ตั้ง profile ให้ SQL Server Agent ใช้ (จำเป็นสำหรับ job/alert notification)
      สมมูลหน้าจอ: Agent Properties -> Alert System -> Database Mail profile
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_set_sqlagent_properties
    @databasemail_profile = N'Fabrikam DBA Profile';
GO

/* ----------------------------------------------------------------------------
   7) ปรับ retention/log level (default 30 วัน, Normal)
   ---------------------------------------------------------------------------- */
EXEC dbo.sysmail_configure_sp @parameter_name = N'RetentionPeriod', @parameter_value = N'14';
EXEC dbo.sysmail_configure_sp @parameter_name = N'LoggingLevel',    @parameter_value = N'2';
GO

/* ----------------------------------------------------------------------------
   8) ทดสอบส่งอีเมล + ตรวจสถานะ (ต้องมี smtp4dev หรือ SMTP จริงรันอยู่)
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_send_dbmail
    @profile_name = N'Fabrikam DBA Profile',
    @recipients   = N'dba-team@fabrikam.example',
    @subject      = N'Test from Database Mail (Module 10)',
    @body         = N'ถ้าเห็นอีเมลนี้ใน smtp4dev ช่องทาง SMTP ใช้ได้แล้ว';
GO

-- รอ 5-10 วินาที แล้วตรวจสถานะการส่ง:
SELECT mailitem_id, sent_status,        -- 0=new 1=sending 2=sent 3=failed 4=retrying
       recipients, subject, sent_date
FROM dbo.sysmail_mailitems
ORDER BY mailitem_id DESC;
-- Expected: sent_status = 2 (sent) — และอีเมลโผล่ใน smtp4dev UI (http://localhost:5000)

-- เมื่อไม่ถึง — อ่าน log ของ Database Mail:
SELECT log_id, event_type, description, log_date
FROM dbo.sysmail_event_log
ORDER BY log_id DESC;
-- Expected: event_type 'error' ระบุสาเหตุ (เช่น SMTP server ตอบปฏิเสธ/port ผิด)

/* ----------------------------------------------------------------------------
   9) ตรวจสถานะระบบ Database Mail (เมื่อสงสัยว่า process หยุดไหม)
   ---------------------------------------------------------------------------- */
EXEC dbo.sysmail_help_status_sp;
-- Expected: DatabaseMail process = STARTED
-- ถ้า STOPPED: EXEC dbo.sysmail_start_sp;  (หยุดชั่วคราว: sysmail_stop_sp)

/* ----------------------------------------------------------------------------
   Clean-up — ลบการตั้งค่าทั้งหมดเมื่อจบหลักสูตร (ปล่อยไว้ใช้ Lab 10 ได้)
   ----------------------------------------------------------------------------
   USE msdb;
   EXEC dbo.sysmail_delete_principalprofile_sp @profile_name = N'Fabrikam DBA Profile';
   EXEC dbo.sysmail_delete_profileaccount_sp   @profile_name = N'Fabrikam DBA Profile';
   EXEC dbo.sysmail_delete_profile_sp          @profile_name = N'Fabrikam DBA Profile';
   EXEC dbo.sysmail_delete_account_sp          @account_name = N'Fabrikam Mail Account';
   EXEC dbo.sysmail_delete_mailitems_sp @sent_before = GETDATE();  -- ลบประวัติเมลทดสอบ
   EXEC dbo.sp_set_sqlagent_properties @databasemail_profile = N'';
   GO
*/
