-- ============================================================================
-- Section 04 — Demo 02: Dynamic Data Masking (DDM)
-- ฐานข้อมูล: AdventureWorks2025 — schema Lab (ตาม demo เดิม "masking")
-- สาธิต: mask 4 แบบ, EXECUTE AS เทียบผล, เพิ่ม/ลบ mask, GRANT UNMASK
-- ============================================================================
USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Lab')
    CREATE SCHEMA Lab;
GO

-- ---------- ขั้น 0: เตรียม user ทดสอบ (ไม่มี UNMASK) ----------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TestMaskUser')
    DROP USER TestMaskUser;
GO
CREATE USER TestMaskUser WITHOUT LOGIN;
GO

-- ---------- ขั้น 1: สร้างตารางที่มี mask ครบ 4 แบบ ----------
IF OBJECT_ID('Lab.EmployeePersonalData', 'U') IS NOT NULL
    DROP TABLE Lab.EmployeePersonalData;
GO
CREATE TABLE Lab.EmployeePersonalData
(
    empid int NOT NULL PRIMARY KEY,
    salary int MASKED WITH (FUNCTION = 'default()') NOT NULL,
    email_address varchar(255) MASKED WITH (FUNCTION = 'email()') NULL,
    voice_mail_pin smallint MASKED WITH (FUNCTION = 'random(0, 9)') NULL,
    company_credit_card_number varchar(30)
        MASKED WITH (FUNCTION = 'partial(0,"XXXX-",4)') NULL,
    home_phone_number varchar(30) NULL
);
GO

GRANT SELECT ON Lab.EmployeePersonalData TO TestMaskUser;
GO

INSERT INTO Lab.EmployeePersonalData
    (empid, salary, email_address, voice_mail_pin,
     company_credit_card_number, home_phone_number)
VALUES
    (1, 25000, 'emp1@adventure-works.net', 9991, '9999-5656-4433-2211', '1234-567890'),
    (2, 35000, 'qx3e@adventure-works.org', 1151, '9999-7676-5566-3141', '2345-314253'),
    (3, 35000, 'zn4456@adventure-works.net', 6514, '9999-7676-5567-2444', '3456-777266');
GO

-- ---------- ขั้น 2: เทียบมุมมอง admin vs user ทั่วไป ----------
-- admin/db_owner เห็นของจริง
SELECT * FROM Lab.EmployeePersonalData;

-- user ธรรมดาเห็น mask
EXECUTE AS USER = 'TestMaskUser';
SELECT * FROM Lab.EmployeePersonalData;
-- คาดหวัง: salary=0, email=sXXX@XXXX.com, pin=random 0-9, card=XXXX-2211,
--          home_phone = ของจริง (ยังไม่ mask)
REVERT;
GO

-- ---------- ขั้น 3: เพิ่ม mask ให้คอลัมน์เดิม ----------
ALTER TABLE Lab.EmployeePersonalData
ALTER COLUMN home_phone_number varchar(30)
    ADD MASKED WITH (FUNCTION = 'partial(4,"-XXX",0)');
GO

EXECUTE AS USER = 'TestMaskUser';
SELECT home_phone_number FROM Lab.EmployeePersonalData;  -- 1234-XXX / 2345-XXX ...
REVERT;
GO

-- ---------- ขั้น 4: ลบ mask ----------
ALTER TABLE Lab.EmployeePersonalData
ALTER COLUMN salary int DROP MASKED;
GO

EXECUTE AS USER = 'TestMaskUser';
SELECT salary FROM Lab.EmployeePersonalData;   -- เห็นของจริงแล้ว (25000/35000)
REVERT;
GO

-- ---------- ขั้น 5: GRANT UNMASK — เปิดทั้ง database ----------
GRANT UNMASK TO TestMaskUser;
GO

EXECUTE AS USER = 'TestMaskUser';
SELECT * FROM Lab.EmployeePersonalData;   -- เห็นทุกคอลัมน์เป็นของจริง
REVERT;
GO

REVOKE UNMASK FROM TestMaskUser;
GO

-- ---------- ขั้น 6: (SQL Server 2022+) granular UNMASK ระดับคอลัมน์ ----------
GRANT UNMASK ON OBJECT::Lab.EmployeePersonalData (email_address) TO TestMaskUser;
GO

EXECUTE AS USER = 'TestMaskUser';
SELECT email_address FROM Lab.EmployeePersonalData;         -- เห็นของจริง (มี UNMASK)
SELECT salary FROM Lab.EmployeePersonalData;                -- ยัง mask (ไม่มี UNMASK คอลัมน์นี้)
REVERT;
GO

REVOKE UNMASK ON OBJECT::Lab.EmployeePersonalData (email_address) FROM TestMaskUser;
GO

-- ---------- ขั้น 7: ตรวจ metadata ของ mask ----------
SELECT c.name AS column_name, c.masking_function
FROM sys.masked_columns mc
JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
JOIN sys.tables t ON t.object_id = mc.object_id
WHERE t.name = 'EmployeePersonalData';
GO

-- ---------- ข้อจำกัดที่ต้องจำ ----------
-- 1) DDM ไม่เข้ารหัส: ข้อมูลบน disk = plaintext — ใครได้ไฟล์ก็อ่านได้หมด
-- 2) side-channel: user ที่มีสิทธิ์พออาจอนุมานค่าจริงได้ (เช่น WHERE + error)
--    จึงใช้ DDM เพื่อ "กันเผลอ" คู่กับ permission ที่เข้มงวด ไม่ใช่เพื่อกันผู้โจมตี
-- 3) DDM ใช้คู่กับ SQL Server Audit ได้ — audit จะเห็น statement ที่รันจริง

-- ---------- Cleanup ----------
DROP TABLE Lab.EmployeePersonalData;
DROP USER TestMaskUser;
GO
-- จบสคริปต์
