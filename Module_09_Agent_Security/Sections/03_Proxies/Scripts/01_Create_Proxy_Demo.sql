-- ============================================================================
-- Module 09, Section 3 — สร้าง Proxy ครบวงจร: credential -> proxy -> subsystem
--                        -> login -> job step ที่รันด้วย proxy
-- ปรับจาก Old/Demofiles/Mod09 (Demo 3 - proxy.sql) + (Demo 2 - quick create job.sql)
--   แทน domain ด้วย local account; เพิ่มการอ่าน subsystem_id แบบไดนามิกเพื่อไม่เดา
-- ต้องมี: sysadmin; credential FileOperation (รัน Scripts/01_Create_Credential.sql
--         ของ Section 2 ก่อน); บน Windows มี local account MACHINE\FileOps
--         (แทน MACHINE ด้วยชื่อเครื่อง) — login Lab09JobUser (รันสคริปต์ Section 1)
-- idempotent — ลบของเดิมก่อนสร้างใหม่
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   1) เตรียม login ผู้ใช้ proxy (สร้างถ้ายังไม่มีจาก Section 1)
   ---------------------------------------------------------------------------- */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'Lab09JobUser')
BEGIN
    CREATE LOGIN Lab09JobUser
        WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
    PRINT N'สร้าง login Lab09JobUser ใหม่';
END
GO

USE msdb;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Lab09JobUser')
    CREATE USER Lab09JobUser FOR LOGIN Lab09JobUser;
ALTER ROLE SQLAgentUserRole ADD MEMBER Lab09JobUser;   -- idempotent: ทำซ้ำได้
GO

/* ----------------------------------------------------------------------------
   2) สร้าง proxy ที่อ้าง credential FileOperation (จาก Section 2)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysproxies WHERE name = N'FileOp')
    EXEC dbo.sp_delete_proxy @proxy_name = N'FileOp';

EXEC dbo.sp_add_proxy
    @proxy_name      = N'FileOp',
    @credential_name = N'FileOperation',
    @enabled         = 1;

-- ตรวจ: proxy + credential ที่อ้าง (แสดงความสัมพันธ์ 1:1)
SELECT sp.name AS proxy_name, sp.enabled,
       c.name AS credential_name, c.identity_desc
FROM dbo.sysproxies AS sp
JOIN sys.credentials AS c ON c.credential_id = sp.credential_id;
-- Expected: แถว FileOp / FileOperation / MACHINE\FileOps

/* ----------------------------------------------------------------------------
   3) ดู subsystem ทั้งหมด แล้วผูก proxy กับ CMDEXEC ด้วย id ที่อ่านจริง
      (ไม่เดา subsystem_id — อ่านจาก msdb.dbo.syssubsystems ด้วยรหัส CMDEXEC)
   ---------------------------------------------------------------------------- */
SELECT subsystem_id, subsystem, subsystem_name
FROM dbo.syssubsystems
ORDER BY subsystem_id;
-- Expected: รายการ subsystem ในตัว: CMDEXEC, PowerShell, SSIS, Snapshot, LogReader, ...

DECLARE @cmdexecId int =
    (SELECT subsystem_id FROM dbo.syssubsystems WHERE subsystem = N'CMDEXEC');

EXEC dbo.sp_grant_proxy_to_subsystem
    @proxy_name   = N'FileOp',
    @subsystem_id = @cmdexecId;
GO

/* ----------------------------------------------------------------------------
   4) มอบ proxy ให้ login Lab09JobUser
   ---------------------------------------------------------------------------- */
-- ลบการมอบเดิมถ้ามี (idempotent)
IF EXISTS (SELECT 1
           FROM dbo.sysproxylogin AS pl
           WHERE pl.proxy_id = (SELECT proxy_id FROM dbo.sysproxies WHERE name = N'FileOp')
             AND pl.sid = SUSER_SID(N'Lab09JobUser'))
    EXEC dbo.sp_revoke_login_from_proxy @proxy_name = N'FileOp',
                                        @login_name = N'Lab09JobUser';

EXEC dbo.sp_grant_login_to_proxy
    @proxy_name = N'FileOp',
    @login_name = N'Lab09JobUser';

-- ตรวจการมอบสิทธิ์ทั้งหมดของ proxy
SELECT p.name AS proxy_name, sysp.name AS granted_login
FROM dbo.sysproxylogin AS pl
JOIN dbo.sysproxies AS p ON p.proxy_id = pl.proxy_id
JOIN sys.server_principals AS sysp ON sysp.sid = pl.sid
WHERE p.name = N'FileOp';
-- Expected: FileOp -> Lab09JobUser
GO

/* ----------------------------------------------------------------------------
   5) Job step ที่รันด้วย proxy — เจ้าขอนเป็น Lab09JobUser (ไม่ใช่ sysadmin)
      คำสั่ง echo แสดง %USERNAME% เพื่อพิสูจน์บริบท Windows account ตอนรัน
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - Copy file via proxy')
    EXEC dbo.sp_delete_job @job_name = N'Lab09 - Copy file via proxy',
                           @delete_unused_schedule = 1;

EXEC dbo.sp_add_job
    @job_name         = N'Lab09 - Copy file via proxy',
    @enabled          = 1,
    @description      = N'Demo: CmdExec step รันด้วย proxy FileOp',
    @owner_login_name = N'Lab09JobUser';

EXEC dbo.sp_add_jobstep
    @job_name          = N'Lab09 - Copy file via proxy',
    @step_name         = N'Copy file (runs as MACHINE\FileOps)',
    @subsystem         = N'CMDEXEC',
    @command           = N'echo %USERNAME% executed job step at %DATE% %TIME%',
    @proxy_name        = N'FileOp',       -- หัวใจของเดโม: รันในบริบท Windows account
    @cmdexec_success_code = 0,
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC dbo.sp_update_job @job_name = N'Lab09 - Copy file via proxy', @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_name = N'Lab09 - Copy file via proxy',
                          @server_name = N'(local)';
GO

/* ----------------------------------------------------------------------------
   6) ทดสอบรัน แล้วดูประวัติ
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_start_job @job_name = N'Lab09 - Copy file via proxy';
GO
-- รอ 5-10 วินาทีแล้วรัน:
EXEC dbo.sp_help_jobhistory @job_name = N'Lab09 - Copy file via proxy', @mode = 'FULL';
-- Expected (บน Windows): ข้อความใน history มีคำว่า "FileOps executed job step at ..."
--                        = ยืนยันว่า step รันในบริบท Windows account ของ credential
-- Expected (run_status = 1)

/* ----------------------------------------------------------------------------
   7) ทดสอบข้อผิดพลาดเมื่อสิทธิ์ไม่ครบ (ทำแบบ manual เพื่อเห็น error จริง)
      7a) revoke สิทธิ์ login ใช้ proxy แล้วลองสร้าง step ใหม่ที่ระบุ proxy
      7b) revoke การผูก subsystem แล้วลองอีกครั้ง
      (รันแบบ manual ทีละบล็อก แล้ว GRANT กลับ)
   ---------------------------------------------------------------------------- */
-- EXEC dbo.sp_revoke_login_from_proxy @proxy_name = N'FileOp',
--                                     @login_name = N'Lab09JobUser';
-- EXECUTE AS LOGIN = N'Lab09JobUser';
-- EXEC dbo.sp_add_jobstep
--     @job_name  = N'Lab09 - Copy file via proxy',
--     @step_name = N'Try without grant',
--     @subsystem = N'CMDEXEC', @command = N'echo test',
--     @proxy_name = N'FileOp';
-- REVERT;
-- -- Expected: ERROR — แจ้งว่า login ไม่มีสิทธิ์ใช้ proxy นี้ (ให้ GRANT กลับด้วย
-- -- sp_grant_login_to_proxy ตามขั้นที่ 4)

/* ----------------------------------------------------------------------------
   Clean-up — ล้าง proxy ทั้งสาย (จากนั้นจึงลบ credential ตาม Section 2 clean-up)
   ----------------------------------------------------------------------------
   EXEC dbo.sp_revoke_login_from_proxy @proxy_name = N'FileOp',
                                       @login_name = N'Lab09JobUser';
   DECLARE @cmdexecId int =
       (SELECT subsystem_id FROM dbo.syssubsystems WHERE subsystem = N'CMDEXEC');
   EXEC dbo.sp_revoke_proxy_from_subsystem @proxy_name = N'FileOp',
                                           @subsystem_id = @cmdexecId;
   EXEC dbo.sp_delete_proxy @proxy_name = N'FileOp';
   IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Lab09 - Copy file via proxy')
       EXEC dbo.sp_delete_job @job_name = N'Lab09 - Copy file via proxy',
                              @delete_unused_schedule = 1;
   GO
*/
