# =============================================================================
# 05_dbatools_Optional.ps1 - dbatools ทางเลือกชุมชน (optional)
# dbatools.io = โมดูล open-source ของชุมชน ห่อ SMO ด้วย cmdlet พร้อมใช้หลายร้อยตัว
# ติดตั้งก่อนรัน: Install-Module dbatools -Scope CurrentUser -Force
# หมายเหตุ: dbatools เป็นโมดูลชุมชน ไม่ใช่ส่วนหนึ่งของ Microsoft SQL Server
# =============================================================================

param(
    [string]$SqlInstance = 'localhost',
    [string]$ComputerName = 'localhost'
)

Clear-Host

# --- Task 0: ตรวจว่าติดตั้ง dbatools แล้ว ---
if (-not (Get-Module dbatools -ListAvailable)) {
    Write-Warning "ยังไม่ได้ติดตั้ง dbatools - รันคำสั่งนี้ก่อน (ทำได้บน PowerShell 5.1 และ 7):"
    Write-Host "    Install-Module dbatools -Scope CurrentUser -Force" -ForegroundColor Yellow
    return
}

# --- Task 1: Get-DbaService - สถานะ service ของ SQL Server ทั้งเครื่อง ---
Write-Host "=== Task 1: Get-DbaService ===" -ForegroundColor Cyan

Get-DbaService -ComputerName $ComputerName |
    Select-Object ComputerName, ServiceType, ServiceName, State, StartUser |
    Format-Table -AutoSize

# เทียบเท่า (built-in): Get-Service *SQL* | Select-Object Name, Status

# --- Task 2: Get-DbaDatabase - รายงาน database รวมข้อมูลที่จำเป็นในครั้งเดียว ---
Write-Host "`n=== Task 2: Get-DbaDatabase ===" -ForegroundColor Cyan

Get-DbaDatabase -SqlInstance $SqlInstance |
    Select-Object Name, Status, RecoveryModel,
                  @{N = 'SizeMB'; E = { [math]::Round($_.SizeMB, 1) } },
                  LastGoodCheckDbTime, Owner |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# ตัวอย่าง filter พร้อมใช้:
#   Get-DbaDatabase -SqlInstance localhost -NoSystemDb      # ไม่เอา system DBs
#   Get-DbaDatabase -SqlInstance localhost -Status 'Offline' # เฉพาะ offline

# --- Task 3: Get-DbaConfig - ค่า config ภายในของ dbatools เอง ---
Write-Host "`n=== Task 3: Get-DbaConfig ===" -ForegroundColor Cyan

Get-DbaConfig |
    Select-Object Name, Value, Type |
    Format-Table -AutoSize

# ตัวอย่างปรับพฤติกรรม dbatools:
#   Set-DbaConfig dbatools.ConnectionTimeout 15      # timeout ต่อ connection
#   Set-DbaConfig maxstringtruncate 2000             # จำกัดความยาวข้อความที่แสดง

# --- Task 4: Backup-DbaDatabase (preview ของการ backup ใน Section 3) ---
Write-Host "`n=== Task 4: Backup-DbaDatabase (preview) ===" -ForegroundColor Cyan

Write-Host "คำสั่งตัวอย่าง (ไม่รันในเดโมนี้ - จะใช้จริงใน Section 3):" -ForegroundColor Yellow
Write-Host "  Backup-DbaDatabase -SqlInstance $SqlInstance `"
Write-Host "      -Database AdventureWorks2025 -Type Full `"
Write-Host "      -BackupDirectory C:\SQLBackups -CompressionAlgorithm Default"
# dbatools จัดการรูปแบบชื่อไฟล์/timestamp/compression ให้โดย default

# --- Task 5: เทียบกับ SqlServer module ---
Write-Host "`n=== Task 5: เทียบเครื่องมือ ===" -ForegroundColor Cyan
Write-Host @'
งานเดียวกัน                    SqlServer module (ทางการ)        dbatools (ชุมชน)
--------------------------    -------------------------------  --------------------------
ดู service                    Get-Service *SQL* / Get-CimInstance  Get-DbaService
ดู database                   Get-ChildItem SQLSERVER:\SQL\...     Get-DbaDatabase
backup                        Backup-SqlDatabase               Backup-DbaDatabase
รัน query                     Invoke-Sqlcmd                    Invoke-DbaQuery
ตรวจการเชื่อมต่อ               Get-SqlInstance                  Test-DbaConnection

เลือกใช้: องค์กรต้องการ support ทางการ -> SqlServer module; งาน migration/inventory
ข้ามหลาย instance เยอะ ๆ -> dbatools สะดวกกว่ามาก อย่าใช้สองชุดปนกันในสคริปต์เดียว
'@

# --- ทดลองเอง ---
# 1) Test-DbaConnection -SqlInstance localhost - ดูผล (เวอร์ชัน, protocol, TDS version)
# 2) Get-DbaDbState / Set-DbaDbReadOnly ใช้ทำงานเดียวกับ Section 2 script 02 ด้วย dbatools
# 3) อ่านรายการ command ทั้งหมด: Get-Command -Module dbatools | Group-Object Verb | Sort Count -Descending
