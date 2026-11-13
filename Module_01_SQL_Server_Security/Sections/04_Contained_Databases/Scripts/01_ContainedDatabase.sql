-- 01_ContainedDatabase.sql
-- สาธิต Partially Contained Database ตามหัวข้อ 4.3 ของ Section 4 (Module 1)
-- ปรับจาก Microsoft 20764D "ContainedDatabase.sql" ให้ idempotent + cleanup

USE [master];
GO

-- ===== STEP A: ดูสถานะปัจจุบันของ option ระดับ server =====
SELECT value_in_use, description
FROM sys.configurations
WHERE name = 'contained database authentication';
GO

-- ===== STEP B: เปิด (หรือยืนยันว่าเปิดแล้ว) =====
IF (SELECT value_in_use FROM sys.configurations WHERE name = 'contained database authentication') = 0
BEGIN
    EXEC sys.sp_configure N'contained database authentication', 1;
    RECONFIGURE;
END
GO

-- ===== STEP C: สร้างฐานข้อมูลแบบ partially contained =====
IF DB_ID(N'PartialData') IS NOT NULL
BEGIN
    ALTER DATABASE PartialData SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PartialData;
END
GO
CREATE DATABASE [PartialData] CONTAINMENT = PARTIAL;
GO

-- ===== STEP D: สร้าง contained users =====
USE [PartialData];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'ClientUser1')
    CREATE USER [ClientUser1] WITH PASSWORD = N'Pa$$w0rd2025';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'ClientUser2')
    CREATE USER [ClientUser2] WITH PASSWORD = N'Pa$$w0rd2025';
GO

SELECT name, authentication_type_desc, type_desc
FROM sys.database_principals
WHERE name LIKE N'Client%';
GO

-- ===== STEP E: ทดสอบ login ด้วย contained user (รันจาก session ใหม่เพื่อเห็นการ auth จริง) =====
-- เชื่อมต่อ SSMS ด้วย SQL Authentication: ClientUser1 / Pa$$w0rd2025 และกำหนด DB = PartialData
-- ไม่ต้องมี login ระดับ server ใด ๆ

-- ===== STEP F: ทดสอบเวลาย้ายฐานข้อมูล =====
BACKUP DATABASE [PartialData] TO DISK = N'D:\SQLBackups\PartialData.bak' WITH CHECKSUM;
-- (หากมี container/server ที่สอง ให้ restore ที่นั่น แล้ว login ด้วย ClientUser1 ได้ทันที)

-- ===== Cleanup =====
USE [master];
GO
ALTER DATABASE [PartialData] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [PartialData];
GO
EXEC sys.sp_configure N'contained database authentication', 0;
RECONFIGURE;
GO
