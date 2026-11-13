# Lab 9: Implementing SQL Server Agent Security (บทที่ 9)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab09** (Exercise 1–2: Job security context / Credentials & Proxies) + [Microsoft Learn — Implement SQL Server Agent security](https://learn.microsoft.com/sql/ssms/agent/implement-sql-server-agent-security), [SQL Server Agent fixed database roles](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent-fixed-database-roles), [CREATE CREDENTIAL](https://learn.microsoft.com/sql/t-sql/statements/create-credential-transact-sql?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> **สิ่งที่ปรับจากแล็บเดิม**: แล็บเดิมใช้ domain `9EXPERT` + Windows account `9EXPERT\ExtractUser` + ฐานข้อมูล InternetSales/SSIS package — เราใช้ **SQL Authentication + Windows local account** (ไม่ต้องมี Active Directory) และฐานข้อมูลทดลอง `LabEnv` ที่สคริปต์สร้างเอง

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** พร้อมใช้ (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- **SQL Server Agent รันอยู่** และรันด้วย login ที่มีสิทธิ์ `sysadmin`
- รันสคริปต์เดโมของ Section 1–3 มาก่อนจะช่วยให้จับไอเดีย แต่แล็บนี้สร้างของใหม่ให้เอง ไม่ต้องพึ่งสคริปต์เดโม
- **Windows เท่านั้น** สำหรับ Exercise 2 (proxy สำหรับ CmdExec ต้องห่อ Windows account) — บน Linux/container ให้ทำ Exercise 1 และอ่านผ่านของ Exercise 2

## Scenario

ทีม Analytics ของ Fabrikam ขอสิทธิ์สร้าง job ของตัวเอง (แล้วจะมาอีเมลให้ทีม DBA ตั้ง schedule ให้เองทุกครั้ง) และขอรัน script ที่ copy ไฟล์ export ไปยังโฟลเดอร์แชร์ของทีมผ่าน Agent ด้วย คุณเป็น DBA ต้อง: (1) มอบสิทธิ์สร้าง job ให้แบบ least privilege และให้พวกเขาเจอข้อจำกัดของจริงด้วยตนเอง, (2) จัดสิทธิ์ OS ที่จำเป็นด้วย credential + proxy โดยไม่ยก sysadmin ให้ใครเลย

## Objectives

1. มอบสิทธิ์ Agent ให้ login ทดสอบด้วย `SQLAgentUserRole` แล้วทดลองสร้าง job ด้วย login นั้น เพื่อสังเกตข้อจำกัดของจริง (บริบทการรัน, CmdExec, การมองเห็น)
2. สร้าง **credential** ที่ห่อ Windows local account + **proxy** ผูกกับ subsystem CmdExec และมอบให้ login ทดสอบ
3. สร้าง job step ที่รันด้วย proxy และทดสอบข้อผิดพลาดเมื่อสิทธิ์ไม่ครบ

---

## Exercise 1: มอบสิทธิ์ Agent ให้ Login ทดสอบ — แล้วให้เขาลองเอง

### Step 1 — เตรียมสภาพแวดล้อมทดลอง

> **ต้องรู้ก่อน**: `LabEnv` คือฐานข้อมูลทดลองที่สคริปต์นี้สร้างเอง มีตาราง log ที่บันทึก `SYSTEM_USER` — เป็นวิธีพิสูจน์บริบทการรันที่เห็นผลทันที (ดู [Section 1.5](../Sections/01_Agent_Security_Context/README.md))

```sql
USE master;
GO
-- ล้างของแล็บเดิม (รันซ้ำได้)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Lab09 Lab - Identity Test')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Lab09 Lab - Identity Test',
                                @delete_unused_schedule = 1;
GO
IF DB_ID(N'LabEnv') IS NOT NULL
BEGIN
    ALTER DATABASE LabEnv SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LabEnv;
END
GO
CREATE DATABASE LabEnv;
GO

USE LabEnv;
GO
CREATE TABLE dbo.AgentIdentityLog
(
    LogID         int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    LogTime       datetime2 NOT NULL DEFAULT SYSDATETIME(),
    RunAsIdentity sysname   NOT NULL
);

CREATE PROCEDURE dbo.RecordAgentIdentity
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AgentIdentityLog (RunAsIdentity) SELECT SYSTEM_USER;
END
GO
```

### Step 2 — สร้าง login ทดสอบ + มอบ SQLAgentUserRole

```sql
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Lab09JobUser')
    DROP LOGIN Lab09JobUser;
CREATE LOGIN Lab09JobUser
    WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO

USE msdb;
GO
CREATE USER Lab09JobUser FOR LOGIN Lab09JobUser;
ALTER ROLE SQLAgentUserRole ADD MEMBER Lab09JobUser;   -- สิทธิ์ Agent น้อยที่สุด

USE LabEnv;
GO
CREATE USER Lab09JobUser FOR LOGIN Lab09JobUser;
GRANT INSERT ON dbo.AgentIdentityLog TO Lab09JobUser;   -- เฉพาะที่จำเป็น
GRANT EXECUTE ON dbo.RecordAgentIdentity TO Lab09JobUser;
GO
```

✅ **สังเกต**: สิทธิ์ที่ให้มี 4 ชิ้นเท่านั้น — Agent role ใน msdb, user ใน LabEnv, INSERT ตาราง log, EXECUTE proc — ทั้งหมดพอสำหรับงานเดียวของทีม

### Step 3 — สร้าง job ด้วย login ทดสอบ (ในบริบทของเขา)

> **ต้องรู้ก่อน**: มีสองวิธี "รันคำสั่งในฐานะ Lab09JobUser" — แบบจริงคือเปิด SSMS connection ใหม่ด้วย SQL Authentication (`Lab09JobUser`/`Pa$$w0rd2025`); แบบเร็วใน session เดียวคือ `EXECUTE AS LOGIN` ซึ่งทำได้เมื่อคุณเป็น sysadmin — แล็บใช้แบบเร็ว

```sql
USE msdb;
GO
EXECUTE AS LOGIN = N'Lab09JobUser';
GO

-- (1) สร้าง job ของตัวเอง — ควรสำเร็จ
EXEC dbo.sp_add_job @job_name = N'Lab09 Lab - Identity Test', @enabled = 1;

-- (2) สร้าง step T-SQL ของตัวเอง — ควรสำเร็จ
EXEC dbo.sp_add_jobstep
    @job_name          = N'Lab09 Lab - Identity Test',
    @step_name         = N'Record identity',
    @subsystem         = N'TSQL',
    @database_name     = N'LabEnv',
    @command           = N'EXEC dbo.RecordAgentIdentity;',
    @on_success_action = 1,
    @on_fail_action    = 2;

-- (3) ลองให้ job เจ้าขอนเป็น sa — ควร ERROR
EXEC dbo.sp_add_job
    @job_name = N'Lab09 Lab - Not mine', @enabled = 1,
    @owner_login_name = N'sa';
GO
-- Expected: (3) error — สมาชิก SQLAgentUserRole เปลี่ยนเจ้าขอนไม่ได้

-- (4) ลองสร้าง step CmdExec โดยไม่มี proxy — ควร ERROR
EXECUTE AS LOGIN = N'Lab09JobUser';
EXEC dbo.sp_add_jobstep
    @job_name = N'Lab09 Lab - Identity Test',
    @step_name = N'Try CmdExec',
    @subsystem = N'CMDEXEC',
    @command   = N'echo test';
REVERT;
GO
-- Expected: error แจ้งว่าไม่มี proxy สำหรับ subsystem CMDEXEC
-- (นี่คือเหตุผลที่ต้องมี Exercise 2)

-- (5) ลองมองเห็น job ของ sysadmin — จะไม่เห็นเลย
EXECUTE AS LOGIN = N'Lab09JobUser';
SELECT name FROM dbo.sysjobs WHERE name = N'syspolicy_purge_history';  -- ลองเทียบ job ระบบ
REVERT;
GO
-- Expected: แถวนี้ job ของ sysadmin ไม่แสดงผลลัพธ์ที่เป็นของทุกคนสำหรับ UserRole
-- (SQLAgentUserRole เห็นเฉพาะ job ที่ตนเองเป็นเจ้าขอน)
```

### Step 4 — รัน job ของ user และตรวจบริบทการรัน

```sql
USE msdb;
GO
-- sysadmin ช่วยลงทะเบียนให้รันบน server (จำเป็นทุก job)
EXEC dbo.sp_add_jobserver @job_name = N'Lab09 Lab - Identity Test',
                          @server_name = N'(local)';
EXEC dbo.sp_start_job @job_name = N'Lab09 Lab - Identity Test';
GO
-- รอ 5-10 วินาที แล้ว:
USE LabEnv;
SELECT LogTime, RunAsIdentity FROM dbo.AgentIdentityLog ORDER BY LogID;
-- Expected: RunAsIdentity = 'Lab09JobUser'  — เจ้าขอนไม่ใช่ sysadmin
--           จึงรันในบริบทของตัวเอง (ต่างจาก job เจ้าขอน sa ที่ได้ NT SERVICE\SQLSERVERAGENT)
```

**Expected:** คุณได้พิสูจน์กฎสามข้อพร้อมกัน: สร้าง job ของตัวเองได้, แตะ subsystem นอก T-SQL ไม่ได้, รันในบริบทตัวเอง — เปรียบเทียบกันชัดเจนถ้ารันเดโมของ Section 1 (`01_Agent_Roles_Job_Owner.sql`) ซึ่งมี job เจ้าขอน sysadmin ให้เทียบ

---

## Exercise 2: Credential + Proxy สำหรับ CmdExec

### Step 1 — สร้าง Windows local account (Windows เท่านั้น)

> **ต้องรู้ก่อน**: proxy ต้องมี **credential** ที่ห่อ **Windows account ที่มีอยู่จริง** — แล็บเดิมใช้ domain account เราใช้ local account แทน สร้างใน Command Prompt (Run as Administrator) หรือ `lusrmgr.msc`:

```bat
net user FileOps Pa$$w0rd2025 /add
```

✅ **สังเกต**: แทนชื่อเครื่องตอนอ้าง account ใน SQL Server ด้วย `MACHINE\FileOps` (เช่น `LABPC1\FileOps`) — ตรวจชื่อเครื่องด้วย `SELECT @@SERVERNAME` หรือ `hostname` ใน cmd; หรือดึงจาก T-SQL: `SELECT @@SERVERNAME`

### Step 2 — สร้าง credential

```sql
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'FileOperation')
    DROP CREDENTIAL FileOperation;

CREATE CREDENTIAL FileOperation
    WITH IDENTITY = N'MACHINE\FileOps',   -- แทน MACHINE ด้วยชื่อเครื่องจริง
         SECRET   = N'Pa$$w0rd2025';

SELECT name, identity_desc FROM sys.credentials
WHERE name = N'FileOperation';
-- Expected: 1 แถว (SECRET ไม่แสดงใน catalog ตามหลักความปลอดภัย)
```

**Expected:** ถ้ารันบน Linux ขั้นนี้จะสร้างได้ แต่ใช้จริงกับ CmdExec ไม่ได้ — ให้จดว่า proxy-CmdExec เป็นฟีเจอร์ฝั่ง Windows

### Step 3 — สร้าง proxy + ผูก subsystem + มอบ login

> **ต้องรู้ก่อน**: `sp_grant_proxy_to_subsystem` รับ `@subsystem_id` — เราไม่เดา id แต่อ่านจาก `msdb.dbo.syssubsystems` ด้วยรหัส `CMDEXEC` (ดู [Section 3.2](../Sections/03_Proxies/README.md))

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysproxies WHERE name = N'FileOp')
    EXEC dbo.sp_delete_proxy @proxy_name = N'FileOp';

EXEC dbo.sp_add_proxy
    @proxy_name      = N'FileOp',
    @credential_name = N'FileOperation',
    @enabled         = 1;

DECLARE @cmdexecId int =
    (SELECT subsystem_id FROM dbo.syssubsystems WHERE subsystem = N'CMDEXEC');
EXEC dbo.sp_grant_proxy_to_subsystem
    @proxy_name   = N'FileOp',
    @subsystem_id = @cmdexecId;

EXEC dbo.sp_grant_login_to_proxy
    @proxy_name = N'FileOp',
    @login_name = N'Lab09JobUser';
GO

SELECT p.name AS proxy_name, c.name AS credential_name, c.identity_desc
FROM dbo.sysproxies AS p JOIN sys.credentials AS c ON c.credential_id = p.credential_id
WHERE p.name = N'FileOp';
-- Expected: FileOp / FileOperation / MACHINE\FileOps
```

### Step 4 — Job step ที่รันด้วย proxy (ทำทุกอย่างให้ครบก่อน)

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 Lab - Export via proxy')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 Lab - Export via proxy',
                           @delete_unused_schedule = 1;

EXEC dbo.sp_add_job @job_name = N'Lab09 Lab - Export via proxy',
    @enabled = 1, @owner_login_name = N'Lab09JobUser';

EXEC dbo.sp_add_jobstep
    @job_name       = N'Lab09 Lab - Export via proxy',
    @step_name      = N'Export file (as MACHINE\FileOps)',
    @subsystem      = N'CMDEXEC',
    @command        = N'echo %USERNAME% > %TEMP%\lab09_proxy_test.txt && type %TEMP%\lab09_proxy_test.txt',
    @proxy_name     = N'FileOp',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC dbo.sp_update_job @job_name = N'Lab09 Lab - Export via proxy', @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_name = N'Lab09 Lab - Export via proxy',
                          @server_name = N'(local)';

EXEC dbo.sp_start_job @job_name = N'Lab09 Lab - Export via proxy';
GO
-- รอ 5-10 วินาที:
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Lab09 Lab - Export via proxy', @mode = 'FULL';
-- Expected (Windows): run_status = 1 และ output แสดง "FileOps" = บริบทของ account ใน credential
```

### Step 5 — ทดสอบ error เมื่อไม่มีสิทธิ์

> **ต้องรู้ก่อน**: วิธี "ตัดสิทธิ์แล้วดูว่าพังตรงไหน" คือวิธีที่ดีที่สุดในการจำตำแหน่งของกลไกแต่ละชิ้น — ทำทีละชั้น: revoke login → ลอง; revoke subsystem → ลอง

```sql
USE msdb;
GO
-- (A) ตัดสิทธิ์ login ใช้ proxy แล้วลองสร้าง step ใหม่
EXEC dbo.sp_revoke_login_from_proxy @proxy_name = N'FileOp',
                                    @login_name = N'Lab09JobUser';

EXECUTE AS LOGIN = N'Lab09JobUser';
EXEC dbo.sp_add_jobstep
    @job_name = N'Lab09 Lab - Export via proxy',
    @step_name = N'Try proxy without grant',
    @subsystem = N'CMDEXEC', @command = N'echo test', @proxy_name = N'FileOp';
REVERT;
GO
-- Expected: ERROR — แจ้งว่า login ไม่มีสิทธิ์ใช้ proxy (แก้ด้วย sp_grant_login_to_proxy)

-- (B) มอบ login กลับ แล้วตัดการผูก subsystem แล้วลองอีกครั้ง
EXEC dbo.sp_grant_login_to_proxy @proxy_name = N'FileOp', @login_name = N'Lab09JobUser';

DECLARE @cmdexecId int =
    (SELECT subsystem_id FROM dbo.syssubsystems WHERE subsystem = N'CMDEXEC');
EXEC dbo.sp_revoke_proxy_from_subsystem @proxy_name = N'FileOp',
                                        @subsystem_id = @cmdexecId;

EXECUTE AS LOGIN = N'Lab09JobUser';
EXEC dbo.sp_add_jobstep
    @job_name = N'Lab09 Lab - Export via proxy',
    @step_name = N'Try proxy without subsystem',
    @subsystem = N'CMDEXEC', @command = N'echo test', @proxy_name = N'FileOp';
REVERT;
GO
-- Expected: ERROR — แจ้งว่า proxy ไม่มีสิทธิ์กับ subsystem CMDEXEC
-- (แก้ด้วย sp_grant_proxy_to_subsystem)

-- (C) เติมขั้น (B) กลับให้ครบก่อนจบ:
EXEC dbo.sp_grant_proxy_to_subsystem @proxy_name = N'FileOp',
                                     @subsystem_id = @cmdexecId;
GO
```

**Expected:** ทั้งสองกรณีพังตอน **สร้าง step** (ก่อนรัน) — ข้อความ error บอกตำแหน่งสิทธิ์ที่ขาดพอดี; ระวังเคสที่พัง "ตอนรัน" เท่านั้น: ถ้า credential ถูกลบ/รหัสผ่านเปลี่ยน — ตรวจด้วย query รวม `sys.credentials` × `msdb.dbo.sysproxies` ใน [Section 2.3](../Sections/02_Credentials/README.md)

---

## 🧹 Clean-up

> ลำดับสำคัญ: job → proxy → credential → login → LabEnv (ลบของที่อ้างกันก่อนเสมอ)

```sql
USE msdb;
GO
-- 1) ลบ jobs
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 Lab - Identity Test')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 Lab - Identity Test',
                           @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 Lab - Export via proxy')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 Lab - Export via proxy',
                           @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - My own job')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 - My own job',
                           @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - Record Agent Identity (sysadmin owner)')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)',
                           @delete_unused_schedule = 1;

-- 2) ลบ proxy (revoke ย้อนทุกชั้นก่อน เหมือน Section 3 clean-up)
IF EXISTS (SELECT 1 FROM dbo.sysproxies WHERE name = N'FileOp')
BEGIN
    EXEC dbo.sp_revoke_login_from_proxy @proxy_name = N'FileOp',
                                        @login_name = N'Lab09JobUser';
    DECLARE @cmdexecId int =
        (SELECT subsystem_id FROM dbo.syssubsystems WHERE subsystem = N'CMDEXEC');
    EXEC dbo.sp_revoke_proxy_from_subsystem @proxy_name = N'FileOp',
                                            @subsystem_id = @cmdexecId;
    EXEC dbo.sp_delete_proxy @proxy_name = N'FileOp';
END
GO

-- 3) ลบ credential
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'FileOperation')
    DROP CREDENTIAL FileOperation;
GO

-- 4) ลบ login (user ใน msdb/LabEnv ถูกลบตาม) — และ Windows local account ใน OS
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Lab09JobUser')
    DROP LOGIN Lab09JobUser;
GO

-- (OS) ลบ Windows local account ที่สร้างไว้ (Command Prompt as Administrator):
-- net user FileOps /delete

-- 5) ลบฐานข้อมูลทดลอง
USE master;
GO
IF DB_ID(N'LabEnv') IS NOT NULL
BEGIN
    ALTER DATABASE LabEnv SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LabEnv;
END
GO
```

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม user ใน SQLAgentUserRole สร้าง step CmdExec ไม่ได้ แต่ sysadmin ทำได้?</b></summary>
CmdExec รันคำสั่ง OS จริง ระบบกำหนดให้ผู้ใช้ต้องพิสูจน์ "ตัวตน Windows ที่รับผิดชอบ" ผ่าน proxy — sysadmin ยกเว้นให้รันในบริบท Agent service account ได้ แต่ user ทั่วไปต้อง GRANT proxy เท่านั้น ซึ่งเป็นด่านกันไม่ให้ใครก็ได้สั่ง OS ผ่าน Agent
</details>

<details>
<summary><b>2. Job เจ้าขอน Lab09JobUser รันแล้ว SYSTEM_USER ใน LabEnv เป็น 'Lab09JobUser' แต่ job เจ้าขอน sa เป็น NT SERVICE\SQLSERVERAGENT — สรุปกฎ?</b></summary>
T-SQL step รันในบริบทของ <b>เจ้าขอน job</b> เสมอ; เจ้าขอนที่เป็น sysadmin จะถูกแทนด้วย Agent service account (เพราะ service account เป็น sysadmin อยู่แล้ว) — จำเป็นหัวใจตอนออกแบบสิทธิ์ให้ job
</details>

<details>
<summary><b>3. ลบ credential ที่ proxy อ้างอยู่ตรง ๆ จะเกิดอะไรขึ้น?</b></summary>
หลังลบ credential, proxy ที่อ้างจะพังตอน execute (step สร้างได้แต่รันล้ม) — ทางที่ถูกคือ revoke login/subsystem → sp_delete_proxy → DROP CREDENTIAL ตามลำดับ และระวังหนึ่งกฎ: การลบ credential จะลบ proxy ที่อ้างอย่างเดียวที่ถูกแจ้งเตือน (จริง ๆ SSMS จะเตือน ให้ทำตามลำดับกันเหนียว)
</details>

<details>
<summary><b>4. ถ้าอยากให้ "ทั้งทีม Analytics" ใช้ proxy ได้จะทำยังไงดีกว่ามอบทีละ login?</b></summary>
ใช้รูปแบบอื่นของ sp_grant_login_to_proxy: <code>@msdb_role = N'SQLAgentUserRole'</code> (มอบให้ทั้ง role) — ระวังว่าสิทธิ์ proxy ถ่ายทอดไปยัง role ที่ใหญ่กว่าอัตโนมัติ (Reader/Operator ใช้ตามได้ด้วย) ตามโมเดล concentric ของ Agent fixed roles
</details>
