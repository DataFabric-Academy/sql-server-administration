-- ============================================================================
-- Module 13 - Section 2 - Script 01: สร้างคลัง baseline ด้วยตัวเอง (DBA_Baseline)
-- ปรับจากแนวคิดแล็บ Mod13 ของ Microsoft 20764D (Lab 13 Exercise 4)
-- รันได้บน: SQL Server 2019+ (แนะนำ 2025)
-- ผลลัพธ์: database DBA_Baseline + ตาราง snapshot + proc เก็บรอบใหม่
-- ============================================================================
IF DB_ID('DBA_Baseline') IS NULL
    CREATE DATABASE DBA_Baseline;
GO

USE DBA_Baseline;
GO

-- ----------------------------------------------------------------------------
-- ตาราง log ของแต่ละรอบ snapshot
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.BaselineRun', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BaselineRun
    (
        RunId      int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_BaselineRun PRIMARY KEY,
        CapturedAt datetime2(3)       NOT NULL CONSTRAINT DF_BaselineRun_At DEFAULT SYSDATETIME(),
        Note       nvarchar(200)      NULL
    );
END;
GO

-- ----------------------------------------------------------------------------
-- Snapshot ของ sys.dm_os_wait_stats (กรอง benign waits แล้ว)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaitStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaitStats
    (
        RunId               int          NOT NULL,
        wait_type           nvarchar(60) NOT NULL,
        waiting_tasks_count bigint       NOT NULL,
        wait_time_ms        bigint       NOT NULL,
        max_wait_time_ms    bigint       NOT NULL,
        signal_wait_time_ms bigint       NOT NULL,
        CONSTRAINT PK_WaitStats PRIMARY KEY (RunId, wait_type)
    );
END;
GO

-- ----------------------------------------------------------------------------
-- Snapshot ของ sys.dm_os_performance_counters (ทุกแถว)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PerfCounters', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfCounters
    (
        RunId         int           NOT NULL,
        object_name   nvarchar(128) NOT NULL,
        counter_name  nvarchar(128) NOT NULL,
        instance_name nvarchar(128) NULL,
        cntr_value    bigint        NOT NULL,
        cntr_type     int           NOT NULL,
        CONSTRAINT PK_PerfCounters PRIMARY KEY (RunId, object_name, counter_name, instance_name)
    );
END;
GO

-- ----------------------------------------------------------------------------
-- Snapshot I/O ต่อ database file จาก sys.dm_io_virtual_file_stats
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.FileStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FileStats
    (
        RunId             int      NOT NULL,
        database_name     sysname  NOT NULL,
        file_name         sysname  NOT NULL,
        type_desc         nvarchar(60) NOT NULL,
        size_on_disk_mb   float    NOT NULL,
        num_of_reads      bigint   NOT NULL,
        io_stall_read_ms  bigint   NOT NULL,
        num_of_writes     bigint   NOT NULL,
        io_stall_write_ms bigint   NOT NULL,
        CONSTRAINT PK_FileStats PRIMARY KEY (RunId, database_name, file_name)
    );
END;
GO

-- ----------------------------------------------------------------------------
-- Stored procedure: เรียกครั้งเดียว = เก็บ snapshot รอบใหม่ทั้งหมด
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_CaptureBaseline', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.usp_CaptureBaseline AS RETURN;');
GO

ALTER PROCEDURE dbo.usp_CaptureBaseline
    @Note nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunId int;

    INSERT dbo.BaselineRun (Note) VALUES (@Note);
    SET @RunId = SCOPE_IDENTITY();

    -- 1) Wait stats (กรอง wait จุดเสียงที่ไม่น่าสนใจออก)
    INSERT dbo.WaitStats (RunId, wait_type, waiting_tasks_count, wait_time_ms,
                          max_wait_time_ms, signal_wait_time_ms)
    SELECT @RunId, wait_type, waiting_tasks_count, wait_time_ms,
           max_wait_time_ms, signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 0
      AND wait_type NOT IN (N'SLEEP_TASK', N'BROKER_TASK_STOP',
                            N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'XE_TIMER_EVENT',
                            N'WAITFOR', N'DIRTY_PAGE_POLL',
                            N'DISPATCHER_QUEUE_SEMAPHORE',
                            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
                            N'XE_DISPATCHER_WAIT', N'LOGMGR_QUEUE');

    -- 2) Performance counters ทั้งหมด
    INSERT dbo.PerfCounters (RunId, object_name, counter_name, instance_name,
                             cntr_value, cntr_type)
    SELECT @RunId, object_name, counter_name, instance_name, cntr_value, cntr_type
    FROM sys.dm_os_performance_counters;

    -- 3) I/O ต่อ file
    INSERT dbo.FileStats (RunId, database_name, file_name, type_desc,
                          size_on_disk_mb, num_of_reads, io_stall_read_ms,
                          num_of_writes, io_stall_write_ms)
    SELECT @RunId,
           DB_NAME(fs.database_id), mf.name, mf.type_desc,
           mf.size * 8 / 1024.0,
           fs.num_of_reads, fs.io_stall_read_ms,
           fs.num_of_writes, fs.io_stall_write_ms
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
    INNER JOIN sys.master_files AS mf
            ON fs.database_id = mf.database_id
           AND fs.file_id     = mf.file_id;

    SELECT @RunId AS NewRunId, @Note AS Note;
END;
GO

-- ----------------------------------------------------------------------------
-- ทดสอบ: เก็บรอบแรก
-- ----------------------------------------------------------------------------
EXEC dbo.usp_CaptureBaseline @Note = N'รอบแรกหลัง setup';
GO

SELECT * FROM dbo.BaselineRun;
GO

-- ----------------------------------------------------------------------------
-- วิเคราะห์: ผลต่าง wait stats ระหว่างรอบล่าสุดกับรอบก่อนหน้า
-- (จะมีผลลัพธ์หลังเรียก usp_CaptureBaseline ครั้งที่สองขึ้นไป)
-- ----------------------------------------------------------------------------
DECLARE @Cur int = (SELECT MAX(RunId) FROM dbo.BaselineRun),
        @Prv int = @Cur - 1;

SELECT c.wait_type,
       c.wait_time_ms - p.wait_time_ms                          AS WaitTimeDelta_ms,
       c.waiting_tasks_count - p.waiting_tasks_count            AS TaskCountDelta,
       c.signal_wait_time_ms - p.signal_wait_time_ms            AS SignalWaitDelta_ms
FROM dbo.WaitStats AS c
JOIN dbo.WaitStats AS p
  ON p.wait_type = c.wait_type
 AND p.RunId = @Prv
WHERE c.RunId = @Cur
ORDER BY WaitTimeDelta_ms DESC;
GO

-- ----------------------------------------------------------------------------
-- Cleanup (รันเมื่อต้องการเริ่มใหม่ทั้งหมด):
-- USE master; DROP DATABASE IF EXISTS DBA_Baseline;
-- ----------------------------------------------------------------------------
