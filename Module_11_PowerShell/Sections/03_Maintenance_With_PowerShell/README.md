# Section 3 — งานบำรุงรักษาประจำวันด้วย PowerShell (Users, Backup/Restore, สำรวจระบบ)

Section นี้เอา PowerShell ลงสนามจริงกับงานบำรุงรักษาที่ DBA ทำทุกสัปดาห์: สร้าง login/user ตาม ticket ความขอความช่วยเหลือ ทำ backup/restore ตามตาราง สำรวจสถานะ instance เพื่อสร้างรายงาน และดูประวัติ Windows update เวลาเกิดเหตุหลัง patch ทุกงานถูกเขียนเป็นสคริปต์ได้หมด — ซึ่งหมายความว่า "รายงานประจำวันที่เคยใช้เวลาคลิกครึ่งชั่วโมง" จะกลายเป็นไฟล์ .ps1 หนึ่งไฟล์ที่รันใน 10 วินาทีและต่อยอดเป็น scheduled task ได้ทันที

รูปแบบการเรียนเหมือน Section ก่อน: อ่านหัวข้อ → รันสคริปต์ใน [`Scripts/`](Scripts/) ทีละ Task → เทียบกับวิธี SSMS/T-SQL ที่คุณคุ้นเคย โดยทุกสคริปต์รันได้บน default instance `localhost` กับ database `AdventureWorks2025`

> **สิทธิ์ที่ใช้**: สร้าง login ต้องเป็น sysadmin หรือมี `ALTER ANY LOGIN`; สร้าง user ใน database ต้องเป็น db_owner หรือมี `ALTER ANY USER`; backup ต้องเป็น db_owner/sysadmin (หรือ role `db_backupoperator`); restore ต้อง sysadmin หรือ db_creator

## 1. จัดการ logins และ users ด้วย PowerShell

วิธีที่พลิกผันได้ดีที่สุดคือรัน T-SQL มาตรฐานผ่าน `Invoke-Sqlcmd` (รู้จาก Module 1–3 อยู่แล้ว) แล้วใช้ PowerShell ทำส่วน "ทำซ้ำ/ตรวจ/รายงาน" รันสคริปต์ [`Scripts/01_Manage_Logins_Users.ps1`](Scripts/01_Manage_Logins_Users.ps1):

```powershell
# สร้าง login แบบ SQL authentication (idempotent - เช็กก่อนเสมอ)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database master `
    -Query "IF SUSER_ID(N'SqlReader2025') IS NULL
            BEGIN
                CREATE LOGIN SqlReader2025 WITH PASSWORD = N'Pa\$\$w0rd2025',
                    CHECK_POLICY = ON, DEFAULT_DATABASE = AdventureWorks2025;
            END;"

# สร้าง user ใน database แล้วเพิ่มเข้า role ที่มีอยู่
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database AdventureWorks2025 `
    -Query "IF DATABASE_PRINCIPAL_ID(N'SqlReader2025') IS NULL
                CREATE USER SqlReader2025 FOR LOGIN SqlReader2025;
            ALTER ROLE db_datareader ADD MEMBER SqlReader2025;"
```

จากนั้นตรวจผลด้วย cmdlet ของ SqlServer module ที่มีให้ใช้:

```powershell
# login ระดับ server
Get-SqlLogin -ServerInstance localhost | Where-Object Name -eq 'SqlReader2025'

# ผู้ใช้และ role ใน database (ผ่าน SMO)
$db = Get-SqlDatabase -ServerInstance localhost -Name AdventureWorks2025
$db.Users | Where-Object Name -eq 'SqlReader2025' | Select-Object Name, LoginType
```

และทำความสะอาดเมื่อจบ:

```powershell
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database AdventureWorks2025 `
    -Query "IF DATABASE_PRINCIPAL_ID(N'SqlReader2025') IS NOT NULL DROP USER SqlReader2025;"
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database master `
    -Query "IF SUSER_ID(N'SqlReader2025') IS NOT NULL DROP LOGIN SqlReader2025;"
```

คำสั่งที่เกี่ยวข้องใน SqlServer module (มีเก็บไว้ใช้เมื่อต้องการ object จริง):

| Cmdlet | ใช้ทำอะไร |
|:-------|:----------|
| `Add-SqlLogin` | สร้าง login จาก PowerShell (รองรับ Windows/SQL auth/Certificate) |
| `Get-SqlLogin` | รายงาน login ทั้งหมด/ตามเงื่อนไข |
| `Remove-SqlLogin` | ลบ login |
| `Invoke-Sqlcmd` + T-SQL | สร้าง/แก้/ลบด้วย T-SQL มาตรฐาน (แนะนำสำหรับ user/role) |

> ถ้าองค์กรใช้ **Microsoft Entra ID** การสร้าง login เป็นรูปแบบ `CREATE LOGIN [user@tenant.com] FROM EXTERNAL PROVIDER;` (SQL Server 2022+) — ในแล็บของเราใช้ SQL authentication เพราะไม่มี dependency กับ domain ให้ปรับเป็น Windows local account (`CREATE LOGIN [MACHINENAME\LocalUser] FROM WINDOWS;`) ได้เช่นกัน

> อ้างอิง: [CREATE LOGIN](https://learn.microsoft.com/sql/t-sql/statements/create-login-transact-sql?view=sql-server-ver17), [Add-SqlLogin](https://learn.microsoft.com/powershell/module/sqlserver/add-sqllogin)

## 2. สำรวจ instance และ databases — Get-SqlInstance / Get-SqlDatabase

`Get-SqlDatabase` คืน SMO Database object ทุกตัวใน instance — ใช้ทำรายงานได้ทันที รันสคริปต์ [`Scripts/02_Instance_Database_Info.ps1`](Scripts/02_Instance_Database_Info.ps1) (ปรับปรุงจาก demo `InspectSqlInstances.ps1` เดิมให้ใช้ cmdlet ทางการแทนการเดิน provider):

```powershell
# รายงาน database ทุกตัว เรียงตามขนาด
Get-SqlDatabase -ServerInstance localhost |
    Select-Object Name, Status, RecoveryModel, CompatibilityLevel,
                  @{N = 'SizeMB'; E = { [math]::Round($_.Size / 1MB, 1) } },
                  LastBackupDate |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# database เฉพาะตัว
Get-SqlDatabase -ServerInstance localhost -Name AdventureWorks2025 |
    Select-Object Name, Size, LastBackupDate, LastGoodCheckDbTime
```

รายงาน "ใช้ได้จริง" สามตัวที่ควรมีติดเครื่อง:

1. **DB ที่ไม่มี backup ใน 24 ชม.** — `Where-Object { $_.LastBackupDate -lt (Get-Date).AddHours(-24) }` (เว้น tempdb)
2. **DB ที่อยู่ SIMPLE ทั้งที่ควร FULL** — `Where-Object RecoveryModel -eq 'Simple'`
3. **DB offline/restore pending** — `Where-Object Status -notmatch 'Normal'`

✅ **สังเกต**: property `LastBackupDate`/`LastGoodCheckDbTime` เป็นค่าที่ SMO เดินไปอ่านจาก msdb เบื้องหลัง — คำสั่งบรรทัดเดียวนี้เทียบเท่ากับ query `msdb.dbo.backupset` หลายบรรทัด

> อ้างอิง: [Get-SqlDatabase](https://learn.microsoft.com/powershell/module/sqlserver/get-sqldatabase)

## 3. Backup และ Restore ด้วย Backup-SqlDatabase / Restore-SqlDatabase

`Backup-SqlDatabase` และ `Restore-SqlDatabase` เป็น cmdlet ทางการของ SqlServer module ที่ห่อ BACKUP DATABASE/RESTORE DATABASE ทั้งก้อน รันสคริปต์ [`Scripts/03_Backup_Restore.ps1`](Scripts/03_Backup_Restore.ps1) ทีละ Task:

```powershell
# Full backup แบบมี checksum + เขียนทับไฟล์เดิม
Backup-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025 `
    -BackupFile C:\SQLBackups\AdventureWorks2025_Full.bak `
    -CompressionOption On `
    -Checksum -Initialize

# Differential backup (-Incremental)
Backup-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025 `
    -BackupFile C:\SQLBackups\AdventureWorks2025_Diff.bak `
    -BackupAction Database -Incremental

# Log backup (recovery model FULL เท่านั้น)
Backup-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025 `
    -BackupFile C:\SQLBackups\AdventureWorks2025_Log.trn `
    -BackupAction Log
```

ตรวจความสมบูรณ์ของไฟล์ backup ก่อนพึ่งพา:

```powershell
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "RESTORE VERIFYONLY FROM DISK = N'C:\SQLBackups\AdventureWorks2025_Full.bak'
            WITH CHECKSUM;"
```

จากนั้น Task สำคัญของ Section นี้ — **restore เป็น database copy ใหม่** (`AdventureWorks2025_Copy`) ซึ่งเป็นรูปแบบที่ใช้ทดสอบ backup จริง: อ่าน logical file names ด้วย `RESTORE FILELISTONLY` แล้ว map เป็น `RelocateFile` objects:

```powershell
# 1) อ่านโครงไฟล์จาก backup
$fileList = Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "RESTORE FILELISTONLY FROM DISK = N'C:\SQLBackups\AdventureWorks2025_Full.bak';"

# 2) หาโฟลเดอร์ default ของ instance
$dataDir = (Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DataDir;").DataDir

# 3) สร้าง RelocateFile ทีละไฟล์
$relocate = foreach ($f in $fileList) {
    $ext = if ($f.Type -eq 'L') { '_Copy.ldf' } else { '_Copy.mdf' }
    New-Object Microsoft.SqlServer.Management.Smo.RelocateFile(
        $f.LogicalName, (Join-Path $dataDir ($f.LogicalName + $ext)))
}

# 4) Restore เป็น database ใหม่
Restore-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025_Copy `
    -BackupFile C:\SQLBackups\AdventureWorks2025_Full.bak `
    -RelocateFile $relocate -ReplaceDatabase
```

✅ **สังเกต**:

- `-RelocateFile` ทำหน้าที่ `WITH MOVE` ใน T-SQL — จำเป็นเมื่อ restore เป็นชื่อ database ใหม่ ไม่ให้ทับไฟล์เดิม
- `-ReplaceDatabase` ทำหน้าที่ `WITH REPLACE` — เขียนทับ database ปลายทางถ้ามีอยู่แล้ว (ทำซ้ำแล็บได้)
- จบ Task ให้รายงานจำนวนแถวเทียบต้นฉบับกับ copy แล้วลบ copy ทิ้ง (Clean-up ในสคริปต์)

> **SQL Server 2025 เสริม**: backup compression algorithm เลือก ZSTD ได้ผ่าน T-SQL `BACKUP ... WITH COMPRESSION, ALGORITHM = ZSTD` (หรือตั้ง server config `backup compression algorithm`) — จาก PowerShell ใช้ `Invoke-Sqlcmd` รัน BACKUP ตรง ๆ ในกรณีต้องการ algorithm ใหม่ รายละเอียดใน Module 5

> อ้างอิง: [Backup-SqlDatabase](https://learn.microsoft.com/powershell/module/sqlserver/backup-sqldatabase), [Restore-SqlDatabase](https://learn.microsoft.com/powershell/module/sqlserver/restore-sqldatabase)

## 4. ตรวจประวัติ Windows Update — Get-HotFix

เวลา "server ช้าผิดปกติ" หลังมีทีม IT อัปเดตเครื่อง หนึ่งในคำถามแรกคือ "มี hotfix ติดตั้งเมื่อไร" บน Windows PowerShell มี cmdlet built-in:

```powershell
# 10 hotfix ล่าสุด เรียงจากวันติดตั้ง
Get-HotFix |
    Sort-Object InstalledOn -Descending |
    Select-Object -First 10 HotFixID, Description, InstalledOn |
    Format-Table -AutoSize

# เช็ก hotfix เฉพาะตัว
Get-HotFix -Id KB5044284 -ErrorAction SilentlyContinue
```

`Get-HotFix` ทำงานผ่าน WMI (`Win32_QuickFixEngineering`) เฉพาะ Windows รันระยะไกลได้ด้วย `Get-HotFix -ComputerName SRV01` (ผ่าน WinRM) — จึงเขียน "รายงาน patch ทุกเครื่องในฟาร์ม" ได้จากเครื่องเดียว บน **Linux** (SQL Server on Linux/container) ให้ใช้ package manager แทน: `apt list --installed`, `rpm -qa --last` หรือ `Get-Content /var/log/apt/history.log` ผ่าน SSH

เชื่อมโยงกับงาน DBA: วันที่ Windows update ต้องไม่ขัดกับวันที่ติดตั้ง SQL Server CU — เทียบกับ `SELECT @@VERSION` (เลข build) และรายการ build ตามเวอร์ชันที่ Microsoft เผยแพร่

> อ้างอิง: [Get-HotFix](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-hotfix)

## 5. สถานการณ์ troubleshoot สั้น ๆ — "DB ช้า เช็กอะไรก่อน 10 นาทีแรก"

รันสคริปต์ [`Scripts/05_Troubleshoot_Scenario.ps1`](Scripts/05_Troubleshoot_Scenario.ps1) — โจทย์: ผู้ใช้แจ้ง "AdventureWorks2025 ช้า" เราเก็บภาพรวมด้วย PowerShell หนึ่งไฟล์ ทีละชุด:

| ลำดับ | เช็กอะไร | เครื่องมือ |
|:-------|:----------|:-----------|
| 1 | สถานะ database (อยู่ RESTORING/RECOVERY_PENDING หรือเปล่า) | `Get-SqlDatabase` |
| 2 | ใครกำลังรันอะไร ใครรอใคร | `Invoke-Sqlcmd` + `sys.dm_exec_requests` |
| 3 | สถานะ wait สะสมตอนนี้ | `sys.dm_os_wait_stats` (TOP 10) |
| 4 | I/O latency ต่อ file | `sys.dm_io_virtual_file_stats` |
| 5 | backup ล่าสุด / log โตเร็ว | `msdb.dbo.backupset` |
| 6 | SQL Server error log ล่าสุด | `Get-SqlErrorLog` |

ผลลัพธ์เป็นรายงาน text ในหน้าจอ (และเก็บลงไฟล์ log ได้) — จุดประสงค์คือสร้าง "ความเคยชินแบบ scripted": ทุกครั้งที่เกิดเหตุ ให้รันสคริปต์ตัวเดิมเพื่อได้ข้อมูลชุดเดียวกันเสมอ ซึ่งเป็นรากฐานของ baseline (Module 13) และการให้หลักฐานเวลาต้องยืนยันกับทีมอื่น

```powershell
# ตัวอย่างชุดที่ 2 จากสคริปต์ - จับ active requests
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database AdventureWorks2025 `
    -Query "SELECT r.session_id, r.status, r.wait_type, r.wait_time,
                   r.blocking_session_id, t.text
            FROM sys.dm_exec_requests AS r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
            WHERE r.session_id > 50;" |
    Format-Table -AutoSize -Wrap
```

## 6. รายงานระดับไฟล์ข้อมูลและ VLF — งานบำรุงที่ลืมกันบ่อย

นอกจากระดับ database ควรรายงานระดับ **file** ด้วย เพราะทั้ง disk capacity และ transaction log fragmentation มองเห็นที่ระดับนี้เท่านั้น โครงรายงานที่รวมในสคริปต์ troubleshoot (ชุด 4) ต่อด้วย VLF:

```powershell
# ขนาดจริง/การใช้จริง/เพดาน autogrow ต่อไฟล์ ของ database เป้าหมาย
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT f.name AS FileName, f.type_desc,
                   f.size * 8 / 1024 AS SizeMB,
                   f.growth,
                   CASE WHEN f.is_percent_growth = 1 THEN '%' ELSE 'MB' END AS GrowthUnit,
                   f.max_size * 8 / 1024 AS MaxSizeMB,
                   mf.type_desc AS FileType
            FROM sys.database_files AS f
            JOIN sys.master_files AS mf ON mf.database_id = DB_ID()
                                       AND mf.file_id = f.file_id;"
```

และ **VLF (Virtual Log File)** — จำนวนชิ้นย่อยภายใน log ที่ถูกสร้างเมื่อ log เติบโตแบบ autogrow เล็ก ๆ บ่อย ๆ; VLF เป็นพันทำให้ recovery/restore และ log backup ช้า (เจาะลึกเรื่อง recovery ใน Module 5):

```powershell
# sys.dm_db_log_info (SQL Server 2016 SP2+) นับ VLF รวมไว้ได้ในบรรทัดเดียว
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT d.name AS DbName,
                   COUNT(lf.database_id) AS VlfCount
            FROM sys.databases AS d
            CROSS APPLY sys.dm_db_log_info(d.database_id) AS lf
            WHERE d.database_id > 4
            GROUP BY d.name
            ORDER BY VlfCount DESC;"
```

**Expected:** database ที่จัดการ log ถูกต้องมี VLF ระดับสิบถึงร้อยล้วน ๆ; ตัวเลขหลักพันบ่งชี้ว่า log เคยโต autogrow เล็ก ๆ สะสมมานาน — ทางแก้คือขยาย log ล่วงหน้าเป็นก้อนใหญ่ครั้งเดียวในช่วง maintenance (ไม่ใช่ SHRINKFILE วนซ้ำซึ่งทำให้กลับมาโตซ้ำอีก) รายละเอียดเชิงกลไกใน Module 5

✅ **สังเกต**: สองรายงานนี้เป็นส่วนที่ SSMS ไม่มีหน้าจอโชว์ตรง ๆ — เขียนเป็น .ps1 ครั้งเดียวใช้ได้ทุก instance

> อ้างอิง: [sys.dm_db_log_info](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-log-info-transact-sql?view=sql-server-ver17), [sys.master_files](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-master-files-transact-sql?view=sql-server-ver17)

## 7. สรุป: รายงานบำรุงรักษาชุดมาตรฐานของโมดูลนี้

รวมทุกอย่างเป็น "รายงานเช้าวันจันทร์" ที่รันหนึ่งไฟล์:

| ลำดับ | รายงาน | แหล่งข้อมูล | สคริปต์/Task |
|:-------|:---------|:--------------|:--------------|
| 1 | DB inventory + ขนาด | `Get-SqlDatabase` | 02 Instance_Database_Info Task 1 |
| 2 | DB ไม่มี backup 24 ชม. | SMO `LastBackupDate` | 02 Task 2 |
| 3 | login ที่เป็น SQL auth + วันสร้าง | `Get-SqlLogin` | 01 Manage_Logins Task 5 |
| 4 | file sizing + VLF count | `sys.master_files`, `sys.dm_db_log_info` | Section 6 ข้างบน |
| 5 | Windows patch ล่าสุด | `Get-HotFix` | 04 Get_HotFix Task 1 |
| 6 | SQL Server build vs CU ล่าสุด | `@@VERSION` | 04 Task 2 |

เมื่อชุดนี้เสถียรแล้ว ปลายทางคือเอาไปตั้ง scheduled task / Agent job ทุกสัปดาห์ (แนวคิดเดียวกับ Multiserver Jobs ใน Module 8) — PowerShell ทำให้ "มาตรฐานเดิมทุกเครื่อง" เป็นเรื่องที่ทำได้จริง

### 🚀 SQL Server 2025 & Modern Notes
- **SqlServer module ใช้กับทุกรุ่นที่ support อยู่** — 2019/2022/2025/Azure SQL; `Backup-SqlDatabase`/`Restore-SqlDatabase` มีทั้งหมด อย่าใช้ SQLPS เก่าตามสคริปต์ตามอินเทอร์เน็ต ([SqlServer module](https://learn.microsoft.com/powershell/module/sqlserver/))
- **ZSTD backup compression (2025)** — ผ่าน T-SQL `BACKUP ... WITH COMPRESSION, ALGORITHM = ZSTD` หรือ server config `backup compression algorithm = 1`; `-CompressionOption On` ของ cmdlet ยังใช้ algorithm ตาม server config ([What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17))
- **dbatools Backup-DbaDatabase** — ตัวเลือกชุมชนที่จัดรูปแบบชื่อไฟล์/retention/หลาย DB ในบรรทัดเดียว เหมาะกับ farm ใหญ่ ([dbatools.io](https://dbatools.io))
- **เวลา patch จริง**: SQL Server 2025 CU ล่าสุดควรตรวจผ่าน `SELECT @@VERSION` เทียบ [รายการ build](https://learn.microsoft.com/sql/releases/sql-server-2025?view=sql-server-ver17) แล้วจับคู่กับ `Get-HotFix` ของ OS ในรายงานเดียว
