/* =============================================================================
   03_RestoreMetadata.sql
   Module 06 - Section 2: อ่าน metadata ของไฟล์ backup ด้วย
   RESTORE HEADERONLY / FILELISTONLY / LABELONLY (ปรับจาก VerifyingBackups.sql เดิม)
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

IF DB_ID(N'LabMetadata') IS NOT NULL
BEGIN
    ALTER DATABASE [LabMetadata] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [LabMetadata];
END
GO
CREATE DATABASE [LabMetadata];
ALTER DATABASE [LabMetadata] SET RECOVERY FULL;
GO

USE [LabMetadata];
GO
CREATE TABLE dbo.T (id INT IDENTITY, note NVARCHAR(50));
INSERT INTO dbo.T (note) VALUES (N'แถวแรก');
GO
USE master;
GO

-- หลาย backup set ในไฟล์เดียว
BACKUP DATABASE [LabMetadata] TO DISK = N'C:\SQLBackups\Meta.bak'
WITH FORMAT, INIT, NAME = N'meta full', CHECKSUM, COMPRESSION;
GO
INSERT INTO [LabMetadata].dbo.T (note) VALUES (N'แถวที่สอง');
GO
BACKUP DATABASE [LabMetadata] TO DISK = N'C:\SQLBackups\Meta.bak'
WITH DIFFERENTIAL, NAME = N'meta diff', CHECKSUM;
GO
BACKUP LOG [LabMetadata] TO DISK = N'C:\SQLBackups\Meta.bak'
WITH NAME = N'meta log', CHECKSUM;
GO

/* ---------------------------------------------------------------
   1) RESTORE HEADERONLY — หนึ่งแถวต่อ backup set
   --------------------------------------------------------------- */
RESTORE HEADERONLY FROM DISK = N'C:\SQLBackups\Meta.bak';
GO
/* คอลัมน์ที่ใช้ตัดสินใจ:
   Position            → ใช้ใน RESTORE ... WITH FILE = n
   BackupType          → 1 = Full, 2 = Log, 5 = Differential
   FirstLSN / LastLSN  → ลำดับของ log chain (restore ต้องต่อถูกขาด)
   DifferentialBaseLSN → LSN ที่ diff นี้เทียบกับ full ตัวที่เป็นฐาน
   DatabaseName / BackupName / BackupFinishDate → ระบุตัวระบุตัวตนของก้อน */

/* ---------------------------------------------------------------
   2) RESTORE FILELISTONLY — หนึ่งแถวต่อไฟล์ data/log ใน backup
      ใช้สร้าง MOVE ตอน restore ไปที่อื่น
   --------------------------------------------------------------- */
RESTORE FILELISTONLY FROM DISK = N'C:\SQLBackups\Meta.bak' WITH FILE = 1;
GO
/* คอลัมน์สำคัญ:
   LogicalName   → อ้างอิงใน MOVE 'LogicalName' TO 'path ใหม่'
   PhysicalName  → path เดิมของเครื่องที่ backup (ต้องเปลี่ยนตอน restore ที่อื่น)
   Type          → D = data, L = log
   Size / MaxSize → วางแผนพื้นที่ปลายทาง */

/* ---------------------------------------------------------------
   3) RESTORE LABELONLY — header ของสื่อทั้งก้อน
   --------------------------------------------------------------- */
RESTORE LABELONLY FROM DISK = N'C:\SQLBackups\Meta.bak';
GO
/* Expected: MediaName, FamilyCount, องค์ประกอบ media set */

/* ---------------------------------------------------------------
   4) ทดสอบการตัดสินใจจาก metadata จริง:
      กู้ diff (FILE=2) บน full (FILE=1) — ใช้ค่า Position จาก HEADERONLY
   --------------------------------------------------------------- */
RESTORE DATABASE [LabMetadata_Copy]
FROM DISK = N'C:\SQLBackups\Meta.bak'
WITH FILE = 1, NORECOVERY,
     MOVE N'LabMetadata'     TO N'C:\SQLBackups\LabMetadata_Copy.mdf',
     MOVE N'LabMetadata_log' TO N'C:\SQLBackups\LabMetadata_Copy_log.ldf';
RESTORE DATABASE [LabMetadata_Copy]
FROM DISK = N'C:\SQLBackups\Meta.bak'
WITH FILE = 2, RECOVERY;
GO
USE [LabMetadata_Copy];
GO
SELECT COUNT(*) AS rows_after_full_plus_diff FROM dbo.T;
GO
/* Expected: 2 แถว (แถวที่สองอยู่ใน diff) — อ่านตำแหน่งจาก metadata แล้วกู้ถูกอัน */

/* ---------------------------------------------------------------
   Cleanup
   --------------------------------------------------------------- */
USE master;
GO
ALTER DATABASE [LabMetadata_Copy] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMetadata_Copy];
ALTER DATABASE [LabMetadata] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [LabMetadata];
GO
-- ลบไฟล์ C:\SQLBackups\Meta.bak และ LabMetadata_Copy* ทีหลัง
GO
