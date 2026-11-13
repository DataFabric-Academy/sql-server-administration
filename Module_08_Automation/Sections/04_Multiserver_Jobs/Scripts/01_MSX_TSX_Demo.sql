-- ============================================================================
-- Module 08, Section 4 — ภาพรวม MSX/TSX (Multiserver Administration)
-- สคริปต์นี้ใช้เดโมบน instance สองตัว:
--   MSX = server แม่ (container หลัก sql2025 / หรือ install ปกติ)
--   TSX = server ลูก (container ที่สอง sql2025b port 1434 — ดู Module 00)
-- เดโมส่วนแรกรันได้บน instance เดียว (ตรวจสถานะ + ดูตารางเป้าหมาย)
-- ส่วนที่ต้องมีสองเครื่องเขียนกำกับไว้ให้ COPY ไปรันที่เครื่องลูกแต่ละขั้น
-- ============================================================================

USE msdb;
GO

/* ============================================================================
   ส่วน A — ตรวจสถานะปัจจุบันของ instance (รันได้ทั้ง MSX และ TSX)
   ============================================================================ */

-- A1) ตัว instance นี้มี job ที่ "มาจาก MSX" หรือไม่?
--     (job ที่ TSX ดาวน์โหลดมาจะมี originating_server_id <> 0 — job local = 0)
SELECT j.name AS multiserver_job_name,
       j.originating_server_id
FROM dbo.sysjobs AS j
WHERE j.originating_server_id <> 0;
-- Expected: standalone instance = ผลลัพธ์ว่าง

-- A2) รายชื่อ target servers ที่ MSX นี้รู้จัก (สมมูลหน้าจอ Multi Server Administration)
EXEC dbo.sp_help_targetserver;
-- Expected: ว่าง = ยังไม่มี TSX เลย; ถ้าเคย enlist จะเห็นแถวต่อ target + last_poll_date

-- A3) ดูตารางกลุ่ม target server (ใช้จัดกลุ่ม TSX เช่น "Datacenter A")
SELECT * FROM dbo.systargetservergroups;
SELECT * FROM dbo.systargetservergroupmembers;

/* ============================================================================
   ส่วน B — เตรียม MSX (รันบนเครื่องแม่เท่านั้น)
   ข้อกำหนดจากระบบ:
     - มี operator ชื่อ MSXOperator ไม่งั้น enlistment จะ error 14363
     - MSX ต้องเป็น Standard/Enterprise (Express ทำ MSX ไม่ได้)
   ============================================================================ */

IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'MSXOperator')
    EXEC dbo.sp_add_operator
        @name          = N'MSXOperator',
        @enabled       = 1,
        @email_address = N'dba-team@fabrikam.example';
PRINT N'MSXOperator พร้อม (ถ้ายังไม่มีก็สร้างแล้ว)';
GO

/* ============================================================================
   ส่วน C — Enlist TSX (รันบนเครื่องลูก sql2025b)
   คัดลอกบล็อกนี้ไปรันที่ TSX เท่านั้น (sp_msx_enlist เพิ่ม "เครื่องปัจจุบัน"
   เข้ารายชื่อ target ของ MSX)
   ข้อควรระวัง container lab: การเชื่อมต่อ MSX<->TSX เปิด TLS + certificate
   validation มา default — ถ้ายังไม่มี certificate ให้ทำตามแนวทางแล็บ
   (optional) หรือใช้ SSMS wizard ซึ่งช่วยจัดการ login credential ให้
   ============================================================================ */

/* -- รันบน TSX (sql2025b) --
USE msdb;
GO
EXEC dbo.sp_msx_enlist
    @msx_server_name = N'host.docker.internal,1433',   -- ชี้ไปยัง MSX (แก้ตามสภาพแวดล้อม)
    @location        = N'Lab container sql2025b';
GO
*/

-- หลัง enlist สำเร็จ ตรวจที่ MSX:
/* -- รันบน MSX --
EXEC dbo.sp_help_targetserver;
-- Expected: มีแถวของ sql2025b + local_time_zone / last_poll_date อัปเดต
-- และตารางนี้จะมี TSX เพิ่ม:
SELECT server_id, server_name, enlist_date, last_poll_date
FROM dbo.systargetservers;
*/

/* ============================================================================
   ส่วน D — สร้าง multiserver job ที่ MSX แล้วกระจายไป TSX
   จุดสำคัญ: ห้ามเรียก sp_add_jobserver กับ multiserver job
   (การลงทะเบียน "รันบน local" ต้องเปลี่ยนเป็นการกระจายแทน)
   ============================================================================ */

/* -- รันบน MSX --
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fleet - Daily user DB backup')
    EXEC dbo.sp_delete_job @job_name = N'Fleet - Daily user DB backup',
                           @delete_unused_schedule = 1;

EXEC dbo.sp_add_job
    @job_name = N'Fleet - Daily user DB backup',
    @enabled  = 1,
    @description = N'Full backup AdventureWorks2025 กระจายไปทุก TSX';

EXEC dbo.sp_add_jobstep
    @job_name       = N'Fleet - Daily user DB backup',
    @step_name      = N'Backup AdventureWorks2025',
    @subsystem      = N'TSQL',
    @database_name  = N'master',
    @command        = N'BACKUP DATABASE [AdventureWorks2025]
                       TO DISK = N''C:\Backups\AW2025_Fleet.bak''
                       WITH COMPRESSION, CHECKSUM;';

EXEC dbo.sp_add_jobschedule
    @job_name          = N'Fleet - Daily user DB backup',
    @name              = N'Nightly 23:30',
    @freq_type         = 4, @freq_interval = 1,
    @freq_subday_type  = 1,
    @active_start_time = 233000;

-- กระจายไป TSX ที่ enlist ไว้ (APPLY = เพิ่ม, REMOVE = ถอน)
EXEC dbo.sp_apply_job_to_targets
    @job_name       = N'Fleet - Daily user DB backup',
    @target_servers = N'sql2025b',
    @operation      = N'APPLY';
GO

-- D1) ตรวจคิวคำสั่งที่รอ TSX ดึง (หัวใจของกลไก MSX/TSX)
EXEC dbo.sp_help_downloadlist @job_name = N'Fleet - Daily user DB backup';
-- Expected: แถวคำสั่ง (operation = ENLIST/INSERT_JOB/INSERT_JOBSTEP/INSERT_JOBSCHEDULE)
--           status คอลัมน์บอกว่า TSX ดึงไปแล้วหรือยัง (0 = ยังอยู่ในคิว)

-- D2) หลัง TSX ดึงงานไปแล้ว ตรวจที่ TSX ว่า job ถูก "ดาวน์โหลด" จริง:
--     (รันบน TSX)
-- SELECT name, originating_server, date_created FROM dbo.sysjobs
-- WHERE name = N'Fleet - Daily user DB backup';
-- Expected: job ปรากฏบน TSX โดย originating_server ชี้ MSX; แก้/ลบที่ TSX โดยตรงไม่ได้
*/

-- D3) ดูผลการรันรวมที่ MSX (ประวัติทุกเครื่องมาที่เดียว — จุดขายหลัก)
/* -- รันบน MSX หลัง TSX รัน job แล้ว --
EXEC dbo.sp_help_jobhistory @job_name = N'Fleet - Daily user DB backup';
-- Expected: แถวประวัติที่รันโดย TSX ถูกอัปโหลดกลับมาแสดงที่ MSX
*/

/* ============================================================================
   ส่วน E — Defect (ถอนตัว) เมื่อเลิกใช้ — ทำ Clean-up ตามแล็บ
   ============================================================================ */

/* -- รันบน TSX: ถอนตัวจาก MSX (ไม่ใส่ @forced_defection ถ้า MSX ยังเข้าถึงได้) --
USE msdb;
GO
EXEC dbo.sp_msx_defect;
GO
*/

/* -- รันบน MSX: ลบ target ทิ้ง (ทำหลัง TSX defect แล้ว) --
USE msdb;
GO
EXEC dbo.sp_delete_targetserver @server_name = N'sql2025b', @post_defection = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fleet - Daily user DB backup')
    EXEC dbo.sp_delete_job @job_name = N'Fleet - Daily user DB backup',
                           @delete_unused_schedule = 1;
GO
*/
