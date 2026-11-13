-- ============================================================================
-- Module 08, Section 1 — ตรวจสถานะ SQL Server Agent และเปิดตัวเลือก Agent XPs
-- รันได้บน SQL Server 2019/2022/2025 (idempotent — รันซ้ำได้)
-- สังเกต: เมื่อ Agent service รันอยู่ ตัวเลือก Agent XPs ถูกเปิดให้อัตโนมัติ
--         เมื่อ Agent หยุด ตัวเลือกถูกปิดอัตโนมัติ — สคริปต์นี้เปิดกลับให้เอง
-- ============================================================================

USE master;
GO

/* ----------------------------------------------------------------------------
   1) ตรวจสถานะบริการ SQL Server Agent และ service account ที่รันอยู่
   ---------------------------------------------------------------------------- */
SELECT servicename,
       service_account,
       startup_type_desc,
       status_desc,
       is_clustered,
       immediate_restart
FROM sys.dm_server_services
WHERE servicename LIKE N'SQL Server Agent%';
-- Expected: status_desc = 'Running', service_account เช่น NT SERVICE\SQLSERVERAGENT
-- ถ้า status_desc = 'Stopped' → เปิดผ่าน SQL Server Configuration Manager หรือ services.msc
--           (Linux/container: ตรวจ docker ps / systemctl status mssql-server-agent)

/* ----------------------------------------------------------------------------
   2) ดูค่าปัจจุบันของ Agent XPs (เป็น advanced option จึงต้องเปิด show advanced)
   ---------------------------------------------------------------------------- */
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

EXEC sp_configure 'Agent XPs';          -- แสดงค่า config_value / run_value
SELECT name, value, value_in_use, description
FROM sys.configurations
WHERE name = N'Agent XPs';

/* ----------------------------------------------------------------------------
   3) เปิด Agent XPs ถ้าปิดอยู่ (เช่น Agent เคยหยุดแล้ว engine ปิดให้เอง)
   ---------------------------------------------------------------------------- */
IF (SELECT value_in_use FROM sys.configurations WHERE name = N'Agent XPs') = 0
BEGIN
    PRINT N'Agent XPs ปิดอยู่ — กำลังเปิด ...';
    EXEC sp_configure 'Agent XPs', 1;
    RECONFIGURE;
    PRINT N'เปิดเรียบร้อย — หากยังทำงานไม่ได้ ตรวจว่า Agent service รันอยู่ด้วย';
END
ELSE
BEGIN
    PRINT N'Agent XPs เปิดอยู่แล้ว — ไม่ต้องแก้อะไร';
END
GO

/* ----------------------------------------------------------------------------
   4) ตรวจ msdb schema ของ Agent พร้อมใช้ — ควรเห็น job ในตัวของระบบ
      (syspolicy_purge_history มีมากับตัวใน Policy-Based Management)
   ---------------------------------------------------------------------------- */
SELECT job_id, name, enabled, date_created, date_modified
FROM msdb.dbo.sysjobs
ORDER BY name;

/* ----------------------------------------------------------------------------
   5) ทดสอบว่า Agent API พร้อมใช้ — เรียก proc ของ Agent แบบไม่มีผลข้างเคียง
   ---------------------------------------------------------------------------- */
EXEC msdb.dbo.sp_help_job @execution_status = 4;   -- 4 = idle jobs (ไม่กำลังรัน)
-- ถ้ารันผ่านโดยไม่ error แปลว่า Agent XPs พร้อมใช้แล้ว
-- Expected: แถวของ job ที่ยังไม่กำลังรัน (ตอนติดตั้งสด = syspolicy_purge_history)
