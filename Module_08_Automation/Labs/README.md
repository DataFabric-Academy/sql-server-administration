# Lab 8: Automating SQL Server Management (บทที่ 8)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab08** (Create Jobs / Job History / Multiserver Jobs) + [Microsoft Learn — SQL Server Agent overview](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent), [sp_add_job](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-job-transact-sql?view=sql-server-ver17), [sp_help_jobhistory](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-help-jobhistory-transact-sql?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> **สิ่งที่ปรับจากแล็บเดิม**: แล็บเดิมใช้ฐานข้อมูล `HumanResources` แยก + domain `9EXPERT` + เครื่อง SQL2/SQL3 — เราใช้ **AdventureWorks2025** + instance เดียว (SQL Authentication/local account) และ Exercise 4 (multiserver) เป็น **optional** ที่ใช้ container ที่สอง

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** พร้อมใช้ (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- **SQL Server Agent service รันอยู่** — ตรวจ: `SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server Agent%'`
- รันด้วย login ที่มีสิทธิ์ `sysadmin`
- สร้างโฟลเดอร์เก็บ backup ได้สบาย (แล็บใช้ default backup path ของ instance โดยอัตโนมัติ)
- Exercise 4 (optional): container ที่สอง `sql2025b` port 1434, `sa/Pa$$w0rd2025` (สร้างตาม Module 00 ทางเลือก B)

## Scenario

บริษัท "Fabrikam Retail" มีฐานข้อมูลยอดขายหลัก (`AdventureWorks2025`) ที่เคย backup ด้วยมือทุกเย็น สัปดาห์ก่อนพนักงานลาป่วยสองวันติด ทีมงานก็ไม่ได้ backup กัน หัวหน้าจึงสั่งให้คุณ (DBA) ทำให้ระบบดูแลตัวเอง:

1. Full backup รายคืน + log backup ทุก 15 นาที
2. CHECKDB ตรวจความเสียหายทุกคืน พร้อมแจ้งอีเมลเมื่อพัง
3. มีวิธีพิสูจน์ว่าเมื่องานล้ม ทีมจะรู้ตัวเร็วพอ (โดยจงใจทำให้ job ล้มใน Exercise 3)
4. (Optional) เตรียมกระจาย job ชุดเดียวกันไป server ใหม่ที่กำลังจะมาด้วย MSX/TSX

## Objectives

1. สร้าง job **"Daily Backup"** (full + log backup ทุก 15 นาที) ด้วย `sp_add_job*` ล้วน
2. สร้าง job CHECKDB + notification เมื่อล้ม (operator)
3. จำลอง job ล้มโดยตั้งใจ แล้วอ่าน `msdb.dbo.sysjobhistory` เพื่อหาสาเหตุ
4. (Optional) สร้าง MSX/TSX ด้วย container ที่สอง และกระจาย job

---

## Exercise 1: สร้าง Job "Daily Backup" ด้วย T-SQL

### Step 1 — ยืนยัน recovery model และโฟลเดอร์ backup

> **ต้องรู้ก่อน**: log backup ทำงานได้เฉพาะฐานข้อมูล FULL (หรือ BULK_LOGGED) — AdventureWorks2025 มาจาก .bak แบบ FULL อยู่แล้ว แต่ยืนยันก่อนเสมอ และเราจะอ่านที่อยู่ backup จาก `SERVERPROPERTY('InstanceDefaultBackupPath')` ซึ่งใช้ได้ตั้งแต่ SQL Server 2019 ทำให้สคริปต์ใช้ได้ทั้ง Windows และ container โดยไม่แก้ path

```sql
SELECT name, recovery_model_desc
FROM sys.databases WHERE name = N'AdventureWorks2025';
-- Expected: FULL — ถ้าเป็น SIMPLE รัน: ALTER DATABASE AdventureWorks2025 SET RECOVERY FULL;

SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260)) AS backup_path;
-- Expected: path เช่น C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Backup
--          หรือ /var/opt/mssql/data บน container — แล็บจะใช้ path นี้โดยอัตโนมัติ
```

### Step 2 — สร้าง job + step full backup

> **ต้องรู้ก่อน**: `sp_add_job` สร้างกล่องงาน, `sp_add_jobstep` ใส่งานย่อย, `sp_add_jobserver` ลงทะเบียนให้รันบน server นี้ — **ลืมขั้นสุดท้าย = job มีอยู่แต่รันไม่ได้** เป็นข้อผิดพลาดคลาสสิก (ดู [Section 2](../Sections/02_Agent_Jobs/README.md))

```sql
USE msdb;
GO

-- ลบ job เดิมถ้ามี (ทำให้แล็บรันซ้ำได้)
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Daily Backup')
    EXEC dbo.sp_delete_job @job_name = N'Daily Backup',
                           @delete_unused_schedule = 1;

DECLARE @jobId BINARY(16);
DECLARE @BackupDir nvarchar(260) =
    CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));
IF RIGHT(@BackupDir, 1) NOT IN (N'\', N'/')
    SET @BackupDir = @BackupDir + CASE
        WHEN @BackupDir LIKE N'%/%' AND @BackupDir NOT LIKE N'%\%' THEN N'/'
        ELSE N'\' END;

EXEC dbo.sp_add_job
    @job_name              = N'Daily Backup',
    @enabled               = 1,
    @description           = N'Lab 8 — Full backup รายคืน + log backup ทุก 15 นาที (AdventureWorks2025)',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',
    @notify_level_eventlog = 2,
    @job_id                = @jobId OUTPUT;

-- Step 1: Full backup — ไฟล์แยกตามวันที่ (YYYYMMDD) เพื่อเก็บหลายรุ่น
DECLARE @fullCmd nvarchar(max) = N'
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N''' + @BackupDir + N'AdventureWorks2025_Full_'
    + CONVERT(nvarchar(8), GETDATE(), 112) + N'.bak''
WITH COMPRESSION, CHECKSUM, STATS = 5;';

EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'Full backup AdventureWorks2025',
    @step_id           = 1,
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = @fullCmd,
    @on_success_action = 3,        -- ไป step ถัดไป
    @on_fail_action    = 2;

-- Step 2: Log backup ทุก 15 นาที — append เข้าไฟล์ประจำวัน (ไม่ใช้ INIT เพื่อคง log chain)
DECLARE @logCmd nvarchar(max) = N'
BACKUP LOG [AdventureWorks2025]
TO DISK = N''' + @BackupDir + N'AdventureWorks2025_Log_'
    + CONVERT(nvarchar(8), GETDATE(), 112) + N'.trn''
WITH CHECKSUM, STATS = 5;';

EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'Log backup AdventureWorks2025',
    @step_id           = 2,
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = @logCmd,
    @on_success_action = 1,        -- จบ job แบบสำเร็จ
    @on_fail_action    = 2;

-- ลงทะเบียนให้รันบน server นี้ (ต้องมีเสมอ!)
EXEC dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';
GO
```

✅ **สังเกต**: step log backup รันแล้วจะ **error ทันทีถ้ายังไม่เคยมี full backup** — โมเดล FULL ต้องมี full backup เป็นจุดตั้งต้นของ log chain (Module 6) จึงออกแบบ flow เป็น full → log ใน job เดียวกัน

### Step 3 — สร้าง schedule ทั้งสองแบบ

> **ต้องรู้ก่อน**: `@freq_type = 4` = รายวัน, `@freq_subday_type = 4` + `@freq_subday_interval = 15` = ทุก 15 นาทีในหนึ่งวัน — job เดียวผูกได้หลาย schedule และทุก schedule ยิง job ซ้ำกันได้ (ดู [Section 2.4](../Sections/02_Agent_Jobs/README.md))

```sql
USE msdb;
GO
-- Schedule A: ทุกคืน 23:00 (สำหรับ step full backup)
EXEC dbo.sp_add_jobschedule
    @job_name          = N'Daily Backup',
    @name              = N'Nightly 23:00',
    @enabled           = 1,
    @freq_type         = 4,
    @freq_interval     = 1,
    @freq_subday_type  = 1,
    @active_start_time = 230000,
    @active_end_date   = 99991231;

-- Schedule B: ทุก 15 นาที (สำหรับ step log backup)
EXEC dbo.sp_add_jobschedule
    @job_name               = N'Daily Backup',
    @name                   = N'Log backup every 15 min',
    @enabled                = 1,
    @freq_type              = 4,
    @freq_interval          = 1,
    @freq_subday_type       = 4,      -- 4 = ทุก x นาที
    @freq_subday_interval   = 15,
    @active_start_time      = 000000, -- เริ่ม 00:00
    @active_end_time        = 235959;
GO
```

**Expected:** ตรวจใน SSMS (SQL Server Agent → Jobs → Daily Backup) จะเห็น 2 steps + 2 schedules — schedule ทั้งสองจะทริกเกอร์ **job ทั้งตัว** (เริ่ม step 1 เสมอ) ซึ่งพอใช้ได้เพราะ full backup ซ้ำในวันเดียวกันเขียนทับไฟล์วันเดียวกันที่ `INIT`... จริง ๆ เราไม่ได้ใส่ INIT สำหรับแบบถูกต้องใน production ให้แยกเป็น **สอง job**: job full (schedule รายคืน) และ job log (schedule ทุก 15 นาที) — รู้ไว้ใช่ว่าเรียนไว้ก่อน ขั้นถัดไปจะรันด้วยมือเพื่อหลบเรื่อง schedule ครับ

### Step 4 — รันด้วยมือและตรวจผล

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Daily Backup';
GO
-- รอ 10-20 วินาที (backup ขนาดเล็กใช้เวลาไม่นาน) แล้วตรวจ:
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Daily Backup';
-- Expected: run_status = 1 (Succeeded) 2 แถว (แถว job สรุป + แถว step)

SELECT bs.database_name, bs.type, bs.backup_start_date, bs.is_compressed, bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'AdventureWorks2025'
ORDER BY bs.backup_finish_date DESC;
-- Expected: type='D' (full) และ type='L' (log) ล่าสุด
```

**Expected:** ไฟล์ `AdventureWorks2025_Full_<วันที่>.bak` และ `..._Log_<วันที่>.trn` ปรากฏใน default backup path — เปิดโฟลเดอร์ดูได้เพื่อพิสูจน์ว่าไฟล์จริงเกิดขึ้น

---

## Exercise 2: Job CHECKDB + Notification เมื่อล้ม

> **เชื่อมโยงกับ Module 10**: notification ทางอีเมลต้องพึ่ง **Database Mail** + **operator** ซึ่งเป็นเนื้อหาหลักของ Module 10 — ในแล็บนี้เราจะสร้าง operator แบบ minimal เพื่อให้การตั้งค่า notification สำเร็จ (ระบบเก็บ config ไว้แล้วส่งได้จริงเมื่อตั้ง Database Mail เสร็จใน Module 10) ถ้ารันเลย Module 10 ให้กลับมาทดสอบอีเมลอีกรอบ

### Step 1 — สร้าง operator แบบ minimal

```sql
USE msdb;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_add_operator
        @name          = N'Fabrikam DBA Team',
        @enabled       = 1,
        @email_address = N'dba-team@fabrikam.example';
GO
-- (อีเมลจริงจะส่งได้เมื่อตั้ง Database Mail ใน Module 10 — Lab 10 Exercise 1)
```

### Step 2 — สร้าง CHECKDB job

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Weekly CHECKDB AdventureWorks2025')
    EXEC dbo.sp_delete_job @job_name = N'Weekly CHECKDB AdventureWorks2025',
                           @delete_unused_schedule = 1;

DECLARE @jobId BINARY(16);
EXEC dbo.sp_add_job
    @job_name              = N'Weekly CHECKDB AdventureWorks2025',
    @enabled               = 1,
    @description           = N'Lab 8 — ตรวจความสมบูรณ์ข้อมูล + แจ้งอีเมลเมื่อล้ม',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',
    @notify_level_eventlog = 2,
    @job_id                = @jobId OUTPUT;

EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'CHECKDB PHYSICAL_ONLY',
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = N'DBCC CHECKDB (N''AdventureWorks2025'') WITH NO_INFOMSGS, PHYSICAL_ONLY, TABLOCK;',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';
GO
```

### Step 3 — ผูก notification เมื่อล้ม + schedule

```sql
USE msdb;
GO
EXEC dbo.sp_update_job
    @job_name                   = N'Weekly CHECKDB AdventureWorks2025',
    @notify_level_email         = 2,        -- แจ้งเมื่อล้ม
    @notify_email_operator_name = N'Fabrikam DBA Team';

EXEC dbo.sp_add_jobschedule
    @job_name          = N'Weekly CHECKDB AdventureWorks2025',
    @name              = N'Sunday 02:00',
    @enabled           = 1,
    @freq_type         = 8,          -- Weekly
    @freq_interval     = 1,          -- 1 = วันอาทิตย์ (บิต: 1=อา 2=จ 4=อ 8=พ 16=พฤ 32=ศ 64=ส)
    @freq_recurrence_factor = 1,
    @freq_subday_type  = 1,
    @active_start_time = 020000;
GO
```

### Step 4 — รันทดสอบและตรวจ notification config

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Weekly CHECKDB AdventureWorks2025';
GO
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Weekly CHECKDB AdventureWorks2025';
-- Expected: run_status = 1

SELECT j.name, j.notify_level_email, o.name AS operator_name, o.email_address
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysoperators AS o ON o.id = j.notify_email_operator_id
WHERE j.name = N'Weekly CHECKDB AdventureWorks2025';
-- Expected: notify_level_email = 2 + operator = Fabrikam DBA Team
```

**Expected:** config ครบ — อีเมลจะถึงจริงหลังตั้ง Database Mail (Lab 10) และตั้ง mail profile ให้ Agent แล้ว; ก่อนหน้านั้น notification ถูก "คิวไว้" ใน config เงียบ ๆ

---

## Exercise 3: จำลอง Job ล้ม และอ่าน sysjobhistory

> **ต้องรู้ก่อน**: `sysjobhistory` บันทึก error ที่ step ที่ล้ม (คอลัมน์ `message`) — สถานะระดับ job (`step_id = 0`) สรุปทั้งงาน การทำให้ job ล้มโดยจงใจคือวิธีฝึก troubleshoot ที่ปลอดภัยที่สุด (ดู [Section 3.1](../Sections/03_Job_Management/README.md))

### Step 1 — ใส่ step ที่จะพังแน่ ๆ ให้ job Daily Backup

```sql
USE msdb;
GO
-- Step 3: backup ฐานข้อมูลที่ไม่มีอยู่จริง — error 911 ชัดเจน
EXEC dbo.sp_add_jobstep
    @job_name          = N'Daily Backup',
    @step_name         = N'Deliberate failure (Lab 8 Ex3)',
    @step_id           = 3,
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = N'BACKUP DATABASE [NoSuchDatabase] TO DISK = N''X:\bad.bak'';',
    @on_success_action = 1,
    @on_fail_action    = 2;
GO
```

### Step 2 — รันให้ล้ม แล้วอ่าน history

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Daily Backup';
GO
-- รอ ~10 วินาที แล้วรัน:
SELECT j.name AS job_name, h.step_id, s.step_name,
       h.run_date, h.run_time, h.run_duration,
       CASE h.run_status WHEN 0 THEN N'Failed' WHEN 1 THEN N'Succeeded'
                         WHEN 2 THEN N'Retry' WHEN 3 THEN N'Canceled'
                         WHEN 4 THEN N'In progress' ELSE N'?' END AS status,
       h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
LEFT JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = h.job_id AND s.step_id = h.step_id
WHERE j.name = N'Daily Backup'
ORDER BY h.instance_id DESC;
```

**Expected:** แถว `step_id = 3` สถานะ **Failed** พร้อมข้อความประมาณ *"Database 'NoSuchDatabase' does not exist. BACKUP DATABASE is terminating abnormally"* — และแถวสรุปของ job (`step_id = 0`) ก็จะ Failed ด้วย (แถว step 1-2 ยัง Succeeded เพราะรันผ่านก่อนเจอ step ที่พัง)

### Step 3 — อ่านผ่าน proc และลบ step ทิ้ง

```sql
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Daily Backup', @mode = 'FULL';
-- สังเกตคอลัมน์ message ของ step 3 — นี่คือจุดแรกเสมอเวลา troubleshoot job จริง

-- เก็บกวาด step ทดสอบออกจาก job
EXEC msdb.dbo.sp_delete_jobstep
    @job_name = N'Daily Backup',
    @step_id  = 3;
GO
-- รัน job ซ้ำเพื่อยืนยันว่ากลับมาสำเร็จ:
EXEC msdb.dbo.sp_start_job @job_name = N'Daily Backup';
```

**Expected:** job กลับมา `run_status = 1` — และข้อสังเกตสำคัญ: **history retention แบบ default (1,000 แถว/100 แถวต่อ job)** ทำให้งานถี่ ๆ เก็บประวัติน้อย ลองตั้งเพิ่มตาม Section 3.4 ด้วย `sp_set_sqlagent_properties @jobhistory_max_rows = 10000, @jobhistory_max_rows_per_job = 1000;` แล้วรัน `sp_help_jobhistory` เทียบจำนวนแถวที่เห็น

---

## Exercise 4 (Optional): MSX/TSX ด้วย Container ที่สอง

> **แบรนด์ "optional"** — Exercise นี้ต้องมี instance สองตัว (container `sql2025b` port 1434) และต้องจัดการ certificate สำหรับการเชื่อมต่อ MSX↔TSX ที่เปิด TLS มาให้ default ในห้องเรียนถ้ายังไม่มี certificate ให้ทำได้ถึงขั้นที่ 2 เพื่อดูกลไก แล้วจดว่า "งานจริงต้องจัดการ cert" ก็เพียงพอ (เทียบเคียง dbatools ใน [Section 4.7](../Sections/04_Multiserver_Jobs/README.md) และ error ที่พบใน [Section 4.5](../Sections/04_Multiserver_Jobs/README.md))

### Step 1 — เตรียม MSX (บน container หลัก sql2025)

```sql
USE msdb;
GO
-- MSX ต้องมี operator ชื่อ MSXOperator ก่อนรับ enlistment (ไม่มี = error 14363)
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'MSXOperator')
    EXEC dbo.sp_add_operator
        @name = N'MSXOperator', @enabled = 1,
        @email_address = N'dba-team@fabrikam.example';
GO
```

### Step 2 — ตรวจสถานะก่อน enlist

```sql
-- บน MSX: ยังไม่มี target server
EXEC msdb.dbo.sp_help_targetserver;
-- Expected: ผลลัพธ์ว่าง

-- บน TSX (sql2025b): ยังไม่มี job ที่มาจาก MSX
SELECT name, originating_server_id FROM msdb.dbo.sysjobs
WHERE originating_server_id <> 0;
-- Expected: ว่าง
```

### Step 3 — Enlist TSX ไปยัง MSX (รันบน sql2025b)

```sql
-- บน container sql2025b (TSX) — แก้ host/port ของ MSX ตามสภาพแวดล้อมจริง
-- (host.docker.internal,1433 ใช้เมื่อ MSX คือ container บน host เดียวกัน)
USE msdb;
GO
EXEC dbo.sp_msx_enlist
    @msx_server_name = N'host.docker.internal,1433',
    @location        = N'Lab container sql2025b';
GO
```

**Expected:** ถ้ามี certificate ครบ — สำเร็จและ `sp_help_targetserver` บน MSX เห็น sql2025b; ถ้ายังไม่มี certificate จะเจอ error เกี่ยวกับ TLS/trust — จดไว้ว่างานจริงต้องเตรียม certificate (ดู [Section 4.2](../Sections/04_Multiserver_Jobs/README.md)) แล้วข้ามไป Step 6 เพื่อ defect/clean-up

### Step 4 — สร้าง job ที่ MSX แล้วกระจาย (บน sql2025)

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fleet - Daily user DB backup')
    EXEC dbo.sp_delete_job @job_name = N'Fleet - Daily user DB backup',
                           @delete_unused_schedule = 1;

EXEC dbo.sp_add_job @job_name = N'Fleet - Daily user DB backup', @enabled = 1;
EXEC dbo.sp_add_jobstep
    @job_name = N'Fleet - Daily user DB backup', @step_name = N'Backup',
    @subsystem = N'TSQL', @database_name = N'master',
    @command = N'BACKUP DATABASE [AdventureWorks2025] TO DISK = N''AW_Fleet.bak'' WITH COMPRESSION;';

EXEC dbo.sp_add_jobschedule
    @job_name = N'Fleet - Daily user DB backup', @name = N'Nightly 23:30',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 1,
    @active_start_time = 233000;

-- กระจายไป TSX (แก้ชื่อ target ให้ตรงชื่อที่ปรากฏใน sp_help_targetserver)
EXEC dbo.sp_apply_job_to_targets
    @job_name       = N'Fleet - Daily user DB backup',
    @target_servers = N'sql2025b',
    @operation      = N'APPLY';
GO

-- ตรวจคิวคำสั่งรอ TSX ดึง:
EXEC msdb.dbo.sp_help_downloadlist @job_name = N'Fleet - Daily user DB backup';
-- Expected: แถวคำสั่ง (ENLIST/INSERT_JOB...) — TSX จะมาดึงตาม polling interval
```

### Step 5 — ตรวจฝั่ง TSX (บน sql2025b)

```sql
-- job จะถูก "ดาวน์โหลด" มาปรากฏบน TSX (ให้เวลา polling ~1 นาที)
SELECT name, originating_server_id, date_created FROM msdb.dbo.sysjobs
WHERE name = N'Fleet - Daily user DB backup';
-- Expected: job มีอยู่บน TSX; แก้/ลบที่ TSX โดยตรงไม่ได้ (นิยามอยู่ที่ MSX)

-- รันมือบน TSX แล้วกลับไปดู history รวมที่ MSX:
EXEC msdb.dbo.sp_start_job @job_name = N'Fleet - Daily user DB backup';
```

### Step 6 — Defect + Clean-up (รันเมื่อจบแล็บ)

```sql
-- บน TSX (sql2025b): ถอนตัวจาก MSX
USE msdb;
GO
EXEC dbo.sp_msx_defect;
GO

-- บน MSX: ลบ target + job fleet ทิ้ง
USE msdb;
GO
EXEC dbo.sp_delete_targetserver @server_name = N'sql2025b', @post_defection = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fleet - Daily user DB backup')
    EXEC dbo.sp_delete_job @job_name = N'Fleet - Daily user DB backup',
                           @delete_unused_schedule = 1;
GO
```

---

## 🧹 Clean-up

ล้างของที่แล็บสร้างทั้งหมด (ยกเว้น operator — เก็บไว้ใช้ใน Module 10 ได้):

```sql
USE msdb;
GO
-- 1) ลบ jobs ของแล็บ (delete_unused_schedule จะลบ schedule ที่ไม่ถูกใช้ต่อด้วย)
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Daily Backup')
    EXEC dbo.sp_delete_job @job_name = N'Daily Backup',
                           @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Weekly CHECKDB AdventureWorks2025')
    EXEC dbo.sp_delete_job @job_name = N'Weekly CHECKDB AdventureWorks2025',
                           @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Demo Job')
    EXEC dbo.sp_delete_job @job_name = N'Fabrikam - Demo Job',
                           @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Maintenance (Ola pattern)')
    EXEC dbo.sp_delete_job @job_name = N'Fabrikam - Maintenance (Ola pattern)',
                           @delete_unused_schedule = 1;

-- 2) ล้างประวัติ backup ของแล็บใน msdb (ไฟล์ .bak/.trn จริงอยู่ใน default path — ลบเองได้)
EXEC dbo.sp_delete_database_backuphistory @database_name = N'AdventureWorks2025';
GO
```

**หมายเหตุ**: `sp_delete_database_backuphistory` ลบแค่บันทึกใน msdb ไม่ใช่ไฟล์ backup จริง — ไฟล์ที่แล็บสร้าง (ราว 30–60 MB) ลบจากโฟลเดอร์ backup ได้เมื่อต้องการ

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไมต้องรัน sp_add_jobserver ทุกครั้งที่สร้าง job ด้วยสคริปต์?</b></summary>
เพราะ sp_add_job สร้าง "นิยาม" เท่านั้น — sp_add_jobserver @server_name = N'(local)' คือการลงทะเบียนว่า Agent ของ server นี้รัน job นี้ ถ้าขาด จะเจอข้อความว่า job ไม่ถูก target ไว้ที่ server ใด (ในระบบ multiserver job กลับไม่เรียกตัวนี้ แต่ใช้ sp_apply_job_to_targets แทน)
</details>

<details>
<summary><b>2. Log backup job ล้มด้วย error "BACKUP LOG cannot be performed because there is no current database backup" — ต้นเหตุคืออะไร?</b></summary>
ฐานข้อมูล FULL recovery แต่ยังไม่เคยมี full backup เลย (หรือเพิ่งเปลี่ยนจาก SIMPLE มา) — log chain ต้องมี full backup เป็นต้นทาง แก้โดยรัน full backup ก่อน และออกแบบ job ให้ full ทำงานก่อน log เสมอ
</details>

<details>
<summary><b>3. หลังเพิ่ม schedule "ทุก 15 นาที" ให้ job เดียวกับ "รายคืน 23:00" จะเกิดอะไรขึ้นเวลา 23:00?</b></summary>
ทุก schedule ทริกเกอร์ "job ทั้งตัว" ตั้งแต่ start step — งานจะทำ full backup ซ้ำระหว่างวันด้วย วิธีถูกต้องคือแยกเป็นสอง job (full / log) ให้แต่ละ job มี schedule ของตัวเอง — แล็บตั้งใจให้เห็นข้อจำกัดนี้เพื่อสอน
</details>

<details>
<summary><b>4. ทำไม job history ของ job อื่นหายไปหลังเริ่มรัน log backup ทุก 15 นาที?</b></summary>
ค่า default ของ job history คือ 1,000 แถวรวม และ 100 แถวต่อ job — log backup สร้าง ~96 แถว/วัน จะกินโควตาและผลักประวัติอื่นออก แก้ด้วย sp_set_sqlagent_properties @jobhistory_max_rows/@jobhistory_max_rows_per_job
</details>
