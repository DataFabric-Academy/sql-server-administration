# Section 3 — ตัวเลือกพิเศษ: COPY_ONLY, Compression (ZSTD), Encryption และ Backup to URL

ตัวเลือกใน Section นี้คือ "กลไกเกรด production" ที่ทำให้ backup ของคุณ**ไม่ก่อปัญหาเพิ่ม** (COPY_ONLY ไม่ทำลาย chain), **เล็กลงและเร็วขึ้น** (ZSTD — อัลกอริทึมใหม่ของ SQL Server 2025), **ปลอดภัยขึ้น** (encrypted backup) และ**อยู่ที่ถูกที่ถูกต้อง** (backup to URL — Azure Blob Storage และ S3-compatible storage) ทุกหัวข้อมีโค้ดรันได้จริงพร้อมวิธีตรวจสอบผล

## 3.1 COPY_ONLY — backup เพิ่มโดยไม่ทำลายลำดับ

| ใช้กับ | พฤติกรรมปกติ | กับ `COPY_ONLY` |
|:--------|:--------------|:-----------------|
| Full backup | เป็น **differential base** ใหม่ (diff ถัดไปเทียบกับตัวนี้) | **ไม่**เปลี่ยน differential base — diff ถัดไปยังเทียบกับ full เดิม |
| Log backup | ตัด log และต่อ log chain | **ไม่**ตัด log, **ไม่**กระทบ log chain — สำเนาเพียว ๆ |

```sql
-- สำเนา full ชั่วคราวก่อนเปลี่ยนแปลงใหญ่ — ตาราง backup ประจำไม่กระเพื่อม
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_pre_migration.bak'
WITH COPY_ONLY, CHECKSUM, COMPRESSION, INIT;

-- สำเนา log เพื่อส่งทีม DBA อีกแผนก / เปิดไฟล์ด้วยเครื่องมืออื่น
BACKUP LOG [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_log_for_forensics.trn'
WITH COPY_ONLY, CHECKSUM;
```

กรณีใช้จริงของ COPY_ONLY:

- ก่อน migration หรือ upgrade ใหญ่ — เก็บจุดย้อนกลับโดยไม่รบกวนตาราง backup ประจำ
- ทำสำเนา DB ไปเครื่อง dev/test โดยไม่กระทบ diff base ของ production
- COPY_ONLY log backup เมื่อต้องเปิด DB สำเนาที่ต้องต่อ chain เดิมต่อ (log ไม่ถูกตัด)
- บน AG secondary (ก่อน SQL Server 2025) — เดิมทำ backup ได้เฉพาะ COPY_ONLY; ตั้งแต่ 2025 full/diff ปกติก็ทำได้แล้ว

ข้อควรจำ: `DIFFERENTIAL` กับ `COPY_ONLY` ใช้พร้อมกันไม่ได้ — COPY_ONLY จะถูกเมิน และกลายเป็น diff ปกติ ([Copy-only backups](https://learn.microsoft.com/sql/relational-databases/backup-restore/copy-only-backups-sql-server?view=sql-server-ver17))

ตรวจแถว copy-only ใน msdb ด้วยคอลัมน์ `is_copy_only = 1` — เครื่องมือ audit ควรกรองตัวเหล่านี้ออกจากการวิเคราะห์ chain

เดโมที่พิสูจน์ด้วย `DifferentialBaseLSN`: [Scripts/01_CopyOnly_Backup.sql](Scripts/01_CopyOnly_Backup.sql)

## 3.2 Compression — MS_XPRESS vs ZSTD (SQL Server 2025)

SQL Server 2025 เพิ่ม **ZSTD** — Microsoft ระบุชัดในเอกสารว่า "faster and more effective than the previous MS_XPRESS algorithm" ใช้ได้สองระดับ:

```sql
-- ระดับ backup เดียว (ระบุอัลกอริทึม + ระดับความบีบ)
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_zstd.bak'
WITH FORMAT, INIT,
     COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM),   -- LOW (default) / MEDIUM / HIGH
     CHECKSUM;
```

ระดับ instance — server configuration `backup compression algorithm`:

```sql
-- ดูค่าปัจจุบัน (default = MS_XPRESS)
SELECT name, value, value_in_use FROM sys.configurations
WHERE name = N'backup compression algorithm';

-- ตั้งให้ WITH COMPRESSION ทุกคำสั่งใช้ ZSTD (ค่า 3 = ZSTD, SQL Server 2025+)
EXEC sys.sp_configure N'backup compression algorithm', 3;
RECONFIGURE;
-- กลับ MS_XPRESS: ตั้งค่า 0
```

ค่าของ `backup compression algorithm` ที่ใช้ได้: **0 = MS_XPRESS** (default), **3 = ZSTD** (SQL Server 2025) — ค่าอื่นเกี่ยวกับ hardware accelerator (QAT ของ SQL Server 2022) นอกขอบเขตคอร์สนี้

วิธีวัดผลจริง — ratio และเวลา (ทุกครั้งที่บีบสำเร็จ ตัวเลขอยู่ใน msdb แล้ว):

```sql
SELECT type, name, backup_start_date, backup_finish_date,
       DATEDIFF(SECOND, backup_start_date, backup_finish_date) AS duration_sec,
       CAST(backup_size / 1048576.0 AS DECIMAL(10,2)) AS raw_MB,
       CAST(compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS compressed_MB,
       CAST(backup_size / compressed_backup_size AS DECIMAL(6,2)) AS ratio
FROM msdb.dbo.backupset
WHERE database_name = N'AdventureWorks2025'
ORDER BY backup_finish_date DESC;
```

ปัจจัยที่กำหนด ratio จริง (จากเอกสาร Backup Compression):

- **ชนิดข้อมูล** — character data บีบได้ดีกว่า; random data บีบแทบไม่ได้
- **ความสม่ำเสมอของข้อมูลในหน้า** — แถวที่คอลัมน์ซ้ำกันมาก = บีบได้มาก
- **การเข้ารหัส** — ข้อมูลที่เข้ารหัสแล้ว (Always Encrypted) บีบเพิ่มได้น้อยมาก
- **Database compression** — ถ้าตารางใช้ compression อยู่แล้ว backup compression แทบไม่ช่วย

ข้อจำกัดที่ต้องจำ:

- compressed กับ uncompressed **รวมกันใน media set เดียวไม่ได้**
- version เก่าอ่าน backup บีบอัดรุ่นใหม่ไม่ได้
- **TDE + COMPRESSION**: ตั้งแต่ SQL Server 2019 CU5 engine จัดการ `MAXTRANSFERSIZE` ให้เอง — ไม่ต้องทำ trick ข้าม version เดิมอีก
- `LEVEL = LOW/MEDIUM/HIGH` มีผลกับ MS_XPRESS และ ZSTD — ยิ่ง HIGH ยิ่งบีบได้แต่ใช้ CPU มากขึ้น วัดบน workload จริงก่อนตัดสินใจ

เดโมเปรียบเทียบ MS_XPRESS vs ZSTD แบบวัดตัวเลขจริง: [Scripts/02_Compression_ZSTD.sql](Scripts/02_Compression_ZSTD.sql)

## 3.3 Backup Encryption — ล็อกไฟล์สำรองด้วย certificate

ไฟล์ .bak ที่ไม่เข้ารหัสคือ "ฐานข้อมูลสำเนาเดินได้" — ใครได้ไฟล์เปิดอ่านทุกอย่างได้ Encryption ทำให้ไฟล์อ่านไม่ได้โดยไม่มี certificate:

ขั้นเตรียม (ครั้งเดียวต่อ instance) — **Database Master Key ของ master + certificate**:

```sql
USE [master];
GO
-- Database Master Key ของฐานข้อมูล master (เก็บรหัสผ่านไว้ให้ดี — หายจะไม่กู้)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO
-- Certificate สำหรับ backup encryption
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = N'BackupCert')
    CREATE CERTIFICATE BackupCert
    WITH SUBJECT = N'Backup encryption certificate', EXPIRY_DATE = '2030-12-31';
GO
```

สั่ง backup ด้วยอัลกอริทึม (AES_128/AES_192/AES_256/TRIPLE_DES_3KEY) — อย่าเลือก TRIPLE_DES_3KEY ในงานใหม่:

```sql
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_encrypted.bak'
WITH FORMAT, INIT,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = BackupCert),
     CHECKSUM, COMPRESSION, STATS = 5;
```

**ข้อกำหนดสำคัญของ restore**:

- ปลายทางต้องมี Database Master Key ของ master **และ** certificate ตัวเดิม (ถ้าไม่มี → RESTORE fail กลางทาง)
- Backup certificate พร้อม private key เก็บเป็นไฟล์ทันทีหลังสร้าง — certificate หาย = backup หมดมูลค่า

```sql
BACKUP CERTIFICATE BackupCert
TO FILE = N'C:\SQLBackups\BackupCert.cer'
WITH PRIVATE KEY (FILE = N'C:\SQLBackups\BackupCert.pvk',
                  ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025');
```

Runbook "restore encrypted backup บนเครื่องใหม่" (ทดสอบจริงใน [Module 7](../../../Module_07_Restoring_Databases/Labs/README.md)):

1. สร้าง Database Master Key ของ master บนปลายทาง (ถ้ายังไม่มี)
2. นำเข้า certificate: `CREATE CERTIFICATE ... FROM FILE = '<.cer>' WITH PRIVATE KEY (FILE = '<.pvk>', DECRYPTION BY PASSWORD = ...)`
3. `RESTORE DATABASE ... FROM DISK` ตามปกติ — engine ถอดรหัสให้เอง
4. ตรวจผล: `msdb.dbo.backupset.is_encrypted = 1` ยืนยันฝั่ง backup; restore สำเร็จ + query ได้ ยืนยันฝั่ง restore

เดโมครบวงจร (สร้างคีย์ → backup เข้ารหัส → จำลอง restore ฝั่งไม่มี cert → นำเข้า cert → restore ผ่าน): [Scripts/03_Encrypted_Backup.sql](Scripts/03_Encrypted_Backup.sql)

หมายเหตุ production: ใช้ certificate ใน master (`SERVER CERTIFICATE`) หรือ `SERVER ASYMMETRIC KEY` ผ่าน EKM/HSM — SQL Server 2025 รองรับ EKM กับ Azure Key Vault ด้วย managed identity ผ่าน Azure Arc

## 3.4 Backup to URL — Azure Blob Storage และ S3-compatible

### Azure Blob Storage (SAS credential)

```sql
USE [master];
GO
-- credential ชื่อ = URL ของ container พอดี
CREATE CREDENTIAL [https://mystorageaccount.blob.core.windows.net/sqlbackups]
    WITH IDENTITY = N'SHARED ACCESS SIGNATURE',
         SECRET = N'sv=2024-05-04&sr=c&si=policy1&sig=...';   -- SAS (ไม่มี ? นำหน้า)
GO

BACKUP DATABASE [AdventureWorks2025]
TO URL = N'https://mystorageaccount.blob.core.windows.net/sqlbackups/AW2025.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5;
```

### S3-compatible object storage (SQL Server 2022+)

```sql
USE [master];
GO
-- server-level credential — ชื่อต้องเป็น s3://endpoint:port/bucket ตรงกับ backup
CREATE CREDENTIAL [s3://10.10.10.10:8787/sqlbackups]
    WITH IDENTITY = N'S3 Access Key',
         SECRET = N'<AccessKeyID>:<SecretKeyID>';   -- ห้ามมี ':' ใน key ทั้งคู่
GO

BACKUP DATABASE [AdventureWorks2025]
TO URL = N's3://10.10.10.10:8787/sqlbackups/AW2025.bak'
WITH FORMAT, COMPRESSION, CHECKSUM, STATS = 10;
```

กติกาที่ใช้ตัดสินใจได้ทันที:

| หัวข้อ | Azure Blob | S3-compatible |
|:--------|:-----------|:---------------|
| Protocol | HTTPS เท่านั้น | HTTPS เท่านั้น (cert ติดตั้งฝั่ง OS ของ SQL Server) |
| Credential | SAS (block blob) / access key (page blob, legacy) | `S3 Access Key` — สร้าง server-level credential ก่อนเสมอ |
| MAXTRANSFERSIZE | default 1 MB, สูงสุด 4 MB (block blob แนะนำ 4 MB) | default 10 MB, ช่วง 5–20 MB |
| Stripe | สูงสุด 64 URLs (~12.8 TB) | สูงสุด 64 URLs |
| Append (NOINIT) | ไม่รองรับ — เขียนทับต้อง `FORMAT` | ไม่รองรับ — เขียนทับต้อง `FORMAT` |
| RETAINDAYS/EXPIREDATE | ไม่รองรับ | ไม่รองรับ |
| Edition | ทุก edition (Linux: block blob เท่านั้น) | Express ไม่รองรับ |

รายละเอียดและ troubleshooting: ([S3 backup to URL](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url-s3-compatible-object-storage?view=sql-server-ver17))

### Immutable storage (SQL Server 2025)

ตั้ง immutability policy **ที่ระดับ container** ใน Azure แล้ว backup ตามปกติ — engine เขียนแบบ one-pass เพราะ blob แก้ไขไม่ได้; ถ้ามีไฟล์ชื่อเดิมแล้ว `WITH FORMAT` จะ fail แทนการเขียนทับ — นี่คือตัวช่วยกัน ransomware ที่เริ่มจากลบ backup ก่อนเสมอ

```sql
-- (บน container ที่ตั้ง immutability policy แล้ว)
BACKUP DATABASE [AdventureWorks2025]
TO URL = N'https://mystorageaccount.blob.core.windows.net/immutable-backups/AW2025.bak'
WITH COMPRESSION, CHECKSUM;
```

### Managed identity (SQL Server 2025, ผ่าน Azure Arc)

SQL Server enabled by Azure Arc ใช้ managed identity สำหรับ backup to URL ได้ — ไม่ต้องเก็บ SAS token ใน sys.credentials เลย ดูขั้นตอนที่ [Back up to URL with managed identity](https://learn.microsoft.com/sql/sql-server/azure-arc/backup-to-url?view=sql-server-ver17)

เดโม template + ตรวจ credential: [Scripts/04_Backup_To_URL.sql](Scripts/04_Backup_To_URL.sql)

## 3.5 เลือกใช้รวมกันอย่างไร (สรุปตัดสินใจ)

| ความต้องการ | ตัวเลือกแนะนำ |
|:-------------|:---------------|
| ลดพื้นที่/เวลา backup แต่ไม่มี hardware พิเศษ | `WITH COMPRESSION` — ZSTD บน SQL Server 2025 |
| Backup ที่ใครขโมยไปเปิดไม่ได้ | `ENCRYPTION (AES_256, SERVER CERTIFICATE = ...)` + เก็บ cert แยกปลอดภัย |
| สำเนาเพิ่มไม่กระทบตาราง backup ประจำ | `WITH COPY_ONLY` |
| นอกไซต์ + กัน ransomware | Backup to URL → immutable container (2025) |
| สภาพแวดล้อมหลาย vendor/ประหยัดค่า cloud | S3-compatible (MinIO บนหน่วยงาน) + credential `S3 Access Key` |
| ลดข้อความรกใน error log | trace flag 3226 + Agent job จัดการการแจ้งเอง |

### 🚀 SQL Server 2025 & Modern Notes
- **ZSTD + LEVEL** — `WITH COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM/HIGH)`; config `backup compression algorithm` = 3 ให้เป็น default ทั้ง instance ([Backup Compression](https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-compression-sql-server?view=sql-server-ver17#zstd-compression-algorithm-introduced-in-sql-server-2025))
- **Immutable blob storage** — รองรับเฉพาะ container-level; backup เขียน one-pass ([Azure immutable storage support](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url?view=sql-server-ver17#azure-immutable-storage-support))
- **Managed identity backup/restore to URL (2025)** — ผ่าน Azure Arc ไม่ต้องจัดการ secret ([Managed identity](https://learn.microsoft.com/sql/sql-server/azure-arc/managed-identity?view=sql-server-ver17))
- S3 backup มาตั้งแต่ **SQL Server 2022** — ใช้ร่วมกับ ZSTD ใหม่ได้ (`COMPRESSION` จำเป็นถ้าจะปรับ MAXTRANSFERSIZE บน S3)
- Trace flag 3226 ยังเป็นตัวจัดการ error log ที่ใช้ร่วมกับ job backup ทุกรูปแบบ

> อ้างอิง: [BACKUP (Transact-SQL)](https://learn.microsoft.com/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver17), [Create an Encrypted Backup](https://learn.microsoft.com/sql/relational-databases/backup-restore/create-an-encrypted-backup?view=sql-server-ver17), [SQL Server backup to URL for Azure Blob Storage](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url?view=sql-server-ver17), [Back up and restore with S3-compatible object storage](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-and-restore-with-s3-compatible-object-storage?view=sql-server-ver17)
