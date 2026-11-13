/* =============================================================================
   02_RestoreEncryptedBackup.sql
   Module 07 - Section 3: restore encrypted backup — fail โดยไม่มี certificate
   และผ่านเมื่อนำเข้าครบ (ปรับจากเดโมเดิม "Restore Encrypted Backup.sql")
   รันได้บน SQL Server 2025 — idempotent, ทุกอย่างสร้างในสคริปต์เดียวจบ
   ============================================================================= */

USE [master];
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   0) เตรียม master key (ถ้ายังไม่มี) + certificate จาก Module 6
   --------------------------------------------------------------- */
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO
IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'EncRestoreCert')
    DROP CERTIFICATE EncRestoreCert;
GO
CREATE CERTIFICATE EncRestoreCert
    WITH SUBJECT = N'Encrypted restore demo', EXPIRY_DATE = '2030-12-31';
GO
BACKUP CERTIFICATE EncRestoreCert
TO FILE = N'C:\SQLBackups\EncRestoreCert.cer'
WITH PRIVATE KEY (FILE = N'C:\SQLBackups\EncRestoreCert.pvk',
                  ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO

/* ---------------------------------------------------------------
   1) DB ทดลอง + encrypted backup
   --------------------------------------------------------------- */
IF DB_ID(N'LabEncRestore') IS NOT NULL
BEGIN
    ALTER DATABASE [LabEncRestore] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabEncRestore];
END
GO
CREATE DATABASE [LabEncRestore];
GO
USE [LabEncRestore];
GO
CREATE TABLE dbo.Secret (id INT IDENTITY, note NVARCHAR(80));
INSERT INTO dbo.Secret (note) VALUES (N'ข้อมูลที่เข้ารหัสในไฟล์ backup');
GO
USE master;
GO
BACKUP DATABASE [LabEncRestore]
TO DISK = N'C:\SQLBackups\EncRestore.bak'
WITH FORMAT, INIT,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = EncRestoreCert),
     CHECKSUM, COMPRESSION;
GO

/* ---------------------------------------------------------------
   2) จำลอง "server ใหม่ที่ไม่มี certificate": ลบ cert แล้วลอง restore
   --------------------------------------------------------------- */
DROP CERTIFICATE EncRestoreCert;
GO

BEGIN TRY
    RESTORE DATABASE [LabEncRestore_Fail]
    FROM DISK = N'C:\SQLBackups\EncRestore.bak'
    WITH FILE = 1,
         MOVE N'LabEncRestore'     TO N'C:\SQLBackups\EncR_Fail.mdf',
         MOVE N'LabEncRestore_log' TO N'C:\SQLBackups\EncR_Fail_log.ldf';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (ไม่มี certificate): ' + ERROR_MESSAGE();
END CATCH
GO
/* Expected: RESTORE DATABASE abort ด้วย error เรื่อง certificate
   (ข้อความแนะนำ: "cannot be restored because the certificate... is not found")
   ไฟล์ .bak โดยไม่มี cert = ทำอะไรไม่ได้เลย — นี่คือจุดประสงค์ของ encryption */

/* ---------------------------------------------------------------
   3) นำเข้า certificate จากสำเนา (.cer + .pvk) แล้ว restore อีกครั้ง
   --------------------------------------------------------------- */
CREATE CERTIFICATE EncRestoreCert
    FROM FILE = N'C:\SQLBackups\EncRestoreCert.cer'
    WITH PRIVATE KEY (FILE = N'C:\SQLBackups\EncRestoreCert.pvk',
                      DECRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO

RESTORE DATABASE [LabEncRestore_OK]
FROM DISK = N'C:\SQLBackups\EncRestore.bak'
WITH FILE = 1,
     MOVE N'LabEncRestore'     TO N'C:\SQLBackups\EncR_OK.mdf',
     MOVE N'LabEncRestore_log' TO N'C:\SQLBackups\EncR_OK_log.ldf',
     RECOVERY;
GO
USE [LabEncRestore_OK];
GO
SELECT * FROM dbo.Secret;
GO
/* Expected: 1 แถว — restore สำเร็จบน "เครื่องใหม่" เมื่อครบ master key + cert */

/* ---------------------------------------------------------------
   บทสรุปเชิงปฏิบัติ (runbook):
   1. สร้าง master key ของ master บนเครื่องปลายทาง (ถ้าไม่มี)
   2. นำเข้า .cer + .pvk ด้วย CREATE CERTIFICATE ... FROM FILE
   3. RESTORE ปกติ — ทดสอบเป็นระยะใน restore drill
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
IF DB_ID(N'LabEncRestore_Fail') IS NOT NULL
BEGIN
    ALTER DATABASE [LabEncRestore_Fail] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabEncRestore_Fail];
END
GO
ALTER DATABASE [LabEncRestore_OK] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabEncRestore_OK];
ALTER DATABASE [LabEncRestore] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabEncRestore];
IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'EncRestoreCert')
    DROP CERTIFICATE EncRestoreCert;
GO
-- ลบไฟล์ C:\SQLBackups\EncRestore* และ EncR_* ทีหลัง
GO
