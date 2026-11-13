-- ============================================================================
-- Module 09, Section 1 — พิสูจน์บริบทการรันของ Agent job (owner vs service account)
-- ปรับจาก Old/Demofiles/Mod09 (Demo 1 - security context.sql) ให้ใช้ LabEnv
-- แทน AdminDB และไม่ต้องมี Active Directory
-- ต้องมี: SQL Server Agent รันอยู่, รันด้วย sysadmin
-- idempotent — ลบของเดิมก่อนสร้างใหม่
-- ============================================================================

USE master;
GO

/* ----------------------------------------------------------------------------
   0) ล้างของเดิม (รันซ้ำได้)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Lab09 - Record Agent Identity (sysadmin owner)')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)',
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

/* ----------------------------------------------------------------------------
   1) ตาราง log บันทึก SYSTEM_USER + proc ที่ job จะเรียก
      SYSTEM_USER ภายใน job step = identity ที่ engine เห็นจริง ตอนรัน
   ---------------------------------------------------------------------------- */
USE LabEnv;
GO
CREATE TABLE dbo.AgentIdentityLog
(
    LogID         int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    LogTime       datetime2 NOT NULL DEFAULT SYSDATETIME(),
    RunAsIdentity sysname   NOT NULL,
    Note          nvarchar(100) NULL
);
GO

CREATE PROCEDURE dbo.RecordAgentIdentity
    @Note nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AgentIdentityLog (RunAsIdentity, Note)
    SELECT SYSTEM_USER, @Note;
END
GO

/* ----------------------------------------------------------------------------
   2) เดโม A — job ที่เจ้าขอนเป็น sysadmin (sa)
      ตามกฎ: T-SQL step รันในบริบทของ Agent service account
      (NT SERVICE\SQLSERVERAGENT) — ไม่ใช่ sa
   ---------------------------------------------------------------------------- */
USE msdb;
GO

EXEC dbo.sp_add_job
    @job_name         = N'Lab09 - Record Agent Identity (sysadmin owner)',
    @enabled          = 1,
    @description      = N'Demo: T-SQL step รันในบริบท Agent service account',
    @owner_login_name = N'sa',
    @delete_level     = 0;

EXEC dbo.sp_add_jobstep
    @job_name          = N'Lab09 - Record Agent Identity (sysadmin owner)',
    @step_name         = N'Record identity',
    @subsystem         = N'TSQL',
    @database_name     = N'LabEnv',
    @command           = N'EXEC dbo.RecordAgentIdentity @Note = N''sysadmin-owned job'';',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC dbo.sp_update_job @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)',
                       @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)',
                          @server_name = N'(local)';

EXEC dbo.sp_start_job @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)';
GO

/* ----------------------------------------------------------------------------
   3) ตรวจผลเดโม A (รอ 5-10 วินาทีก่อนรัน SELECT)
   ---------------------------------------------------------------------------- */
USE LabEnv;
GO
SELECT LogID, LogTime, RunAsIdentity, Note FROM dbo.AgentIdentityLog;
-- Expected: RunAsIdentity = 'NT SERVICE\SQLSERVERAGENT' (หรือ account ที่ Agent ใช้)
--           แม้เจ้าขอน job เป็น sa — นี่คือกฎ "sysadmin owner -> service account context"

/* ----------------------------------------------------------------------------
   4) เดโม B — user ที่ไม่ใช่ sysadmin สร้าง job ของตัวเอง
      ตามกฎ: T-SQL step รันในบริบทของเจ้าขอน (Lab09JobUser)
      สร้างด้วย EXECUTE AS LOGIN เพื่อให้ทั้งเดโมอยู่ใน session เดียว
      (ใน SSMS ทำทางเลือกคือเปิด connection ใหม่ด้วย SQL auth ของ Lab09JobUser)
   ---------------------------------------------------------------------------- */
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
ALTER ROLE SQLAgentUserRole ADD MEMBER Lab09JobUser;
GO

USE LabEnv;
GO
CREATE USER Lab09JobUser FOR LOGIN Lab09JobUser;
-- สิทธิ์ที่จำเป็น "เท่าที่จำเป็น" สำหรับงานของ job ตัวนี้
GRANT INSERT ON dbo.AgentIdentityLog TO Lab09JobUser;
GRANT EXECUTE ON dbo.RecordAgentIdentity TO Lab09JobUser;
GO

/* -- เดโม B: สร้าง job ในบริบท Lab09JobUser --------------------------------
   หมายเหตุ: EXECUTE AS LOGIN ใช้ได้เมื่อผู้รันเป็น sysadmin (ในห้องเรียน)
   หากต้องการสมจริงขึ้น ให้เปิด SSMS connection ใหม่ด้วย SQL auth Lab09JobUser
   แล้วรันบล็อกในคอมเมนต์แทน
--------------------------------------------------------------------------- */
USE msdb;
GO
EXECUTE AS LOGIN = N'Lab09JobUser';
GO

-- user สร้าง job ของตัวเอง (สมาชิก SQLAgentUserRole ทำได้)
EXEC dbo.sp_add_job @job_name = N'Lab09 - My own job', @enabled = 1;

EXEC dbo.sp_add_jobstep
    @job_name          = N'Lab09 - My own job',
    @step_name         = N'Record identity',
    @subsystem         = N'TSQL',
    @database_name     = N'LabEnv',
    @command           = N'EXEC dbo.RecordAgentIdentity @Note = N''non-sysadmin-owned job'';',
    @on_success_action = 1,
    @on_fail_action    = 2;
-- Expected: สำเร็จ (job ใหม่เจ้าขอน = Lab09JobUser)

-- ทดลองสร้าง step CmdExec โดยไม่มี proxy
EXEC dbo.sp_add_jobstep
    @job_name          = N'Lab09 - My own job',
    @step_name         = N'Try CmdExec without proxy',
    @subsystem         = N'CMDEXEC',
    @command           = N'echo hello';
GO
-- Expected: ERROR จาก sp_add_jobstep — ข้อความแจ้งว่าผู้ใช้ไม่มีสิทธิ์ใช้
--           subsystem CMDEXEC จนกว่าจะมี proxy (ข้อจำกัดกลางของ Agent security
--           ตามหัวข้อ 1.4 — ทางแก้คือ proxy ใน Section 3 และ Lab Exercise 2)

REVERT;
GO

-- ให้ job ของ user รันได้บน server (sysadmin ทำขั้นนี้ให้)
EXEC msdb.dbo.sp_add_jobserver @job_name = N'Lab09 - My own job',
                               @server_name = N'(local)';
EXEC msdb.dbo.sp_start_job @job_name = N'Lab09 - My own job';
GO

/* ----------------------------------------------------------------------------
   5) ตรวจผลเดโม B (รอ 5-10 วินาที)
   ---------------------------------------------------------------------------- */
USE LabEnv;
GO
SELECT LogID, LogTime, RunAsIdentity, Note FROM dbo.AgentIdentityLog
ORDER BY LogID;
-- Expected: มีสองแถว —
--   แถว 1: RunAsIdentity = NT SERVICE\SQLSERVERAGENT   (job เจ้าขอน sysadmin)
--   แถว 2: RunAsIdentity = Lab09JobUser                (job เจ้าขอน user ทั่วไป)
-- ยืนยันกฎบริบทการรันใน Section 1.2

-- สำรวจเจ้าขอน job ทั้งหมด (owner_sid -> ชื่อ login):
SELECT j.name AS job_name,
       sp.name AS owner_login,
       CASE WHEN IS_SRVROLEMEMBER('sysadmin', sp.name) = 1 THEN N'sysadmin'
            ELSE N'non-sysadmin' END AS owner_class
FROM msdb.dbo.sysjobs AS j
JOIN sys.server_principals AS sp ON sp.sid = j.owner_sid
WHERE j.name LIKE N'Lab09%';

/* ----------------------------------------------------------------------------
   Clean-up — รันเมื่อจบเดโม
   ----------------------------------------------------------------------------
   USE msdb;
   IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - Record Agent Identity (sysadmin owner)')
       EXEC dbo.sp_delete_job @job_name = N'Lab09 - Record Agent Identity (sysadmin owner)',
                              @delete_unused_schedule = 1;
   IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - My own job')
       EXEC dbo.sp_delete_job @job_name = N'Lab09 - My own job',
                              @delete_unused_schedule = 1;
   IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Lab09JobUser')
       DROP LOGIN Lab09JobUser;   -- ลบ user ใน msdb/LabEnv ตามไปอัตโนมัติ
   GO
   USE master;
   IF DB_ID(N'LabEnv') IS NOT NULL
   BEGIN
       ALTER DATABASE LabEnv SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
       DROP DATABASE LabEnv;
   END
   GO
*/
