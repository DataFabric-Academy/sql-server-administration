-- =============================================================================
-- 01_Explore_XE_Metadata.sql - สำรวจ catalog ของ Extended Events ใน instance
-- สคริปต์อ่านอย่างเดียว (ไม่สร้าง/ไม่แก้อะไร) รันได้บน SQL Server 2019 ถึง 2025
-- สิทธิ์: VIEW SERVER STATE (sysadmin ผ่านหมด)
-- ปรับปรุงจากแนวคิดคอร์ส 20764D Module 12 (เดิมรันบน SQL Server 2016/AdventureWorks2016)
-- =============================================================================

USE master;
GO

-- Task 1: packages ที่มากับ instance
-- สองตัวหลัก: sqlserver (events/actions ของ engine) และ package0 (targets/infra)
SELECT name, guid, description
FROM sys.dm_xe_packages
ORDER BY name;
GO

-- Task 2: event ทั้งหมด จัดกลุ่มตาม package
SELECT p.name AS package_name,
       COUNT(*) AS event_count
FROM sys.dm_xe_objects AS o
JOIN sys.dm_xe_packages AS p ON p.guid = o.package_guid
WHERE o.object_type = 'event'
GROUP BY p.name
ORDER BY event_count DESC;
GO

-- Task 3: events ที่ใช้บ่อยในงาน DBA (ของ package sqlserver)
SELECT o.name AS event_name, o.description
FROM sys.dm_xe_objects AS o
JOIN sys.dm_xe_packages AS p ON p.guid = o.package_guid
WHERE o.object_type = 'event'
  AND p.name = 'sqlserver'
  AND o.name IN (
        'sql_batch_completed', 'sql_batch_starting',
        'rpc_completed', 'rpc_starting',
        'error_reported',
        'lock_acquired', 'lock_released',
        'transaction_log',
        'wait_info',
        'file_written', 'file_read',
        'blocked_process_report',
        'xml_deadlock_report')
ORDER BY o.name;
GO

-- Task 4: actions ที่ใช้ได้ (ข้อมูลเพิ่ม ณ จุดเกิด event)
SELECT o.name AS action_name, o.description
FROM sys.dm_xe_objects AS o
JOIN sys.dm_xe_packages AS p ON p.guid = o.package_guid
WHERE o.object_type = 'action'
  AND p.name = 'sqlserver'
  AND o.name IN ('sql_text', 'client_hostname', 'client_app_name',
                 'session_id', 'database_name', 'username', 'client_pid')
ORDER BY o.name;
GO

-- Task 5: targets ทั้งหมด (จะใช้จริงใน Section 2)
SELECT o.name AS target_name, o.capabilities_desc, o.description
FROM sys.dm_xe_objects AS o
JOIN sys.dm_xe_packages AS p ON p.guid = o.package_guid
WHERE o.object_type = 'target'
ORDER BY o.name;
GO

-- Task 6: fields (data) ของ event ที่จะใช้ใน Section 2 - sql_batch_completed
-- สังเกต duration เป็นไมโครวินาที (คำอธิบายเขียนไว้ใน description)
SELECT oc.name AS column_name, oc.column_type, oc.type_name, oc.description
FROM sys.dm_xe_object_columns AS oc
JOIN sys.dm_xe_packages AS p ON p.guid = oc.object_package_guid
WHERE oc.object_name = 'sql_batch_completed'
  AND p.name = 'sqlserver'
  AND oc.column_type = 'data'
ORDER BY oc.name;
GO

-- Task 7: customizable attributes ของ target event_file
-- (filename, max_file_size, max_rollover_files)
SELECT oc.name AS parameter_name, oc.column_value AS default_value, oc.description
FROM sys.dm_xe_object_columns AS oc
WHERE oc.object_name = 'event_file'
  AND oc.column_type = 'customizable';
GO

-- Task 8: ดู definition ของ session ในตัว (system_health)
-- (รายละเอียดการใช้งาน system_health อยู่ใน Section 2 Script 04)
SELECT s.name, s.create_time, s.total_regular_buffers, s.dropped_event_count
FROM sys.dm_xe_sessions AS s
WHERE s.name = 'system_health';

-- ดู events ที่ system_health จับ
SELECT se.event_name
FROM sys.server_event_session_events AS se
JOIN sys.server_event_sessions AS ss ON ss.event_session_id = se.event_session_id
WHERE ss.name = 'system_health'
ORDER BY se.event_name;
GO

-- Task 9: ทดลองเอง
-- 1) หา event เกี่ยวกับ 'sort' :  WHERE o.name LIKE '%sort%'
-- 2) ดู fields ของ rpc_completed (เทียบกับ sql_batch_completed - มี statement param ไหม)
-- 3) รายงานว่า system_health มี target อะไร (sys.server_event_session_targets)
