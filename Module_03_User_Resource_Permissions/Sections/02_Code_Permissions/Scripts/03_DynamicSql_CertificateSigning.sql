-- ============================================================================
-- Section 02 — Demo 03: Dynamic SQL หัก Ownership Chaining + Certificate Signing
-- ฐานข้อมูล: AdventureWorks2025
-- เทียบ 3 สถานการณ์:
--   A) proc + dynamic SQL ปกติ     → error (chain หัก)
--   B) proc + EXECUTE AS OWNER     → ทำงานได้ (บริบทเปลี่ยนทั้ง proc)
--   C) proc + certificate signing  → ทำงานได้ (บริบทผู้เรียกไม่เปลี่ยน — แนะนำ)
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoDynUser')
    DROP LOGIN DemoDynUser;
GO
CREATE LOGIN DemoDynUser WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoDynUser')
    DROP USER DemoDynUser;
GO
CREATE USER DemoDynUser FOR LOGIN DemoDynUser;
GO

-- ---------- เตรียมตารางทดสอบใน schema ที่ user ไม่มีสิทธิ์ ----------
IF OBJECT_ID('dbo.DemoSecretNotes', 'U') IS NOT NULL
    DROP TABLE dbo.DemoSecretNotes;
GO
CREATE TABLE dbo.DemoSecretNotes (NoteId int NOT NULL PRIMARY KEY, Body nvarchar(200));
GO
INSERT INTO dbo.DemoSecretNotes VALUES (1, N'ข้อมูลที่ต้องเข้าถึงผ่าน proc เท่านั้น');
GO

-- ============================================================
-- สถานการณ์ A: dynamic SQL แบบธรรมดา → ownership chaining ไม่ทำงาน
-- ============================================================
IF OBJECT_ID('dbo.uspDynPlain', 'P') IS NOT NULL
    DROP PROCEDURE dbo.uspDynPlain;
GO
CREATE PROCEDURE dbo.uspDynPlain @NoteId int
AS
    -- ควรใช้ sp_executesql เพื่อกัน SQL injection ในการใช้งานจริง
    EXEC ('SELECT NoteId, Body FROM dbo.DemoSecretNotes WHERE NoteId = ' + @NoteId);
GO

GRANT EXECUTE ON dbo.uspDynPlain TO DemoDynUser;
GO

EXECUTE AS USER = 'DemoDynUser';
EXEC dbo.uspDynPlain @NoteId = 1;
-- error 229: The SELECT permission was denied on the object 'DemoSecretNotes'
-- เพราะ statement ใน EXEC() ถูกประเมินสิทธิ์ใหม่ในบริบทผู้เรียก (DemoDynUser)
REVERT;
GO

-- ============================================================
-- สถานการณ์ B: EXECUTE AS OWNER — ใช้ได้ แต่บริบทเปลี่ยนทั้ง proc
-- ============================================================
IF OBJECT_ID('dbo.uspDynAsOwner', 'P') IS NOT NULL
    DROP PROCEDURE dbo.uspDynAsOwner;
GO
CREATE PROCEDURE dbo.uspDynAsOwner @NoteId int
WITH EXECUTE AS OWNER
AS
    SELECT USER_NAME() AS executing_context;   -- จะเห็นเป็น dbo ไม่ใช่ตัวผู้เรียก
    EXEC ('SELECT NoteId, Body FROM dbo.DemoSecretNotes WHERE NoteId = ' + @NoteId);
GO

GRANT EXECUTE ON dbo.uspDynAsOwner TO DemoDynUser;
GO

EXECUTE AS USER = 'DemoDynUser';
EXEC dbo.uspDynAsOwner @NoteId = 1;   -- ทำงานได้ แต่ context = dbo (audit ไม่เห็นตัวจริง)
REVERT;
GO

-- ============================================================
-- สถานการณ์ C: Certificate Signing (แนะนำ)
-- ============================================================
-- 1) certificate ใน database
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'DemoDynProcCert')
    DROP CERTIFICATE DemoDynProcCert;
GO
CREATE CERTIFICATE DemoDynProcCert
    WITH SUBJECT = 'Sign dynamic-SQL procedures (Module 03 demo)';
GO

-- 2) user จาก certificate — "ผู้แบกสิทธิ์" ไม่มี login จริง
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CertUser_DemoDynProc')
    DROP USER CertUser_DemoDynProc;
GO
CREATE USER CertUser_DemoDynProc FROM CERTIFICATE DemoDynProcCert;
GO

-- 3) มอบสิทธิ์ขั้นต่ำ "เฉพาะที่โค้ดต้องใช้" ให้ cert user
GRANT SELECT ON dbo.DemoSecretNotes TO CertUser_DemoDynProc;
GO

-- 4) proc แบบ CALLER (คงบริบทผู้เรียก) + ลงลายมือชื่อ
IF OBJECT_ID('dbo.uspDynSigned', 'P') IS NOT NULL
    DROP PROCEDURE dbo.uspDynSigned;
GO
CREATE PROCEDURE dbo.uspDynSigned @NoteId int
AS
    SELECT USER_NAME() AS executing_context;   -- ยังเป็น DemoDynUser!
    EXEC ('SELECT NoteId, Body FROM dbo.DemoSecretNotes WHERE NoteId = ' + @NoteId);
GO

GRANT EXECUTE ON dbo.uspDynSigned TO DemoDynUser;
GO

ADD SIGNATURE TO OBJECT::dbo.uspDynSigned BY CERTIFICATE DemoDynProcCert
    WITH PASSWORD = 'Pa$$w0rd2025';
GO

EXECUTE AS USER = 'DemoDynUser';
EXEC dbo.uspDynSigned @NoteId = 1;
-- ทำงานได้: สิทธิ์ SELECT มาจาก certificate user แต่บริบท (USER_NAME()) ยังเป็น DemoDynUser
REVERT;
GO

-- ตรวจลายมือชื่อที่ผูกกับ proc
SELECT OBJECT_NAME(major_id) AS signed_object, cp.certificate_name, cp.certificate_id
FROM sys.crypt_properties cp
WHERE class = 1 AND major_id = OBJECT_ID('dbo.uspDynSigned');
GO

-- ---------- Cleanup ----------
DROP PROCEDURE dbo.uspDynSigned;
DROP PROCEDURE dbo.uspDynAsOwner;
DROP PROCEDURE dbo.uspDynPlain;
DROP TABLE dbo.DemoSecretNotes;
DROP USER CertUser_DemoDynProc;
DROP CERTIFICATE DemoDynProcCert;
DROP USER DemoDynUser;
GO
USE master;
GO
DROP LOGIN DemoDynUser;
GO
-- จบสคริปต์
