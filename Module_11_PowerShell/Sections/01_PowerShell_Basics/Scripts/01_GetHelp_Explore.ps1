# =============================================================================
# 01_GetHelp_Explore.ps1 - พื้นฐานการสำรวจ PowerShell: Get-Help / Get-Command / Get-Member
# ปรับปรุงจากแนวทางคอร์ส 20764D Module 11 (เดิมใช้ SQLPS - เปลี่ยนเป็น SqlServer module)
# รันบน PowerShell 7+ ที่ติดตั้ง SqlServer module แล้ว
# รันทีละ Task ใน terminal (pwsh) เพื่อเห็นผลของแต่ละคำสั่ง
# =============================================================================

param(
    [string]$ServerInstance = 'localhost'
)

Clear-Host

# --- Task 1: ตรวจเวอร์ชัน PowerShell และ module ---
Write-Host "=== Task 1: ตรวจสภาพแวดล้อม ===" -ForegroundColor Cyan

$PSVersionTable.PSVersion                       # ต้องเป็น 7.x
Get-Module SqlServer -ListAvailable |
    Select-Object Name, Version, Path           # SqlServer module ต้องมีอยู่

# --- Task 2: อัปเดต help file (ทำครั้งแรกครั้งเดียว ต้อง admin ถ้า scope เครื่อง) ---
# Update-Help -Module SqlServer -ErrorAction SilentlyContinue

# --- Task 3: Get-Command - ค้นหาคำสั่งก่อนเดา ---
Write-Host "`n=== Task 3: คำสั่งใน SqlServer module จัดกลุ่มตาม verb ===" -ForegroundColor Cyan

Get-Command -Module SqlServer |
    Group-Object Verb |
    Sort-Object Count -Descending |
    Select-Object Name, Count |
    Format-Table -AutoSize

# คำสั่งเกี่ยวกับ backup มีอะไรบ้าง
Write-Host "=== คำสั่ง verb 'Backup' ===" -ForegroundColor Yellow
Get-Command -Module SqlServer -Verb Backup |
    Select-Object Name, ModuleName |
    Format-Table -AutoSize

# --- Task 4: Get-Help - อ่านคู่มือแบบมีตัวอย่าง ---
Write-Host "`n=== Task 4: Get-Help Invoke-Sqlcmd (ตัวอย่าง 2 อันแรก) ===" -ForegroundColor Cyan
Get-Help Invoke-Sqlcmd -Examples | Select-Object -First 20

# รูปแบบอื่น:
#   Get-Help Backup-SqlDatabase -Full       อ่านทุกหัวข้อ
#   Get-Help Restore-SqlDatabase -Parameter Incremental   ดูพารามิเตอร์เดียว
#   Get-Help about_Execution_Policies       หัวข้อ conceptual

# --- Task 5: Get-Member - object จริงหน้าตาเป็นอย่างไร ---
Write-Host "`n=== Task 5: ชนิด object ที่ provider คืนมา ===" -ForegroundColor Cyan

$dbs = Get-ChildItem SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases -ErrorAction SilentlyContinue
if ($dbs) {
    $dbs | Get-Member -MemberType Property |
        Select-Object Name, MemberType -First 25 |
        Format-Table -AutoSize

    Write-Host "ชนิด object: $($dbs[0].GetType().FullName)"
    # ควรได้ Microsoft.SqlServer.Management.Smo.Database  -- นี่คือ SMO
}
else {
    Write-Warning "ไม่พบ SQLSERVER: drive - รัน Import-Module SqlServer ก่อน"
}

# --- Task 6: ทดลองเอง ---
# 1) หาคำสั่งทั้งหมดที่มีคำว่า 'Log' ในชื่อ: Get-Command -Module SqlServer -Noun *Log*
# 2) อ่านตัวอย่างของ Backup-SqlDatabase: Get-Help Backup-SqlDatabase -Examples
# 3) ดู method ของ Database object: $dbs | Get-Member -MemberType Method
