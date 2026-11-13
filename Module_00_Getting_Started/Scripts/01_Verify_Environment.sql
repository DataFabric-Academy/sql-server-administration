-- 01_Verify_Environment.sql
-- ตรวจความพร้อมของ environment ก่อนเริ่มเรียนทุกโมดูล
-- รันใน SSMS (sqlcmd mode ไม่จำเป็น) บน instance ที่จะใช้เรียน

USE master;
GO

-- 1) เวอร์ชันของ SQL Server (คาดหวัง 17.x = SQL Server 2025)
SELECT @@SERVERNAME AS ServerName,
       @@VERSION AS Version;
-- ✅ ควรเห็น: Microsoft SQL Server 2025 (RTM...) - 17.x.xxxx.x

-- 2) Services ที่รันอยู่ — SQL Server Agent ต้อง RUNNING สำหรับ Module 8-10
SELECT servicename, service_account, startup_type_desc, status_desc, is_clustered
FROM sys.dm_server_services;
-- ✅ SQL Server Agent ต้องสถานะ RUNNING

-- 3) ฐานข้อมูล AdventureWorks2025 พร้อมใช้
IF DB_ID(N'AdventureWorks2025') IS NULL
    PRINT N'❌ AdventureWorks2025 ยังไม่ถูก restore — รัน 00_Restore_AdventureWorks2025.sql ก่อน';
ELSE
    PRINT N'✅ AdventureWorks2025 พร้อมใช้';
GO

USE AdventureWorks2025;
GO

-- 4) ตารางหลักที่แล็บใช้
SELECT COUNT(*) AS SalesOrderHeader_Rows
FROM Sales.SalesOrderHeader;          -- คาดหวัง ~31,465 แถว

-- 5) Instant File Initialization & default paths (Module 05-07 ใช้อ้างอิง)
SELECT name, physical_name, size / 128 AS SizeMB, growth
FROM sys.master_files
WHERE database_id = 2;                -- tempdb

-- 6) คอนฟิกพื้นฐานที่โมดูลอื่นจะพูดถึง
SELECT [name], [value], [value_in_use], [description]
FROM sys.configurations
WHERE [name] IN (
    N'max degree of parallelism',
    N'cost threshold for parallelism',
    N'max server memory (MB)',
    N'common criteria compliance enabled',
    N'backup compression default',
    N'backup compression algorithm',
    N'show advanced options'
)
ORDER BY [name];
-- ✅ 'backup compression algorithm' มีเฉพาะ SQL Server 2025+ (0 = MS_XPRESS, 3 = ZSTD)

-- 7) Extended Events: system_health session ต้องเปิด (Module 12)
SELECT name, create_time, total_buffer_size
FROM sys.dm_xe_sessions
WHERE name = N'system_health';
-- ✅ ต้องมี 1 แถว

-- 8) Query Store ยังปิดสำหรับ AdventureWorks2025 (Module 08/13 จะเปิดเอง)
SELECT name, is_query_store_on
FROM sys.databases
WHERE name = N'AdventureWorks2025';

-- 9) SQL Server Agent ต้องพร้อม (ตาราง msdb พร้อม)
USE msdb;
GO
SELECT COUNT(*) AS JobCount FROM msdb.dbo.sysjobs;

PRINT N'=== ตรวจเสร็จสิ้น — แก้ทุก ❌ ก่อนเริ่ม Module 1 ===';
