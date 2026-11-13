-- ============================================================================
-- Module 14 - Section 3 - Script 03: OPENROWSET(BULK ...) — อ่านไฟล์เป็น rowset
-- ปรับจาก: Microsoft 20764D Mod15 Demo 07 (OPENROWSET)
-- รันได้บน: SQL Server 2019+ (S3/Blob path ต้อง 2022+)
-- ⚠️ แก้ @SetupDir ด้านล่างให้ตรงกับที่คุณวางโฟลเดอร์ Scripts\Data
--    (path ฝั่งเครื่อง SQL Server)
-- โน้ต: OPENROWSET(BULK) ต้องใช้ literal path เหมือน BULK INSERT จึงใช้ dynamic SQL
--      ครอบตัวแปร @SetupDir
-- ============================================================================
USE AdventureWorks2025;
GO

IF SCHEMA_ID('Lab') IS NULL
    EXEC('CREATE SCHEMA Lab;');
GO

-- ----------------------------------------------------------------------------
-- Task 0: ประกาศ path หลัก (แก้จุดเดียว ใช้ทั้งไฟล์)
-- ----------------------------------------------------------------------------
DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';
GO  -- หมายเหตุ: ตัวแปรอยู่ในแต่ละ batch ด้านล่างจะประกาศซ้ำ — แก้ทุกจุดที่มีคำว่า C:\CourseFiles

-- ----------------------------------------------------------------------------
-- Task 1: อ่านไฟล์ทั้งก้อนเป็นไบต์ดิบ (SINGLE_BLOB) — เช่น เก็บ document
-- ----------------------------------------------------------------------------
DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';

DECLARE @sql nvarchar(max) =
    N'SELECT BulkColumn AS RawBytes, DATALENGTH(BulkColumn) AS LengthBytes
      FROM OPENROWSET(BULK ''' + REPLACE(@SetupDir + N'currency_codes.csv', N'''', N'''''') + N''', SINGLE_BLOB) AS f;';

EXEC (@sql);
GO

-- ----------------------------------------------------------------------------
-- Task 2: อ่านทั้งไฟล์เป็นข้อความ (SINGLE_CLOB) แล้วนับบรรทัด — ไฟล์ TLD 1,252 แถว
-- ----------------------------------------------------------------------------
DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';

DECLARE @sql nvarchar(max) =
    N'SELECT COUNT(*) AS LineCount
      FROM STRING_SPLIT(
          (SELECT BulkColumn
           FROM OPENROWSET(BULK ''' + REPLACE(@SetupDir + N'top_level_domains.csv', N'''', N'''''') + N''', SINGLE_CLOB) AS f),
          CHAR(10));';

EXEC (@sql);
GO

-- ----------------------------------------------------------------------------
-- Task 3: อ่านเป็น "แถว" ด้วย format file (ไฟล์ currency_codes.fmt ที่แจกมา)
-- ----------------------------------------------------------------------------
DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';

DECLARE @sql nvarchar(max) =
    N'SELECT *
      FROM OPENROWSET(
              BULK '''      + REPLACE(@SetupDir + N'currency_codes.csv', N'''', N'''''') + N''',
              FORMATFILE = ''' + REPLACE(@SetupDir + N'currency_codes.fmt', N'''', N'''''') + N'''
           ) AS rows;';

EXEC (@sql);
-- ควรได้ 105 แถว x 3 คอลัมน์ (CurrencyCode, CurrencyName, ModifiedDate)
GO

-- ----------------------------------------------------------------------------
-- Task 4: INSERT ... SELECT กรองก่อนเข้าตาราง (ผ่าน OPENROWSET)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.CurrencyOpenRowset;
GO

CREATE TABLE Lab.CurrencyOpenRowset
(
    CurrencyCode char(3)       NOT NULL PRIMARY KEY,
    CurrencyName nvarchar(100) NOT NULL,
    ModifiedDate datetime      NULL
);
GO

DECLARE @SetupDir nvarchar(260) =
    N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';

DECLARE @sql nvarchar(max) =
    N'INSERT Lab.CurrencyOpenRowset (CurrencyCode, CurrencyName, ModifiedDate)
      SELECT CurrencyCode, CurrencyName, ModifiedDate
      FROM OPENROWSET(
              BULK '''      + REPLACE(@SetupDir + N'currency_codes.csv', N'''', N'''''') + N''',
              FORMATFILE = ''' + REPLACE(@SetupDir + N'currency_codes.fmt', N'''', N'''''') + N'''
           ) AS rows
      WHERE CurrencyCode IN (''THB'', ''USD'', ''EUR'', ''JPY'');';

EXEC (@sql);
GO

SELECT * FROM Lab.CurrencyOpenRowset;
GO

-- ----------------------------------------------------------------------------
-- Task 5 (แบบ cloud — SQL Server 2022+): Azure Blob / S3 ผ่าน EXTERNAL DATA SOURCE
-- ต้องมี credential ที่เหมาะสม — ดู README หัวข้อ 4.3 ก่อนรันจริง
-- ----------------------------------------------------------------------------
-- CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025';
--
-- -- แบบ Azure Blob (SAS)
-- CREATE DATABASE SCOPED CREDENTIAL BlobCred
--     WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
--          SECRET   = 'sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2027-01-01T00:00:00Z&sig=...';
--
-- CREATE EXTERNAL DATA SOURCE BlobSrc
--     WITH (LOCATION = 'abs://mystorageaccount.blob.core.windows.net/imports');
--
-- SELECT * FROM OPENROWSET(BULK 'currency_codes.csv',
--                           DATA_SOURCE = 'BlobSrc',
--                           SINGLE_CLOB) AS f;
--
-- -- แบบ S3-compatible (s3://) — credential ชนิด 'S3 Access Key'
-- CREATE DATABASE SCOPED CREDENTIAL S3Cred
--     WITH IDENTITY = 'S3 Access Key',
--          SECRET   = 'accessKey:secretKey';
--
-- CREATE EXTERNAL DATA SOURCE S3Src
--     WITH (LOCATION = 's3://10.0.0.10:9000/imports',
--           CREDENTIAL = S3Cred);
--
-- SELECT * FROM OPENROWSET(BULK 'currency_codes.csv',
--                           DATA_SOURCE = 'S3Src',
--                           SINGLE_CLOB) AS f;
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- Cleanup
-- ----------------------------------------------------------------------------
-- DROP TABLE IF EXISTS Lab.CurrencyOpenRowset;
