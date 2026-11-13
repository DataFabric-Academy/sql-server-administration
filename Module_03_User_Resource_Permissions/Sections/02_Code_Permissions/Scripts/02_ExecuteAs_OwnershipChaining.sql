-- ============================================================================
-- Section 02 — Demo 02: EXECUTE AS และ Ownership Chaining
-- ฐานข้อมูล: AdventureWorks2025
-- สาธิต: (1) ownership chaining เมื่อ owner เดียวกัน  (2) chain หักเมื่อ owner ต่างกัน
--        (3) EXECUTE AS OWNER บน proc
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoChainUser')
    DROP LOGIN DemoChainUser;
GO
CREATE LOGIN DemoChainUser WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoChainUser')
    DROP USER DemoChainUser;
GO
CREATE USER DemoChainUser FOR LOGIN DemoChainUser;
GO

-- ---------- ขั้น 1: ตารางทดสอบใน schema dbo (owner เดียวกับ proc) ----------
IF OBJECT_ID('dbo.DemoChainNotes', 'U') IS NOT NULL
    DROP TABLE dbo.DemoChainNotes;
GO
CREATE TABLE dbo.DemoChainNotes
(
    NoteId int NOT NULL PRIMARY KEY,
    Body   nvarchar(200) NOT NULL
);
GO
INSERT INTO dbo.DemoChainNotes (NoteId, Body) VALUES (1, N'สวัสดี'), (2, N'โค้ดกับข้อมูลคนเดียวกัน');
GO

-- proc แบบ static SQL (ไม่มี dynamic SQL) — อยู่ schema dbo เจ้าของตารางเหมือนกัน
IF OBJECT_ID('dbo.uspChainDemo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.uspChainDemo;
GO
CREATE PROCEDURE dbo.uspChainDemo
AS
    SELECT NoteId, Body FROM dbo.DemoChainNotes;   -- static → อยู่ใน chain
GO

-- ---------- ขั้น 2: ให้ EXECUTE บน proc เท่านั้น ----------
GRANT EXECUTE ON dbo.uspChainDemo TO DemoChainUser;
GO

EXECUTE AS USER = 'DemoChainUser';
EXEC dbo.uspChainDemo;                          -- ทำงานได้ — ownership chaining
SELECT * FROM dbo.DemoChainNotes;               -- error 229 — อ่านตรงไม่ได้
REVERT;
GO

-- ---------- ขั้น 3: ทำให้ chain หัก (owner ต่างกัน) ----------
-- สร้าง schema ใหม่ + ย้ายตารางไปอยู่กับ owner คนละคน
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'OtherOwner')
    CREATE SCHEMA OtherOwner AUTHORIZATION dbo;
GO
-- เปลี่ยน owner ของ schema เป็น user จริงคนหนึ่ง เพื่อทำให้ owner ต่างจาก dbo
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoTableOwner')
    DROP USER DemoTableOwner;
GO
CREATE USER DemoTableOwner WITHOUT LOGIN;
ALTER AUTHORIZATION ON SCHEMA::OtherOwner TO DemoTableOwner;
GO

ALTER SCHEMA OtherOwner TRANSFER dbo.DemoChainNotes;
GO

-- โยก proc ให้อ่านตารางตำแหน่งใหม่
ALTER PROCEDURE dbo.uspChainDemo
AS
    SELECT NoteId, Body FROM OtherOwner.DemoChainNotes;   -- owner ของ schema นี้ = DemoTableOwner
GO

EXECUTE AS USER = 'DemoChainUser';
EXEC dbo.uspChainDemo;   -- error 229 — chain หัก (proc owner dbo ≠ ตาราง owner DemoTableOwner)
REVERT;
GO

-- ---------- ขั้น 4: แก้ด้วย EXECUTE AS OWNER ----------
ALTER PROCEDURE dbo.uspChainDemo
WITH EXECUTE AS OWNER
AS
    SELECT NoteId, Body FROM OtherOwner.DemoChainNotes;
GO

EXECUTE AS USER = 'DemoChainUser';
EXEC dbo.uspChainDemo;    -- ทำงานได้ — โค้ดรันในบริบทเจ้าของ proc (DemoTableOwner)
REVERT;
GO

-- ---------- ขั้น 5: EXECUTE AS เทียบ CALLER / OWNER / SELF ----------
IF OBJECT_ID('dbo.uspContextDemo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.uspContextDemo;
GO
CREATE PROCEDURE dbo.uspContextDemo
WITH EXECUTE AS OWNER
AS
    SELECT USER_NAME() AS executing_context;   -- แสดงบริบทขณะรันโค้ด
GO

EXECUTE AS USER = 'DemoChainUser';
EXEC dbo.uspContextDemo;   -- คืน DemoTableOwner (OWNER) ไม่ใช่ DemoChainUser (CALLER)
REVERT;
GO

ALTER PROCEDURE dbo.uspContextDemo
WITH EXECUTE AS CALLER
AS
    SELECT USER_NAME() AS executing_context;
GO

EXECUTE AS USER = 'DemoChainUser';
EXEC dbo.uspContextDemo;   -- คืน DemoChainUser (CALLER)
REVERT;
GO

-- ---------- Cleanup ----------
DROP PROCEDURE dbo.uspContextDemo;
DROP PROCEDURE dbo.uspChainDemo;
ALTER SCHEMA dbo TRANSFER OtherOwner.DemoChainNotes;   -- โยกกลับ
DROP TABLE dbo.DemoChainNotes;
DROP SCHEMA OtherOwner;
DROP USER DemoTableOwner;
DROP USER DemoChainUser;
GO
USE master;
GO
DROP LOGIN DemoChainUser;
GO
-- จบสคริปต์
