# =============================================================================
# 04_Get_HotFix.ps1 - ตรวจประวัติ Windows Update ของเครื่อง (และเทียบกับ SQL Server build)
# Get-HotFix = cmdlet built-in บน Windows (ผ่าน WMI Win32_QuickFixEngineering)
# ใช้บริบท: เกิดเหตุ "server ช้า" หลังมีทีมอื่น patch เครื่อง / วางแผน patch window
# ข้อจำกัด: Windows เท่านั้น - บน SQL Server on Linux ใช้ apt/rpm ดู (ดูท้ายไฟล์)
# =============================================================================

param(
    [string[]]$ComputerName = @('localhost')   # ระยะไกลได้ถ้าเปิด WinRM เช่น 'SQL01','SQL02'
)

Clear-Host

# --- Task 1: hotfix ล่าสุด 10 รายการ ---
Write-Host "=== Task 1: 10 hotfix ล่าสุด ===" -ForegroundColor Cyan

Get-HotFix -ComputerName $ComputerName[0] |
    Sort-Object InstalledOn -Descending |
    Select-Object -First 10 HotFixID, Description, InstalledOn |
    Format-Table -AutoSize

# --- Task 2: เทียบวันติดตั้ง OS patch กับ build ของ SQL Server ---
Write-Host "`n=== Task 2: SQL Server build ปัจจุบัน ===" -ForegroundColor Cyan

$version = Invoke-Sqlcmd -ServerInstance 'localhost' -TrustServerCertificate `
    -Query "SELECT @@VERSION AS FullVersion,
                   SERVERPROPERTY('ProductVersion') AS ProductVersion,
                   SERVERPROPERTY('ProductLevel') AS ProductLevel,
                   SERVERPROPERTY('ProductUpdateLevel') AS ProductUpdateLevel;"
$version | Format-List

Write-Host "เทียบเลข build กับรายการเผยแพร่ทางการ:" -ForegroundColor Yellow
Write-Host "  https://learn.microsoft.com/sql/releases/sql-server-2025?view=sql-server-ver17"
Write-Host "OS patch ล่าสุด: $((Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn)"
# เป้าหมาย: รู้ว่า "เหตุการณ์เกิดหลัง patch เมื่อวัน X" เทียบเวลาได้จากสองรายงานนี้

# --- Task 3: ค้นหา hotfix เฉพาะตัว ---
Write-Host "`n=== Task 3: ค้นหา hotfix ===" -ForegroundColor Cyan

$kb = 'KB5044284'   # ตัวอย่าง - เปลี่ยนเป็น KB ที่สนใจ
$found = Get-HotFix -Id $kb -ErrorAction SilentlyContinue
if ($found) { $found | Select-Object HotFixID, Description, InstalledOn | Format-List }
else        { Write-Host "$kb ไม่พบบนเครื่องนี้" }

# --- Task 4: รายงานหลายเครื่องพร้อมกัน (ผ่าน WinRM) ---
Write-Host "`n=== Task 4: รายงานหลายเครื่อง ===" -ForegroundColor Cyan

foreach ($cn in $ComputerName) {
    try {
        $latest = Get-HotFix -ComputerName $cn -ErrorAction Stop |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1
        Write-Host ("{0,-20} patch ล่าสุด: {1} ({2})" -f $cn, $latest.HotFixID, $latest.InstalledOn)
    }
    catch {
        Write-Warning ("{0}: เข้าถึงไม่ได้ ({1})" -f $cn, $_.Exception.Message.Split([char]10)[0])
    }
}

# --- Task 5: (บริบท SQL Server) ดูว่า CU ล่าสุดติดตั้งเมื่อไร ---
Write-Host "`n=== Task 5: ตรวจ SQL Server service start time (หลัง patch) ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance 'localhost' -TrustServerCertificate `
    -Query "SELECT servicename, service_account,
                   last_startup_time, startup_type_desc, status_desc
            FROM sys.dm_server_services
            WHERE servicename LIKE 'SQL Server (%';" |
    Format-List

# --- บน Linux (SQL Server on Linux / container) ใช้แทน Get-HotFix ---
#   Ubuntu:   apt list --installed 2>/dev/null | grep mssql
#   RHEL:     rpm -qa --last | grep mssql
#   ประวัติ update OS: cat /var/log/apt/history.log  หรือ  dnf history
#   ผ่าน PowerShell remote: Invoke-Command -HostName <linux> -UserName <user> -ScriptBlock { ... }

# --- ทดลองเอง ---
# 1) เขียน function Get-SqlPatchReport ที่คืนรายงานเดียวรวม OS hotfix + SQL build ต่อ 1 เครื่อง
# 2) ทำ CSV รวมหลายเครื่องแล้วเปิดใน Excel เพื่อวางแผน patch window
