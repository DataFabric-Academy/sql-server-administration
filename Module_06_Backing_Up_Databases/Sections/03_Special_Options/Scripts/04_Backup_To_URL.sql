/* =============================================================================
   04_Backup_To_URL.sql
   Module 06 - Section 3: Backup to URL — Azure Blob Storage (SAS) และ
   S3-compatible storage (SQL Server 2022+) + immutable storage note (2025)
   รันได้เฉพาะส่วน disk demo โดยอัตโนมัติ — ส่วน URL ต้องมี storage จริง
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) DB ทดลองเล็ก
   --------------------------------------------------------------- */
IF DB_ID(N'LabURL') IS NOT NULL
BEGIN
    ALTER DATABASE [LabURL] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabURL];
END
GO
CREATE DATABASE [LabURL];
GO
BACKUP DATABASE [LabURL]
TO DISK = N'C:\SQLBackups\LabURL_local.bak'
WITH FORMAT, INIT, CHECKSUM, COMPRESSION, NAME = N'local reference';
GO

/* ---------------------------------------------------------------
   2) Azure Blob Storage — ทำบน storage account ของคุณ
      ขั้นตอน: สร้าง storage account + container ใน Azure Portal →
      สร้าง SAS token (service level, container, read/write/create/list) →
      สร้าง credential ชื่อตรงกับ URL ของ container →  backup
   --------------------------------------------------------------- */
/* แทนค่าตัวหนังสือสีเทาด้วยของจริงแล้วรัน:

CREATE CREDENTIAL [https://mystorageaccount.blob.core.windows.net/sqlbackups]
    WITH IDENTITY = N'SHARED ACCESS SIGNATURE',
         SECRET = N'sv=2024-05-04&sr=c&si=sqlbackuppolicy&sig=<ของจริง ไม่มี ? นำหน้า>';
GO

BACKUP DATABASE [LabURL]
TO URL = N'https://mystorageaccount.blob.core.windows.net/sqlbackups/LabURL.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5;
GO

-- ตรวจและ restore ย้อนกลับ:
RESTORE HEADERONLY
FROM URL = N'https://mystorageaccount.blob.core.windows.net/sqlbackups/LabURL.bak';
GO

RESTORE DATABASE [LabURL_Restored]
FROM URL = N'https://mystorageaccount.blob.core.windows.net/sqlbackups/LabURL.bak'
WITH MOVE N'LabURL'     TO N'C:\SQLBackups\LabURL_Restored.mdf',
     MOVE N'LabURL_log' TO N'C:\SQLBackups\LabURL_Restored_log.ldf',
     RECOVERY;
GO

-- ลบ credential หลังจบ
-- DROP CREDENTIAL [https://mystorageaccount.blob.core.windows.net/sqlbackups];
*/

/* ---------------------------------------------------------------
   3) S3-compatible object storage (SQL Server 2022+)
      ขั้นตอน: สร้าง bucket ใน MinIO/NetApp/Dell/หรือ AWS S3 →
      ติดตั้ง certificate HTTPS ที่ endpoint ให้ SQL Server เชื่อถือ →
      สร้าง server-level credential ที่ชื่อ = s3://endpoint:port/bucket → backup
   --------------------------------------------------------------- */
/* แทนค่าด้วย endpoint ของคุณแล้วรัน:

USE master;
GO
CREATE CREDENTIAL [s3://10.10.10.10:8787/sqlbackups]
    WITH IDENTITY = N'S3 Access Key',
         SECRET = N'<AccessKeyID>:<SecretKeyID>';
GO

BACKUP DATABASE [LabURL]
TO URL = N's3://10.10.10.10:8787/sqlbackups/LabURL.bak'
WITH FORMAT, COMPRESSION, CHECKSUM, STATS = 10;
GO

-- RESTORE DATABASE [LabURL_Restored]
-- FROM URL = N's3://10.10.10.10:8787/sqlbackups/LabURL.bak'
-- WITH MOVE N'LabURL' TO N'C:\SQLBackups\LabURL_Restored.mdf',
--      MOVE N'LabURL_log' TO N'C:\SQLBackups\LabURL_Restored_log.ldf',
--      REPLACE, STATS = 10;
*/

/* ---------------------------------------------------------------
   4) กติกาของ URL backup ที่ใช้ตัดสินใจได้เลย
   --------------------------------------------------------------- */
SELECT N'ปลายทาง URL ต้องเป็น HTTPS (s3:// นับเป็น https ภายใน)' AS rule;
SELECT N'Azure: SAS ใช้กับ block blob, access key ใช้กับ page blob (legacy)' AS rule;
SELECT N'S3: MAXTRANSFERSIZE 5-20 MB (default 10 MB); stripe สูงสุด 64 URLs' AS rule;
SELECT N'URL backup ไม่รองรับ INIT/NOINIT ปกติ — เขียนทับต้อง WITH FORMAT' AS rule;
SELECT N'RETAINDAYS/EXPIREDATE ใช้กับ URL backup ไม่ได้' AS rule;

/* ---------------------------------------------------------------
   5) SQL Server 2025 — immutable blob storage
      (ทำบน container ที่ตั้ง immutability policy แล้ว)
      - backup เขียนแบบ one-pass (ไม่มีการ pre-allocate เขียนทับ)
      - WITH FORMAT ทับไฟล์เดิม = fail (blob เขียนทับไม่ได้)
      - managed identity (ผ่าน Azure Arc) แทน SAS token ได้
   --------------------------------------------------------------- */
/* BACKUP DATABASE [LabURL]
   TO URL = N'https://mystorageaccount.blob.core.windows.net/immutable-backups/LabURL.bak'
   WITH COMPRESSION, CHECKSUM;
   -- ลบไฟล์ย้อนกลับไม่ได้จนกว่า policy หมดอายุ — กัน ransomware ลบ backup
*/

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabURL] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabURL];
GO
-- ลบไฟล์ C:\SQLBackups\LabURL* ทีหลัง
GO
