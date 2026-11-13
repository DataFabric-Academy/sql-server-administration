-- ============================================================================
-- Module 08, Section 2 — สร้าง Maintenance Job ตามแพตเทิร์น Ola Hallengren
-- สคริปต์นี้แสดงโครง job ที่ห่องาน maintenance จริง:
--   Step 1: DatabaseBackup   (full backup ทุก user database)
--   Step 2: DatabaseIntegrityCheck (CHECKDB)
--   Step 3: IndexOptimize    (index + statistics)
-- สองโหมดให้เลือก:
--   โหมด A (default): ใช้ T-SQL มาตรฐานที่รันได้ทันทีโดยไม่ต้องดาวน์โหลดอะไร
--   โหมด B: เปลี่ยนคำสั่งเป็นเรียก proc ของ Ola (ติดตั้งจาก https://ola.hallengren.com ก่อน)
-- idempotent — ลบ job เดิมก่อนสร้างใหม่
-- ============================================================================

USE msdb;
GO

/* ----------------------------------------------------------------------------
   0) อ่าน default backup path ของ instance (SQL Server 2019+)
      ทำให้สคริปต์ใช้ได้ทั้ง Windows, Linux และ container
   ---------------------------------------------------------------------------- */
DECLARE @BackupDir nvarchar(260) =
    CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));

-- ให้แน่ใจว่าท้าย path มีตัวคั่น (Windows = '\', Linux = '/')
IF @BackupDir IS NULL SET @BackupDir = N'C:\Backups\';   -- fallback สำหรับของเก่า
IF RIGHT(@BackupDir, 1) NOT IN (N'\', N'/')
    SET @BackupDir = @BackupDir + CASE
        WHEN @BackupDir LIKE N'%/%' AND @BackupDir NOT LIKE N'%\%' THEN N'/'
        ELSE N'\' END;

PRINT N'Backup directory ที่ใช้: ' + @BackupDir;

/* ----------------------------------------------------------------------------
   1) ลบ job เดิม แล้วสร้าง job ใหม่
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Fabrikam - Maintenance (Ola pattern)')
    EXEC dbo.sp_delete_job @job_name = N'Fabrikam - Maintenance (Ola pattern)',
                           @delete_unused_schedule = 1;

DECLARE @jobId BINARY(16);

EXEC dbo.sp_add_job
    @job_name              = N'Fabrikam - Maintenance (Ola pattern)',
    @enabled               = 1,
    @description           = N'Full backup -> CHECKDB -> IndexOptimize ตามแพตเทิร์น Ola Hallengren',
    @category_name         = N'Database Maintenance',   -- category มีให้แล้วในทุก install
    @owner_login_name      = N'sa',
    @notify_level_eventlog = 2,        -- เขียน Windows event log เมื่อ fail
    @notify_level_email    = 0,
    @job_id                = @jobId OUTPUT;

/* ----------------------------------------------------------------------------
   2) Step 1 — Full backup ทุก user database (โหมด A: T-SQL มาตรฐาน)
      ในโหมด B เปลี่ยน @command เป็น:
        EXECUTE dbo.DatabaseBackup @Databases = 'USER_DATABASES',
            @Directory = N'D:\Backups', @BackupType = 'FULL',
            @Compress = 'Y', @CheckSum = 'Y', @CleanupTime = 604800;
      (มีจริงเมื่อติดตั้ง MaintenanceSolution.sql จาก ola.hallengren.com ลง master)
   ---------------------------------------------------------------------------- */
DECLARE @fullCmd nvarchar(max) =
    N'BACKUP DATABASE [AdventureWorks2025] TO DISK = N''' + @BackupDir
    + N'AdventureWorks2025_Full_' + CONVERT(nvarchar(8), GETDATE(), 112) + N'.bak''
WITH COMPRESSION, CHECKSUM, STATS = 5;';

EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'1 - Full backup',
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = @fullCmd,
    @on_success_action = 3,        -- ไป step ถัดไป
    @on_fail_action    = 2;        -- จบด้วย fail (จะไม่ CHECKDB ต่อถ้า backup พัง)

/* ----------------------------------------------------------------------------
   3) Step 2 — CHECKDB แบบ PHYSICAL_ONLY รายคืน (โหมด A)
      โหมด B: EXECUTE dbo.DatabaseIntegrityCheck @Databases = 'USER_DATABASES',
                 @CheckCommands = 'CHECKDB';
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'2 - CHECKDB (PHYSICAL_ONLY)',
    @subsystem         = N'TSQL',
    @database_name     = N'master',
    @command           = N'DBCC CHECKDB (N''AdventureWorks2025'') WITH NO_INFOMSGS, PHYSICAL_ONLY, TABLOCK;',
    @on_success_action = 3,
    @on_fail_action    = 2;

/* ----------------------------------------------------------------------------
   4) Step 3 — Index maintenance (โหมด A: UPDATE STATISTICS ง่าย ๆ)
      โหมด B (ของจริงแบบ Ola):
        EXECUTE dbo.IndexOptimize @Databases = 'USER_DATABASES',
            @FragmentationLow = NULL,
            @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE',
            @FragmentationHigh = 'INDEX_REBUILD_ONLINE',
            @Indexes = 'ALL_INDEXES', @UpdateStatistics = 'ALL',
            @MIN_PAGE_COUNT = 1000;
      หมายเหตุ: @MIN_PAGE_COUNT กันตารางเล็กเกินไม่ให้ rebuild สูญเปล่า
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobstep
    @job_id            = @jobId,
    @step_name         = N'3 - Index/Statistics maintenance',
    @subsystem         = N'TSQL',
    @database_name     = N'AdventureWorks2025',
    @command           = N'EXEC sp_updatestats;',
    @on_success_action = 1,        -- จบ job แบบสำเร็จ
    @on_fail_action    = 2;

-- ปล่อย job ให้รันได้
EXEC dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';
GO

/* ----------------------------------------------------------------------------
   5) Schedule — ทุกคืน 23:00
   ---------------------------------------------------------------------------- */
EXEC dbo.sp_add_jobschedule
    @job_name          = N'Fabrikam - Maintenance (Ola pattern)',
    @name              = N'Nightly maintenance 23:00',
    @enabled           = 1,
    @freq_type         = 4,          -- Daily
    @freq_interval     = 1,
    @freq_subday_type  = 1,
    @active_start_time = 230000;
GO

/* ----------------------------------------------------------------------------
   6) รันทดสอบทันทีและดูประวัติ
   ---------------------------------------------------------------------------- */
EXEC msdb.dbo.sp_start_job @job_name = N'Fabrikam - Maintenance (Ola pattern)';
GO
-- รอจน job จบ (backup AdventureWorks2025 ใช้เวลาขึ้นกับเครื่อง) แล้วตรวจ:
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Fabrikam - Maintenance (Ola pattern)';
-- Expected: run_status = 1 (Succeeded); ไฟล์ backup วันนี้อยู่ใน default backup path

-- ตรวจ backup set ล่าสุดที่ Agent เขียนลง msdb (จะเห็นถ้าต้องการ verify ด้วย
-- RESTORE VERIFYONLY ก็อ่าน path จากบรรทัดนี้ไปใช้):
SELECT TOP 5 bs.database_name, bs.type AS backup_type,     -- D = Full
       bs.backup_start_date, bs.backup_finish_date, bs.is_compressed,
       bs.has_backup_checksums, bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'AdventureWorks2025'
ORDER BY bs.backup_finish_date DESC;
-- Expected: แถวแรก = backup_type 'D' (full), is_compressed = 1, has_backup_checksums = 1

/* ----------------------------------------------------------------------------
   Clean-up
   ----------------------------------------------------------------------------
   IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Fabrikam - Maintenance (Ola pattern)')
       EXEC msdb.dbo.sp_delete_job @job_name = N'Fabrikam - Maintenance (Ola pattern)',
                                   @delete_unused_schedule = 1;
*/
