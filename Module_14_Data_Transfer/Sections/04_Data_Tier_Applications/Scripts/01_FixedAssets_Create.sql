-- ============================================================================
-- Module 14 - Section 4 - Script 01: สร้าง database ตัวอย่าง FixedAssets
-- (แทนไฟล์ FixedAssets_1.0.9.1.dacpac ของหลักสูตรเดิม — สร้างเองให้ครบในตัว)
-- ใช้กับ: Lab 14 Exercise 4 (extract dacpac -> deploy -> upgrade)
-- รันได้บน: SQL Server 2019+
-- ============================================================================
USE master;
GO

IF DB_ID('FixedAssets') IS NOT NULL
    DROP DATABASE FixedAssets;
GO

CREATE DATABASE FixedAssets;
GO

USE FixedAssets;
GO

-- ----------------------------------------------------------------------------
-- โครงสร้าง: หมวดสินทรัพย์ + สินทรัพย์ + การบันทึกซ่อมบำรุง
-- ----------------------------------------------------------------------------
CREATE SCHEMA Asset;
GO

CREATE TABLE Asset.AssetCategory
(
    CategoryId   int IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_AssetCategory PRIMARY KEY,
    CategoryName nvarchar(60)       NOT NULL CONSTRAINT u_CategoryName UNIQUE,
    UsefulLifeYears tinyint         NOT NULL
        CONSTRAINT ck_UsefulLife CHECK (UsefulLifeYears BETWEEN 1 AND 50)
);
GO

CREATE TABLE Asset.FixedAsset
(
    AssetId        int IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_FixedAsset PRIMARY KEY,
    CategoryId     int          NOT NULL
        CONSTRAINT FK_Asset_Category FOREIGN KEY REFERENCES Asset.AssetCategory (CategoryId),
    AssetName      nvarchar(100) NOT NULL,
    PurchaseDate   date         NOT NULL,
    PurchaseCost   decimal(18, 2) NOT NULL
        CONSTRAINT ck_Cost CHECK (PurchaseCost >= 0),
    Location       nvarchar(60) NULL
);
GO

CREATE TABLE Asset.MaintenanceLog
(
    LogId        int IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_MaintenanceLog PRIMARY KEY,
    AssetId      int          NOT NULL
        CONSTRAINT FK_Maintenance_Asset FOREIGN KEY REFERENCES Asset.FixedAsset (AssetId),
    LogDate      datetime2(0) NOT NULL CONSTRAINT df_LogDate DEFAULT SYSDATETIME(),
    Description  nvarchar(200) NOT NULL,
    Cost         decimal(10, 2) NOT NULL CONSTRAINT df_Cost DEFAULT (0)
);
GO

CREATE NONCLUSTERED INDEX ix_FixedAsset_Category
    ON Asset.FixedAsset (CategoryId) INCLUDE (AssetName, PurchaseCost);
GO

-- ----------------------------------------------------------------------------
-- ข้อมูลตัวอย่าง
-- ----------------------------------------------------------------------------
INSERT Asset.AssetCategory (CategoryName, UsefulLifeYears)
VALUES (N'เครื่องจักรการผลิต', 10),
       (N'ยานพาหนะ',          7),
       (N'คอมพิวเตอร์/เซิร์ฟเวอร์', 4),
       (N'เครื่องมือวัด',      5);

INSERT Asset.FixedAsset (CategoryId, AssetName, PurchaseDate, PurchaseCost, Location)
VALUES (1, N'CNC Machine #1',      '2023-02-14', 1850000.00, N'โรงงาน A - ไลน์ 1'),
       (1, N'CNC Machine #2',      '2024-06-01', 1920000.00, N'โรงงาน A - ไลน์ 2'),
       (2, N'Truck Isuzu 4 ล้อ',   '2022-09-30',  745000.00, N'คลังสินค้ากลาง'),
       (3, N'Server Dell R760',    '2024-11-11',   480000.00, N'Data Center'),
       (3, N'Switch Arista 48p',   '2024-11-11',    95000.00, N'Data Center'),
       (4, N'Multimeter Fluke 87V','2025-01-20',    22500.00, N'ห้อง Maintenance');

INSERT Asset.MaintenanceLog (AssetId, LogDate, Description, Cost)
VALUES (1, '2025-03-05 09:30', N'เปลี่ยนหัวกัด CNC', 12400.00),
       (3, '2025-06-18 14:00', N'เปลี่ยนยาง + รอบล้อ', 8750.00),
       (4, '2025-09-01 11:15', N'อัปเดต firmware + ตรวจ RAID', 0.00);
GO

SELECT c.CategoryName, COUNT(a.AssetId) AS Assets, SUM(a.PurchaseCost) AS TotalCost
FROM Asset.FixedAsset AS a
JOIN Asset.AssetCategory AS c ON c.CategoryId = a.CategoryId
GROUP BY c.CategoryName
ORDER BY c.CategoryName;
GO
