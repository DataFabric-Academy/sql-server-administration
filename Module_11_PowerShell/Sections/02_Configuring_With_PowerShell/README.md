# Section 2 — ตั้งค่า SQL Server ด้วย PowerShell (Instance & Database Configuration)

การตั้งค่าผ่านหน้าจอ SSMS (Server Properties / Database Properties) ใช้งานสะดวก แต่มีสองข้อจำกัดเมื่อทำงานจริง: **ไม่เป็นเอกสาร** (คลิกไปแล้วรู้ได้อย่างไรว่าตอนนี้ค่า config เป็นอะไร แก้เมื่อไร ใครแก้) และ**ทำเกินหนึ่งเครื่องไม่ได้** Section นี้สอนการอ่านและเปลี่ยนการตั้งค่าระดับ instance และ database ด้วย PowerShell สามช่องทาง: cmdlet ของ `SqlServer` module (`Get-SqlInstance`), SMO objects (`$srv.Configuration`, `$db.DatabaseOptions`), และ T-SQL ผ่าน `Invoke-Sqlcmd` (`sp_configure`) — พร้อมกันนี้จะตั้งค่าเครื่องมือเขียนสคริปต์ (**VS Code + PowerShell extension**) แทน ISE ที่ deprecated และแนะนำ **dbatools** — โมดูลชุมชนที่กลายเป็นมาตรฐานจริงในงาน SQL Server automation

> **ความปลอดภัยก่อนทุกอย่าง**: สคริปต์ใน Section นี้แก้ค่า configuration ระดับ instance ทุกอย่างเขียนแบบ **บันทึกค่าเดิม → เปลี่ยน → ตรวจผล → ย้อนกลับ** เสมอ บน production ควรทำเทียบเท่า: เก็บค่าเดิมลงไฟล์/CMDB ก่อนเปลี่ยนและ document เหตุผลของการเปลี่ยน

> **สิทธิ์ที่ใช้**: การแก้ instance configuration ต้องเป็น sysadmin (หรือ `ALTER SETTINGS` permission) การแก้ database options ต้องมีสิทธิ์ `ALTER DATABASE` (โดยปกติ db_owner ขึ้นไป) ให้รันด้วย login admin ของ instance ทดลอง

## 1. อ่านค่าการตั้งค่า — Get-SqlInstance และ SMO Server object

`Get-SqlInstance` เป็น cmdlet ทางการของ SqlServer module สำหรับ "ดึง instance จากเครื่องเป้าหมาย" — จริง ๆ มันคืน SMO `Server` object มาให้ทั้งก้อน รันสคริปต์ [`Scripts/01_View_Instance_Info.ps1`](Scripts/01_View_Instance_Info.ps1) ทีละ Task:

```powershell
Import-Module SqlServer

# ดึง instance แล้วเลือก property สำคัญ
Get-SqlInstance -ServerInstance 'localhost' |
    Select-Object Name, Version, Edition,
                  ProductLevel,          # RTM / CUxx / SPxx
                  Collation,
                  IsIntegratedSecurityOnly,
                  Processors, PhysicalMemory |
    Format-List
```

✅ **สังเกต**: `Get-SqlInstance -ServerInstance localhost` รองรับหลาย server พร้อมกัน (`-ServerInstance 'srv1','srv2'` หรือ pipe จากไฟล์) — นี่คือจุดเริ่มของการ inventory ทุก instance ในองค์กรด้วยสคริปต์เดียว

เทียบเท่ากับคำสั่ง T-SQL ที่คุณคุ้นเคย:

| ข้อมูล | T-SQL | PowerShell |
|:-------|:------|:-----------|
| เวอร์ชัน/edition | `SELECT @@VERSION` / `SERVERPROPERTY(...)` | `Get-SqlInstance` properties |
| ค่า config ทุกตัว | `SELECT * FROM sys.configurations` | `$srv.Configuration.Properties` |
| Smart Admin (Managed Backup to Azure) | `msdb.dbo.smart_admin_*` | `Get-SqlSmartAdmin` |

สำหรับ **`Get-SqlSmartAdmin`** — cmdlet นี้อ่านค่าของ "Smart Admin" ซึ่งเป็นระบบจัดการ backup อัตโนมัติไปยัง Azure Blob Storage (Managed Backup to Microsoft Azure, อยู่ใน msdb) ในระบบทดลองที่ไม่ได้เปิด Managed Backup ค่าจะยังคืน object มาให้ดูได้ (retention days, storage URL เป็นค่า default ว่าง) ใช้เมื่อสำรวจว่า instance ไหนเปิด managed backup ไว้และค่า retention เท่าไร:

```powershell
Get-SqlSmartAdmin -ServerInstance 'localhost' |
    Select-Object Parent, BackupEnabled, BackupRetentionPeriodInDays |
    Format-List
```

> จุดตัดสินใจเรื่องเครื่องมือ: อ่าน/เขียน instance info แบบทางการ = `SqlServer` module; การตั้งค่า server ที่ลึก ๆ (UserOptions, Configuration) = SMO; การรัน T-SQL เฉพาะทาง = `Invoke-Sqlcmd` เลือกให้ตรงงานและรู้ว่าข้างหลังทั้งหมดวิ่งผ่าน SMO ชุดเดียวกัน

> อ้างอิง: [Get-SqlInstance](https://learn.microsoft.com/powershell/module/sqlserver/get-sqlinstance), [Get-SqlSmartAdmin](https://learn.microsoft.com/powershell/module/sqlserver/get-sqlsmartadmin), [SERVERPROPERTY](https://learn.microsoft.com/sql/t-sql/functions/serverproperty-transact-sql?view=sql-server-ver17)

## 2. เปลี่ยน database options ด้วย SMO

ตัวอย่างคลาสสิกจากคอร์สเดิม (`ChangeProperties.ps1`): เปิด database เป็น **READ_ONLY** ช่วงปิดงบ ปรับ **AUTO_SHRINK** ปิดลง แล้วเปิดกลับ ทำผ่าน SMO ได้โดยตรง:

รันสคริปต์ [`Scripts/02_Change_Database_Options.ps1`](Scripts/02_Change_Database_Options.ps1) — สคริปต์สร้าง database ทดลอง `LabEnv` เอง (ไม่ไปแตะ AdventureWorks2025) แล้วทำงานตามลำดับ "ดูค่า → เปลี่ยน → `.Alter()` → ตรวจ → ย้อน":

```powershell
Import-Module SqlServer

# 1) ได้ Database object จาก provider
Set-Location SQLSERVER:\SQL\localhost\DEFAULT\Databases
$db = Get-Item LabEnv

# 2) ดูค่าปัจจุบัน
$db | Select-Object Name, RecoveryModel, CompatibilityLevel |
    Format-List
$db.DatabaseOptions |
    Select-Object AutoShrink, AutoClose, ReadOnly, AnsiNullsEnabled |
    Format-List

# 3) เปลี่ยน + .Alter() = ยื่น ALTER DATABASE จริง
$db.DatabaseOptions.ReadOnly = $true
$db.Alter()

# 4) ตรวจผล
(Get-Item SQLSERVER:\SQL\localhost\DEFAULT\Databases\LabEnv).DatabaseOptions.ReadOnly

# 5) ย้อนกลับ
$db.DatabaseOptions.ReadOnly = $false
$db.Alter()
```

ตาราง mapping ที่ใช้บ่อย (SMO property ↔ T-SQL `ALTER DATABASE ... SET`):

| SMO | T-SQL เทียบเท่า | เหมาะกับ |
|:----|:----------------|:---------|
| `$db.DatabaseOptions.ReadOnly` | `ALTER DATABASE x SET READ_ONLY` | ปิดงบ/ย้าย server |
| `$db.DatabaseOptions.AutoShrink` | `SET AUTO_SHRINK OFF` (ควร OFF เสมอ) | best practice ห้ามเปิด |
| `$db.DatabaseOptions.AutoClose` | `SET AUTO_CLOSE OFF` (บน server ปกติ) | best practice |
| `$db.DatabaseOptions.AutoUpdateStatistics` | `SET AUTO_UPDATE_STATISTICS ON` | best practice เปิดไว้ |
| `$db.RecoveryModel` | `SET RECOVERY FULL/SIMPLE/BULK_LOGGED` | Module 5 ของคอร์สนี้ |
| `$db.DatabaseOptions.PageVerify` | `SET PAGE_VERIFY CHECKSUM` | best practice |

✅ **สังเกต**: ระหว่าง database เป็น READ_ONLY การ query อ่านได้ปกติ แต่ UPDATE จะได้ error หมายเลข 3906 ("failed to update database ... because the database is read-only") — ลองใน Task ที่สคริปต์เตรียมไว้

**ข้อระวังเรื่อง `.Alter()`**: SMO ส่งเฉพาะ property ที่เปลี่ยนไป (dirty properties) ทำให้ปลอดภัยกว่าคิด แต่การเรียก `.Alter()` บน object ที่ดึงมานานแล้ว อาจทับการเปลี่ยนแปลงที่คนอื่นทำในระหว่างนั้น — ดึง object ใหม่ก่อนแก้เสมอในสคริปต์ที่รันยาว

> อ้างอิง: [Database Options (SMO)](https://learn.microsoft.com/sql/relational-databases/server-management-objects-smo/program-flow-tasks?view=sql-server-ver17), [ALTER DATABASE SET options](https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-set-options?view=sql-server-ver17)

## 3. เปลี่ยน instance settings — สองทาง (SMO Configuration และ sp_configure)

### ทาง A — SMO Configuration object

ค่า instance configuration ทั้งหมด (`sys.configurations` ทุกแถว) map เป็น property ของ `$srv.Configuration`:

```powershell
$srv = Get-Item SQLSERVER:\SQL\localhost\DEFAULT

# ดูค่า config ที่ใช้บ่อย
$srv.Configuration |
    Select-Object MinServerMemory, MaxServerMemory,
                  MaxDegreeOfParallelism, CostThresholdForParallelism |
    Format-List

# เปลี่ยน max server memory เป็น 4096 MB
$srv.Configuration.MaxServerMemory.ConfigValue = 4096
$srv.Configuration.Alter()
```

จุดสังเกต: ที่นี่เราแก้ **`.ConfigValue`** ของ property (`.RunValue` คือค่าที่ engine ใช้จริงขณะนี้ — ส่วนใหญ่จะอัปเดตตามหลัง RECONFIGURE) เทียบเท่า T-SQL: `EXEC sp_configure 'max server memory (MB)', 4096; RECONFIGURE;`

### ทาง B — sp_configure ผ่าน Invoke-Sqlcmd

รันสคริปต์ [`Scripts/04_sp_configure_InvokeSqlcmd.ps1`](Scripts/04_sp_configure_InvokeSqlcmd.ps1) — ใช้ `cost threshold for parallelism` เป็นตัวอย่าง (อย่าเยียนกับ max server memory ที่เราจะใช้ในแล็บ):

```powershell
# เปิด advanced options ก่อน (ค่าบางตัวมองไม่เห็นเว้นแต่เปิด)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;"

# อ่านค่าปัจจุบัน
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism';"

# เปลี่ยนเป็น 40 (เหมาะกับ workload ทั่วไปตามแนวทางชุมชน; default 5 ล้าสมัย)
Invoke-Sqlcmd -ServerInstance localhost -TrustServerCertificate `
    -Query "EXEC sp_configure 'cost threshold for parallelism', 40; RECONFIGURE;"
```

ตารางเปรียบเทียบสองทาง:

| | SMO Configuration | sp_configure + Invoke-Sqlcmd |
|:--|:------------------|:------------------------------|
| ประเภทค่า | property มี IntelliSense ใน VS Code | string อ้างชื่อ config เปลี่ยนได้ทุกตัวแม้ไม่มี property |
| เสี่ยงพิมพ์ผิด | ต่ำ (compile time) | สูงกว่า (runtime error เมื่อชื่อผิด) |
| ใช้ข้าม instance หลายตัว | ต้อง New-Object ต่อ server | วน foreach + `-ServerInstance` ได้เลย |
| แนะนำ | แก้ config ที่รู้ชื่อ | แก้ config เฉพาะที่ / รายชื่อจากตาราง |

> **หมายเหตุ HADR**: คำสั่ง PowerShell ที่ใช้ตั้งค่า Always On เช่น `Set-SqlHADREndpoint` (แก้ endpoint), `Enable-SqlAlwaysOn`, `New-SqlAvailabilityGroup` อยู่นอกขอบเขตโมดูลนี้ — รู้ไว้ว่ามีและอยู่ใน SqlServer module เดียวกัน หากองค์กรใช้ Availability Group ให้ศึกษาต่อจาก [SqlServer module docs](https://learn.microsoft.com/powershell/module/sqlserver/)

## 4. VS Code + PowerShell extension — เครื่องมือเขียนสคริปต์มาตรฐาน

**PowerShell ISE ถูก deprecate** และไม่รองรับ PowerShell 7 เครื่องมือแทนที่ทางการคือ **Visual Studio Code** + **PowerShell extension**:

1. ติดตั้ง [VS Code](https://code.visualstudio.com/) (หรือ VS Code ที่แถมกับ SQL Server setup)
2. เปิด Extensions (Ctrl+Shift+X) ค้นหา **PowerShell** (ผู้พัฒนา: Microsoft) กด Install
3. Ctrl+Shift+P > "PowerShell: Show Session Menu" > เลือก **PowerShell 7** เป็น runtime ของหน้าต่าง integrated
4. สร้างโฟลเดอร์สำหรับคอร์ส แล้วเปิดด้วย `code .` — ไฟล์ .ps1 จะมี IntelliSense รวมถึง cmdlet ของ SqlServer module (โหลด module ด้วย `Import-Module SqlServer` ที่บรรทัดบนก่อน IntelliSense จะจับ)

ฟีเจอร์ที่ใช้บ่อยในงาน DBA:

| ฟีเจอร์ | ใช้ทำอะไร |
|:---------|:----------|
| F5 = รันทั้งไฟล์, F8 = รันที่เลือก | ทดสอบทีละ Task เหมือน SSMS |
| IntelliSense + parameter hints | หลบพิมพ์พารามิเตอร์ผิด (สำคัญมากกับ SMO) |
| **PSScriptAnalyzer** (มากับ extension) | เตือน best practice เช่น `Write-Host`, alias ย่อ ฯลฯ |
| Git integration | version control สคริปต์ DBA — เก็บไว้ใน repo เดียวกับคอร์สนี้ |

> อ้างอิง: [Using Visual Studio Code for PowerShell Development](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/vscode/using-vscode)

## 5. dbatools — ทางเลือกชุมชน (optional)

**dbatools** ([dbatools.io](https://dbatools.io)) เป็นโมดูล open-source ของชุมชนที่ห่อ SMO ด้วย cmdlet หลายร้อยตัวชื่ออ่านรู้เรื่อง (`Get-DbaDatabase`, `Test-DbaConnection`, `Backup-DbaDatabase`, `Invoke-DbaQuery` ...) เป็นมาตรฐาน de facto ในงาน SQL Server automation ร่วมสมัย มีสองระดับการใช้:

1. **Microsoft ทางการ** (`SqlServer` module) — จ่าย support ได้ ผูกกับ SQL Server ทุกรุ่น เหมาะกับองค์กรที่ต้องการเส้นทาง support
2. **dbatools** — ชุมชน, เร็ว, ครอบคลุม migration/inventory แต่ไม่มี contract support จาก Microsoft

รันสคริปต์ [`Scripts/05_dbatools_Optional.ps1`](Scripts/05_dbatools_Optional.ps1) (ติดตั้งก่อน: `Install-Module dbatools -Scope CurrentUser -Force`):

```powershell
# สถานะ service ของ SQL Server บนเครื่อง (เทียบ Get-Service *SQL*)
Get-DbaService -ComputerName localhost |
    Select-Object ComputerName, ServiceName, State, ServiceType |
    Format-Table -AutoSize

# database ทั้งหมดพร้อมข้อมูลที่ SSMS ต้องเปิดหลายหน้าจอ
Get-DbaDatabase -SqlInstance localhost |
    Select-Object Name, Status, RecoveryModel, SizeMB, LastGoodCheckDbTime |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# ดู/จัดการค่า config ภายในของ dbatools เอง
Get-DbaConfig
```

✅ **สังเกต**: งานเดียวกันใน `Get-ChildItem SQLSERVER:\SQL\...\Databases` ต้องเขียน pipeline เองเพื่อจัด format — dbatools จัดรูปให้พร้อมใช้ และมี `-SqlInstance` รับหลาย server ในบรรทัดเดียว นี่คือคุณค่าหลักของมัน

> **นโยบายของคอร์ส**: เราใช้ `SqlServer` module เป็นหลัก (เพราะเป็นชุดทางการที่ควรรู้ก่อน) และใช้ dbatools แบบ "เสริมเฉพาะหัวข้อ" — เมื่อไปทำงานจริงให้เลือกชุดเดียวในองค์กรแล้วยึด consistent

> อ้างอิง: [dbatools.io — free PowerShell module for SQL Server](https://dbatools.io), [Install dbatools](https://dbatools.io/install)

## 6. แผนที่ "แก้ค่า → ย้อนกลับ" ที่ใช้ได้จริง

สคริปต์จริงในที่ทำงานควรมีรูปแบบเดียวกับที่ Section นี้ใช้:

```powershell
# 1. บันทึกค่าเดิม
$original = $srv.Configuration.MaxServerMemory.ConfigValue
"$($(Get-Date).ToString('s'));localhost;MaxServerMemory;$original" |
    Add-Content "$env:TEMP\config-change.log"

# 2. เปลี่ยน
$srv.Configuration.MaxServerMemory.ConfigValue = 4096
$srv.Configuration.Alter()

# 3. ย้อนกลับเมื่อจบการทดสอบ
$srv.Configuration.MaxServerMemory.ConfigValue = $original
$srv.Configuration.Alter()
```

## 7. จัดการ config ข้ามหลาย instance และเก็บเป็น snapshot เทียบเวลา

ข้อดีเต็ม ๆ ของ PowerShell ปรากฏเมื่อ config ต้อง "ให้ตรงกันทุกเครื่อง" โครงที่ใช้ได้จริง (และเป็นแนวทางของแล็บ):

```powershell
$servers = @('localhost', 'localhost,1434')   # เพิ่มได้เรื่อย ๆ (container ที่สองของ Module 00)

$report = foreach ($si in $servers) {
    Invoke-Sqlcmd -ServerInstance $si -TrustServerCertificate `
        -Query "SELECT @@SERVERNAME AS ServerName, name, value_in_use
                FROM sys.configurations
                WHERE name IN ('max server memory (MB)', 'min server memory (MB)',
                               'max degree of parallelism', 'cost threshold for parallelism',
                               'optimize for ad hoc workloads', 'backup compression algorithm');" |
        Select-Object @{N = 'Server'; E = { $_.ServerName } }, name, value_in_use
}

$report | Format-Table -AutoSize
$report | Export-Csv "$env:TEMP\ConfigBaseline.csv" -NoTypeInformation -Encoding UTF8
```

จุดที่ควรทำเป็นนิสัย:

1. **เก็บ snapshot ของ config ลงไฟล์ (เช่น ConfigBaseline.csv) ทุกครั้งที่แก้** — เวลาเกิดเหตุ "เครื่องนี้ช้าลงหลังบางอย่างเปลี่ยน" คุณเทียบ snapshot สองชุดแล้วเจอตัวแปลภายในนาทีเดียว
2. **เปลี่ยนทีละค่าและวัดผล** — แก้ config หกตัวพร้อมกันแล้ว performance ดีขึ้น คุณไม่รู้ว่าตัวไหนทำงาน และถ้าพังก็ไม่รู้ตัวไหนทำพัง
3. **สิทธิ์ระดับที่เหมาะ** — แก้ instance config ต้องสิทธิ์ `ALTER SETTINGS` (sysadmin มีโดย default); ในระบบที่ให้สิทธิ์แบบ least-privilege ให้แยกคนที่อนุมัติ/คนที่รันและเก็บ log ร่วมกัน

สิ่งที่เกี่ยวโยงกับโมดูลถัดไป: วิธี "snapshot → เก็บ → เทียบเวลา" นี้คือหัวใจเดียวกับ baseline ของ DMVs ใน **Module 13** — config เป็นตัวเลข static เทียบง่าย, ค่า DMV เป็นตัวสะสมต้อง snapshot สองรอบหาผลต่าง เรียนรู้แบบที่ง่าย (config) ก่อนแล้วค่อยไปแบบ dynamic

### 🚀 SQL Server 2025 & Modern Notes
- **`Import-Module SQLPS` เป็นของยุคจบ** — โมดูล SQLPS (SQL Server 2016-) ไม่อัปเดตต่อ; ทุกสคริปต์ให้ใช้ `Install-Module SqlServer` + `Import-Module SqlServer` ([SqlServer module](https://learn.microsoft.com/powershell/module/sqlserver/))
- **ISE deprecated → VS Code + PowerShell extension** — ISE รองรับเฉพาะ Windows PowerShell 5.1 และไม่มีแผนพัฒนาต่อ ([PowerShell ISE](https://learn.microsoft.com/powershell/scripting/components/ise-intro))
- **SQLSERVER: drive ไม่ต้อง `New-PSDrive` ใน PowerShell 7** — หลักสูตรเดิมมีขั้นตอนสร้าง PSDrive เอง (ยุค SQLPS ที่ทำงานบน Windows PowerShell 2.0) ปัจจุบัน import module แล้ว drive โผล่ทันที ([SQL Server PowerShell provider](https://learn.microsoft.com/sql/powershell/navigate-the-sql-server-powershell-drive?view=sql-server-ver17))
- **dbatools เป็นมาตรฐานชุมชน** — สำหรับ migration/inventory ข้ามหลาย instance จำนวนมาก เกินความสามารถของ SqlServer module แบบเปลือย ([dbatools.io](https://dbatools.io))
- **PowerShell 7 cross-platform** — จัดการ SQL Server บน Linux ได้จากเครื่อง Windows (เช่น container `sql2025b` ของ Module 00) โดยใช้ `Get-SqlInstance -ServerInstance 'localhost,1434'`
