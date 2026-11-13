# Lab 11: จัดการ SQL Server ด้วย PowerShell (บทที่ 11)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab11** (Working with SQL Server Using PowerShell) + [Microsoft Learn — SqlServer module](https://learn.microsoft.com/powershell/module/sqlserver/), [SQL Server PowerShell](https://learn.microsoft.com/sql/powershell/sql-server-powershell?view=sql-server-ver17), [Az.Sql module](https://learn.microsoft.com/powershell/module/az.sql/)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว

## Prerequisites
- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** restore เรียบร้อย
- **PowerShell 7+** และ **SqlServer module** (Module 00):
  ```powershell
  Install-Module -Name SqlServer -Scope CurrentUser -Force
  ```
- รันด้วย login ที่เป็น sysadmin บน instance ทดลอง (Task config ต้องใช้)
- เครื่อง Windows สำหรับ `Get-HotFix` (Task patch report)
- Exercise 4 (optional) ต้องมี **Azure subscription** — มีค่าใช้จ่ายเล็กน้อยหากลืมลบ (อ่านข้อควรระวังใน Exercise)

> **เครื่องมือเขียนสคริปต์**: แนะนำเปิด VS Code + PowerShell extension (Section 2) — F8 เพื่อรันทีละ Task

## Scenario
คุณเป็น DBA ของบริษัทค้าปลีกที่เพิ่งเปิด instance SQL Server 2025 ตัวใหม่ทีมวิศวกรรมขอสามอย่าง: (1) รายงาน "มี database อะไรใน instance บ้าง ใหญ่แค่ไหน มี backup เมื่อไร" ส่งเป็นไฟล์ทุกสัปดาห์ (2) ทดลองลด `max server memory` ลงเพื่อโหลด application ตัวใหม่บนเครื่องเดียวกัน แล้วต้องย้อนได้ (3) ทดสอบว่า backup ของ AdventureWorks2025 กู้คืนได้จริงโดย restore เป็น copy — นอกจากนี้ทีม cloud อยากให้ทดลองสร้าง Azure SQL Database หนึ่งตัวด้วย PowerShell เพื่อจะต่อยอดเป็นสคริปต์ส่งมอบ

## Objectives
1. สำรวจ SQL Server ผ่าน SQLSERVER: drive และ `Get-SqlInstance` แล้วทำรายงาน database เป็นไฟล์
2. เปลี่ยน `max server memory` ผ่าน sp_configure และ SMO แล้วย้อนกลับค่าเดิม
3. Backup + restore AdventureWorks2025 ด้วย `Backup-SqlDatabase` / `Restore-SqlDatabase` (ทดสอบกับ database copy)
4. (Optional) สร้าง Azure SQL logical server + database ด้วย Az module พร้อม managed identity แล้วลบให้สะอาด

---

## Exercise 1: สำรวจ SQLSERVER: drive และรายงาน database

### Step 1 — ตรวจสภาพแวดล้อม

เปิด PowerShell 7 (`pwsh`) แล้วรัน:

```powershell
$PSVersionTable.PSVersion                       # ต้องเป็น 7.x
Get-Module SqlServer -ListAvailable |
    Select-Object Name, Version                 # ต้องมี SqlServer
Import-Module SqlServer
```

> **ต้องรู้ก่อน**: `Import-Module SqlServer` จะสร้าง **SQLSERVER: drive** ให้อัตโนมัติ (PowerShell 7) — ในหลักสูตรเดิมต้องสร้าง PSDrive เองเพราะใช้ SQLPS บน Windows PowerShell 2.0

✅ **สังเกต**: `Get-PSDrive` ต้องแสดง `SQLSERVER` ในรายการ

### Step 2 — เดินโครงสร้างเหมือนไฟร์ซิสเทม

```powershell
Set-Location SQLSERVER:\SQL\localhost\DEFAULT
Get-ChildItem                                   # เทียบ Object Explorer ใน SSMS

Get-ChildItem SQLSERVER:\SQL\localhost\DEFAULT\Databases |
    Select-Object Name, Status, RecoveryModel   # database ทุกตัว
```

**Expected:** โครงใต้ instance เหมือน Object Explorer (Databases, Logins, JobServer ฯลฯ) และรายการ database รวม `AdventureWorks2025`

### Step 3 — รายงาน database เรียงตามขนาด + เก็บเป็นไฟล์

> **ต้องรู้ก่อน**: จาก demo `InspectSqlInstances.ps1` เดิม — เราเขียนใหม่ด้วย `Get-SqlDatabase` (cmdlet ทางการ) แทนการเดิน provider ล้วน ผลข้อมูลเหมือนกัน แต่ filter/format ง่ายกว่า (รายละเอียด: [Section 3 Script 02](../Sections/03_Maintenance_With_PowerShell/Scripts/02_Instance_Database_Info.ps1))

```powershell
$report = Get-SqlDatabase -ServerInstance localhost |
    Select-Object Name, Status, RecoveryModel, CompatibilityLevel,
                  @{N = 'SizeMB'; E = { [math]::Round($_.Size / 1MB, 1) } },
                  LastBackupDate |
    Sort-Object SizeMB -Descending

$report | Format-Table -AutoSize

# เก็บเป็น CSV สำหรับรายงานสัปดาห์
$report | Export-Csv "$env:TEMP\DbInventory_Lab11.csv" -NoTypeInformation -Encoding UTF8
Get-Content "$env:TEMP\DbInventory_Lab11.csv" -TotalCount 5
```

✅ **สังเกต**: `LastBackupDate` เป็น `null`/ว่างบน database ที่ยังไม่เคย backup — สังเกตว่า AdventureWorks2025 มีวันที่หลัง restore เอง

**Expected:** ได้ไฟล์ CSV เปิดใน Excel ได้ มีคอลัมน์ครบตามที่ทีมขอ — นี่คือรายงานสัปดาห์ที่ใช้เวลา 30 วินาทีต่อครั้ง

---

## Exercise 2: เปลี่ยน max server memory แล้วย้อนกลับ

### Step 1 — บันทึกค่าปัจจุบัน

> **ต้องรู้ก่อน**: `max server memory (MB)` คือเพดาน memory ที่ SQL Server buffer pool ใช้ได้ (ค่า default = หน่วยความจำเครื่องทั้งหมด ซึ่งมักเยอะเกินสำหรับเครื่องร่วมงาน) การเปลี่ยนค่าด้วย `sp_configure` มีผลทันทีหลัง `RECONFIGURE` โดยไม่ restart — รายละเอียด: [Section 2](../Sections/02_Configuring_With_PowerShell/README.md)

```powershell
$original = (Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT value_in_use AS Val FROM sys.configurations
            WHERE name = 'max server memory (MB)';").Val
Write-Host "ค่าเดิม: $original MB" -ForegroundColor Green
# จำเลขนี้ไว้ - จะใช้ย้อนกลับ
```

### Step 2 — เปลี่ยนด้วย sp_configure (ผ่าน Invoke-Sqlcmd)

```powershell
# ลดเป็น 4096 MB (เหมาะกับเครื่องที่ต้องแบ่งให้ application)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query 'EXEC sp_configure ''max server memory (MB)'', 4096; RECONFIGURE;'

# ตรวจผล
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations
            WHERE name = 'max server memory (MB)';"
```

✅ **สังเกต**: `value_in_use` เปลี่ยนเป็น 4096 ทันที — และใน SSMS Server Properties > Memory จะแสดงค่าเดียวกัน

### Step 3 — เปลี่ยนด้วย SMO เทียบกัน

```powershell
Import-Module SqlServer
$srv = New-Object Microsoft.SqlServer.Management.Smo.Server 'localhost'

# อ่านค่าผ่าน Configuration object (RunValue = ค่าที่ engine ใช้จริงตอนนี้)
$srv.Configuration.MaxServerMemory | Select-Object ConfigValue, RunValue

# เปลี่ยนเป็น 8192 MB ด้วย SMO
$srv.Configuration.MaxServerMemory.ConfigValue = 8192
$srv.Configuration.Alter()

# ตรวจผลด้วย T-SQL อีกครั้ง
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT value_in_use FROM sys.configurations
            WHERE name = 'max server memory (MB)';"
```

**Expected:** `value_in_use` = 8192 — สองวิธีให้ผลเหมือนกัน (SMO ที่ Alter() เรียก sp_configure + RECONFIGURE ให้เอง) เลือกใช้ตามสไตล์ที่ทีมใช้: T-SQL-first หรือ object-first

### Step 4 — ย้อนกลับค่าเดิม

```powershell
# ใช้ค่าที่บันทึกไว้ใน Step 1
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query 'EXEC sp_configure ''max server memory (MB)'', $(Original); RECONFIGURE;' `
    -Variable "Original=$original"

Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT value_in_use FROM sys.configurations
            WHERE name = 'max server memory (MB)';"
```

**Expected:** กลับเป็นค่าเดิมทุกตัวเลข — ย้ำ pattern: บันทึกก่อนเปลี่ยนเสมอ และใน production ให้เก็บลงไฟล์ log ไม่ใช่แค่ตัวแปร

> **หมายเหตุจาก Lab เดิม** (ChangeServerSettings.ps1): เดิมแล็บทดลองแก้ `LoginMode` และ `UserOptions` ด้วย SMO — `LoginMode` ต้อง restart instance จึงมีผลจึงไม่รวมในแล็บปัจจุบัน (ดู Task 5 ของ [03_Instance_Config_SMO.ps1](../Sections/02_Configuring_With_PowerShell/Scripts/03_Instance_Config_SMO.ps1) สำหรับการตรวจอย่างเดียว)

---

## Exercise 3: Backup + Restore ด้วย PowerShell (ทดสอบกับ database copy)

### Step 1 — เตรียมโฟลเดอร์ backup

```powershell
$BackupDir = 'C:\SQLBackups'
if (-not (Test-Path $BackupDir)) { New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null }
$BackupFile = Join-Path $BackupDir 'AdventureWorks2025_Lab11.bak'
```

> **ต้องรู้ก่อน**: SQL Server service account ต้องเขียนไฟล์ในโฟลเดอร์นี้ได้ โฟลเดอร์ default ของ instance (`SERVERPROPERTY('InstanceDefaultBackupPath')`) มีสิทธิ์ถูกต้องอยู่แล้ว — ถ้าเขียนไม่ได้จะ error ระหว่าง backup

### Step 2 — Full backup

```powershell
Backup-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025 `
    -BackupFile $BackupFile `
    -CompressionOption On `
    -Checksum -Initialize

Get-Item $BackupFile |
    Select-Object FullName, @{N = 'SizeMB'; E = { [math]::Round($_.Length / 1MB, 2) } }
```

✅ **สังเกต**: ขนาดไฟล์เล็กกว่า database จริงมาก (compression ทำงาน) — ตามแล็บเดิมที่ใช้ backup เป็นสื่อกลาง

### Step 3 — ตรวจไฟล์ก่อนใช้

```powershell
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "RESTORE VERIFYONLY FROM DISK = N'$($BackupFile -replace "'", "''")' WITH CHECKSUM;"
```

**Expected:** ไม่มี error, ข้อความ `The backup set on file 1 is valid.` — VERIFYONLY อ่านโครงไฟล์ครบแต่ยังไม่ใช่การ restore จริง (Step 4-6 คือการทดสอบที่แน่นอน)

### Step 4 — อ่านโครงไฟล์และเตรียม RelocateFile (WITH MOVE)

```powershell
$fileList = Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "RESTORE FILELISTONLY FROM DISK = N'$($BackupFile -replace "'", "''")';"
$fileList | Select-Object LogicalName, PhysicalName, Type | Format-Table -AutoSize

$dataDir = (Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS D;").D
$logDir  = (Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS D;").D

$relocate = foreach ($f in $fileList) {
    $ext  = if ($f.Type -eq 'L') { '_LabCopy.ldf' } else { '_LabCopy.mdf' }
    $path = if ($f.Type -eq 'L') { Join-Path $logDir ($f.LogicalName + $ext) }
            else                 { Join-Path $dataDir ($f.LogicalName + $ext) }
    New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($f.LogicalName, $path)
}
$relocate
```

✅ **สังเกต**: ชื่อ logical file ของ AdventureWorks2025.bak มักเป็น `AdventureWorks2025` + `AdventureWorks2025_log` — เรา map ใหม่เป็นไฟล์ชื่อ `_LabCopy` เพื่อไม่ชนไฟล์เดิม

### Step 5 — Restore เป็น database copy

```powershell
Restore-SqlDatabase -ServerInstance localhost `
    -Database AdventureWorks2025_LabCopy `
    -BackupFile $BackupFile `
    -RelocateFile $relocate `
    -ReplaceDatabase
```

**Expected:** ไม่มี error และ `AdventureWorks2025_LabCopy` โผล่ใน Object Explorer — restore ซ้ำได้เพราะ `-ReplaceDatabase`

### Step 6 — ทดสอบว่าข้อมูลใช้ได้จริง

```powershell
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT COUNT(*) AS Orders_InCopy
            FROM AdventureWorks2025_LabCopy.Sales.SalesOrderHeader;

            SELECT TOP (3) name, recovery_model_desc
            FROM AdventureWorks2025_LabCopy.sys.databases
            WHERE name = 'AdventureWorks2025_LabCopy';"
```

**Expected:** จำนวนแถวตรงกับต้นฉบับ (`SELECT COUNT(*) FROM AdventureWorks2025.Sales.SalesOrderHeader`) — **นี่คือการทดสอบ backup ที่แน่นอนที่สุด: restore ได้ + ข้อมูลอ่านได้**

### Step 7 — (Optional) ทดลอง backup แบบอื่น

```powershell
# Differential (สำรองเฉพาะส่วนที่เปลี่ยนหลัง full)
Backup-SqlDatabase -ServerInstance localhost -Database AdventureWorks2025 `
    -BackupFile (Join-Path $BackupDir 'AdventureWorks2025_Diff.bak') `
    -BackupAction Database -Incremental

# หรือใช้ dbatools (ถ้าติดตั้งไว้): Backup-DbaDatabase -SqlInstance localhost `
#     -Database AdventureWorks2025 -Type Full -BackupDirectory $BackupDir
```

---

## Exercise 4 (Optional): สร้าง Azure SQL Database ด้วย Az module

> ⚠️ **ค่าใช้จ่าย**: ต้องมี Azure subscription Database edition Basic เก็บเงินรายชั่วโมง (ต่ำ แต่สะสม) — ทำ Exercise นี้ต้องรัน Clean-up (Step 5) ให้จบทุกครั้ง

### Step 1 — เชื่อมต่อ Azure

```powershell
Install-Module Az -Scope CurrentUser -Force       # ครั้งแรก (หรือ Install-Module Az.Sql, Az.Accounts, Az.Resources)
Connect-AzAccount
Get-AzContext | Select-Object SubscriptionName, Account
```

> **ต้องรู้ก่อน**: รายละเอียด managed identity และโครงสร้าง logical server: [Section 4](../Sections/04_Azure_SQL_PowerShell/README.md) และสคริปต์ [02_New_AzSqlServer_Db.ps1](../Sections/04_Azure_SQL_PowerShell/Scripts/02_New_AzSqlServer_Db.ps1)

### Step 2 — สร้าง resource group + logical server (พร้อม managed identity)

```powershell
$rg       = 'rg-sqladm-lab11'
$location = 'southeastasia'
$server   = "sqladm-$(Get-Random -Maximum 99999)".ToLower()

New-AzResourceGroup -Name $rg -Location $location

$cred = New-Object System.Management.Automation.PSCredential(
    'sqladmin2025', (ConvertTo-SecureString 'Pa$$w0rd2025' -AsPlainText -Force))

$srv = New-AzSqlServer -ResourceGroupName $rg -ServerName $server `
    -Location $location -ServerVersion '12.0' `
    -SqlAdministratorCredentials $cred -AssignIdentity

$srv.Identity.PrincipalId     # managed identity ของ server (ใช้ต่อใน Module 4 บริบท EKM)
```

### Step 3 — เปิด firewall + สร้าง database

```powershell
$myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip
New-AzSqlServerFirewallRule -ResourceGroupName $rg -ServerName $server `
    -FirewallRuleName 'AllowMe' -StartIpAddress $myIp -EndIpAddress $myIp

New-AzSqlDatabase -ResourceGroupName $rg -ServerName $server `
    -DatabaseName 'sqladm11db' -Edition Basic
```

### Step 4 — ทดสอบเชื่อมต่อด้วยเครื่องมือเดิม

```powershell
Invoke-Sqlcmd -ServerInstance "$server.database.windows.net" -Database 'sqladm11db' `
    -Username 'sqladmin2025' -Password 'Pa$$w0rd2025' `
    -Query "SELECT @@SERVERNAME AS Server, DATABASEPROPERTYEX(DB_NAME(), 'Edition') AS Edition;"
```

✅ **สังเกต**: `Invoke-Sqlcmd` ใช้กับ Azure SQL ได้เหมือน localhost — ความต่างอยู่ที่ feature ที่ไม่มี (BACKUP DATABASE ฯลฯ) ไม่ใช่เครื่องมือ

### Step 5 — ลบให้สะอาด (บังคับทำ)

```powershell
Remove-AzResourceGroup -Name $rg -Force
Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue   # ต้องไม่เหลืออะไร
```

---

## 🧹 Clean-up

```powershell
# 1) Database copy จาก Exercise 3 (ถ้ายังไม่ลบ)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate -Database master `
    -Query 'IF DB_ID(N''AdventureWorks2025_LabCopy'') IS NOT NULL
            BEGIN
                ALTER DATABASE [AdventureWorks2025_LabCopy] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [AdventureWorks2025_LabCopy];
            END;'

# 2) ไฟล์รายงานชั่วคราว
Remove-Item "$env:TEMP\DbInventory_Lab11.csv" -ErrorAction SilentlyContinue

# 3) ไฟล์ backup (ตัดสินใจเอง - เก็บไว้ทดสอบ restore ต่อหรือไม่)
# Remove-Item C:\SQLBackups\AdventureWorks2025_Lab11.bak, C:\SQLBackups\AdventureWorks2025_Diff.bak

# 4) ค่า config ที่ทดลองเปลี่ยน - ตรวจว่าย้อนครบ (Exercise 2)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations
            WHERE name = 'max server memory (MB)';"

# 5) ทรัพยากร Azure (Exercise 4 - บังคับถ้าทำแล้ว)
# Remove-AzResourceGroup -Name 'rg-sqladm-lab11' -Force
```

> ยืนยันสุดท้าย: instance ทดลองกลับสู่สภาพเดิม (config = ค่าเดิม, ไม่มี database ค้าง, ไม่มีทรัพยากร Azure)

## Quiz ท้ายแล็บ

1. ทำไมการเดิน SQLSERVER: drive ใน PowerShell 7 จึงไม่ต้องสร้าง PSDrive เองเหมือนหลักสูตรเดิม?
2. `sp_configure` กับ SMO `Configuration.Alter()` ให้ผลเหมือนกันได้อย่างไร และควรใช้วิธีไหนเมื่อไร?
3. เหตุใด Step 3 (VERIFYONLY) ไม่พอ ต้อง restore จริงเป็น copy เพิ่มจึงเรียกว่า "ทดสอบ backup แล้ว"?
4. `-RelocateFile` ทำหน้าที่ตัวไหนใน T-SQL และถ้าไม่ใส่ตอน restore เป็น database ใหม่จะเกิดอะไร?
5. Exercise 4 สร้าง server ด้วย `-AssignIdentity` ได้ managed identity ไปทำอะไร และเกี่ยวกับ SQL Server 2025 on-premises อย่างไร?
