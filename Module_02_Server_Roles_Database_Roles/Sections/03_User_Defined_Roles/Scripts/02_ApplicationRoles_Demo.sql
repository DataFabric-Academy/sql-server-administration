-- 02_ApplicationRoles_Demo.sql
-- สาธิต application role ตามหัวข้อ 3.2 ของ Section 3 (Module 2)
-- ปรับจาก Microsoft 20764D "Demo 4 - application roles.sql"

USE [AdventureWorks2025];
GO

-- ===== Step 1: สร้าง application role =====
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'purchase_order' AND type = 'A')
    DROP APPLICATION ROLE [purchase_order];
GO
CREATE APPLICATION ROLE [purchase_order] WITH PASSWORD = N'Pa$$w0rd2025';
GO

-- ===== Step 2: ให้ role สิทธิ์ SELECT ที่ schema Purchasing =====
GRANT SELECT ON SCHEMA::Purchasing TO [purchase_order];
GO

-- ===== Step 3: ก่อนเปิด role — user ปัจจุบันอ่าน Sales ได้ =====
SELECT TOP (5) CustomerID, AccountNumber FROM Sales.Customer;
GO

-- ===== Step 4: เปิด application role (เก็บ cookie เพื่อปิดทีหลัง) =====
DROP TABLE IF EXISTS #cookie;
DECLARE @cookie_store varbinary(8000);
EXEC sp_setapprole
    @rolename      = N'purchase_order',
    @password      = N'Pa$$w0rd2025',
    @fCreateCookie = true,
    @cookie        = @cookie_store OUTPUT;
SELECT @cookie_store AS cookie INTO #cookie;
GO

-- ===== Step 5: หลังเปิด role — สิทธิ์ของ user จริงหายไปทั้งหมด =====
-- (คำสั่งต่อไปนี้จะ FAIL เพราะ app role ไม่มีสิทธิ์ที่ Sales)
BEGIN TRY
    SELECT TOP (5) CustomerID, AccountNumber FROM Sales.Customer;
END TRY
BEGIN CATCH
    PRINT N'ถูกปฏิเสธ (คาดหวัง): ' + ERROR_MESSAGE();
END CATCH
GO

-- แต่อ่าน Purchasing ได้เพราะ role มีสิทธิ์
SELECT TOP (5) ShipMethodID, Name FROM Purchasing.ShipMethod;
GO

-- ===== Step 6: identity — login จริงยังมองเห็น USER_NAME คือ app role =====
SELECT SUSER_SNAME() AS suser_sname,
       SUSER_NAME()  AS suser_name,
       USER_NAME()   AS user_name;   -- 'purchase_order'
GO

-- ===== Step 7: ปิด application role ด้วย cookie =====
DECLARE @cookie varbinary(8000) = (SELECT TOP (1) cookie FROM #cookie);
EXEC sp_unsetapprole @cookie;
GO

-- ===== Step 8: กลับมาเป็น user เดิมแล้ว =====
SELECT SUSER_SNAME() AS suser_sname, USER_NAME() AS user_name;
SELECT TOP (5) CustomerID, AccountNumber FROM Sales.Customer;   -- ทำงานได้อีกครั้ง
GO

-- ===== Cleanup =====
DROP APPLICATION ROLE IF EXISTS [purchase_order];
GO
