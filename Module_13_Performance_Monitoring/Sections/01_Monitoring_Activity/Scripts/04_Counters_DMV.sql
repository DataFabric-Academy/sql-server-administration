-- ============================================================================
-- Module 13 - Section 1 - Script 04: SQL Server counters ผ่าน sys.dm_os_performance_counters
-- ปรับจาก: Microsoft 20764D Mod13 "Demo 3 - counters.sql"
-- รันได้บน: SQL Server 2019+ (สิทธิ์ VIEW SERVER STATE)
-- โน้ต: ข้อมูลชุดนี้เป็นชุดเดียวกับ Windows Performance Monitor (perfmon)
--       แต่อ่านด้วย T-SQL ได้จึงเก็บ baseline อัตโนมัติได้ง่าย
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 1: ดู counter ทั้งหมด (กว่า 500 แถว — ลอง scroll ดู object ต่าง ๆ)
-- ----------------------------------------------------------------------------
SELECT object_name, counter_name, instance_name, cntr_value, cntr_type
FROM sys.dm_os_performance_counters
ORDER BY object_name, counter_name, instance_name;
GO

-- ----------------------------------------------------------------------------
-- Task 2: ตัวชี้วัดสำคัญที่คัดมาแล้ว
-- คำอธิบาย cntr_type (ค่าคงที่ของ Windows):
--   65792      = ค่า point-in-time (อ่านตรง ๆ ได้ เช่น PLE, Active Temp Tables)
--   272696576  = ค่าต่อวินาที (ต้อง snapshot สองรอบ หาผลต่าง / เวลา)
--   537003264  = ค่าแบบ fraction (ต้องหารด้วย base counter เช่น cache hit ratio)
-- ----------------------------------------------------------------------------
SELECT object_name, counter_name, instance_name, cntr_value, cntr_type
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'Buffer cache hit ratio', N'Buffer cache hit ratio base',
                       N'Page life expectancy', N'Log Growths', N'Log Shrinks',
                       N'Active Temp Tables', N'Batch Requests/sec',
                       N'SQL Compilations/sec', N'SQL Re-Compilations/sec',
                       N'Memory Grants Pending', N'Processes blocked',
                       N'Total Server Memory (KB)', N'Target Server Memory (KB)')
   OR (object_name LIKE N'%Databases%' AND counter_name = N'Log Growths')
ORDER BY object_name, counter_name, instance_name;
GO

-- ----------------------------------------------------------------------------
-- Task 3: อ่าน Buffer cache hit ratio อย่างถูกวิธี (หารด้วย base counter)
-- ----------------------------------------------------------------------------
WITH Raw AS (
    SELECT counter_name, cntr_value
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Buffer Manager%'
      AND counter_name IN (N'Buffer cache hit ratio', N'Buffer cache hit ratio base')
)
SELECT MAX(CASE WHEN counter_name = N'Buffer cache hit ratio'      THEN cntr_value END) AS HitRatio,
       MAX(CASE WHEN counter_name = N'Buffer cache hit ratio base' THEN cntr_value END) AS Base,
       CAST(MAX(CASE WHEN counter_name = N'Buffer cache hit ratio' THEN cntr_value END) AS float)
     / NULLIF(MAX(CASE WHEN counter_name = N'Buffer cache hit ratio base' THEN cntr_value END), 0)
       AS BufferCacheHitRatio
FROM Raw;
GO

-- ----------------------------------------------------------------------------
-- Task 4: วัด Batch Requests/sec จริง ๆ ด้วยการ snapshot สองรอบ (ห่างกัน 10 วินาที)
-- ค่า counter ที่ cntr_type = 272696576 เป็นค่าสะสม ต้องหาผลต่างและหารด้วยเวลา
-- ----------------------------------------------------------------------------
DECLARE @v1 bigint,
        @t1 datetime2(3) = SYSDATETIME();

SELECT @v1 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%SQL Statistics%'
  AND counter_name = N'Batch Requests/sec';

WAITFOR DELAY '00:00:10';

SELECT (c.cntr_value - @v1) / 10.0 AS BatchRequestsPerSec,
       @t1 AS MeasuredFrom
FROM sys.dm_os_performance_counters AS c
WHERE c.object_name LIKE N'%SQL Statistics%'
  AND c.counter_name = N'Batch Requests/sec';
GO

-- ----------------------------------------------------------------------------
-- Task 5: ตรวจ Log Growths ต่อ database (counter แบบสะสมตั้งแต่ restart)
-- ค่าควรเป็น 0 หรือใกล้ศูนย์ระหว่างเวลาทำงานปกติ
-- ----------------------------------------------------------------------------
SELECT instance_name AS DatabaseName,
       cntr_value    AS LogGrowthsSinceRestart
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%Databases%'
  AND counter_name = N'Log Growths'
  AND instance_name NOT IN (N'_Total')
ORDER BY cntr_value DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 6: Active Temp Tables + Processes blocked (point-in-time)
-- ----------------------------------------------------------------------------
SELECT counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'Active Temp Tables', N'Processes blocked');
GO
