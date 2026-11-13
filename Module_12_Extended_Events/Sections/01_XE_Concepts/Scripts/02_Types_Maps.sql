-- =============================================================================
-- 02_Types_Maps.sql - Types/Maps: แปล map_key (ตัวเลข) เป็นข้อความที่อ่านได้
-- เหตุผล: event fields หลายตัวเก็บเป็น key ของ map type เช่น wait_type, lock mode,
--         log operation การอ่านผล XML จึงต้องรู้ map หรือดึง /text ที่แปลแล้ว
-- สคริปต์อ่านอย่างเดียว รันได้ทุกเวอร์ชัน SQL Server ที่ support อยู่
-- =============================================================================

USE master;
GO

-- Task 1: รายการ map types ทั้งหมดใน package sqlserver
SELECT DISTINCT dvm.name AS map_name, dvm.object_package_guid
FROM sys.dm_xe_map_values AS dvm
JOIN sys.dm_xe_packages AS p ON p.guid = dvm.object_package_guid
WHERE p.name = 'sqlserver'
ORDER BY map_name;
GO

-- Task 2: wait_types map - แปล wait_type key เป็นชื่อ (ใช้กับ event wait_info)
-- ลองหา wait ที่คุ้นจาก Module 13: PAGEIOLATCH_SH, LCK_M_S, WRITELOG, CXPACKET
SELECT map_key, map_value
FROM sys.dm_xe_map_values
WHERE name = 'wait_types'
  AND object_package_guid = (SELECT guid FROM sys.dm_xe_packages WHERE name = 'sqlserver')
ORDER BY map_key;
GO

-- Task 3: lock_mode map - ใช้กับ event lock_acquired / lock_released
SELECT map_key, map_value
FROM sys.dm_xe_map_values
WHERE name = 'lock_mode'
  AND object_package_guid = (SELECT guid FROM sys.dm_xe_packages WHERE name = 'sqlserver')
ORDER BY map_key;
GO

-- Task 4: log_op map - operation codes ของ event transaction_log
-- (LOP_DELETE_SPLIT คือ mid-page split - ใช้ในแล็บ Exercise 4)
SELECT map_key, map_value
FROM sys.dm_xe_map_values
WHERE name = 'log_op'
  AND object_package_guid = (SELECT guid FROM sys.dm_xe_packages WHERE name = 'sqlserver')
ORDER BY map_key;
GO

-- Task 5: ตรวจว่า field ไหนของ event ใช้ map type ใด
-- (type_name ที่ลงท้าย map ระบุว่า field นั้นอ่านค่าจาก map ตัวไหน)
SELECT oc.object_name AS event_name,
       oc.name AS field_name,
       oc.type_name AS map_type
FROM sys.dm_xe_object_columns AS oc
JOIN sys.dm_xe_packages AS p ON p.guid = oc.object_package_guid
WHERE p.name = 'sqlserver'
  AND oc.object_name IN ('wait_info', 'lock_acquired', 'transaction_log')
  AND oc.column_type = 'data'
  AND oc.type_name LIKE '%map%'
ORDER BY oc.object_name, oc.name;
GO

-- Task 6: ทดลองเอง
-- 1) หา map ของ event 'error_reported' แล้วดูว่า severity map เป็นข้อความไหม
-- 2) นับว่า wait_types map มีกี่รายการ แล้วเทียบกับ sys.dm_os_wait_stats ที่เห็นใน Module 13
-- 3) เขียน query ที่ join sys.dm_xe_object_columns กับ sys.dm_xe_map_values
--    เพื่อแสดง "field -> map -> ค่าที่เป็นไปได้" ในตารางเดียว
