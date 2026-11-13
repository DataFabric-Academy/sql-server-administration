-- ============================================================================
-- Module 13 - Section 2 - Script 03: Data Collector (แนวทาง legacy) — เปิด/ตรวจ/ปิด
-- รันได้บน: SQL Server 2019-2025 (Windows), สิทธิ์ sysadmin (หรือ dc_admin)
-- ⚠️ ความหมายของโมดูลนี้: Data Collector = LEGACY — ทำงานได้แต่ไม่ใช่การลงทุน
--    ใหม่ในโลกปัจจุบัน (ใช้ Query Store + DMV baseline + Azure Arc แทน)
--    สคริปต์นี้ใช้เพื่อ "เข้าใจ/ดูแลระบบเดิม" เท่านั้น
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 1: ตรวจสถานะปัจจุบันของ Data Collector (ก่อนเปิดอะไรทั้งสิ้น)
-- ----------------------------------------------------------------------------
USE msdb;
GO

SELECT name,
       collection_mode,          -- 0 = Non-cached, 1 = Cached
       is_running,
       days_until_expiration,
       proxy_id
FROM msdb.dbo.syscollector_collection_sets;
GO

-- ----------------------------------------------------------------------------
-- Task 2: เปิด Data Collector
-- (ต้อง configure Management Data Warehouse ผ่าน SSMS wizard ก่อน
--  จึงจะมี standard collection sets ให้ใช้ — ดู README ของ Section นี้)
-- ----------------------------------------------------------------------------
EXEC msdb.dbo.sp_syscollector_enable_collector;
GO

SELECT name,
       collection_mode,
       is_running,
       collection_job_id,        -- Agent job ที่รันเก็บข้อมูล
       upload_job_id             -- Agent job ที่อัปโหลดเข้า MDW
FROM msdb.dbo.syscollector_collection_sets;
GO

-- ----------------------------------------------------------------------------
-- Task 3: ตรวจสาม role ของ Data Collector ใน msdb
--   dc_admin   = จัดการ collection sets ได้ทั้งหมด
--   dc_operator= เริ่ม/หยุด collection, ดู log
--   dc_reader  = อ่านข้อมูลใน MDW
-- ----------------------------------------------------------------------------
SELECT dp.name, dp.type_desc
FROM msdb.sys.database_principals AS dp
WHERE dp.name IN (N'dc_admin', N'dc_operator', N'dc_reader');
GO

-- ----------------------------------------------------------------------------
-- Task 4: ดู execution log (เมื่อ collection sets เริ่มวิ่งแล้ว)
-- ----------------------------------------------------------------------------
SELECT TOP (20)
       log_id,
       parent_log_id,
       collection_set_id,
       start_time,
       last_iteration_time,
       finish_time,
       runtime_status,        -- 1 = started, 2 = running, 3 = finished ...
       failure_count
FROM msdb.dbo.syscollector_collector_execution_log
ORDER BY start_time DESC;
GO

-- ----------------------------------------------------------------------------
-- Task 5: เริ่ม/หยุด collection set เฉพาะชุด (ตัวอย่าง: Disk Usage)
-- แก้ @collection_set_id จากผล Task 2
-- ----------------------------------------------------------------------------
-- EXEC msdb.dbo.sp_syscollector_start_collection_set @collection_set_id = 1;
-- EXEC msdb.dbo.sp_syscollector_stop_collection_set  @collection_set_id = 1;
GO

-- ----------------------------------------------------------------------------
-- Cleanup: ปิด Data Collector เมื่อจบแล็บ
-- (หากต้องการล้างถาวร: ลบ collection sets ที่สร้างเอง + ถอนการ configure MDW
--  ผ่าน SSMS: right-click instance > Tasks > Configure Data Collection)
-- ----------------------------------------------------------------------------
-- EXEC msdb.dbo.sp_syscollector_disable_collector;
