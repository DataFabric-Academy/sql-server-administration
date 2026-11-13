# Lab 10: Responding to Alerts and Notifications (บทที่ 10)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab10** (Database Mail / Operators / Alerts / Test alert) + [Microsoft Learn — Database Mail](https://learn.microsoft.com/sql/relational-databases/database-mail/database-mail?view=sql-server-ver17), [sp_add_alert](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-alert-transact-sql?view=sql-server-ver17), [sp_add_operator](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-operator-transact-sql?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> **สิ่งที่ปรับจากแล็บเดิม**: แล็บเดิมใช้ domain `9EXPERT`, อีเมล `student@adventureworks.msft` และกระตุ้น log full ด้วย while-loop — เราใช้ **smtp4dev** (fake SMTP ฟรีสำหรับห้องเรียน), notification **email-only** (pager/net send กำลังถูกถอด) และทดสอบ alert ด้วย `RAISERROR ... WITH LOG` ที่ควบคุมได้

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** พร้อมใช้ (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- **SQL Server Agent รันอยู่** และรันด้วย login ที่มีสิทธิ์ `sysadmin`
- Docker (แนะนำ) สำหรับ **smtp4dev** — หรือมี SMTP server จริง + ที่อยู่อีเมลที่คุณเข้าถึงกล่องขาเข้าได้
- **จาก Module 8**: job `Daily Backup` อยู่ใน instance (ถ้าลบไปแล้ว รัน Exercise 1 ของ Lab 8 ซ้ำก่อน — Exercise 3 ของแล็บนี้ผูก notification กับ job นี้)

## Scenario

หลังจากที่ทีมคุณทำ backup/CHECKDB อัตโนมัติสำเร็จ (Lab 8) เมื่อคืนที่ผ่านมา job ล้มเงียบ ๆ ทั้งคืนและไม่มีใครรู้ตัวจนเช้า หัวหน้าสั่ง: "ตั้งแต่วันนี้ ทุกงานที่พังต้องมีเมลถึงทีมภายในไม่กี่นาที" — แล็บนี้คุณจะประกอบช่องทางอีเมลจริง (Database Mail + smtp4dev), สร้าง operator รับเมล, สร้าง alert จับ severity 17 และ deadlocks, แล้วผูก notification ให้ job เดิมของ Module 8 แจ้งเมื่อล้มจริง

## Objectives

1. สร้าง Database Mail account/profile และทดสอบส่งอีเมล (ด้วย smtp4dev หรือ SMTP จริง)
2. สร้าง operator + alert (severity 17 และ message 1205 deadlock) แล้วกระตุ้นด้วย RAISERROR
3. ผูก job fail notification ให้ job `Daily Backup` จาก Module 8 และยืนยันว่าอีเมลถึงเมื่อ job ล้ม

---

## Exercise 1: Database Mail Profile + ทดสอบส่งอีเมล

### Step 1 — รัน smtp4dev (fake SMTP server ของห้องเรียน)

> **ต้องรู้ก่อน**: Database Mail คุยกับ SMTP server ใดก็ได้ — smtp4dev คือ SMTP จำลองที่รับ "ทุกที่อยู่" และให้เปิดดูอีเมลที่ได้ในเว็บ UI เหมาะสุดสำหรับพิสูจน์ทั้งสายโดยไม่ยุ่ง mail server จริง ([smtp4dev](https://github.com/rnwood/smtp4dev))

```bash
docker run --rm -p 5000:80 -p 25:25 -v smtp4dev-data:/smtp4dev rnwood/smtp4dev:latest
# เมื่อรันแล้ว: เว็บดูอีเมลอยู่ที่ http://localhost:5000 (SMTP ฟัง port 25)
```

> ไม่มี Docker? ใช้ SMTP จริงขององค์กร/ผู้ให้บริการได้เลย — เปลี่ยนค่าใน Step 2 เป็น mail server, port (มัก 587), `@enable_ssl = 1` และ username/password ตามจริง

### Step 2 — สร้าง Database Mail account + profile

> **ต้องรู้ก่อน**: Account = ข้อมูล SMTP จริง, Profile = กล่องห่อ account ที่ Agent/proc อ้าง; การมอบ profile ให้ "public + default" ทำให้ทุก user ใน DatabaseMailUserRole ใช้ได้ทันที (ลึกที่ [Section 2.2](../Sections/02_Database_Mail/README.md))

```sql
USE msdb;
GO
-- (0) เปิดใช้ Database Mail XPs
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1; RECONFIGURE;
GO

-- (1) Account ชี้ smtp4dev
IF EXISTS (SELECT 1 FROM dbo.sysmail_account WHERE name = N'Lab10 Mail Account')
    EXEC dbo.sysmail_delete_account_sp @account_name = N'Lab10 Mail Account';

EXEC dbo.sysmail_add_account_sp
    @account_name    = N'Lab10 Mail Account',
    @description     = N'SMTP ของแล็บ (smtp4dev)',
    @email_address   = N'sqlserver@fabrikam.example',
    @display_name    = N'Fabrikam SQL Server',
    @replyto_address = N'dba-team@fabrikam.example',
    @mailserver_name = N'localhost',
    @mailserver_type = N'SMTP',
    @port            = 25,
    @enable_ssl      = 0;
GO

-- (2) Profile + ผูก account
IF EXISTS (SELECT 1 FROM dbo.sysmail_profile WHERE name = N'Lab10 DBA Profile')
    EXEC dbo.sysmail_delete_profile_sp @profile_name = N'Lab10 DBA Profile';

EXEC dbo.sysmail_add_profile_sp
    @profile_name = N'Lab10 DBA Profile',
    @description  = N'Profile ของแล็บ Module 10';

EXEC dbo.sysmail_add_profileaccount_sp
    @profile_name    = N'Lab10 DBA Profile',
    @account_name    = N'Lab10 Mail Account',
    @sequence_number = 1;

-- (3) มอบ profile ให้ทุก user ที่อยู่ใน DatabaseMailUserRole + เป็น default
EXEC dbo.sysmail_add_principalprofile_sp
    @profile_name   = N'Lab10 DBA Profile',
    @principal_name = N'public',
    @is_default     = 1;
GO

-- (4) ตั้ง profile ให้ SQL Server Agent ใช้ (จำเป็นทุก notification ของ Agent)
EXEC dbo.sp_set_sqlagent_properties
    @databasemail_profile = N'Lab10 DBA Profile';
GO
```

✅ **สังเกต**: ถ้าตั้งผ่าน SSMS ตรวจได้ที่ Agent Properties → **Alert System** — ช่อง Database Mail profile ต้องแสดง `Lab10 DBA Profile` (ถ้าไม่แสดง ให้ restart Agent หลังตั้ง)

### Step 3 — ส่งอีเมลทดสอบและตรวจสถานะ

```sql
USE msdb;
GO
EXEC dbo.sp_send_dbmail
    @profile_name = N'Lab10 DBA Profile',
    @recipients   = N'dba-team@fabrikam.example',
    @subject      = N'Lab 10: Database Mail ทดสอบ',
    @body         = N'ถ้าเห็นอีเมลนี้ใน smtp4dev ช่องทาง SMTP พร้อมใช้แล้ว';

-- รอ 5-10 วินาทีแล้วตรวจ:
SELECT TOP 5 mailitem_id, sent_status,    -- 2 = sent, 3 = failed
       recipients, subject, sent_date
FROM dbo.sysmail_mailitems ORDER BY mailitem_id DESC;

SELECT TOP 5 log_id, event_type, description, log_date
FROM dbo.sysmail_event_log ORDER BY log_id DESC;
GO
```

**Expected:** `sent_status = 2` และอีเมลโผล่ใน http://localhost:5000; ถ้า `sent_status = 3` — อ่าน `sysmail_event_log`: สาเหตุที่พบบ่อยคือ smtp4dev ยังไม่รัน (connection refused) หรือ port ชนกับ process อื่น

---

## Exercise 2: Operator + Alerts และกระตุ้นด้วย RAISERROR

### Step 1 — สร้าง operator

> **ต้องรู้ก่อน**: operator คือ "ที่อยู่ตรรกะของผู้รับ" ไม่ใช่ user ของ SQL Server — ใช้อีเมลทีม/distribution list เสมอ; พารามิเตอร์ pager/netsend ที่เห็นใน syntax กำลังถูกถอด (email-only)

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Lab10 DBA Team')
    EXEC dbo.sp_delete_operator @name = N'Lab10 DBA Team';

EXEC dbo.sp_add_operator
    @name          = N'Lab10 DBA Team',
    @enabled       = 1,
    @email_address = N'dba-team@fabrikam.example';   -- smtp4dev รับทุกที่อยู่

-- ตั้งเป็น fail-safe operator (ใช้เมื่อ notification ปกติ fail) — proc อยู่ใน master
EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator = N'Lab10 DBA Team',
                                  @notificationmethod = 1;
GO
```

### Step 2 — สร้าง alert: severity 17 + message 1205 (deadlock)

> **ต้องรู้ก่อน**: (a) alert จับเฉพาะข้อความที่ถึง **Windows Application Log** — severity 17 จาก `RAISERROR ... WITH LOG` เข้าถึงจุดนั้นจริง; (b) `@delay_between_responses` กันเมลล้นเมื่อ error ซ้ำถี่; (c) ถ้าใช้ `@message_id` ให้ `@severity = 0` (และกลับกัน) — ดู [Section 3.2](../Sections/03_Operators_Alerts/README.md)

```sql
USE msdb;
GO
-- (A) severity 17 — เหตุการณ์ resource/software ทั่วไป (เช่น log full 9002)
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Lab10 - Severity 17')
    EXEC dbo.sp_delete_alert @name = N'Lab10 - Severity 17';

EXEC dbo.sp_add_alert
    @name                         = N'Lab10 - Severity 17',
    @severity                     = 17,
    @enabled                      = 1,
    @delay_between_responses      = 30,
    @notification_message         = N'Lab10: severity 17 — ตรวจ error log ทันที',
    @include_event_description_in = 1;

EXEC dbo.sp_add_notification
    @alert_name          = N'Lab10 - Severity 17',
    @operator_name       = N'Lab10 DBA Team',
    @notification_method = 1;

-- (B) message 1205 — deadlock victim (โจทย์ทางเลือกของแล็บเดิม)
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Lab10 - Deadlock (1205)')
    EXEC dbo.sp_delete_alert @name = N'Lab10 - Deadlock (1205)';

EXEC dbo.sp_add_alert
    @name                         = N'Lab10 - Deadlock (1205)',
    @message_id                   = 1205,    -- ใช้ message_id => severity = 0
    @enabled                      = 1,
    @delay_between_responses      = 30,
    @include_event_description_in = 1;

EXEC dbo.sp_add_notification
    @alert_name          = N'Lab10 - Deadlock (1205)',
    @operator_name       = N'Lab10 DBA Team',
    @notification_method = 1;
GO
```

✅ **สังเกต**: error 1205 ที่แอปพลิเคชันจับด้วย TRY/CATCH ปกติ **ไม่ถึง Application Log** — alert ตัวนี้จะยิงเฉพาะเมื่อ deadlock ถูกบันทึกเป็นข้อความ log (เช่นจาก RAISERROR 1205 WITH LOG ในทดสอบ หรือ deadlock ที่ engine เขียนเมื่อเกิดพร้อม trace flag) — จึงตั้งให้เห็นโครง แต่ตัวที่ยิงแน่ในขั้นถัดไปคือ severity 17

### Step 3 — กระตุ้น alert ด้วย RAISERROR และตรวจสายงาน

```sql
-- กระตุ้น severity 17 (ต้อง sysadmin หรือ ALTER TRACE เพราะ WITH LOG)
RAISERROR (N'Lab10: simulated severity 17 for alert test.', 17, 1) WITH LOG;
GO
-- กระตุ้น deadlock alert (เหมือนจำลอง victim message):
RAISERROR (1205, 16, 1) WITH LOG;   -- ถึง Application Log จาก WITH LOG เสมอ
GO
```

**Expected:** ภายใน ~10-30 วินาที (Agent ตรวจเป็นระยะ) อีเมลจะถึง smtp4dev สองฉบับ ตรวจยืนยันจากสามจุดตามลำดับสายงาน:

```sql
-- (1) ข้อความถึง Application Log จริงไหม (ต้นสาย):
EXEC xp_readerrorlog 0, 1, N'Lab10: simulated severity 17';

-- (2) Database Mail ส่งสำเร็จไหม:
SELECT TOP 5 mailitem_id, sent_status, subject
FROM msdb.dbo.sysmail_mailitems ORDER BY mailitem_id DESC;

-- (3) Agent log จับ alert แล้วหรือยัง (ปลายสายฝั่ง Agent):
EXEC xp_readerrorlog 0, 2, N'Lab10 - Severity 17';
```

### Step 4 (Optional) — จำลอง log full แบบแล็บเดิม

> **ต้องรู้ก่อน**: แล็บเดิมกระตุ้น error 9002 จริงด้วยการยัดข้อมูลจน log เต็ม — ทำได้บนฐานข้อมูลทดลองเล็กที่จำกัดขนาด log (MAXSIZE) ห้ามทำกับ AdventureWorks2025

```sql
-- สร้าง DB ทดลอง log จำกัด 8MB
USE master;
GO
IF DB_ID(N'Lab10LogFull') IS NULL
    CREATE DATABASE Lab10LogFull;
ALTER DATABASE Lab10LogFull MODIFY FILE (NAME = Lab10LogFull_log, MAXSIZE = 8MB);
GO

USE Lab10LogFull;
GO
IF OBJECT_ID('dbo.t') IS NULL CREATE TABLE dbo.t (c nvarchar(4000));
BEGIN TRY
    WHILE 1 = 1
        INSERT dbo.t (c) SELECT REPLICATE(N'x', 4000);   -- ยัดจน log เต็ม
END TRY
BEGIN CATCH
    PRINT N'Log full caught: ' + CONVERT(nvarchar(20), ERROR_NUMBER());
END CATCH;
GO
-- Expected: error 9002 (transaction log full, severity 17) — alert 'Lab10 - Severity 17'
--           ยิงเพราะ 9002 เขียนลง Application Log เมื่อเกิดจริง
-- (เมื่อจบ: ลบฐานข้อมูลทดลอง — Clean-up)
```

---

## Exercise 3: Job Fail Notification ให้ Job จาก Module 8

### Step 1 — ผูก notification ให้ job `Daily Backup`

> **ต้องรู้ก่อน**: นี่คือต่อจาก Module 8 Exercise 2 — ตอนนั้นเราตั้ง `@notify_level_email = 2` ให้ operator เงียบ ๆ (เมลยังไม่ถึงเพราะ Database Mail ยังไม่มี) ตอนนี้ช่องทางพร้อมแล้ว ให้ระบบทำงานจริงครบวง

```sql
USE msdb;
GO
-- ผูก notification เมื่อ job ล้ม ให้ operator ที่สร้างใน Exercise 2
EXEC dbo.sp_update_job
    @job_name                   = N'Daily Backup',
    @notify_level_email         = 2,     -- แจ้งเมื่อล้ม (1=สำเร็จ 2=ล้ม 3=ทั้งสอง)
    @notify_email_operator_name = N'Lab10 DBA Team';
GO

SELECT j.name, j.notify_level_email, o.name AS operator_name, o.email_address
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysoperators AS o ON o.id = j.notify_email_operator_id
WHERE j.name = N'Daily Backup';
-- Expected: notify_level_email = 2, operator = Lab10 DBA Team
```

### Step 2 — ทำให้ job ล้มโดยจงใจ แล้วดูอีเมล

```sql
USE msdb;
GO
-- ใส่ step ที่พังแน่ ๆ (backup ฐานข้อมูลที่ไม่มีจริง)
EXEC dbo.sp_add_jobstep
    @job_name          = N'Daily Backup',
    @step_name         = N'Deliberate failure (Lab 10)',
    @step_id           = 3,
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = N'BACKUP DATABASE [NoSuchDatabase] TO DISK = N''X:\bad.bak'';',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC dbo.sp_start_job @job_name = N'Daily Backup';
GO
-- รอ 10-20 วินาทีแล้วตรวจ:
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Daily Backup';
-- Expected: run_status = 0 (Failed) เพราะ step 3

SELECT TOP 5 mailitem_id, sent_status, subject, sent_date
FROM msdb.dbo.sysmail_mailitems ORDER BY mailitem_id DESC;
-- Expected: อีเมลการแจ้งเตือน job fail ปรากฏ (subject ระบุ "Failed" + ชื่อ job)
```

**Expected:** สายงานครบวงจรจริงเป็นครั้งแรก: **job ล้ม → Agent เขียน history + ยิง notification → Database Mail ส่งผ่าน SMTP → smtp4dev รับอีเมล** — เปิด UI smtp4dev ดูฉบับเต็มของเมลแจ้งเตือน (มีรายชื่อ step ที่ล้ม + ข้อความ error)

### Step 3 — เก็บกวาด step ทดสอบ

```sql
USE msdb;
GO
EXEC dbo.sp_delete_jobstep @job_name = N'Daily Backup', @step_id = 3;
EXEC dbo.sp_start_job @job_name = N'Daily Backup';    -- ยืนยันว่ากลับมาสำเร็จ
GO
```

---

## 🧹 Clean-up

```sql
USE msdb;
GO
-- 1) ลบ alerts + operator
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Lab10 - Severity 17')
    EXEC dbo.sp_delete_alert @name = N'Lab10 - Severity 17';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Lab10 - Deadlock (1205)')
    EXEC dbo.sp_delete_alert @name = N'Lab10 - Deadlock (1205)';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Severity 17')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Severity 17';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Log Full (9002)')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Log Full (9002)';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - AW2025 Log Used > 90%')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - AW2025 Log Used > 90%';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Deadlock graph (WMI)')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Deadlock graph (WMI)';

EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator = N'', @notificationmethod = 0;
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Lab10 DBA Team')
    EXEC dbo.sp_delete_operator @name = N'Lab10 DBA Team';
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_delete_operator @name = N'Fabrikam DBA Team';
GO

-- 2) เก็บกวาดข้อความ custom จาก Section 1 (ถ้าสร้างไว้)
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50001)
    EXEC dbo.sp_dropmessage @msgnum = 50001;
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50002)
    EXEC dbo.sp_dropmessage @msgnum = 50002;
GO

-- 3) ลบ Database Mail config + ตั้ง Agent profile กลับว่าง
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysmail_profile WHERE name = N'Lab10 DBA Profile')
BEGIN
    EXEC dbo.sysmail_delete_principalprofile_sp @profile_name = N'Lab10 DBA Profile';
    EXEC dbo.sysmail_delete_profileaccount_sp   @profile_name = N'Lab10 DBA Profile';
    EXEC dbo.sysmail_delete_profile_sp          @profile_name = N'Lab10 DBA Profile';
END
IF EXISTS (SELECT 1 FROM dbo.sysmail_account WHERE name = N'Lab10 Mail Account')
    EXEC dbo.sysmail_delete_account_sp @account_name = N'Lab10 Mail Account';
EXEC dbo.sysmail_delete_mailitems_sp @sent_before = GETDATE();   -- ลบเมลทดสอบ

EXEC dbo.sp_set_sqlagent_properties @databasemail_profile = N'';
GO

-- 4) ลบฐานข้อมูลทดลอง (ถ้าทำ Exercise 2 Step 4)
USE master;
GO
IF DB_ID(N'Lab10LogFull') IS NOT NULL
BEGIN
    ALTER DATABASE Lab10LogFull SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Lab10LogFull;
END
GO

-- (Docker) หยุด smtp4dev เมื่อจบแล็บ: docker stop <container-id> (สร้างด้วย --rm)
```

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม RAISERROR severity 17 ต้องใส่ WITH LOG จึง trigger alert ได้?</b></summary>
เพราะ alert engine ของ Agent อ่านเฉพาะข้อความที่เขียนลง <b>Windows Application Log</b> — severity 11-18 ไม่ถูกเขียนเป็น default WITH LOG คือคำสั่งให้เขียน ทางเลือกอื่นคือข้อความ custom ที่ตั้ง @with_log='TRUE' ตั้งแต่ sp_addmessage
</details>

<details>
<summary><b>2. sp_send_dbmail คืน success แต่ผู้รับบอกว่าไม่ได้รับเมล — ตรวจจุดไหนก่อน?</b></summary>
sp_send_dbmail แค่ใส่งานลงคิว (asynchronous) — ตรวจต่อที่ <code>msdb.dbo.sysmail_mailitems</code> (sent_status: 3=failed, 4=retrying) และ <code>sysmail_event_log</code> ที่ระบุคำตอบจาก SMTP server; ถ้า sent_status = 2 แล้วผู้รับไม่เห็น ปัญหาอยู่นอก SQL Server (spam filter / ที่อยู่ผิด)
</details>

<details>
<summary><b>3. Alert severity 17 ยิงถี่มากจนเมลล้น — ปรับค่าไหน?</b></summary>
<code>@delay_between_responses</code> ของ sp_add_alert — ตั้งเป็นวินาที (เช่น 300) ทำให้เหตุการณ์ที่เกิดซ้ำในช่วงเวลานั้นถูกนับแต่ไม่ส่งการแจ้งซ้ำ ตรวจจำนวนครั้งที่เกิดจริงด้วย occurrence_count ของ sysalerts
</details>

<details>
<summary><b>4. ต่างกันอย่างไรระหว่าง "job notification" (Lab 10 Exercise 3) กับ "alert notification" (Exercise 2)?</b></summary>
Job notification ผูกที่ระดับ job (sp_update_job @notify_level_email) — ยิงเมื่อ job จบ/ล้ม; Alert notification ผูกที่ alert (sp_add_notification) — ยิงเมื่อเหตุการณ์ error/metric ตรงเงื่อนไข ต่างชนิดกันทั้งคู่แต่ไปถึง operator เดียวกัน ปฏิบัติที่ดีคือใช้ทั้งสอง: job notification สำหรับงานสำคัญรายตัว + alert สำหรับเหตุการณ์ระดับ server
</details>
