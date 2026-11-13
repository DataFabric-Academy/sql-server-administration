/* =============================================================================
   01_MediaSets_Stripe_Mirror.sql
   Module 06 - Section 1: media set / family / backup set, stripe และ MIRROR TO
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
EXEC sys.xp_create_subdir N'C:\SQLBackups\mirror';
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง
   --------------------------------------------------------------- */
IF DB_ID(N'LabMediaSets') IS NOT NULL
BEGIN
    ALTER DATABASE [LabMediaSets] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabMediaSets];
END
GO
CREATE DATABASE [LabMediaSets];
ALTER DATABASE [LabMediaSets] SET RECOVERY FULL;
GO

USE [LabMediaSets];
GO
CREATE TABLE dbo.Media (id INT IDENTITY, payload CHAR(8000) DEFAULT 'x');
INSERT INTO dbo.Media DEFAULT VALUES;
GO 500
USE master;
GO

/* ---------------------------------------------------------------
   2) Backup set สามอันในไฟล์เดียว (NOINIT เป็น default)
      → สังเกต backup set numbering 1, 2, 3
   --------------------------------------------------------------- */
BACKUP DATABASE [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets.bak'
WITH FORMAT, INIT, NAME = N'set 1 - full', CHECKSUM, COMPRESSION;
GO
INSERT INTO [LabMediaSets].dbo.Media DEFAULT VALUES;
GO 100
BACKUP DATABASE [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets.bak'
WITH DIFFERENTIAL, NAME = N'set 2 - differential', CHECKSUM;   -- append (NOINIT)
GO
BACKUP LOG [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets.bak'
WITH NAME = N'set 3 - log', CHECKSUM;                          -- append (NOINIT)
GO

-- อ่านโครงสร้าง: 3 backup sets ใน media set เดียว
RESTORE HEADERONLY FROM DISK = N'C:\SQLBackups\MediaSets.bak';
GO
/* Expected: 3 แถว, Position = 1/2/3, BackupType = 1 (full) / 5 (diff) / 2 (log)
   MediaSetName ตรงกันทุกแถว — การอ้างอิง restore ใช้ WITH FILE = <Position> */

/* ---------------------------------------------------------------
   3) Stripe backup — สองไฟล์เป็น media set เดียว
   --------------------------------------------------------------- */
BACKUP DATABASE [LabMediaSets]
TO DISK = N'C:\SQLBackups\Stripe_1.bak',
   DISK = N'C:\SQLBackups\Stripe_2.bak'
WITH FORMAT, MEDIANAME = N'StripeDemo', NAME = N'striped full', CHECKSUM;
GO
RESTORE HEADERONLY FROM DISK = N'C:\SQLBackups\Stripe_1.bak';
GO
/* Expected: แถวเดียว, FamilyCount = 2 — restore ต้องระบุทั้งสองไฟล์ */

/* ---------------------------------------------------------------
   4) MIRROR TO — Enterprise/Developer เท่านั้น (จะ error ถ้า edition ไม่รองรับ)
   --------------------------------------------------------------- */
BEGIN TRY
    BACKUP DATABASE [LabMediaSets]
    TO DISK = N'C:\SQLBackups\MirrorMain.bak'
    MIRROR TO DISK = N'C:\SQLBackups\mirror\MirrorCopy.bak'
    WITH FORMAT, NAME = N'mirrored full', CHECKSUM;
    PRINT N'MIRROR TO succeeded (Enterprise/Developer edition)';
END TRY
BEGIN CATCH
    PRINT N'MIRROR TO ไม่รองรับบน edition นี้: ' + ERROR_MESSAGE();
END CATCH
GO

/* ---------------------------------------------------------------
   5) INIT + การตรวจ expiration (RETAINDAYS)
   --------------------------------------------------------------- */
BACKUP DATABASE [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets_Exp.bak'
WITH FORMAT, INIT, RETAINDAYS = 7, NAME = N'retain 7 days', CHECKSUM;
GO
-- INIT พร้อม backup set ยังไม่หมดอายุ → fail; SKIP จะเขียนทับได้
BEGIN TRY
    BACKUP DATABASE [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets_Exp.bak'
    WITH INIT, NAME = N'attempt overwrite without SKIP';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (ยังไม่หมดอายุ): ' + ERROR_MESSAGE();
END CATCH
GO
BACKUP DATABASE [LabMediaSets] TO DISK = N'C:\SQLBackups\MediaSets_Exp.bak'
WITH SKIP, INIT, NAME = N'overwrite with SKIP', CHECKSUM;
GO

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabMediaSets] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMediaSets];
GO
-- ลบไฟล์ C:\SQLBackups\MediaSets* และ Stripe_* / MirrorMain* ทีหลัง
-- (PowerShell: Remove-Item C:\SQLBackups\MediaSets*, C:\SQLBackups\Stripe_*, C:\SQLBackups\MirrorMain* -Recurse)
GO
