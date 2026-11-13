-- ============================================================================
-- Module 14 - Section 2 - Script 01: ตารางทดลองสำหรับ Import/Export Wizard
-- รันได้บน: SQL Server 2019+ บน AdventureWorks2025 (schema Lab)
-- ใช้กับ: README หัวข้อ 2 (เคส copy ตาราง + เคส copy ผล query)
-- ============================================================================
USE AdventureWorks2025;
GO

IF SCHEMA_ID('Lab') IS NULL
    EXEC('CREATE SCHEMA Lab;');
GO

-- ----------------------------------------------------------------------------
-- ตารางต้นทางสำหรับเคส A: copy ตารางทั้งใบ
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS Lab.Suppliers;
GO

CREATE TABLE Lab.Suppliers
(
    SupplierId   int IDENTITY(1, 1) NOT NULL
        CONSTRAINT PK_Suppliers PRIMARY KEY,
    SupplierName nvarchar(100)      NOT NULL,
    Country      varchar(50)        NOT NULL,
    Email        varchar(120)       NULL,
    IsActive     bit                NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
    CreatedAt    datetime2(3)       NOT NULL CONSTRAINT DF_Suppliers_At DEFAULT SYSDATETIME()
);
GO

SET IDENTITY_INSERT Lab.Suppliers ON;

INSERT Lab.Suppliers (SupplierId, SupplierName, Country, Email, IsActive)
VALUES (1, N'Bamboo Parts Co.',        N'TH', N'contact@bambooparts.example', 1),
       (2, N'Mekong Textiles',         N'TH', N'sales@mekongtex.example',     1),
       (3, N'Sumatra Coffee Traders',  N'ID', N'info@sumatracoffee.example',  1),
       (4, N'Java Paper Mills',        N'ID', NULL,                           0),
       (5, N'Ho Chi Minh Electronics', N'VN', N'sales@hcme.example',          1),
       (6, N'Penang Semiconductor',    N'MY', N'contact@penangsemi.example',  1),
       (7, N'Cebu Marine Supplies',    N'PH', N'hello@cebumarine.example',    0),
       (8, N'Hanoi Ceramics',          N'VN', N'sales@hanoiceramics.example', 1);

SET IDENTITY_INSERT Lab.Suppliers OFF;
GO

-- ----------------------------------------------------------------------------
-- View สำหรับเคส B: copy ผลของ query (เฉพาะ supplier ที่ยัง active)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS Lab.vw_ActiveSuppliers;
GO

CREATE VIEW Lab.vw_ActiveSuppliers
AS
SELECT SupplierName, Country, Email
FROM Lab.Suppliers
WHERE IsActive = 1;
GO

SELECT * FROM Lab.Suppliers;
SELECT * FROM Lab.vw_ActiveSuppliers;
GO

-- ----------------------------------------------------------------------------
-- Cleanup: รันเมื่อจบ Section (หลังทำแบบฝึกหัดเสร็จ)
-- ----------------------------------------------------------------------------
-- DROP VIEW IF EXISTS Lab.vw_ActiveSuppliers;
-- DROP TABLE IF EXISTS Lab.Suppliers;
-- DROP TABLE IF EXISTS Lab.Suppliers_RoundTrip;
-- DROP TABLE IF EXISTS Lab.ActiveSuppliers;
