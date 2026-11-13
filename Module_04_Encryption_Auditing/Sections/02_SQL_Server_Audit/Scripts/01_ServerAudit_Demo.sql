-- ============================================================================
-- Section 02 — Demo 01: Server Audit ครบวงจร (ปลายทางไฟล์ + server spec)
-- ฐานข้อมูล: master (audit) + AdventureWorks2025
-- แก้ @AUDIT_PATH ให้เป็นโฟลเดอร์ที่ SQL Server service account เขียนได้ก่อนรัน
-- ============================================================================
USE master;
GO

-- ---------- ขั้น 0: ลบของเดิมถ้ามี (idempotent) ----------
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'LabServerSpec')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_audit_specifications
               WHERE name = 'LabServerSpec' AND is_state_enabled = 1)
        ALTER SERVER AUDIT SPECIFICATION LabServerSpec WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION LabServerSpec;
END
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'LabAudit')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'LabAudit' AND is_state_enabled = 1)
        ALTER SERVER AUDIT LabAudit WITH (STATE = OFF);
    DROP SERVER AUDIT LabAudit;
END
GO

-- ---------- ขั้น 1: สร้าง Server Audit (ปลายทางไฟล์) ----------
CREATE SERVER AUDIT LabAudit
TO FILE
(
    FILEPATH = 'C:\AuditLogs\',          -- <-- แก้ path นี้ (ต้องมีโฟลเดอร์จริง)
    MAXSIZE = 50 MB,
    MAX_ROLLOVER_FILES = 10
)
WITH (QUEUE_DELAY = 5000, ON_FAILURE = CONTINUE);
GO

ALTER SERVER AUDIT LabAudit WITH (STATE = ON);
GO

-- ---------- ขั้น 2: Server Audit Specification — จับ failed login ----------
CREATE SERVER AUDIT SPECIFICATION LabServerSpec
FOR SERVER AUDIT LabAudit
ADD (FAILED_LOGIN_GROUP)
WITH (STATE = ON);
GO

-- ---------- ขั้น 3: สร้างเหตุการณ์ failed login ----------
-- ลองล็อกอินด้วยพาสเวิร์ดผิดจาก SSMS หรือ sqlcmd:
--   sqlcmd -S localhost -U SomeUser -P WrongPass
-- (ผลจะ flush ลงไฟล์ภายใน QUEUE_DELAY = 5 วินาที)

-- ---------- ขั้น 4: ตรวจ metadata ของ audit ----------
SELECT name, status_desc, is_state_enabled, create_date
FROM sys.server_audits;
GO

SELECT s.name AS spec_name, sd.audit_action_name, sd.is_state_enabled
FROM sys.server_audit_specifications s
JOIN sys.server_audit_specification_details sd
     ON sd.server_specification_id = s.server_specification_id;
GO

-- ไฟล์ .sqlaudit ถูกสร้างแล้วหรือยัง
SELECT name, is_state_enabled, status_desc,
       cast(max_file_size as varchar(20)) + ' MB' AS max_file_size
FROM sys.server_file_audits;
GO

-- ---------- ขั้น 5: เหตุการณ์เกิดขึ้นจริงเข้าไฟล์หรือยัง (ตัวอย่างอ่านไฟล์) ----------
-- แก้ path ให้ตรงกับ FILEPATH ด้านบน — รูปแบบไฟล์: LabAudit_<GUID>_*.sqlaudit
SELECT TOP 20 event_time, action_id, session_id, server_principal_name,
              target_server_principal_name, succeeded, class_type
FROM sys.fn_get_audit_file('C:\AuditLogs\LabAudit*', default, default)
ORDER BY event_time DESC;
GO
-- (รายละเอียดการอ่านไฟล์อยู่ใน Section 03)

-- ---------- Cleanup ----------
ALTER SERVER AUDIT SPECIFICATION LabServerSpec WITH (STATE = OFF);
DROP SERVER AUDIT SPECIFICATION LabServerSpec;
ALTER SERVER AUDIT LabAudit WITH (STATE = OFF);
DROP SERVER AUDIT LabAudit;
GO
-- ไฟล์ .sqlaudit ค้างอยู่ในโฟลเดอร์ — ลบด้วย OS เมื่อไม่ต้องใช้
-- จบสคริปต์
