-- ============================================================================
-- Section 02 — Demo 02: Database Audit Specification
-- ฐานข้อมูล: AdventureWorks2025 (ใช้ Server Audit "LabAudit" จาก Demo 01 หรือสร้างใหม่)
-- จับ: SELECT/INSERT บนตาราง HR + DDL (SCHEMA_OBJECT_CHANGE_GROUP)
-- ============================================================================
USE master;
GO

-- ---------- เตรียม audit (ถ้ายังไม่มีจาก Demo 01) ----------
IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'LabAudit')
BEGIN
    CREATE SERVER AUDIT LabAudit
    TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 50 MB, MAX_ROLLOVER_FILES = 10)
    WITH (QUEUE_DELAY = 5000, ON_FAILURE = CONTINUE);
    ALTER SERVER AUDIT LabAudit WITH (STATE = ON);
END
ELSE IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'LabAudit' AND is_state_enabled = 0)
BEGIN
    ALTER SERVER AUDIT LabAudit WITH (STATE = ON);
END
GO

USE AdventureWorks2025;
GO

-- ---------- ขั้น 1: ลบ spec เดิมถ้ามี (แก้ spec ต้องปิดก่อน) ----------
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'LabDbAuditSpec')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
               WHERE name = 'LabDbAuditSpec' AND is_state_enabled = 1)
        ALTER DATABASE AUDIT SPECIFICATION LabDbAuditSpec WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION LabDbAuditSpec;
END
GO

-- ---------- ขั้น 2: สร้าง Database Audit Specification ----------
CREATE DATABASE AUDIT SPECIFICATION LabDbAuditSpec
FOR SERVER AUDIT LabAudit
ADD (SELECT, INSERT ON OBJECT::HumanResources.Department BY public),
ADD (SELECT ON SCHEMA::Sales BY public),
ADD (SCHEMA_OBJECT_CHANGE_GROUP)
WITH (STATE = ON);
GO

-- ---------- ขั้น 3: สร้างเหตุการณ์ให้ audit จับ ----------
-- 3a) SELECT ที่ตรงกับ action ที่ประกาศ
SELECT TOP 5 DepartmentID, Name FROM HumanResources.Department;
SELECT TOP 3 SalesOrderID, OrderDate FROM Sales.SalesOrderHeader;
GO

-- 3b) INSERT ที่ถูกจับ + ลบทิ้ง
INSERT INTO HumanResources.Department (DepartmentID, Name, GroupName)
VALUES (991, N'AuditDemoDept', N'Executive General and Administration');
DELETE FROM HumanResources.Department WHERE DepartmentID = 991;  -- DELETE ไม่ได้ประกาศ จะไม่ถูกจับ
GO

-- 3c) DDL → SCHEMA_OBJECT_CHANGE_GROUP
CREATE TABLE Sales.AuditDemoTable (Id int);
DROP TABLE Sales.AuditDemoTable;
GO

-- ---------- ขั้น 4: แก้ไข spec (ต้องปิด → แก้ → เปิด) ----------
ALTER DATABASE AUDIT SPECIFICATION LabDbAuditSpec WITH (STATE = OFF);
GO

ALTER DATABASE AUDIT SPECIFICATION LabDbAuditSpec
ADD (UPDATE ON OBJECT::HumanResources.Department BY public);

ALTER DATABASE AUDIT SPECIFICATION LabDbAuditSpec WITH (STATE = ON);
GO
-- ต่อจากนี้ UPDATE บน Department ก็ถูกจับด้วย

-- ---------- ขั้น 5: ตรวจ metadata ของ spec ----------
SELECT sp.name AS spec_name, sp.is_state_enabled,
       sd.audit_action_name, sd.class_desc,
       sd.schema_name, OBJECT_NAME(sd.major_id) AS object_name,
       sd.audited_result
FROM sys.database_audit_specifications sp
JOIN sys.database_audit_specification_details sd
     ON sd.database_specification_id = sp.database_specification_id
WHERE sp.name = 'LabDbAuditSpec'
ORDER BY sd.audit_action_name;
GO

-- เทียบกับรายการ action ทั้งหมดที่ระบบมี
SELECT name, class_desc, parent_class_desc, containing_group_name
FROM sys.dm_audit_actions
WHERE name IN ('SELECT', 'INSERT', 'UPDATE', 'SCHEMA_OBJECT_CHANGE_GROUP')
ORDER BY name;
GO

-- ---------- ขั้น 6: อ่านผลจากไฟล์ audit (ตัวอย่างสั้น — ลึกที่ Section 03) ----------
SELECT TOP 30 event_time, action_id, object_name, statement,
              server_principal_name, succeeded
FROM sys.fn_get_audit_file('C:\AuditLogs\LabAudit*', default, default)
ORDER BY event_time DESC;
GO
-- คาดหวัง: เห็น statement SELECT/INSERT/CREATE TABLE ที่รันเมื่อกี้
-- action_id = 'SL' (SELECT), 'IN' (INSERT), 'UP' (UPDATE), 'CR' (CREATE), 'DF' (DROP) ฯลฯ

-- ---------- Cleanup ----------
ALTER DATABASE AUDIT SPECIFICATION LabDbAuditSpec WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION LabDbAuditSpec;
GO

USE master;
GO
ALTER SERVER AUDIT LabAudit WITH (STATE = OFF);
DROP SERVER AUDIT LabAudit;
GO
-- จบสคริปต์
