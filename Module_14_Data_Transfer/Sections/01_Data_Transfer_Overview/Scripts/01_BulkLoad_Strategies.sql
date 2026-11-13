-- ============================================================================
-- Module 14 - Section 1 - Script 01: เทคนิคเร่ง bulk load (ปรับจาก Mod15 เดิม)
-- สิ่งที่สาธิต:
--   1) Minimal logging: SIMPLE recovery + TABLOCK + heap
--   2) เทียบ log usage ระหว่างโหลดแบบ fully logged กับ TABLOCK
--   3) Disable/enable constraints แบบ WITH CHECK CHECK (trusted)
--   4) ALTER INDEX ... DISABLE + REBUILD
-- รันได้บน: SQL Server 2019+ (สร้าง database ทดลอง LabLoad ให้เอง)
-- หมายเหตุ: ตั้งใจใช้ database แยก LabLoad (SIMPLE) ไม่แตะ recovery model
--           ของ AdventureWorks2025
-- ============================================================================
USE master;
GO

-- ----------------------------------------------------------------------------
-- Task 0: เตรียม database ทดลอง (SIMPLE recovery เพื่อ minimal logging)
-- ----------------------------------------------------------------------------
IF DB_ID('LabLoad') IS NULL
    CREATE DATABASE LabLoad;
GO

ALTER DATABASE LabLoad SET RECOVERY SIMPLE;
GO

USE LabLoad;
GO

-- ----------------------------------------------------------------------------
-- Task 1: ตารางทดลองแบบ heap (ยังไม่มี clustered index)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.LoadTarget;
GO

CREATE TABLE dbo.LoadTarget
(
    RowId      bigint        NOT NULL,
    RowData    nvarchar(40)  NOT NULL,
    SomeNumber int           NOT NULL,
    CreatedAt  datetime2(3)  NOT NULL
);
GO

-- ----------------------------------------------------------------------------
-- Task 2-5: เทียบ log usage ระหว่างโหลดแบบ fully logged กับ minimal logging
-- (ทำใน batch เดียวเพราะตัวแปร T-SQL มีขอบเขตระดับ batch)
-- ----------------------------------------------------------------------------
DECLARE @LogUsedBefore     float,
        @LogAfterFull      float,
        @LogBeforeTablock  float,
        @LogAfterTablock   float;

-- Task 2: จับค่า log ก่อนโหลด
SELECT @LogUsedBefore = used_log_space_in_bytes / 1048576.0
FROM sys.dm_db_log_space_usage;

-- Task 3: โหลด 200,000 แถว แบบ fully logged (explicit transaction, ไม่มี TABLOCK)
BEGIN TRANSACTION;

INSERT dbo.LoadTarget (RowId, RowData, SomeNumber, CreatedAt)
SELECT TOP (200000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
       CONCAT(N'DataRow-', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))),
       1000 + (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500),
       SYSDATETIME()
FROM sys.all_objects AS a1
CROSS JOIN sys.all_objects AS a2;

COMMIT;

SELECT @LogAfterFull = used_log_space_in_bytes / 1048576.0
FROM sys.dm_db_log_space_usage;

-- Task 4: ล้างแล้วโหลดซ้ำแบบ minimal logging (heap + TABLOCK, SIMPLE recovery)
TRUNCATE TABLE dbo.LoadTarget;

SELECT @LogBeforeTablock = used_log_space_in_bytes / 1048576.0
FROM sys.dm_db_log_space_usage;

INSERT dbo.LoadTarget WITH (TABLOCK)   -- <<< TABLOCK คือกุญแจของ minimal logging
       (RowId, RowData, SomeNumber, CreatedAt)
SELECT TOP (200000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
       CONCAT(N'DataRow-', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))),
       1000 + (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500),
       SYSDATETIME()
FROM sys.all_objects AS a1
CROSS JOIN sys.all_objects AS a2;

SELECT @LogAfterTablock = used_log_space_in_bytes / 1048576.0
FROM sys.dm_db_log_space_usage;

-- Task 5: เทียบผล — แถวที่โหลดแบบ TABLOCK ใช้ log น้อยกว่าหลายเท่า
SELECT @LogAfterFull - @LogUsedBefore       AS LogUsedMB_FullyLogged,
       @LogAfterTablock - @LogBeforeTablock AS LogUsedMB_MinimalLogging,
       N'เงื่อนไข minimal logging: SIMPLE/BULK_LOGGED + TABLOCK + heap (หรือ empty table)'
           AS Reminder;
GO

-- ----------------------------------------------------------------------------
-- Task 6: Disable/enable constraint — ความต่างของ trusted กับ untrusted
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.LoadTargetSettings;
DROP TABLE IF EXISTS dbo.LoadTargetMaster;
GO

CREATE TABLE dbo.LoadTargetMaster
(
    MasterId int NOT NULL CONSTRAINT PK_LoadTargetMaster PRIMARY KEY,
    Name     nvarchar(50) NOT NULL CONSTRAINT u_LoadTargetMaster_Name UNIQUE
);

CREATE TABLE dbo.LoadTargetSettings
(
    SettingId int NOT NULL CONSTRAINT PK_LoadTargetSettings PRIMARY KEY,
    MasterId  int NOT NULL,
    Value     nvarchar(50) NOT NULL,
    CONSTRAINT FK_Settings_Master FOREIGN KEY (MasterId)
        REFERENCES dbo.LoadTargetMaster (MasterId)
);

INSERT dbo.LoadTargetMaster (MasterId, Name) VALUES (1, N'Zone-A'), (2, N'Zone-B');
INSERT dbo.LoadTargetSettings (SettingId, MasterId, Value)
VALUES (1, 1, N'theme=dark'), (2, 1, N'lang=th'), (3, 2, N'theme=light');
GO

-- สถานะเริ่มต้น: enabled + trusted
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.LoadTargetSettings');

-- ปิด FK
ALTER TABLE dbo.LoadTargetSettings NOCHECK CONSTRAINT FK_Settings_Master;

-- (จุดนี้ INSERT แถวที่ผิด FK ได้ — จำลอง bulk load ที่ "เชื่อข้อมูลต้นทาง")
INSERT dbo.LoadTargetSettings (SettingId, MasterId, Value)
VALUES (9, 99, N'orphan-row');

-- เปิดกลับแบบไม่ตรวจข้อมูลเก่า -> untrusted (is_not_trusted = 1)
ALTER TABLE dbo.LoadTargetSettings CHECK CONSTRAINT FK_Settings_Master;
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.LoadTargetSettings');

-- เปิดกลับแบบ WITH CHECK CHECK -> ตรวจข้อมูลเก่าด้วย จึง trusted
-- (แถว orphan จากด้านบนจะทำให้คำสั่งนี้ FAIL — แสดงว่าการตรวจทำงานจริง!)
ALTER TABLE dbo.LoadTargetSettings WITH CHECK CHECK CONSTRAINT FK_Settings_Master;
GO

-- ลบ orphan ทิ้งแล้ว enable ใหม่ให้ trusted
DELETE FROM dbo.LoadTargetSettings WHERE SettingId = 9;

ALTER TABLE dbo.LoadTargetSettings WITH CHECK CHECK CONSTRAINT FK_Settings_Master;

SELECT name, is_disabled, is_not_trusted   -- ตอนนี้ trusted แล้ว
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.LoadTargetSettings');
GO

-- ----------------------------------------------------------------------------
-- Task 7: ปิด index ก่อนโหลด เปิดด้วย REBUILD
-- ----------------------------------------------------------------------------
CREATE NONCLUSTERED INDEX ix_LoadTarget_RowData
    ON dbo.LoadTarget (RowData);
GO

-- ดูสถานะ
SELECT name, index_id, type_desc, is_disabled
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.LoadTarget');

-- ปิด nonclustered index (ข้อมูลยังเข้าได้ แต่ index นี้ไม่ถูก update)
ALTER INDEX ix_LoadTarget_RowData ON dbo.LoadTarget DISABLE;

SELECT name, index_id, type_desc, is_disabled
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.LoadTarget');

-- ...ตรงนี้คือจุด bulk load...

-- เปิดกลับด้วย REBUILD (สร้าง index จากข้อมูลทั้งหมดในครั้งเดียว)
ALTER INDEX ix_LoadTarget_RowData ON dbo.LoadTarget REBUILD;

SELECT name, index_id, type_desc, is_disabled
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.LoadTarget');
GO

-- ----------------------------------------------------------------------------
-- Cleanup (ปลายทาง): รันเมื่อต้องการลบของทดลองทั้งหมด
-- ----------------------------------------------------------------------------
-- USE master;
-- DROP DATABASE IF EXISTS LabLoad;
