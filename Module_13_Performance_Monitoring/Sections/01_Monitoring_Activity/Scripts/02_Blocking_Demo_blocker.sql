-- ============================================================================
-- Module 13 - Section 1 - Script 02: ผู้ BLOCK (blocker) — รันใน SSMS Session 1
-- ปรับจาก: Microsoft 20764D Mod13 "Demo 2a - blocker.sql"
-- รันได้บน: SQL Server 2019+ ฐาน AdventureWorks2025
-- ขั้นตอน: รันไฟล์นี้จนถึง UPDATE แล้วปล่อยค้างไว้ (ห้าม COMMIT/ROLLBACK)
--          ต่อด้วย 03_Blocking_Demo_blocked.sql ในหน้าต่าง (session) ที่สอง
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 1: เตรียมตารางทดลอง (idempotent — สร้างครั้งแรกครั้งเดียว)
-- ----------------------------------------------------------------------------
USE AdventureWorks2025;
GO

IF SCHEMA_ID('Lab') IS NULL
    EXEC('CREATE SCHEMA Lab;');
GO

IF OBJECT_ID('Lab.BlockingDemo', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.BlockingDemo
    (
        Id          int          NOT NULL CONSTRAINT PK_BlockingDemo PRIMARY KEY,
        ProductName nvarchar(50) NOT NULL,
        Balance     int          NOT NULL
    );

    INSERT Lab.BlockingDemo (Id, ProductName, Balance)
    VALUES (1, N'Widget A', 100),
           (2, N'Gadget B', 50);
END
GO

SELECT * FROM Lab.BlockingDemo;
GO

-- ----------------------------------------------------------------------------
-- Task 2: เปิด TRANSACTION แล้ว UPDATE — lock จะถือไว้จนกว่า COMMIT/ROLLBACK
-- ----------------------------------------------------------------------------
BEGIN TRANSACTION;

UPDATE Lab.BlockingDemo
SET Balance = Balance + 1
WHERE Id = 1;

SELECT @@TRANCOUNT AS OpenTransactions,
       SUSER_SNAME() AS CurrentLogin,
       @@SPID AS ThisSessionId;
-- ห้ามรัน COMMIT หรือ ROLLBACK ตอนนี้!
-- ต่อไป: รัน 03_Blocking_Demo_blocked.sql ในหน้าต่างที่สอง แล้วสังเกต blocking

-- ----------------------------------------------------------------------------
-- Task 3 (ทำเมื่อจบการทดลอง): เลือกยกเลิกคอมเมนต์ตามต้องการแล้วรัน
-- ----------------------------------------------------------------------------
-- COMMIT;    -- ปล่อย lock, session ที่รอจะรันต่อสำเร็จ
-- ROLLBACK;  -- ย้อนค่า Balance กลับ 100 และปล่อย lock

-- ----------------------------------------------------------------------------
-- Task 4 (ทำเมื่อจบโมดูล): ล้างตารางทดลอง
-- ----------------------------------------------------------------------------
-- DROP TABLE IF EXISTS Lab.BlockingDemo;
