-- ============================================================================
-- Section 01 — Demo 02: Audit ด้วย AFTER Trigger + Log Table
-- ฐานข้อมูล: AdventureWorks2025 — สร้าง schema Lab เอง (idempotent, มี cleanup)
-- ============================================================================
USE AdventureWorks2025;
GO

-- ---------- เตรียม schema Lab ----------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Lab')
    CREATE SCHEMA Lab;
GO

-- ---------- ตารางทดสอบ + ตาราง log ----------
IF OBJECT_ID('Lab.SalaryDemo', 'U') IS NOT NULL DROP TABLE Lab.SalaryDemo;
IF OBJECT_ID('Lab.AuditLog', 'U')   IS NOT NULL DROP TABLE Lab.AuditLog;
GO

CREATE TABLE Lab.SalaryDemo
(
    Id           int NOT NULL PRIMARY KEY,
    EmployeeName nvarchar(50) NOT NULL,
    Salary       int NOT NULL
);
GO

CREATE TABLE Lab.AuditLog
(
    AuditId    int IDENTITY PRIMARY KEY,
    EventTime  datetime2 NOT NULL DEFAULT SYSDATETIME(),
    ChangedBy  sysname   NOT NULL DEFAULT SUSER_SNAME(),
    Action     nvarchar(10) NOT NULL,
    OldValue   nvarchar(200) NULL,
    NewValue   nvarchar(200) NULL
);
GO

-- ---------- AFTER Trigger จับ INSERT/UPDATE/DELETE ----------
IF OBJECT_ID('Lab.trg_AuditSalary', 'TR') IS NOT NULL
    DROP TRIGGER Lab.trg_AuditSalary;
GO
CREATE TRIGGER Lab.trg_AuditSalary
ON Lab.SalaryDemo
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- DELETE: อยู่ใน deleted แต่ไม่อยู่ใน inserted
    INSERT INTO Lab.AuditLog (Action, OldValue, NewValue)
    SELECT N'DELETE', CONCAT(d.Id, N'|', d.EmployeeName, N'|', d.Salary), NULL
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i WHERE i.Id = d.Id);

    -- INSERT: อยู่ใน inserted แต่ไม่อยู่ใน deleted
    INSERT INTO Lab.AuditLog (Action, OldValue, NewValue)
    SELECT N'INSERT', NULL, CONCAT(i.Id, N'|', i.EmployeeName, N'|', i.Salary)
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.Id = i.Id);

    -- UPDATE: อยู่ทั้งคู่ → เก็บค่าก่อน/หลัง
    INSERT INTO Lab.AuditLog (Action, OldValue, NewValue)
    SELECT N'UPDATE',
           CONCAT(d.Id, N'|', d.EmployeeName, N'|', d.Salary),
           CONCAT(i.Id, N'|', i.EmployeeName, N'|', i.Salary)
    FROM deleted d JOIN inserted i ON i.Id = d.Id;
END
GO

-- ---------- ทดสอบ 3 เหตุการณ์ ----------
INSERT INTO Lab.SalaryDemo VALUES (1, N'Somchai', 45000);
INSERT INTO Lab.SalaryDemo VALUES (2, N'Somsri', 52000);
GO

UPDATE Lab.SalaryDemo SET Salary = 60000 WHERE Id = 1;
GO

DELETE FROM Lab.SalaryDemo WHERE Id = 2;
GO

-- ---------- ดู log ----------
SELECT * FROM Lab.AuditLog ORDER BY AuditId;
GO
-- สังเกต: ChangedBy = SUSER_SNAME() ของคนที่ทำธุรกรรม — log รู้ "ใคร" และ "เปลี่ยนอะไร"
-- ข้อจำกัด: trigger รันใน transaction เดียวกัน → DML ช้าลง; และ user ที่มีสิทธิ์
-- ALTER TABLE สามารถ DROP trigger ได้ (audit อยู่ใน database เดียวกัน)

-- ---------- สาธิตจุดอ่อน: trigger ถูกปิดได้ ----------
DISABLE TRIGGER Lab.trg_AuditSalary ON Lab.SalaryDemo;
INSERT INTO Lab.SalaryDemo VALUES (3, N'NoAudit', 99999);
GO

SELECT * FROM Lab.AuditLog WHERE Action = N'INSERT' AND NewValue LIKE N'3|%';
GO
-- คาดหวัง: ไม่มีแถวใหม่เข้า log — INSERT ล่าสุด "ลอดผ่าน"
ENABLE TRIGGER Lab.trg_AuditSalary ON Lab.SalaryDemo;
GO

-- ---------- Cleanup ----------
DROP TRIGGER Lab.trg_AuditSalary;
DROP TABLE Lab.SalaryDemo;
DROP TABLE Lab.AuditLog;
GO
-- schema Lab มีหลาย demo ใช้ ถ้าต้องการลบ: DROP SCHEMA Lab;
-- จบสคริปต์
