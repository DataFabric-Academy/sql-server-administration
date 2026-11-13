# =============================================================================
# 02_Change_Database_Options.ps1 - เปลี่ยน database options ด้วย SMO แล้วย้อนกลับ
# ปรับปรุงจาก Old/Labfiles/Lab11/Starter/ChangeProperties.ps1.txt (คอร์ส 20764D)
#   เดิม: Import-Module SQLPS; แก้ AdventureWorks2016 (CompatibilityLevel/AnsiNulls/
#         AutoShrink/ReadOnly/RecoveryModel)
#   ใหม่: SqlServer module + PowerShell 7; สร้าง database ทดลอง LabEnv เอง
#         (ไม่ไปแตะ AdventureWorks2025) เปลี่ยนแบบ "บันทึกค่าเดิม -> เปลี่ยน -> ย้อน"
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$DatabaseName   = 'LabEnv'      # database ทดลอง - สคริปต์สร้างให้เอง
)

Clear-Host
Import-Module SqlServer

# --- Task 1: สร้าง database ทดลองถ้ายังไม่มี (idempotent) ---
Write-Host "=== Task 1: เตรียม database $DatabaseName ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database master `
    -Query "IF DB_ID(N'$DatabaseName') IS NULL
            BEGIN
                CREATE DATABASE $DatabaseName;   -- SIMPLE recovery model ตาม default ของ model
            END
            SELECT name, recovery_model_desc FROM sys.databases WHERE name = N'$DatabaseName';"

# --- Task 2: ดึง Database object ผ่าน provider แล้วดูค่าปัจจุบัน ---
Write-Host "`n=== Task 2: ดูค่าปัจจุบันของ $DatabaseName ===" -ForegroundColor Cyan

Set-Location SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases
$db = Get-Item $DatabaseName

Write-Host "--- Properties ระดับ database ---" -ForegroundColor Yellow
$db | Select-Object Name, RecoveryModel, CompatibilityLevel, CreateDate, Collation |
    Format-List

Write-Host "--- DatabaseOptions ---" -ForegroundColor Yellow
$db.DatabaseOptions |
    Select-Object AutoShrink, AutoClose, ReadOnly, AnsiNullsEnabled,
                  AutoUpdateStatistics, PageVerify |
    Format-List

# --- Task 3: เปิด READ_ONLY แล้วตรวจผล (จาก Lab เดิม: ReadOnly = $true) ---
Write-Host "`n=== Task 3: เปิด READ_ONLY ===" -ForegroundColor Cyan

$db.DatabaseOptions.ReadOnly = $true
$db.Alter()
Write-Host "เรียก .Alter() แล้ว - SMO ยื่น ALTER DATABASE ... SET READ_ONLY ให้เรียบร้อย"

# ตรวจผล - ดึง object ใหม่เสมอหลัง Alter เพื่อไม่อ่านค่า cache เก่า
$dbFresh = Get-Item SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases\$DatabaseName
Write-Host ("ReadOnly = {0}" -f $dbFresh.DatabaseOptions.ReadOnly) -ForegroundColor Green

# สาธิตผลข้างเคียง: พยายามเขียนข้อมูลขณะ READ_ONLY (ต้อง error 3906)
try {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $DatabaseName `
        -Query "CREATE TABLE dbo.TestWrite (Id int);" -ErrorAction Stop
}
catch {
    Write-Warning "เขียนไม่ได้ขณะ READ_ONLY (คาดหวังไว้): $($_.Exception.Message.Split([char]10)[0])"
}

# --- Task 4: ย้อนกลับเป็น READ_WRITE ---
Write-Host "`n=== Task 4: ย้อนกลับ READ_WRITE ===" -ForegroundColor Cyan

$db.DatabaseOptions.ReadOnly = $false
$db.Alter()
(Get-Item SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases\$DatabaseName).DatabaseOptions.ReadOnly

# --- Task 5: เปลี่ยน RecoveryModel (จาก Lab เดิม) แล้วย้อน ---
Write-Host "`n=== Task 5: RecoveryModel SIMPLE -> FULL -> SIMPLE ===" -ForegroundColor Cyan

$origModel = (Get-Item SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases\$DatabaseName).RecoveryModel
Write-Host "ค่าเดิม: $origModel"

# เปลี่ยนเป็น FULL (SMO enum) - เทียบเท่า ALTER DATABASE ... SET RECOVERY FULL
$db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full
$db.Alter()
Write-Host ("ตอนนี้: {0}" -f (Get-Item SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases\$DatabaseName).RecoveryModel) -ForegroundColor Green

# ย้อนกลับค่าเดิม
$db.RecoveryModel = $origModel
$db.Alter()

# --- Task 6: ปรับ best-practice options (ค่าที่ควรตั้งในระบบจริง) ---
Write-Host "`n=== Task 6: ตั้ง best practice (ปิด AutoShrink/AutoClose เสมอ) ===" -ForegroundColor Cyan

$db.DatabaseOptions.AutoShrink = $false        # ควร OFF ทุก database เสมอ
$db.DatabaseOptions.AutoClose  = $false        # ควร OFF บน server ปกติ
$db.DatabaseOptions.PageVerify = 'Checksum'    # SET PAGE_VERIFY CHECKSUM
$db.Alter()
(Get-Item SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases\$DatabaseName).DatabaseOptions |
    Select-Object AutoShrink, AutoClose, PageVerify |
    Format-List

# --- Clean-up (optional) ---
# จบทดลองถ้าต้องการลบ database ทดลอง:
# Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database master `
#     -Query "IF DB_ID(N'$DatabaseName') IS NOT NULL ALTER DATABASE $DatabaseName SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
#             IF DB_ID(N'$DatabaseName') IS NOT NULL DROP DATABASE $DatabaseName;"

# --- ทดลองเอง ---
# 1) เปลี่ยน AutoUpdateStatistics เป็น $true (ถ้ายังไม่เป็น) แล้วดู T-SQL ที่ SMO ยื่นจริง:
#    ตรวจจาก sys.dm_exec_query_stats/Extended Events หรือตั้ง $srv.ConnectionContext.CapturedSql
# 2) ทำรายงาน "database ไหน AutoShrink เปิดอยู่" ทั้ง instance ด้วย Get-ChildItem + Where-Object
