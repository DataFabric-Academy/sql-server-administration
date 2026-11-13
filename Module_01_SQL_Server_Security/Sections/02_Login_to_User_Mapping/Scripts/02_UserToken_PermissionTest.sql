-- 02_UserToken_PermissionTest.sql
-- ทดสอบสิทธิ์ผ่าน user token ตามหัวข้อ 2.4 ของ Section 2 (Module 1)

USE [AdventureWorks2025];
GO

-- โจทย์: Superman อ่านได้เฉพาะ schema Sales แต่ห้ามอ่านตาราง CreditCard
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Superman')
    CREATE USER [Superman] FOR LOGIN [Superman];
GO

GRANT CONNECT TO [Superman];
GRANT SELECT ON SCHEMA::[Sales] TO [Superman];
DENY  SELECT ON OBJECT::[Sales].[CreditCard] TO [Superman];
GO

-- ทดสอบสิทธิ์ในฐานะ Superman
EXECUTE AS USER = N'Superman';
PRINT N'--- อ่าน Sales.SalesOrderHeader (ควรผ่าน) ---';
SELECT TOP 3 SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader ORDER BY SalesOrderID;

PRINT N'--- อ่าน Sales.CreditCard (ควรถูก DENY บล็อก) ---';
BEGIN TRY
    SELECT TOP 3 * FROM Sales.CreditCard;
    PRINT N'ผ่าน?! (ไม่ควรเกิด)';
END TRY
BEGIN CATCH
    PRINT N'ถูกบล็อกเป็นที่เรียบร้อย: ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO

-- ===== Cleanup =====
REVOKE SELECT ON SCHEMA::[Sales] FROM [Superman];
REVOKE SELECT ON OBJECT::[Sales].[CreditCard] FROM [Superman];
REVOKE CONNECT FROM [Superman];
GO
