# =============================================================================
# 03_SQLSERVER_Provider.ps1 - เดิน SQLSERVER: drive และรายงาน database
# ปรับปรุงจาก Old/Demofiles/Mod11/InspectSqlInstances.ps1.txt (คอร์ส 20764D)
#   - เดิม: Import-Module SQLPS และทำงานบน Windows PowerShell  -> เปลี่ยนเป็น SqlServer module + PowerShell 7
#   - เดิม: เดิน SQLSERVER:\SQL\localhost แล้วดูทุก instance  -> คงแนวคิดเดิม แต่ใช้ cmdlet/encoding ใหม่
#   - ตัด New-PSDrive (ไม่จำเป็นใน PowerShell 7 - drive ถูกสร้างให้อัตโนมัติเมื่อ import)
# =============================================================================

param(
    [string]$ComputerName  = 'localhost',   # เครื่องที่มี SQL Server (named instance ใช้ 'localhost\INSTANCE')
    [string]$OutputDir     = "$env:TEMP"    # ที่เก็บรายงาน
)

Clear-Host

# --- Task 1: Import module แล้วดู drive ที่ provider สร้างให้ ---
Import-Module SqlServer
Get-PSDrive | Select-Object Name, Provider, Root | Format-Table -AutoSize
# ควรเห็น SQLSERVER: อยู่ในรายการโดยไม่ต้อง New-PSDrive เอง

# --- Task 2: สำรวจ instance ทั้งหมดบนเครื่อง (เดิม: cd SQLSERVER:\SQL\localhost) ---
Write-Host "=== Task 2: instance ทั้งหมดบน $ComputerName ===" -ForegroundColor Cyan

Set-Location SQLSERVER:
Set-Location "SQL\$ComputerName"
Get-ChildItem |
    Select-Object Name, Version, Edition |
    Format-Table -AutoSize
# มีเฉพาะ default instance ก็จะเห็น DEFAULT (named instance เห็นชื่อ instance)

# --- Task 3: รายงาน database ทุกตัวใน default instance (จาก demo เดิม #5) ---
Write-Host "`n=== Task 3: รายงาน database เรียงตามขนาด ===" -ForegroundColor Cyan

$defaultInstance = Get-Item "SQLSERVER:\SQL\$ComputerName\DEFAULT" -ErrorAction SilentlyContinue
if (-not $defaultInstance) {
    Write-Error "ไม่พบ default instance บน $ComputerName - แก้ -ComputerName เป็น 'hostname\instancename' แล้วปรับ Task ให้ตรง"
    return
}

$databaseReport = $defaultInstance.Databases |
    Select-Object Name, Status, CompatibilityLevel, RecoveryModel, Collation,
                  @{N = 'SizeMB';           E = { [math]::Round($_.Size / 1MB, 1) } },
                  @{N = 'IndexSpaceUsageMB'; E = { [math]::Round($_.IndexSpaceUsage / 1024.0, 1) } },
                  LastBackupDate

$databaseReport |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# --- Task 4: เก็บรายงานเป็นไฟล์ (เดิม: Out-File / ConvertTo-XML / CSV) ---
Write-Host "=== Task 4: เก็บรายงานเป็น CSV ===" -ForegroundColor Cyan

$csvPath = Join-Path $OutputDir "Databases_$($ComputerName -replace '[\\/:]', '_').csv"
$databaseReport |
    Sort-Object SizeMB -Descending |
    Export-Csv $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "เขียนแล้ว: $csvPath" -ForegroundColor Green
Get-Content $csvPath -TotalCount 4

# --- Task 5: รายงานที่ใช้ได้จริง - DB ไหนไม่เคย backup (หรือไม่มี full backup ล่าสุด 7 วัน) ---
Write-Host "`n=== Task 5: database ที่ไม่มี backup ภายใน 7 วัน ===" -ForegroundColor Cyan

$databaseReport |
    Where-Object { $_.Name -notin @('tempdb', 'model', 'master') -and
                   ( -not $_.LastBackupDate -or $_.LastBackupDate -lt (Get-Date).AddDays(-7) ) } |
    Select-Object Name, LastBackupDate |
    Format-Table -AutoSize

# --- Task 6: เดินโครงใต้ database เหมือนไฟร์ซิสเทม ---
Write-Host "=== Task 6: ตารางใน AdventureWorks2025 (ผ่าน provider) ===" -ForegroundColor Cyan

Set-Location "SQLSERVER:\SQL\$ComputerName\DEFAULT\Databases\AdventureWorks2025\Tables"
Get-ChildItem |
    Select-Object -First 10 Name, Schema, RowCount |
    Format-Table -AutoSize

Set-Location $HOME   # ออกจาก SQLSERVER: drive กลับโฟลเดอร์บ้าน

# --- ทดลองเอง ---
# 1) เดินไป SQLSERVER:\SQL\<เครื่องคุณ>\DEFAULT\Logins แล้วรายงาน login ทั้งหมด
# 2) เดินไป ...DEFAULT\Databases\msdb\JobServer\Jobs แล้วดูว่ามี job อะไรบ้าง (มี SQL Agent)
# 3) เปลี่ยน Task 5 เป็น "database ที่ recovery model เป็น SIMPLE"
