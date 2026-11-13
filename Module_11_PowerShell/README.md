# Module 11 — การจัดการ SQL Server ด้วย PowerShell เบื้องต้น

จนถึงโมดูลนี้คุณได้จัดการ SQL Server ด้วย SSMS และ T-SQL เป็นหลัก ซึ่งเพียงพอกับ instance เดียวแต่ไม่สเกล — งานจริงของ DBA คือดูแลหลาย instance ทำงานซ้ำ ๆ ทุกสัปดาห์ (รายงาน backup, ปรับ config, สร้าง login ตาม ticket) และทำให้ขั้นตอนเดิมเกิดผลแบบเดิมทุกครั้ง โมดูลนี้จึงพาเข้าสู่ **PowerShell** — shell และ scripting language ทางการของ Microsoft ที่คุยกับ SQL Server ผ่าน **SMO (SQL Server Management Objects)** และ **SqlServer module** ทำให้ทุกงานที่เคยคลิกใน SSMS แปลงเป็นสคริปต์ที่รันซ้ำ ตรวจย้อนหลัง และกระจายไปหลายเซิร์ฟเวอร์ได้

หลักสูตรเดิม (20764D) สอน PowerShell ด้วยโมดูล SQLPS บน Windows PowerShell 2.0 ซึ่งล้าสมัยหมดอายุแล้ว เนื้อหาทั้งโมดูลนี้ถูกเขียนใหม่บน **PowerShell 7.x (cross-platform) + SqlServer module (Install-Module SqlServer)** ครอบคลุมตั้งแต่พื้นฐานภาษา, SQLSERVER: drive (PowerShell Provider), การตั้งค่า instance/database, งานบำรุงรักษา (login, backup/restore), จนถึงการสร้าง Azure SQL Database ด้วย Az module และแนะนำ **dbatools** — โมดูลชุมชนที่เป็นมาตรฐานจริงในสนามงาน

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – ใช้ PowerShell กับ SQL Server ได้**: ติดตั้ง SqlServer module, ห่มตัวเองด้วย `Get-Help`/`Get-Command`, เขียน pipeline พื้นฐานและรัน T-SQL ด้วย `Invoke-Sqlcmd`
- **ระดับ 2 – สำรวจระบบแบบ scripted**: เดินโครงสร้างด้วย SQLSERVER: drive (`SQLSERVER:\SQL\localhost\DEFAULT`), ใช้ SMO objects อ่าน property ของ instance/database และทำรายงาน CSV อัตโนมัติ
- **ระดับ 3 – เปลี่ยนและย้อนค่าตั้งอย่างปลอดภัย**: แก้ database options ผ่าน SMO (`.Alter()`), แก้ instance config ผ่าน `Configuration` object และ `sp_configure` ด้วยรูปแบบ "บันทึกค่าเดิม → เปลี่ยน → ย้อน"
- **ระดับ 4 – ทำงานบำรุงรักษาจริง + ต่อยอดคลาวด์**: สร้าง login/user/role, backup/restore ด้วย `Backup-SqlDatabase`/`Restore-SqlDatabase`, ตรวจ Windows patch ด้วย `Get-HotFix`, และสร้าง/ลบ Azure SQL DB ด้วย Az module รวมถึงเลือกใช้ dbatools ได้ถูกบริบท

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [พื้นฐาน PowerShell และ SQLSERVER: drive (PowerShell 7, SMO, Invoke-Sqlcmd)](Sections/01_PowerShell_Basics/README.md) |
| 2 | [ตั้งค่า SQL Server ด้วย PowerShell (Get-SqlInstance, SMO Configuration, sp_configure, VS Code, dbatools)](Sections/02_Configuring_With_PowerShell/README.md) |
| 3 | [งานบำรุงรักษา (users/roles, backup/restore, Get-HotFix, troubleshooting)](Sections/03_Maintenance_With_PowerShell/README.md) |
| 4 | [Azure SQL ด้วย PowerShell (Az module, managed identity, ความต่าง SMO บน Azure)](Sections/04_Azure_SQL_PowerShell/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. ความต่างระหว่าง SQLPS, Windows PowerShell 5.1 และ PowerShell 7 คืออะไร และควรใช้ชุดไหนกับ SQL Server?</b></summary>

SQLPS คือโมดูล PowerShell เก่าที่แถมกับ SQL Server 2016 ลงมา (ไม่อัปเดตแล้ว อย่าใช้); Windows PowerShell 5.1 คือ shell ที่มากับ Windows (`powershell.exe`); PowerShell 7.x คือรุ่น cross-platform ปัจจุบัน (`pwsh.exe`) ที่รองรับ `SqlServer` module รุ่นล่าสุด ชุดที่ควรใช้คือ **PowerShell 7 + `Install-Module SqlServer`** ทุกงาน และเปลี่ยนเครื่องมือแก้ไฟล์จาก ISE (deprecated) เป็น VS Code + PowerShell extension

```powershell
$PSVersionTable.PSVersion                 # ต้องเป็น 7.x
Get-Module SqlServer -ListAvailable       # module ทางการต้องมี
```
— อ่านละเอียด: [Section 1](Sections/01_PowerShell_Basics/README.md)
</details>

<details>
<summary><b>2. การกำหนด <code>$db.DatabaseOptions.ReadOnly = $true</code> ทำให้ database กลายเป็น read-only แล้วหรือยัง ทำอย่างไรให้ "จริง"?</b></summary>

ยังไม่จริง — การกำหนดค่าเพียงแก้ข้อมูลใน memory ของ SMO object เท่านั้น ต้องเรียก **`.Alter()`** ซึ่งเป็น method ที่ส่ง T-SQL `ALTER DATABASE ... SET READ_ONLY` ไปยัง server จริง รูปแบบเดียวกันใช้กับทุก SMO object: `$srv.Configuration.MaxServerMemory.ConfigValue = 4096` ต้องตามด้วย `$srv.Configuration.Alter()` และหลังแก้ให้ดึง object ใหม่ (เช่น `Get-Item` ใหม่) เพื่ออ่านค่าปัจจุบันจริง
— อ่านละเอียด: [Section 2](Sections/02_Configuring_With_PowerShell/README.md)
</details>

<details>
<summary><b>3. ทำไมจึงควร "บันทึกค่าเดิม → เปลี่ยน → ย้อนกลับ" เวลาแก้ config ด้วย PowerShell และย้อนด้วยวิธีใดได้บ้าง?</b></summary>

เพราะ PowerShell ทำให้การแก้ config "เร็วขึ้น 10 เท่า" ซึ่งแปลว่าทำพลาดเร็วขึ้น 10 เท่าเช่นกัน การบันทึกค่าเดิม (ลงไฟล์ log/CMDB) ทำให้สามารถ: (1) ย้อนได้ทันทีเมื่อ performance เสียหายหลังเปลี่ยน (2) อธิบายเหตุผลต่อ audit ได้ การย้อนทำได้สองทาง — กำหนดค่าเดิมกลับผ่าน SMO `.Alter()` หรือ `EXEC sp_configure '<name>', <ค่าเดิม>; RECONFIGURE;` ผ่าน `Invoke-Sqlcmd`
— อ่านละเอียด: [Section 2](Sections/02_Configuring_With_PowerShell/README.md)
</details>

<details>
<summary><b>4. Restore database ใหม่ด้วย Restore-SqlDatabase ต้องใส่ -RelocateFile เมื่อไร และสร้าง RelocateFile objects ได้อย่างไร?</b></summary>

เมื่อ restore เป็น **database ใหม่ที่ไม่ใช่ต้นฉบับ** (เช่น copy สำหรับทดสอบ) เพราะไฟล์ .mdf/.ldf ใน backup อ้าง path เดิมของต้นฉบับ — ไม่ MOVE จะทับไฟล์ของ database เดิมหรือ error ว่า path มีไฟล์แล้ว สร้างได้จาก logical file names ที่อ่านด้วย `RESTORE FILELISTONLY`:

```powershell
$fileList = Invoke-Sqlcmd -Query "RESTORE FILELISTONLY FROM DISK = N'C:\SQLBackups\AW.bak';"
$relocate = foreach ($f in $fileList) {
    New-Object Microsoft.SqlServer.Management.Smo.RelocateFile(
        $f.LogicalName, (Join-Path $dataDir ($f.LogicalName + '_Copy.mdf')))
}
Restore-SqlDatabase -ServerInstance localhost -Database AW_Copy `
    -BackupFile C:\SQLBackups\AW.bak -RelocateFile $relocate -ReplaceDatabase
```
— อ่านละเอียด: [Section 3](Sections/03_Maintenance_With_PowerShell/README.md)
</details>

<details>
<summary><b>5. เครื่องมือชุดไหนใช้กับ Azure SQL Database ได้บ้าง และอะไรที่ "ไม่มี" บน Azure SQL DB?</b></summary>

ใช้ได้: `Invoke-Sqlcmd` (เชื่อมต่อ `*.database.windows.net` ตรง ๆ), SMO ในส่วนอ่าน metadata/DDL ทั่วไป, cmdlet ฝั่ง `Az.Sql` (`New-AzSqlServer`, `New-AzSqlDatabase`, `Get-AzSqlDatabase`) ไม่มี: **`BACKUP DATABASE`/`RESTORE DATABASE`** (Azure ทำ automatic backup ให้เอง — ใช้ point-in-time restore), instance-level `sp_configure` (แทนด้วย database-scoped options) และ Event sessions ต้องเป็น `ON DATABASE` เท่านั้น
— อ่านละเอียด: [Section 4](Sections/04_Azure_SQL_PowerShell/README.md)
</details>

<details>
<summary><b>6. dbatools เทียบกับ SqlServer module — ควรเลือกใช้อย่างไร?</b></summary>

**SqlServer module** เป็นของทางการ ผูกกับ SQL Server support lifecycle เหมาะกับองค์กรที่ต้องการเส้นทาง support ชัดเจน; **dbatools** เป็นของชุมชน (open source) มี cmdlet พร้อมใช้หลายร้อยตัวสำหรับ migration/inventory/backup ข้ามหลาย instance เหมาะกับ farm ใหญ่และงานเร่ง ๆ หลักการคือเลือกชุดเดียวในองค์กรแล้วยึดต่อเนื่อง อย่าผสมสองชุดในสคริปต์เดียวโดยไม่มีเหตุผล
— อ่านละเอียด: [Section 2](Sections/02_Configuring_With_PowerShell/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **SQLPS และ SQL Server ISE หมดยุค** — ทุกสคริปต์ใหม่ใช้ `SqlServer` module + PowerShell 7 และแก้ไฟล์ด้วย VS Code; SQLSERVER: drive ถูกสร้างอัตโนมัติเมื่อ import ไม่ต้อง `New-PSDrive`
- **Encryption by default ใน SqlServer module v22+** — ต้อง `-TrustServerCertificate` กับ self-signed cert สอดคล้องกับมาตรฐาน TLS 1.3/TDS 8.0 ของ SQL Server 2025
- **ZSTD backup compression (2025)** — `BACKUP ... WITH COMPRESSION, ALGORITHM = ZSTD` ผ่าน `Invoke-Sqlcmd` เมื่อต้องการ algorithm ใหม่นอกเหนือจาก `-CompressionOption On`
- **Managed identity ผ่าน Azure Arc (2025)** — SQL Server on-premises ที่เชื่อมต่อ Arc ใช้ managed identity กับ EKM/backup to URL; ฝั่ง Azure SQL สร้างด้วย `New-AzSqlServer -AssignIdentity`
- **dbatools คือมาตรฐานชุมชน** — ใช้เสริมจุดที่ SqlServer module ยังไม่มี cmdlet พร้อมใช้ (Get-DbaService, Get-DbaDatabase, Backup-DbaDatabase)
- **Read-SqlXEvent** — cmdlet ใหม่ใน SqlServer module อ่าน .xel ไฟล์/live XE session โดยตรง (จะใช้ต่อใน Module 12)

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [SqlServer PowerShell module](https://learn.microsoft.com/powershell/module/sqlserver/), [SQL Server PowerShell](https://learn.microsoft.com/sql/powershell/sql-server-powershell?view=sql-server-ver17), [dbatools.io](https://dbatools.io)
