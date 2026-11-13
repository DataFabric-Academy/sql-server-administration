-- ============================================================================
-- Section 03 — Demo 01: อ่านไฟล์ audit log ด้วย sys.fn_get_audit_file
-- สร้าง audit จับกิจกรรม → ทำกิจกรรม → อ่าน/กรองผล → cleanup
-- แก้ @AUDIT_PATH ตรง 2 จุด (CREATE SERVER AUDIT และ fn_get_audit_file)
-- ============================================================================
USE master;
GO

-- ---------- ขั้น 0: เตรียม (idempotent) ----------
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'ReadDemoAudit')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'ReadDemoAudit' AND is_state_enabled = 1)
        ALTER SERVER AUDIT ReadDemoAudit WITH (STATE = OFF);
    DROP SERVER AUDIT ReadDemoAudit;
END
GO

CREATE SERVER AUDIT ReadDemoAudit
TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 20 MB, MAX_ROLLOVER_FILES = 5)
WITH (QUEUE_DELAY = 0, ON_FAILURE = CONTINUE);   -- 0 = เขียนทันที สะดวกตอนทดสอบ
GO

ALTER SERVER AUDIT ReadDemoAudit WITH (STATE = ON);
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'ReadDemoDbSpec')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
               WHERE name = 'ReadDemoDbSpec' AND is_state_enabled = 1)
        ALTER DATABASE AUDIT SPECIFICATION ReadDemoDbSpec WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION ReadDemoDbSpec;
END
GO

CREATE DATABASE AUDIT SPECIFICATION ReadDemoDbSpec
FOR SERVER AUDIT ReadDemoAudit
ADD (SELECT ON OBJECT::Production.Product BY public)
WITH (STATE = ON);
GO

-- ---------- ขั้น 1: สร้างกิจกรรมที่จะถูกจับ ----------
SELECT TOP 5 ProductID, Name FROM Production.Product;
GO

-- ---------- ขั้น 2: อ่านไฟล์ audit ----------
-- แก้ path ตรงนี้ให้ตรงกับ FILEPATH ด้านบน
SELECT TOP 30
       event_time,
       action_id,                          -- 'SL' = SELECT, 'LGIS' = login success ...
       class_type,
       server_principal_name,
       database_principal_name,
       object_name,
       statement,
       succeeded,
       session_id
FROM sys.fn_get_audit_file('C:\AuditLogs\ReadDemoAudit*', default, default)
ORDER BY event_time DESC;
GO

-- ---------- ขั้น 3: กรองเฉพาะ session ของเรา (ทริคตอนทดสอบ) ----------
SELECT event_time, action_id, object_name, statement, succeeded
FROM sys.fn_get_audit_file('C:\AuditLogs\ReadDemoAudit*', default, default)
WHERE session_id = @@SPID
ORDER BY event_time DESC;
GO

-- ---------- ขั้น 4: กรองตามเวลา (ตัวอย่าง: 10 นาทีล่าสุด) ----------
SELECT event_time, action_id, server_principal_name, statement
FROM sys.fn_get_audit_file('C:\AuditLogs\ReadDemoAudit*', default, default)
WHERE event_time >= DATEADD(MINUTE, -10, SYSDATETIME())
  AND action_id = 'SL'
ORDER BY event_time DESC;
GO

-- ---------- ขั้น 5: EXECUTE AS — audit ตามบริบทผู้รัน ----------
CREATE USER AuditTestUser WITHOUT LOGIN;
GRANT SELECT ON Production.Product TO AuditTestUser;
GO

EXECUTE AS USER = 'AuditTestUser';
SELECT TOP 3 ProductID, Name FROM Production.Product;
REVERT;
GO

-- ในไฟล์จะบันทึก server_principal_name = คนจริง แต่
-- database_principal_name = AuditTestUser (บริบทที่ถูกสวม)
SELECT event_time, action_id, server_principal_name, database_principal_name, statement
FROM sys.fn_get_audit_file('C:\AuditLogs\ReadDemoAudit*', default, default)
ORDER BY event_time DESC;
GO

-- ---------- Cleanup ----------
ALTER DATABASE AUDIT SPECIFICATION ReadDemoDbSpec WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION ReadDemoDbSpec;
DROP USER AuditTestUser;
GO
USE master;
GO
ALTER SERVER AUDIT ReadDemoAudit WITH (STATE = OFF);
DROP SERVER AUDIT ReadDemoAudit;
GO
-- จบสคริปต์
