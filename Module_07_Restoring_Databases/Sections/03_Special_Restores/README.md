# Section 3 — การกู้แบบพิเศษ: Filegroup (Piecemeal), Encrypted Backup, Page Restore และ System Databases

ปัญหาไม่ได้เกิดแบบ "ทั้งฐานข้อมูลหายหมด" เสมอไป — บางครั้งเสียเฉพาะ disk ที่เก็บ filegroup เดียว, บางครั้งเสียเฉพาะ **page หนึ่งหน้า** จากล้านหน้า (หน้าที่มีข้อมูลของสาขาที่กำลังรออนุมัติ), บางครั้งไฟล์ backup ถูกเข้ารหัสไว้และ certificate อยู่ที่ server เดิม และบางครั้งที่พังคือ **master** ที่ทำให้ instance ทั้งเครื่องขึ้นไม่มา — Section นี้เตรียมคุณรับมือทั้งสี่แบบพร้อมโค้ดที่รันได้จริง

## 3.1 File/Filegroup Restore และ Piecemeal Restore

เมื่อฐานข้อมูลแบ่ง filegroup (เช่น warehouse ที่แยก data ปัจจุบันกับ archive read-only) คุณเลือกกู้ **ส่วนที่จำเป็นก่อน** แล้วปล่อยส่วนนอกคอยทีหลัง — ผู้ใช้กลับมาทำงานได้เร็วขึ้นหลายชั่วโมง

ลำดับมาตรฐาน (offline piecemeal):

```sql
-- 1) เริ่มด้วย PRIMARY + filegroup ที่ระบุ แบบ PARTIAL
RESTORE DATABASE [AWDataWarehouse]
    FILEGROUP = N'Current'
FROM DISK = N'C:\SQLBackups\AWDW.bak'
WITH FILE = 1, PARTIAL, NORECOVERY;

-- 2) ต่อ log ตามลำดับจนครบช่วงเวลา
RESTORE LOG [AWDataWarehouse]
FROM DISK = N'C:\SQLBackups\AWDW_Log.trn'
WITH NORECOVERY;

-- 3) เปิดใช้งานส่วนที่กู้แล้ว (filegroup ที่เหลือยัง OFFLINE)
RESTORE DATABASE [AWDataWarehouse] WITH RECOVERY;
-- ตอนนี้: PRIMARY + Current ออนไลน์, Archive ยัง offline (query จะ error)

-- 4) กู้ filegroup ที่เหลือภายหลัง — read-only FG กู้ตรง ๆ ได้เลย
RESTORE DATABASE [AWDataWarehouse]
    FILEGROUP = N'Archive'
FROM DISK = N'C:\SQLBackups\AWDW.bak'
WITH FILE = 1, RECOVERY;
```

ข้อจำกัด/จุดที่ต้องเช็ค:

- กู้แบบ **online** (DB ออนไลน์ไปด้วยระหว่างกู้ filegroup) ต้อง Enterprise/Developer edition; offline piecemeal ใช้ได้ทุก edition
- filegroup ที่ออฟไลน์จนกว่าจะกู้ — ตารางที่อยู่บนนั้น query ไม่ได้ (error "filegroup is offline")
- **read-only filegroup ที่ไม่เปลี่ยนแปลงตั้งแต่ backup** กู้ด้วย RECOVERY ทันทีได้ ไม่ต้องต่อ log
- ขั้นแรกของ piecemeal ต้องครอบ **PRIMARY filegroup** เสมอ (เพิ่ม filegroup อื่นเป็นรายการที่ 2, 3, …)
- ตรวจ filegroup ไหนออนไลน์/ออฟไลน์: `sys.database_files` (คอลัมน์ `state_desc`)

```sql
-- สำรวจก่อนออกแบบ: filegroup ไหนใหญ่/read-only อย่างไร
SELECT name, type_desc, state_desc, is_read_only, size * 8 / 1024 AS size_MB
FROM [AWDataWarehouse].sys.database_files;
```

เดโมจริงครบ 3 filegroup แบบทำตามได้ทีละขั้น: [Scripts/01_FileRestore_Piecemeal.sql](Scripts/01_FileRestore_Piecemeal.sql)

## 3.2 Restore จาก Encrypted Backup

หลักการเดียว: **มี certificate คู่ตัว = กู้ได้, ไม่มี = RESTORE fail** (รายละเอียดการสร้างใน [Module 6 Section 3](../../../Module_06_Backing_Up_Databases/Sections/03_Special_Options/README.md)):

1. ปลายทางต้องมี **Database Master Key ของ master** ก่อน (`CREATE MASTER KEY` — ถ้ายังไม่มี)
2. นำเข้า certificate ตัวเดิมจากสำเนา `.cer` + `.pvk` (หรือ backup/restore ผ่าน `BACKUP CERTIFICATE`)
3. `RESTORE DATABASE ... FROM DISK` ปกติ — engine ถอดรหัสให้เอง

```sql
USE [master];
GO
-- หาก master ยังไม่มี master key:
CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Pa$$w0rd2025';
GO
-- นำเข้า certificate จากสำเนาที่เก็บไว้
CREATE CERTIFICATE BackupCert
    FROM FILE = N'C:\SQLBackups\BackupCert.cer'
    WITH PRIVATE KEY (FILE = N'C:\SQLBackups\BackupCert.pvk',
                      DECRYPTION BY PASSWORD = N'Pa$$w0rd2025');
GO
-- แล้วกู้ตามปกติ
RESTORE DATABASE [AW2025_Restored]
FROM DISK = N'C:\SQLBackups\AW_encrypted.bak'
WITH FILE = 1, REPLACE;
```

จุดที่คนพลาดบ่อย:

- ลืม master key (สร้าง cert ก่อนไม่ได้ — ขั้น 1 ต้องมาก่อนขั้น 2)
- ใช้ cert ตัวอื่นที่ "สร้างใหม่ชื่อเดียวกัน" (ไม่ผ่าน — ต้องเป็นตัวเดิมจริง ๆ ที่มี private key ตรงกัน)
- ไม่เคยทดสอบ restore จนถึงวันเกิดเหตุ — drill ต้องรวม encrypted backup ทุกรอบ
- certificate ใกล้หมดอายุ (`EXPIRY_DATE`) — เกินวันหมดอายุ backup ใหม่ไม่ได้ วางแผน renew ล่วงหน้า

เดโมที่พลาดโดยจงใจเพื่อเห็น error จริง (fail → นำเข้า cert → ผ่าน): [Scripts/02_RestoreEncryptedBackup.sql](Scripts/02_RestoreEncryptedBackup.sql) และแล็บ Exercise 2

## 3.3 Page Restore — กู้เฉพาะหน้าที่เสีย

เมื่อ page ใดพัง (error 823/824 จาก hardware/disk) SQL Server บันทึกลง **`msdb.dbo.suspect_pages`** — ถ้ามี log chain ครบและฐานข้อมูลเป็น FULL/BULK_LOGGED คุณกู้เฉพาะหน้านั้นได้ **โดยไม่ต้อง offline ทั้งฐานข้อมูล** (online page restore — Enterprise/Developer; offline page restore ใช้ได้ทุก edition)

เงื่อนไขทั้งหมด:

- Recovery model **FULL/BULK_LOGGED** และ log chain ไม่ขาด
- มี full/file backup ที่ครอบ page นั้น + log ทุกอันตั้งแต่ backup นั้นจนถึงปัจจุบัน
- จำนวน page ที่เสียต้องเล็กมาก (ไม่ใช่วิธีกู้ทั้ง DB); ห้ามเจอ minimal-logged operation ใน log ช่วงนั้น (BULK_LOGGED)
- ขั้นตอนจบด้วย **log backup ตัวใหม่หลังแก้เสร็จ** (เพราะ tail ถูกใช้ตอน restore page)

ค่า `event_type` ใน `suspect_pages` ที่ควรจำ:

| event_type | ความหมาย |
|:-----------|:---------|
| 1 | 823 error (disk/hardware) หรือ 824 ที่ไม่ใช่ checksum/torn page |
| 2 | Bad checksum |
| 3 | Torn page |
| 4 | Restored (page ถูกกู้หลังเคย suspect) |
| 5 | Repaired ด้วย DBCC |
| 7 | Deallocated ด้วย DBCC |

```sql
-- หา page เสียจาก suspect_pages
SELECT DB_NAME(database_id) AS db_name, file_id, page_id, event_type, error_count
FROM msdb.dbo.suspect_pages
WHERE database_id = DB_ID(N'AW2025');

-- กู้เฉพาะ page (รูปแบบ fileId:pageId)
RESTORE DATABASE [AW2025]
    PAGE = N'1:300'
FROM DISK = N'C:\SQLBackups\AW2025.bak'
WITH FILE = 1, NORECOVERY;

-- ต่อ log ทุกอันจนปัจจุบัน แล้วจบด้วย tail
RESTORE LOG [AW2025]
FROM DISK = N'C:\SQLBackups\AW2025_Log.trn'
WITH RECOVERY;

-- จบด้วย log backup ใหม่ (เปิด chain ต่อได้ปกติ)
BACKUP LOG [AW2025] TO DISK = N'C:\SQLBackups\AW2025_Log.trn' WITH CHECKSUM;
```

จัดการ `suspect_pages`: แถวถูกอัปเดตอัตโนมัติเมื่อ DBCC CHECKDB/restore แก้ไขสำเร็จ หรือลบเองได้ (sysadmin/db_owner ของ msdb) หลังจบการซ่อม: `DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(...)`

เดโมที่ "ทำลาย page จริง ๆ แล้วกู้กลับ" ครบทั้งวงจร (จำลองเสียด้วย PowerShell บน sandbox DB ที่สร้างเพื่อทดลอง): [Scripts/03_PageRestore.sql](Scripts/03_PageRestore.sql) และ [Labs Exercise 3](../../Labs/README.md)

> ใน production ควบคู่กัน: `DBCC CHECKDB WITH NO_INFOMSGS` ตามรอบ + alert บน error 823/824 + ทดสอบ restore — เครื่องมือทางการที่ห้ามพลาดคือ [DBCC CHECKDB](https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql?view=sql-server-ver17)

## 3.4 System Databases — master, model, msdb, tempdb/resource

| ฐานข้อมูล | Backup ได้ไหม | กู้อย่างไร | เมื่อพังแล้วผลคือ |
|:-----------|:--------------|:-----------|:------------------|
| **master** | ได้ (full เท่านั้น) | **single-user mode** (`-m`) แล้ว restore; ถ้าไฟล์พังหนัก → rebuild | instance ไม่ขึ้นเลย (logins, linked servers, endpoint หาย) |
| **model** | ได้ | restore ปกติ (แต่ต้องใช้ `-m` เพราะ connections ใช้ model ขณะสร้าง DB) | DB ใหม่ทุกตัวจะสร้างผิด template |
| **msdb** | ได้ | restore ปกติ (หยุด SQL Agent ก่อน) | job, schedule, alert, backup history หาย |
| **tempdb** | **ไม่ได้** | ถูกสร้างใหม่ทุกครั้งที่ service ขึ้น | ไม่มีผลถาวร |
| **resource** | **ไม่ได้** | มากับไฟล์ executable ของ SQL Server | แก้ด้วยการ repair/reinstall |

### สิ่งที่อยู่ในแต่ละ system database (เหตุผลว่าทำไมต้อง backup)

| ฐานข้อมูล | สิ่งที่หายถ้าไม่มี backup |
|:-----------|:---------------------------|
| master | logins, linked servers, endpoints, server configuration, ข้อมูล file locations ของทุก DB |
| model | template ของ DB ใหม่ทั้งหมด (ตั้งค่า recovery model, file sizes, objects มาตรฐานที่ทีมฝังไว้) |
| msdb | Agent jobs/schedules/operators, backup & restore history, maintenance plans, Database Mail profiles |

### กู้ master — ขั้นตอนจริง

master พังทำให้ SQL Server **ขึ้นไม่มา** — เตรียม backup ของ master ทุกครั้งที่เปลี่ยน server-level configuration (สร้าง login, endpoint, linked server):

```sql
BACKUP DATABASE [master] TO DISK = N'C:\SQLBackups\master.bak' WITH CHECKSUM, COMPRESSION;
```

เมื่อต้องกู้ (instance ยังขึ้นได้):

1. หยุด SQL Server service
2. เริ่มใหม่ด้วย **single-user mode**: `net start MSSQLSERVER /m"SQLCMD"` (หรือ startup parameter `-m`)
3. เชื่อมด้วย `sqlcmd -S .` แล้ว `RESTORE DATABASE master FROM DISK = N'C:\SQLBackups\master.bak' WITH REPLACE;`
4. restart ปกติ แล้วเริ่ม SQL Agent ใหม่

เมื่อ master เสียจน restore ไม่ได้ → **rebuild system databases** (เครื่องมือติดตั้ง):

```text
Setup.exe /QUIET /ACTION=RebuildDatabase /INSTANCENAME=MSSQLSERVER
/SQLSYSADMINACCOUNTS=<admin> /SAPWD=Pa$$w0rd2025
```

จากนั้น restore master.bak กลับเข้าไป (ทำให้ logins/endpoints กลับมา) — ตัวเลขที่ rebuild ไม่เคยคืน: server configuration ที่ตั้งเอง, สิทธิ์ที่ grant เอง — บันทึกสคริปต์ server config ไว้เสมอ (ทำเป็น runbook)

เดโมอ่าน/backup system DBs + คำสั่งกู้ทั้งหมดในรูปคอมเมนต์ runbook: [Scripts/04_SystemDatabases.sql](Scripts/04_SystemDatabases.sql)

## 3.5 เทียบเครื่องมือกู้เฉพาะจุด — เลือกให้ถูกโจทย์

| โจทย์ | เครื่องมือ | เงื่อนไขหลัก |
|:------|:-----------|:--------------|
| disk เสียเฉพาะ volume ของ filegroup หนึ่ง | File/filegroup restore (+ piecemeal) | มี backup ครบทุก FG + log chain |
| อยากเปิดใช้ส่วนงานจริงก่อนจบการกู้ | Piecemeal restore (`WITH PARTIAL`) | PRIMARY มาก่อนเสมอ; Enterprise สำหรับ online |
| page เสียหลัก ๆ หน้าเดียว | Page restore | FULL/BULK_LOGGED + log ครบ + backup ครอบ page |
| backup เป็นของลับที่ต้องกู้ | Encrypted restore | master key + certificate ตัวเดิม |
| instance ทั้งเครื่องขึ้นไม่มา | Restore/rebuild master | ต้องมี master.bak + วิธีเข้า single-user mode |
| job/ประวัติ backup หาย | Restore msdb | หยุด SQL Agent ก่อน, จบด้วย restart |
| DB ใหม่เริ่มต้นผิด template | Restore model | single-user mode เมื่อ connections ขัด |

### 🚀 SQL Server 2025 & Modern Notes
- **Restore from URL/S3** — กู้จาก cloud ได้ทุกคำสั่งใน Section นี้ (`FROM URL`) รวมถึง restore จาก managed identity (2025, Azure Arc)
- **ZSTD (2025)** — ไฟล์ที่บีบด้วย ZSTD decompress เร็ว ทำให้ page/filegroup restore เฉพาะจุดสั้นลงอีกชั้น
- **ADR บน tempdb (2025)** — ทำให้สถานการณ์ "tempdb เกี่ยวข้องกับ recovery" เร็วขึ้น
- **Log shipping TLS 1.3 (2025)** — standby ที่กู้ด้วย STANDBY file ผ่าน log shipping ต้องอ่าน breaking changes ก่อน upgrade

> อ้างอิง: [Piecemeal Restores](https://learn.microsoft.com/sql/relational-databases/backup-restore/piecemeal-restores-sql-server?view=sql-server-ver17), [Restore Pages](https://learn.microsoft.com/sql/relational-databases/backup-restore/restore-pages-sql-server?view=sql-server-ver17), [Back Up and Restore of System Databases](https://learn.microsoft.com/sql/relational-databases/backup-restore/back-up-and-restore-of-system-databases-sql-server?view=sql-server-ver17), [Rebuild System Databases](https://learn.microsoft.com/sql/database-engine/install-windows/rebuild-system-databases?view=sql-server-ver17)
