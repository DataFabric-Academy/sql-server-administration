/* =============================================================================
   03_Encrypted_Backup.sql
   Module 06 - Section 3: backup encryption — Database Master Key + certificate
   → BACKUP ... ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = ...)
   รันได้บน SQL Server 2025 — idempotent
   ระวัง: แล็บนี้สร้าง/ลบ master key ของ master บนเครื่องทดลองเท่านั้น
   ============================================================================= */

USE [master];
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   0) แล็บ sandbox ของตัวเอง: ถ้า master มี master key อยู่แล้ว (จาก Module 4)
      จะไม่สร้างซ้ำ — สคริปต์นี้ทำงานได้ทั้งกรณี
   --------------------------------------------------------------- */
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO

/* ---------------------------------------------------------------
   1) Certificate สำหรับ backup encryption
   --------------------------------------------------------------- */
IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'BackupLabCert')
    DROP CERTIFICATE BackupLabCert;   -- DROP CERTIFICATE ไม่รองรับ IF EXISTS ในตัวเอง
GO
CREATE CERTIFICATE BackupLabCert
    WITH SUBJECT = N'Backup encryption lab certificate',
         EXPIRY_DATE = '2030-12-31';
GO

/* ---------------------------------------------------------------
   2) Backup certificate พร้อม private key — ของประจำตัวที่ต้องเก็บให้ปลอดภัย
   --------------------------------------------------------------- */
BACKUP CERTIFICATE BackupLabCert
TO FILE = N'C:\SQLBackups\BackupLabCert.cer'
WITH PRIVATE KEY ( FILE = N'C:\SQLBackups\BackupLabCert.pvk',
                   ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025' );
GO
/* สองไฟล์นี้ (.cer + .pvk) คือ "กุญแจของทุก encrypted backup" — เก็บแยกจากไฟล์ .bak */

/* ---------------------------------------------------------------
   3) DB ทดลอง + backup เข้ารหัส AES_256
   --------------------------------------------------------------- */
IF DB_ID(N'LabEncrypted') IS NOT NULL
BEGIN
    ALTER DATABASE [LabEncrypted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabEncrypted];
END
GO
CREATE DATABASE [LabEncrypted];
GO
USE [LabEncrypted];
GO
CREATE TABLE dbo.Secrets (id INT IDENTITY, note NVARCHAR(100));
INSERT INTO dbo.Secrets (note) VALUES (N'ข้อมูลที่ต้องปกปิด');
GO
USE master;
GO

BACKUP DATABASE [LabEncrypted]
TO DISK = N'C:\SQLBackups\Encrypted.bak'
WITH FORMAT, INIT,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = BackupLabCert),
     CHECKSUM, COMPRESSION, STATS = 10,
     NAME = N'encrypted backup demo';
GO
/* ยืนยันความเข้ารหัสจาก msdb (is_encrypted = 1) */
SELECT name, is_encrypted, backup_finish_date
FROM msdb.dbo.backupset
WHERE database_name = N'LabEncrypted'
ORDER BY backup_finish_date DESC;
GO

/* ---------------------------------------------------------------
   4) จำลอง restore ฝั่ง "ไม่มี certificate":
      - ลบ certificate ชั่วคราว (ต้องมีสำเนา .cer/.pvk แล้วจึงทำ)
      - restore จะ fail
      - นำเข้า certificate กลับ แล้ว restore ผ่าน
   --------------------------------------------------------------- */
DROP CERTIFICATE [BackupLabCert];
GO

-- (a) RESTORE โดยไม่มี cert → fail
BEGIN TRY
    RESTORE DATABASE [LabEncrypted_Restore1]
    FROM DISK = N'C:\SQLBackups\Encrypted.bak'
    WITH FILE = 1,
         MOVE N'LabEncrypted'     TO N'C:\SQLBackups\Enc_Restore1.mdf',
         MOVE N'LabEncrypted_log' TO N'C:\SQLBackups\Enc_Restore1_log.ldf';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (ไม่มี certificate): ' + ERROR_MESSAGE();
END CATCH
GO
/* Expected: RESTORE fail พร้อมข้อความเรื่อง certificate ที่ใช้เข้ารหัสไม่พบ
   — นี่คือเหตุผลที่ต้อง backup .cer/.pvk ไว้แยกต่างหาก */

-- (b) นำเข้า certificate กลับจากสำเนา (ต้องมี master key ของ master อยู่แล้ว)
CREATE CERTIFICATE BackupLabCert
    FROM FILE = N'C:\SQLBackups\BackupLabCert.cer'
    WITH PRIVATE KEY ( FILE = N'C:\SQLBackups\BackupLabCert.pvk',
                       DECRYPTION BY PASSWORD = N'Pa$$w0rd2025' );
GO

-- (c) RESTORE ครั้งที่สอง → ผ่าน
RESTORE DATABASE [LabEncrypted_Restore2]
FROM DISK = N'C:\SQLBackups\Encrypted.bak'
WITH FILE = 1,
     MOVE N'LabEncrypted'     TO N'C:\SQLBackups\Enc_Restore2.mdf',
     MOVE N'LabEncrypted_log' TO N'C:\SQLBackups\Enc_Restore2_log.ldf',
     RECOVERY;
GO
USE [LabEncrypted_Restore2];
GO
SELECT COUNT(*) AS rows_restored FROM dbo.Secrets;
GO
/* Expected: 1 — encrypted backup กู้ได้สมบูรณ์เมื่อ certificate อยู่ครบ */

/* ---------------------------------------------------------------
   หมายเหตุ production:
   - ใช้ certificate ที่สร้างใน master (SERVER CERTIFICATE) หรือ
     SERVER ASYMMETRIC KEY ผ่าน EKM/HSM (SQL Server 2025 รองรับ Azure Key Vault
     ด้วย managed identity ผ่าน Azure Arc)
   - เก็บ .cer/.pvk ไว้หลายที่ตาม 3-2-1 rule เหมือนไฟล์ .bak
   - encryption ใช้ร่วมกับ compression ได้ (บีบก่อนเข้ารหัสโดย engine จัดการ)
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
IF DB_ID(N'LabEncrypted_Restore1') IS NOT NULL
BEGIN
    ALTER DATABASE [LabEncrypted_Restore1] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabEncrypted_Restore1];
END
GO
ALTER DATABASE [LabEncrypted_Restore2] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabEncrypted_Restore2];
ALTER DATABASE [LabEncrypted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabEncrypted];
IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'BackupLabCert')
    DROP CERTIFICATE BackupLabCert;
GO
-- ลบไฟล์ C:\SQLBackups\Encrypted.bak, BackupLabCert.* และ Enc_Restore* ทีหลัง
GO
