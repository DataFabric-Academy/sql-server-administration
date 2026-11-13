-- ============================================================================
-- Module 14 - Section 3 - Script 01: นำเข้า currency codes ด้วย BULK INSERT
-- ปรับจาก: Microsoft 20764D Mod15 Demo 06 + Lab15 Exercise 1 (จาก Finance DB
--          เดิม มาใช้ schema Lab บน AdventureWorks2025)
-- รันได้บน: SQL Server 2019+ (แนะนำ 2025)
-- ⚠️ แก้ตัวแปร @SetupDir ด้านล่างให้ตรงกับที่คุณวางโฟลเดอร์ Scripts/Data
--    (ต้องเป็น path ที่ "เครื่อง SQL Server" มองเห็น — ไม่ใช่เครื่อง client)
-- ไฟล์ข้อมูล: currency_codes.csv (105 แถวข้อมูล + header, comma, CRLF)
-- โน้ต: BULK INSERT ต้องใช้ "string literal" ใน FROM จึงต้องครอบด้วย dynamic SQL
--      เพื่อที่จะใช้ตัวแปร path ได้ (ดู BULK INSERT docs — example C)
-- ============================================================================
USE AdventureWorks2025;
GO

IF SCHEMA_ID('Lab') IS NULL
    EXEC('CREATE SCHEMA Lab;');
GO

-- ----------------------------------------------------------------------------
-- Task 1: ตารางปลายทาง (idempotent)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.CurrencyImport;
GO

CREATE TABLE Lab.CurrencyImport
(
    CurrencyCode char(3)       NOT NULL CONSTRAINT PK_CurrencyImport PRIMARY KEY,
    CurrencyName nvarchar(100) NOT NULL,
    ModifiedDate datetime      NULL
);
GO

-- ----------------------------------------------------------------------------
-- Task 2: BULK INSERT แบบเต็มรูป (ผ่าน dynamic SQL เพื่อใช้ตัวแปร path)
-- ----------------------------------------------------------------------------
DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';
-- ^^ แก้ path นี้ก่อนรัน! ตรวจว่าไฟล์อยู่เครื่อง server:
--    เปิด SSMS เชื่อมต่อ server แล้วรัน xp_fixeddrives หรือใช้ UNC ถ้าไฟล์อยู่ share

DECLARE @DataFile nvarchar(300) =
    @SetupDir + N'currency_codes.csv';

TRUNCATE TABLE Lab.CurrencyImport;

DECLARE @sql nvarchar(max) =
    N'BULK INSERT Lab.CurrencyImport
      FROM ''' + REPLACE(@DataFile, N'''', N'''''') + N'''
      WITH (
          FIELDTERMINATOR = '','',
          ROWTERMINATOR   = ''\r\n'',   -- ไฟล์ที่แจกมาเป็น CRLF แบบ Windows
          FIRSTROW        = 2,          -- ข้ามบรรทัด header (engine ไม่ validate แถวที่ข้าม)
          CODEPAGE        = ''65001'',  -- UTF-8 (ไฟล์ ASCII ใช้ ''ACP'' ก็ได้)
          TABLOCK,                      -- เปิดทางให้ minimal logging (SIMPLE/BULK_LOGGED)
          CHECK_CONSTRAINTS,            -- ตรวจ FK/CHECK ระหว่างโหลด
          MAXERRORS       = 10,
          ERRORFILE       = ''' + REPLACE(@SetupDir + N'currency_errors.log', N'''', N'''''') + N'''
      );';

EXEC (@sql);
GO

-- ----------------------------------------------------------------------------
-- Task 3: ตรวจผล — ควรได้ 105 แถว
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS ImportedRows FROM Lab.CurrencyImport;

SELECT TOP (10) * FROM Lab.CurrencyImport ORDER BY CurrencyCode;
GO

-- ----------------------------------------------------------------------------
-- Task 4 (เปรียบเทียบ): import โดยไม่ใส่ CHECK_CONSTRAINTS + ใช้ BATCHSIZE
--  - ตั้งใจให้เห็นว่า constraint "ไม่ถูกตรวจ" และหากมี FK จะกลายเป็น untrusted
--  - BATCHSIZE = commit เป็นรอบ 50 แถว / ROWS_PER_BATCH = บอกขนาดไฟล์โดยประมาณ
-- ----------------------------------------------------------------------------
TRUNCATE TABLE Lab.CurrencyImport;

DECLARE @SetupDir2 nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';

DECLARE @sql2 nvarchar(max) =
    N'BULK INSERT Lab.CurrencyImport
      FROM ''' + REPLACE(@SetupDir2 + N'currency_codes.csv', N'''', N'''''') + N'''
      WITH (
          FIELDTERMINATOR = '','',
          ROWTERMINATOR   = ''\r\n'',
          FIRSTROW        = 2,
          BATCHSIZE       = 50,     -- commit เป็นรอบ 50 แถว (กัน transaction ใหญ่)
          ROWS_PER_BATCH  = 105,    -- บอก engine ขนาดไฟล์โดยประมาณ (ช่วยจัดสรร)
          TABLOCK                       -- ไม่ใส่ CHECK_CONSTRAINTS = ไม่ตรวจ constraint
      );';

EXEC (@sql2);
GO

SELECT COUNT(*) AS ImportedRows_NoCheckConstraints FROM Lab.CurrencyImport;
GO

-- ----------------------------------------------------------------------------
-- Cleanup
-- ----------------------------------------------------------------------------
-- DROP TABLE IF EXISTS Lab.CurrencyImport;
