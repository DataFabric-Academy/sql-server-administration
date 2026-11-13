/* =============================================================================
   01_FileRestore_Piecemeal.sql
   Module 07 - Section 3: piecemeal restore — กู้ PRIMARY + Current ให้ใช้งานก่อน
   แล้วกู้ ArchiveFG (read-only) ทีหลัง — ปรับจาก Lab07 Restore AWDataWarehouse
   รันได้บน SQL Server 2025 (online file restore ต้อง Enterprise/Developer)
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB แบบ warehouse: PRIMARY + Current (read/write) + ArchiveFG (read-only)
   --------------------------------------------------------------- */
IF DB_ID(N'LabPiecemeal') IS NOT NULL
BEGIN
    ALTER DATABASE [LabPiecemeal] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabPiecemeal];
END
GO
CREATE DATABASE [LabPiecemeal]
ON  PRIMARY ( NAME = N'LabPM_prim', FILENAME = N'C:\SQLBackups\LabPM_prim.mdf' ),
    FILEGROUP [Current]
             ( NAME = N'LabPM_cur', FILENAME = N'C:\SQLBackups\LabPM_cur.ndf' ),
    FILEGROUP [ArchiveFG]
             ( NAME = N'LabPM_arch', FILENAME = N'C:\SQLBackups\LabPM_arch.ndf' )
LOG ON       ( NAME = N'LabPM_log', FILENAME = N'C:\SQLBackups\LabPM_log.ldf' );
GO
ALTER DATABASE [LabPiecemeal] SET RECOVERY FULL;
GO

USE [LabPiecemeal];
GO
CREATE TABLE dbo.FactSales (id INT IDENTITY, amount DECIMAL(10,2)) ON [Current];
CREATE TABLE dbo.FactSalesArchive (id INT, amount DECIMAL(10,2)) ON [ArchiveFG];
INSERT INTO dbo.FactSales (amount) VALUES (100.50), (200.75), (300.25);
INSERT INTO dbo.FactSalesArchive (id, amount) VALUES (1, 999.99);
GO
ALTER DATABASE [LabPiecemeal] MODIFY FILEGROUP [ArchiveFG] READ_ONLY;
GO
USE master;
GO

/* ---------------------------------------------------------------
   2) Backup: full (ทั้ง DB) + log หลังเปลี่ยนแปลง
   --------------------------------------------------------------- */
BACKUP DATABASE [LabPiecemeal]
TO DISK = N'C:\SQLBackups\LabPM.bak'
WITH FORMAT, INIT, NAME = N'PM full (ทุก filegroup)', CHECKSUM;
GO
USE [LabPiecemeal];
GO
INSERT INTO dbo.FactSales (amount) VALUES (400.00);
USE master;
GO
BACKUP LOG [LabPiecemeal] TO DISK = N'C:\SQLBackups\LabPM_log.trn'
WITH FORMAT, INIT, NAME = N'PM log 1', CHECKSUM;
GO

/* ---------------------------------------------------------------
   3) จำลองเหตุการณ์: กู้ใหม่บนชื่อเดิมแบบ piecemeal
      ขั้นแรก: PRIMARY + Current ด้วย WITH PARTIAL, NORECOVERY
   --------------------------------------------------------------- */
RESTORE DATABASE [LabPiecemeal]
    FILEGROUP = N'Current'
FROM DISK = N'C:\SQLBackups\LabPM.bak'
WITH FILE = 1, PARTIAL, NORECOVERY,
     REPLACE;
GO
RESTORE LOG [LabPiecemeal]
FROM DISK = N'C:\SQLBackups\LabPM_log.trn'
WITH NORECOVERY;
GO
RESTORE DATABASE [LabPiecemeal] WITH RECOVERY;
GO

/* Expected: DB ONLINE — แต่ ArchiveFG ยัง OFFLINE
   ตรวจสถานะ filegroup ทีละไฟล์: */
SELECT name, type_desc, state_desc
FROM [LabPiecemeal].sys.database_files;
GO

/* ---------------------------------------------------------------
   4) ข้อมูลงานจริง (Current) ใช้ได้แล้ว — ผู้ใช้กลับมาทำงานได้ทันที
   --------------------------------------------------------------- */
USE [LabPiecemeal];
GO
SELECT * FROM dbo.FactSales;
GO
/* Expected: 4 แถว (รวม 400.00 จาก log) — piecemeal กู้ครบตามลำดับ */

/* ---------------------------------------------------------------
   5) query filegroup ที่ offline → error จริง
   --------------------------------------------------------------- */
BEGIN TRY
    SELECT TOP 1 * FROM dbo.FactSalesArchive;
END TRY
BEGIN CATCH
    PRINT N'EXPECTED (ArchiveFG ยัง offline): ' + ERROR_MESSAGE();
END CATCH
GO
USE master;
GO

/* ---------------------------------------------------------------
   6) กู้ ArchiveFG (read-only ตั้งแต่ backup) — RECOVERY ทันที ไม่ต้องต่อ log
   --------------------------------------------------------------- */
RESTORE DATABASE [LabPiecemeal]
    FILEGROUP = N'ArchiveFG'
FROM DISK = N'C:\SQLBackups\LabPM.bak'
WITH FILE = 1, RECOVERY;
GO
USE [LabPiecemeal];
GO
SELECT TOP 1 * FROM dbo.FactSalesArchive;
GO
/* Expected: 999.99 — ทั้ง DB ออนไลน์ครบแล้ว */

/* ---------------------------------------------------------------
   ข้อจำกัดที่ควรจำ:
   - online file restore (กู้ filegroup ระหว่าง DB online) = Enterprise/Developer
   - offline piecemeal = ทุก edition (DB offline จนจบ)
   - read-only FG ที่ "ไม่เปลี่ยนตั้งแต่ backup" กู้ RECOVERY ตรง ๆ ได้
   - read/write FG ต้องต่อ log ครบจนจุดเวลาปัจจุบันจึง RECOVERY ได้
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabPiecemeal] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabPiecemeal];
GO
-- ลบไฟล์ C:\SQLBackups\LabPM* ทีหลัง
GO
