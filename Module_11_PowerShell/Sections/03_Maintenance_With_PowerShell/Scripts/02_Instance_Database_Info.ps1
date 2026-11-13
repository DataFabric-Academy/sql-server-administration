# =============================================================================
# 02_Instance_Database_Info.ps1 - สำรวจ instance/databases และทำรายงานใช้ได้จริง
# ปรับปรุงจาก Old/Demofiles/Mod11/InspectSqlInstances.ps1.txt (20764D)
#   เดิม: เดิน SQLSERVER: drive + Select-Object ต่อกัน -> ใหม่: ใช้ Get-SqlInstance /
#         Get-SqlDatabase (cmdlet ทางการ) + รายงาน "ใช้ได้จริง" 3 แบบ
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$ReportDir      = "$env:TEMP"
)

Clear-Host
Import-Module SqlServer

# --- Task 1: รายงาน database ทุกตัว เรียงตามขนาด (จาก demo เดิม #5) ---
Write-Host "=== Task 1: รายงาน database ทั้ง instance ===" -ForegroundColor Cyan

$allDb = Get-SqlDatabase -ServerInstance $ServerInstance

$allDb |
    Select-Object Name, Status, RecoveryModel, CompatibilityLevel,
                  @{N = 'SizeMB';  E = { [math]::Round($_.Size / 1MB, 1) } },
                  @{N = 'DataMB';  E = { [math]::Round($_.DataSpaceUsage / 1024.0, 1) } },
                  @{N = 'IndexMB'; E = { [math]::Round($_.IndexSpaceUsage / 1024.0, 1) } },
                  LastBackupDate |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# --- Task 2: รายงานที่ 1 - DB ที่ไม่มี full backup ภายใน 24 ชั่วโมง ---
Write-Host "`n=== Task 2: DB ที่ไม่มี backup ใน 24 ชม. ===" -ForegroundColor Cyan

$allDb |
    Where-Object { $_.Name -notin @('tempdb') -and
                   ( -not $_.LastBackupDate -or $_.LastBackupDate -lt (Get-Date).AddHours(-24) ) } |
    Select-Object Name, LastBackupDate, RecoveryModel |
    Format-Table -AutoSize

# หมายเหตุ: บนระบบทดลองที่เพิ่ง restore อาจเห็น master/model เพราะยังไม่เคย backup - ปกติ

# --- Task 3: รายงานที่ 2 - Recovery model ของ database ผู้ใช้ ---
Write-Host "`n=== Task 3: Recovery model ต่อ database ===" -ForegroundColor Cyan

$allDb |
    Where-Object { $_.Name -notin @('master', 'model', 'msdb', 'tempdb') } |
    Select-Object Name, RecoveryModel,
                  @{N = 'LastFullBackup'; E = { if ($_.LastBackupDate) { $_.LastBackupDate } else { 'ยังไม่เคย' } } } |
    Format-Table -AutoSize

# --- Task 4: รายงานที่ 3 - database ที่สถานะไม่ปกติ ---
Write-Host "`n=== Task 4: DB สถานะผิดปกติ (offline/restoring/suspect) ===" -ForegroundColor Cyan

$allDb |
    Where-Object { "$($_.Status)" -notmatch 'Normal|AutoClosed' } |
    Select-Object Name, Status, CreateDate |
    Format-Table -AutoSize

# ถ้าไม่มีแถวแปลว่า database ทุกตัวใช้งานปกติ - รายงานว่างก็เป็นข้อมูลที่ดี

# --- Task 5: เก็บรายงานรวมเป็นไฟล์ CSV (ส่งต่อทีม/เก็บ history) ---
Write-Host "`n=== Task 5: export รายงานรวม ===" -ForegroundColor Cyan

$reportPath = Join-Path $ReportDir "DbInventory_$(Get-Date -Format yyyyMMdd_HHmm).csv"
$allDb |
    Select-Object Name, Status, RecoveryModel, CompatibilityLevel, Size, LastBackupDate |
    Sort-Object Name |
    Export-Csv $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "เขียนแล้ว: $reportPath" -ForegroundColor Green

# --- Task 6: ข้อมูล instance ระดับ service (เสริม) ---
Write-Host "`n=== Task 6: ข้อมูล instance ===" -ForegroundColor Cyan

Get-SqlInstance -ServerInstance $ServerInstance |
    Select-Object Name, Version, Edition, ProductLevel,
                  @{N = 'PhysicalMemoryMB'; E = { $_.PhysicalMemory } },
                  Processors, IsClustered |
    Format-List

# --- ทดลองเอง ---
# 1) เปลี่ยน Task 2 ให้ใช้ threshold 7 วัน แล้วส่งผลออก email จำลอง (เพียง Write-Host)
# 2) สร้าง function Get-DbaDbReport ที่รับ -ServerInstance หลายตัวพร้อมกัน
# 3) ใช้ dbatools เทียบ: Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Select Name, SizeMB
