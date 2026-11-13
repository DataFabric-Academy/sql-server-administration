-- ============================================================================
-- Section 03 — Demo 02: ปัญหา audit ที่พบบ่อย + ลำดับปิด/ลบที่ถูกต้อง
-- ฐานข้อมูล: master + AdventureWorks2025
-- สคริปต์นี้เป็น "playbook" — อ่านคอมเมนต์คู่ไปกับ Section 03 README
-- ============================================================================
USE master;
GO

-- ---------- การวินิจฉัย: audit ทั้งหมด + สถานะจริง ----------
-- (ตรวจว่า audit ที่คิดว่าเปิดอยู่ จริง ๆ ผ่าน/พังอะไร)
SELECT name, audit_guid, is_state_enabled, status_desc, status_change_dt,
       on_failure_desc, queue_delay
FROM sys.server_audits;
GO
-- ค่า status_desc ที่เป็นปัญหา:
--   AFTER_ERROR   → เขียนไฟล์ไม่ได้ (เช็ค folder permission ของ service account)
--   SHUTTING_DOWN → เกิดเหตุการณ์ ON_FAILURE ทำระบบปิด (ON_FAILURE = SHUTDOWN)
--   MSSQL_AUDIT_* → สถานะชั่วคราวระหว่างเปิด/ปิด

-- ---------- โจทย์ 1: audit "เปิดแล้วแต่ไม่มีไฟล์เกิด" ----------
-- ขั้นแรก: service account เขียนไฟล์ได้จริงหรือเปล่า ดูจาก error log ล่าสุด
EXEC xp_readerrorlog 0, 1, N'Audit';   -- ค้นหา 'Audit' ใน error log ปัจจุบัน
GO
-- ข้อความที่มักเจอ:
--   "The audit ... failed to write to file ..."  → folder permission / path ผิด
-- แก้: ให้สิทธิ์ Modify แก้ SQL Server service account บนโฟลเดอร์ (Windows)
--      หรือบน Linux: chown mssql:mssql /var/opt/mssql/audit
-- แล้วเปิดใหม่:
--   ALTER SERVER AUDIT <ชื่อ> WITH (STATE = ON);

-- ---------- โจทย์ 2: ตรวจว่า spec ไหนผูกกับ audit ไหน ----------
SELECT sa.name AS audit_name,
       sas.name AS server_spec_name
FROM sys.server_audits sa
LEFT JOIN sys.server_audit_specifications sas ON sas.audit_guid = sa.audit_guid;
GO

USE AdventureWorks2025;
GO
SELECT das.name AS db_spec_name, das.audit_guid,
       sa.name AS audit_name
FROM sys.database_audit_specifications das
LEFT JOIN sys.server_audits sa ON sa.audit_guid = das.audit_guid;
GO

-- ---------- โจทย์ 3: ลำดับการปิดและลบที่ถูกต้อง ----------
-- พยายามลบผิดลำดับจะ error 33005 (audit/spec ยังเปิด) — playbook:
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'PlaybookAudit')
BEGIN
    PRINT N'ข้าม — PlaybookAudit มีอยู่แล้ว ไม่สร้างซ้ำ';
END
ELSE
BEGIN
    -- 1) สร้างตัวอย่างเพื่อซ้อมลบ (แก้ path ให้เขียนได้)
    CREATE SERVER AUDIT PlaybookAudit
    TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 10 MB, MAX_ROLLOVER_FILES = 2)
    WITH (QUEUE_DELAY = 5000, ON_FAILURE = CONTINUE);
    ALTER SERVER AUDIT PlaybookAudit WITH (STATE = ON);
END
GO

USE AdventureWorks2025;
GO
-- (ต่อจากบล็อกก่อน — ถ้าสร้างใหม่ สร้าง db spec ให้เองหรือใช้ของเดิมก็ได้)

-- ลำดับที่ทำงานเสมอ:
--   Step 1: ปิด + ลบ DATABASE AUDIT SPECIFICATION ทุกตัวที่ audit_guid ตรงกัน
--   Step 2: ปิด + ลบ SERVER AUDIT SPECIFICATION ทุกตัวที่ audit_guid ตรงกัน
--   Step 3: ปิด + ลบ SERVER AUDIT
-- ตัวอย่างแบบตรวจเงื่อนไขให้ idempotent (ถ้ามีชื่อเหล่านี้อยู่):
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'PlaybookDbSpec')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
               WHERE name = 'PlaybookDbSpec' AND is_state_enabled = 1)
        ALTER DATABASE AUDIT SPECIFICATION PlaybookDbSpec WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION PlaybookDbSpec;
END
GO

USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'PlaybookSrvSpec')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_audit_specifications
               WHERE name = 'PlaybookSrvSpec' AND is_state_enabled = 1)
        ALTER SERVER AUDIT SPECIFICATION PlaybookSrvSpec WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION PlaybookSrvSpec;
END
GO

IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'PlaybookAudit')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'PlaybookAudit' AND is_state_enabled = 1)
        ALTER SERVER AUDIT PlaybookAudit WITH (STATE = OFF);
    DROP SERVER AUDIT PlaybookAudit;
END
GO

-- ---------- โจทย์ 4: ปิด audit ชั่วคราวแล้วเปิดคืน (โดยไม่ลบ) ----------
-- (ตัวอย่างในคอมเมนต์ — ปิดเพื่อ load ข้อมูลใหญ่แล้วเปิดคืน)
-- ALTER SERVER AUDIT LabAudit WITH (STATE = OFF);
-- ... BACKUP/BULK LOAD ...
-- ALTER SERVER AUDIT LabAudit WITH (STATE = ON);

-- ---------- โจทย์ 5: ย้าย/เก็บ archive ไฟล์ .sqlaudit แล้วอ่านย้อนหลัง ----------
-- คัดลอกไฟล์ไป file share แล้วอ่านจาก UNC ได้เลย (ไม่ต้องมี instance ต้นทาง):
-- SELECT TOP 50 *
-- FROM sys.fn_get_audit_file('\\fileserver\audit-archive\LabAudit*', default, default)
-- ORDER BY event_time DESC;

-- จบสคริปต์
