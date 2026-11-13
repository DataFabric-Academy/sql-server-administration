# =============================================================================
# 01_View_Instance_Info.ps1 - อ่านข้อมูลและการตั้งค่า instance
# ใช้ Get-SqlInstance (SqlServer module) + SMO Server object + sys.configurations
# ปรับปรุงจากแนวทางคอร์ส 20764D (เดิมใช้ SQLPS)
# =============================================================================

param(
    [string]$ServerInstance = 'localhost'
)

Clear-Host

# --- Task 1: Get-SqlInstance - ข้อมูล instance แบบ cmdlet ทางการ ---
Write-Host "=== Task 1: Get-SqlInstance ===" -ForegroundColor Cyan

Get-SqlInstance -ServerInstance $ServerInstance |
    Select-Object Name, Version, Edition, ProductLevel, Collation,
                  IsIntegratedSecurityOnly, Processors, PhysicalMemory |
    Format-List

# เทียบเท่า T-SQL: SELECT SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('Edition'), ...

# --- Task 2: SMO Server object ผ่าน provider ---
Write-Host "`n=== Task 2: SMO Server ผ่าน SQLSERVER: drive ===" -ForegroundColor Cyan

$srv = Get-Item "SQLSERVER:\SQL\$($ServerInstance -replace '\\', '\')\DEFAULT" -ErrorAction SilentlyContinue
if (-not $srv) {
    # ถ้าเป็น named instance เช่น localhost\SQLEXPRESS ให้แก้ path ตรงนี้
    Write-Warning "ไม่พบ default instance - แก้ path SQLSERVER:\SQL\<host>\<instance> ให้ตรงเครื่องคุณ"
    return
}

$srv | Select-Object Name, ComputerNamePhysicalNetBIOS, VersionString, Edition,
                     IsClustered, RootDirectory, DefaultFile |
    Format-List

# --- Task 3: ค่า configuration ทั้งหมดผ่าน SMO ---
Write-Host "`n=== Task 3: SMO Configuration (ชุดเดียวกับ sys.configurations) ===" -ForegroundColor Cyan

$srv.Configuration |
    Select-Object MinServerMemory, MaxServerMemory, MaxDegreeOfParallelism,
                  CostThresholdForParallelism, RemoteAccess, DefaultTraceEnabled |
    Format-List

# ดูทุกค่า (หลายร้อยตัว): $srv.Configuration.Properties |
#     Select-Object DisplayName, ConfigValue, RunValue | Format-Table

# --- Task 4: อ่านค่าผ่าน T-SQL (เทียบเท่า Task 3) ---
Write-Host "`n=== Task 4: sys.configurations ผ่าน Invoke-Sqlcmd ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, value_in_use, value, description
            FROM sys.configurations
            WHERE name IN ('max server memory (MB)', 'min server memory (MB)',
                           'max degree of parallelism', 'cost threshold for parallelism')
            ORDER BY name;" |
    Format-Table -AutoSize

# --- Task 5: Get-SqlSmartAdmin - สถานะ Managed Backup to Azure (Smart Admin) ---
Write-Host "`n=== Task 5: Get-SqlSmartAdmin ===" -ForegroundColor Cyan

try {
    Get-SqlSmartAdmin -ServerInstance $ServerInstance -ErrorAction Stop |
        Select-Object BackupEnabled, BackupRetentionPeriodInDays,
                      @{N = 'Instance'; E = { $_.Parent.Name } } |
        Format-List
    # BackupEnabled = $false บน instance ปกติที่ไม่ได้เปิด Managed Backup to Microsoft Azure
}
catch {
    Write-Warning "Smart Admin อ่านไม่ได้: $($_.Exception.Message)"
}

# --- ทดลองเอง ---
# 1) inventory หลายเครื่อง: Get-SqlInstance -ServerInstance 'localhost','localhost,1434' ถ้ามี container ที่สอง
# 2) เขียนรายงาน CSV ของ sys.configurations ทั้งหมด (ใช้ Task 4 เปลี่ยน WHERE)
# 3) เทียบผล Task 3 กับหน้า Server Properties > Memory ของ SSMS
