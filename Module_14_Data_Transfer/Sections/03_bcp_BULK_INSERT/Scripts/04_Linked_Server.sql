-- ============================================================================
-- Module 14 - Section 3 - Script 04: Linked Server (loopback) + 4-part query
-- รันได้บน: SQL Server 2019+ (Windows) — ไม่ต้องมี server ที่สอง เพราะชี้กลับ
--           instance ตัวเอง (loopback) เพื่อสาธิตกลไก
-- สิทธิ์: sysadmin หรือ ALTER ANY LINKED SERVER
-- ข้อแตกต่างจริงจากคอร์สเก่า: เดิมชี้ไป SQL2 (server อื่นบน domain) — ที่นี่ทำแบบ
--           self-contained; ถ้ามี server จริง/instance ที่สอง (เช่น sql2025b:1434)
--           เปลี่ยน @datasrc แล้วใช้ sp_addlinkedsrvlogin แบบ SQL auth แทน
-- ============================================================================
USE master;
GO

-- ----------------------------------------------------------------------------
-- Task 1: สร้าง linked server ชื่อ LOOPBACK ชี้กลับมา instance ตัวเอง
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'LOOPBACK')
    EXEC sp_dropserver 'LOOPBACK', 'droplogins';
GO

DECLARE @Self nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('ServerName'));

EXEC sp_addlinkedserver
     @server     = N'LOOPBACK',
     @srvproduct = N'',                -- สำหรับ SQL Server provider ปล่อยว่าง
     @provider   = N'MSOLEDBSQL',      -- Microsoft OLE DB Driver for SQL Server
     @datasrc    = @Self;              -- ชื่อ instance ตัวเอง (หรือ 'localhost\INSTANCE')
GO

-- ----------------------------------------------------------------------------
-- Task 2: กำหนดการ login — ใช้ credential ของผู้เรียก (useself)
-- ----------------------------------------------------------------------------
EXEC sp_addlinkedsrvlogin
     @rmtsrvname = N'LOOPBACK',
     @useself    = N'TRUE';
GO

-- ----------------------------------------------------------------------------
-- Task 3: query แบบ 4-part name
-- ----------------------------------------------------------------------------
SELECT TOP (5)
       CurrencyCode, Name
FROM LOOPBACK.AdventureWorks2025.Production.Currency
ORDER BY CurrencyCode;
GO

-- ----------------------------------------------------------------------------
-- Task 4: แบบ OPENQUERY — ส่ง query ไปรันฝั่ง remote แล้วคืนผล (คุม execution ดีกว่า)
-- ----------------------------------------------------------------------------
SELECT TOP (5) *
FROM OPENQUERY(LOOPBACK,
     N'SELECT CurrencyCode, Name
       FROM AdventureWorks2025.Production.Currency
       ORDER BY CurrencyCode') AS remote_currency;
GO

-- ----------------------------------------------------------------------------
-- Task 5: ตรวจดู metadata + execution ของ linked server
-- ----------------------------------------------------------------------------
SELECT s.name, s.provider, s.data_source, s.is_linked, s.is_remote_login_enabled
FROM sys.servers AS s
WHERE s.name = N'LOOPBACK';
GO

-- ----------------------------------------------------------------------------
-- รูปแบบ "ของจริง" — ชี้ไป instance ที่สองด้วย SQL auth (ไม่ต้องมี domain)
-- ตัวอย่าง: container ที่สองของคอร์ส (sql2025b, port 1434, sa/Pa$$w0rd2025)
-- ----------------------------------------------------------------------------
-- EXEC sp_addlinkedserver
--      @server     = N'SQL2025B',
--      @srvproduct = N'',
--      @provider   = N'MSOLEDBSQL',
--      @datasrc    = N'localhost,1434';
--
-- EXEC sp_addlinkedsrvlogin
--      @rmtsrvname = N'SQL2025B',
--      @useself    = N'FALSE',
--      @locallogin = NULL,               -- ใช้กับทุก local login (ให้จำกัดเฉพาะ login จริง)
--      @rmtuser    = N'sa',
--      @rmtpassword= N'Pa$$w0rd2025';
--
-- SELECT TOP (5) * FROM SQL2025B.AdventureWorks2025.Production.Currency;
--
-- คำเตือน: @useself='FALSE' ทุกคนใช้บัญชี sa ร่วมกัน — ในทางปฏิบัติจำกัด
--          @locallogin ให้เฉพาะ login ที่ต้องใช้ และให้สิทธิ์บัญชีปลายทางน้อยที่สุด

-- ----------------------------------------------------------------------------
-- Cleanup
-- ----------------------------------------------------------------------------
-- EXEC sp_dropserver 'LOOPBACK', 'droplogins';
