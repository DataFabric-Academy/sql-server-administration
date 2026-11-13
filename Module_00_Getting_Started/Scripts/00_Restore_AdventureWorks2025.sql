-- 00_Restore_AdventureWorks2025.sql
-- Restore AdventureWorks2025 สำหรับใช้ในแล็บทุกโมดูลของคอร์ส
-- ดาวน์โหลดไฟล์ .bak จาก:
-- https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2025.bak
-- แก้ @BackupPath / @DataPath ให้ตรงเครื่องของคุณก่อนรัน

USE master;
GO

DECLARE @BackupPath nvarchar(4000) = N'D:\SetupFiles\AdventureWorks2025.bak';
DECLARE @DataPath    nvarchar(4000) = N'D:\SQLData\';
DECLARE @LogPath     nvarchar(4000) = N'D:\SQLLog\';

IF DB_ID(N'AdventureWorks2025') IS NOT NULL
BEGIN
    ALTER DATABASE AdventureWorks2025 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AdventureWorks2025;
END
GO

RESTORE DATABASE [AdventureWorks2025]
FROM DISK = N'D:\SetupFiles\AdventureWorks2025.bak'
WITH
    MOVE N'AdventureWorks2025'     TO N'D:\SQLData\AdventureWorks2025.mdf',
    MOVE N'AdventureWorks2025_log' TO N'D:\SQLLog\AdventureWorks2025_log.ldf',
    REPLACE, RECOVERY, STATS = 10;
GO

-- ตรวจสอบผลลัพธ์
SELECT name, compatibility_level, recovery_model_desc, state_desc
FROM sys.databases
WHERE name = N'AdventureWorks2025';
GO

USE AdventureWorks2025;
GO
SELECT TOP 5
    soh.SalesOrderID, soh.OrderDate, soh.TotalDue,
    COUNT(sod.SalesOrderDetailID) AS LineCount
FROM Sales.SalesOrderHeader AS soh
JOIN Sales.SalesOrderDetail AS sod ON sod.SalesOrderID = soh.SalesOrderID
GROUP BY soh.SalesOrderID, soh.OrderDate, soh.TotalDue
ORDER BY soh.SalesOrderID;
GO
