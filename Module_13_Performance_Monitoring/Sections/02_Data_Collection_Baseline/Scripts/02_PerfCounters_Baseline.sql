-- ============================================================================
-- Module 13 - Section 2 - Script 02: Baseline จาก sys.dm_os_performance_counters
-- ข้อกำหนดเบื้องต้น: รัน 01_DBA_Baseline_Setup.sql ก่อน (มี DBA_Baseline)
-- รันได้บน: SQL Server 2019+
-- หัวใจของสคริปต์: ค่า counter ส่วนใหญ่เป็น "ค่าสะสม" — ต้องหาผลต่างระหว่าง
--                  snapshot สองรอบจึงได้ "อัตราต่อช่วงเวลา" ที่ใช้เทียบ baseline
-- ============================================================================

USE DBA_Baseline;
GO

-- ----------------------------------------------------------------------------
-- Task 1: เก็บรอบใหม่ (รอบที่สองขึ้นไปจึงจะเทียบได้)
-- ----------------------------------------------------------------------------
EXEC dbo.usp_CaptureBaseline @Note = N'รอบเทียบ perf counters';
GO

-- ----------------------------------------------------------------------------
-- Task 2: Batch Requests/sec ระหว่างสองรอบล่าสุด
-- คำนวณ: (ค่าสะสมรอบใหม่ - ค่าสะสมรอบเก่า) / วินาทีระหว่างรอบ
-- ----------------------------------------------------------------------------
DECLARE @Cur  int = (SELECT MAX(RunId) FROM dbo.BaselineRun),
        @Prv  int = @Cur - 1,
        @Secs float =
            (SELECT DATEDIFF(second, p.CapturedAt, c.CapturedAt)
             FROM dbo.BaselineRun AS c
             JOIN dbo.BaselineRun AS p ON p.RunId = @Prv
             WHERE c.RunId = @Cur);

IF @Secs IS NULL OR @Secs = 0
    SELECT 'ยังมี snapshot รอบเดียว — รอ 5-15 นาที แล้วรัน usp_CaptureBaseline อีกครั้ง' AS Note;
ELSE
    SELECT c.counter_name,
           c.instance_name,
           c.cntr_value - p.cntr_value                      AS DeltaValue,
           @Secs                                            AS SecondsBetweenRuns,
           (c.cntr_value - p.cntr_value) / @Secs            AS ValuePerSecond
    FROM dbo.PerfCounters AS c
    JOIN dbo.PerfCounters AS p
      ON p.object_name   = c.object_name
     AND p.counter_name  = c.counter_name
     AND p.instance_name = c.instance_name
     AND p.RunId         = @Prv
    WHERE c.RunId = @Cur
      AND c.object_name LIKE N'%SQL Statistics%'
      AND c.counter_name IN (N'Batch Requests/sec',
                             N'SQL Compilations/sec',
                             N'SQL Re-Compilations/sec')
    ORDER BY c.counter_name;
GO

-- ----------------------------------------------------------------------------
-- Task 3: ค่า point-in-time (cntr_type = 65792) — อ่านจากรอบล่าสุดตรง ๆ ได้
-- เช่น Page Life Expectancy, Active Temp Tables, Log Growths
-- ----------------------------------------------------------------------------
SELECT counter_name, instance_name, cntr_value
FROM dbo.PerfCounters
WHERE RunId = (SELECT MAX(RunId) FROM dbo.BaselineRun)
  AND counter_name IN (N'Page life expectancy',
                       N'Active Temp Tables',
                       N'Log Growths',
                       N'Memory Grants Pending',
                       N'Processes blocked')
ORDER BY counter_name, instance_name;
GO

-- ----------------------------------------------------------------------------
-- Task 4: Log Growths ต่อ database เทียบระหว่างสองรอบ (ควรเป็น 0)
-- ----------------------------------------------------------------------------
DECLARE @Cur int = (SELECT MAX(RunId) FROM dbo.BaselineRun),
        @Prv int = @Cur - 1;

SELECT c.instance_name AS DatabaseName,
       c.cntr_value - ISNULL(p.cntr_value, c.cntr_value) AS LogGrowthsDelta
FROM dbo.PerfCounters AS c
LEFT JOIN dbo.PerfCounters AS p
       ON p.object_name   = c.object_name
      AND p.counter_name  = c.counter_name
      AND p.instance_name = c.instance_name
      AND p.RunId         = @Prv
WHERE c.RunId = @Cur
  AND c.object_name LIKE N'%Databases%'
  AND c.counter_name = N'Log Growths'
  AND c.instance_name <> N'_Total'
ORDER BY LogGrowthsDelta DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 5: I/O latency ต่อ file จากสองรอบล่าสุด (ms ต่อ read/write เฉลี่ยในช่วงนั้น)
-- ----------------------------------------------------------------------------
DECLARE @Cur int = (SELECT MAX(RunId) FROM dbo.BaselineRun),
        @Prv int = @Cur - 1;

SELECT c.database_name,
       c.file_name,
       c.type_desc,
       c.num_of_reads      - p.num_of_reads      AS ReadsDelta,
       c.io_stall_read_ms  - p.io_stall_read_ms  AS ReadStallDelta_ms,
       CAST((c.io_stall_read_ms - p.io_stall_read_ms)
            / NULLIF(c.num_of_reads - p.num_of_reads, 0) AS decimal(10, 2)) AS AvgReadLatency_ms,
       c.num_of_writes     - p.num_of_writes     AS WritesDelta,
       CAST((c.io_stall_write_ms - p.io_stall_write_ms)
            / NULLIF(c.num_of_writes - p.num_of_writes, 0) AS decimal(10, 2)) AS AvgWriteLatency_ms
FROM dbo.FileStats AS c
JOIN dbo.FileStats AS p
  ON p.database_name = c.database_name
 AND p.file_name     = c.file_name
 AND p.RunId         = @Prv
WHERE c.RunId = @Cur
ORDER BY AvgReadLatency_ms DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 6: ตั้ง Agent job เก็บอัตโนมัติ (โครง — รันคำสั่งนี้เพื่อสร้าง job)
-- เก็บทุก 15 นาที + ลบ snapshot เก่ากว่า 30 วัน
-- ----------------------------------------------------------------------------
-- USE msdb;
-- EXEC dbo.sp_add_job @job_name = N'DBA - Capture Baseline Snapshot', @delete_level = 0;
-- EXEC dbo.sp_add_jobstep @job_name = N'DBA - Capture Baseline Snapshot',
--      @step_name = N'Capture', @subsystem = N'TSQL',
--      @database_name = N'DBA_Baseline',
--      @command = N'EXEC dbo.usp_CaptureBaseline @Note = N''auto'';';
-- EXEC dbo.sp_add_jobschedule @job_name = N'DBA - Capture Baseline Snapshot',
--      @name = N'Every 15 min', @freq_type = 4, @freq_interval = 1,
--      @freq_subday_type = 4, @freq_subday_interval = 15;
-- EXEC dbo.sp_add_jobserver @job_name = N'DBA - Capture Baseline Snapshot';
