-- ============================================================================
-- Section 04 — Demo 01: TDE ครบวงจร (DMK → Cert → DEK → เปิดใช้ → ตรวจ → ย้อน)
-- ฐานข้อมูล: master + AdventureWorks2025
-- ปรับจาก Lab04 Exercise 3 เดิม (20764D) — idempotent + cleanup ในตัว
-- ระวัง: เปิด TDE จะเข้ารหัส tempdb บน instance ด้วย รันบน VM ทดลองเท่านั้น
-- ============================================================================
USE master;
GO

-- ---------- ขั้น 1: DMK ใน master ----------
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'master'
               AND is_master_key_encrypted_by_server = 1)
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025';
GO

-- ---------- ขั้น 2: certificate สำหรับ TDE ----------
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'TDE_Cert')
    DROP CERTIFICATE TDE_Cert;
GO
CREATE CERTIFICATE TDE_Cert WITH SUBJECT = 'Module 04 TDE demo certificate';
GO

-- (เตือนจาก SQL Server: หลังสร้าง DEK จะแจ้งให้ backup cert — ทำตามขั้น 3)

-- ---------- ขั้น 3: BACKUP CERTIFICATE (ทำจริงถ้าต้องการเก็บไฟล์) ----------
-- แก้ path เป็นโฟลเดอร์ที่ SQL Server service เขียนได้:
-- BACKUP CERTIFICATE TDE_Cert
-- TO FILE = 'C:\SetupFiles\TDE_Cert.cer'
-- WITH PRIVATE KEY (
--     FILE = 'C:\SetupFiles\TDE_Cert_pk.pvk',
--     ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025'
-- );
-- GO

-- ---------- ขั้น 4: DEK ใน user database ----------
USE AdventureWorks2025;
GO
IF EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
           WHERE database_id = DB_ID('AdventureWorks2025'))
BEGIN
    -- ถ้า DB นี้มี DEK อยู่แล้ว ให้หยุดและตรวจสถานะเอง
    PRINT N'AdventureWorks2025 มี DEK อยู่แล้ว — ตรวจสถานะด้านล่าง';
END
ELSE
BEGIN
    CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TDE_Cert;
END
GO

-- ---------- ขั้น 5: เปิด encryption ----------
ALTER DATABASE AdventureWorks2025 SET ENCRYPTION ON;
GO

-- ---------- ขั้น 6: ตรวจสถานะ (encryption_state = 3 เมื่อเสร็จ) ----------
-- รันซ้ำหลายรอบจนกว่า percent_complete = 100
SELECT d.name, d.is_encrypted,
       ek.encryption_state,      -- 3 = ENCRYPTED
       ek.percent_complete,
       ek.key_algorithm, ek.key_length,
       ek.encryption_scan_state
FROM sys.dm_database_encryption_keys ek
JOIN sys.databases d ON d.database_id = ek.database_id;
GO
-- สังเกต: tempdb จะเข้ารหัสอัตโนมัติด้วย (encryption_state ของ tempdb ตามมา)
-- ข้อยกเว้นเครื่อง dev ที่ TDE เพิ่งเปิด: รอ scan จนเสร็จก่อนถอดท้ายสคริปต์

-- ---------- ขั้น 7: (ทางเลือก) suspend/resume encryption scan ----------
-- มีประโยชน์เมื่อ scan ใหญ่บนระบบจริง ทำได้ตั้งแต่ SQL Server 2019:
-- ALTER DATABASE AdventureWorks2025 SET ENCRYPTION SUSPEND;
-- ALTER DATABASE AdventureWorks2025 SET ENCRYPTION RESUME;

-- ---------- ขั้น 8: ตรวจ cert ที่ไม่เคย backup (error 33091 ที่เตือนไว้) ----------
SELECT c.name AS certificate_name, c.pvt_key_last_backup_date,
       DB_NAME(dek.database_id) AS encrypted_database
FROM sys.certificates c
JOIN sys.dm_database_encryption_keys dek
     ON c.thumbprint = dek.encryptor_thumbprint;
GO
-- pvt_key_last_backup_date = NULL → cert ยังไม่ถูก backup — ควร backup ทันทีในระบบจริง

-- ---------- ขั้น 9: เทียบ backup compression กับ TDE ----------
-- ตั้งแต่ SQL Server 2019 CU5 ใช้ WITH COMPRESSION กับ TDE ได้โดยตรง
-- (ระบบจะเพิ่ม MAXTRANSFERSIZE เป็น 128K อัตโนมัติ) — 2025 ยังมี ALGORITHM = ZSTD:
-- BACKUP DATABASE AdventureWorks2025
-- TO DISK = 'C:\SetupFiles\AW2025_tde.bak'
-- WITH COMPRESSION, CHECKSUM;
-- GO

-- ---------- Cleanup: ปิด TDE คืนสภาพ (ต้องทำตามลำดับ) ----------
USE master;
GO
ALTER DATABASE AdventureWorks2025 SET ENCRYPTION OFF;
GO
-- รอถอดรหัสเสร็จ (encryption_state กลับเป็น 1) แล้วค่อยลบ DEK:
USE AdventureWorks2025;
GO
DROP DATABASE ENCRYPTION KEY;
GO

USE master;
GO
DROP CERTIFICATE TDE_Cert;
-- DMK ใน master ไม่ลบ (instance อาจใช้งาน object อื่นต่อ)
-- ถ้า DMK ถูกสร้างขึ้นใหม่โดยสคริปต์นี้และไม่มีใครใช้ ให้ลบเอง:
-- DROP MASTER KEY;   -- ระวัง: จะ fail ถ้ามี cert/key อื่นอยู่ใต้ DMK
GO
-- จบสคริปต์
