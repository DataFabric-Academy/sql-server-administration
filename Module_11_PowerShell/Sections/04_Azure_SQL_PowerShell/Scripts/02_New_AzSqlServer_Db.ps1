# =============================================================================
# 02_New_AzSqlServer_Db.ps1 - สร้าง Azure SQL logical server + database ด้วย Az module
# รวม: resource group, server พร้อม managed identity (-AssignIdentity),
#       firewall rule เปิด IP เครื่องคุณ, database edition Basic (ราคาต่ำสำหรับการเรียน)
# ค่าใช้จ่าย: database เก็บเงินรายชั่วโมง - ใช้เสร็จรัน 04_Cleanup_Az.ps1 ทันที
# =============================================================================

param(
    [string]$ResourceGroup = 'rg-sqladm-11',
    [string]$Location      = 'southeastasia',      # เปลี่ยนเป็น region ใกล้คุณ (Get-AzLocation)
    [string]$AdminLogin    = 'sqladmin2025',
    [string]$AdminPassword = 'Pa$$w0rd2025',       # รหัสผ่านห้องเรียนเท่านั้น
    [string]$DatabaseName  = 'sqladm11db',
    [string]$ClientIp      = ''                    # ใส่ public IP เครื่องคุณ (Task 2 ช่วยหาให้)
)

Clear-Host

# --- Task 1: ชื่อ server ต้อง unique ทั่วโลก ---
if (-not $script:ServerName) {
    $script:ServerName = "sqladm-$(Get-Random -Maximum 99999)"
    $script:ServerName = $script:ServerName.ToLower()
}
Write-Host "ชื่อ logical server ที่จะสร้าง: $script:ServerName.database.windows.net" -ForegroundColor Cyan

# --- Task 2: หา public IP ของเครื่องคุณอัตโนมัติ (สำหรับ firewall rule) ---
if (-not $ClientIp) {
    try {
        $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 10).ip
        Write-Host "ตรวจพบ public IP: $ClientIp" -ForegroundColor Green
    }
    catch {
        Write-Warning "หา IP ไม่ได้ ($($_.Exception.Message)) - ใส่ -ClientIp '<IP>' เองหรือแก้ตัวแปร"
        return
    }
}

# --- Task 3: สร้าง resource group ---
Write-Host "`n=== Task 3: New-AzResourceGroup ===" -ForegroundColor Cyan

New-AzResourceGroup -Name $ResourceGroup -Location $Location |
    Select-Object ResourceGroupName, Location |
    Format-List

# --- Task 4: สร้าง logical server + managed identity ---
Write-Host "`n=== Task 4: New-AzSqlServer (-AssignIdentity) ===" -ForegroundColor Cyan

$securePwd = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$adminCred = New-Object System.Management.Automation.PSCredential($AdminLogin, $securePwd)

$server = New-AzSqlServer `
    -ResourceGroupName $ResourceGroup `
    -ServerName $script:ServerName `
    -Location $Location `
    -ServerVersion '12.0' `
    -SqlAdministratorCredentials $adminCred `
    -AssignIdentity

Write-Host "สร้าง server แล้ว:" -ForegroundColor Green
$server | Select-Object ServerName, Location, ServerVersion |
    Format-List

Write-Host "Managed identity (system-assigned):" -ForegroundColor Green
$server.Identity | Select-Object Type, PrincipalId | Format-List
# PrincipalId นี้คือ identity ของ server ใน Microsoft Entra ID - ใช้ให้สิทธิ์กับ
# Azure Storage/Key Vault ฯลฯ โดยไม่เก็บ secret (ดู README ของ Section นี้)

# --- Task 5: เปิด firewall rule ให้ IP ของเครื่องคุณ ---
Write-Host "`n=== Task 5: New-AzSqlServerFirewallRule ===" -ForegroundColor Cyan

New-AzSqlServerFirewallRule `
    -ResourceGroupName $ResourceGroup `
    -ServerName $script:ServerName `
    -FirewallRuleName 'AllowMyIp' `
    -StartIpAddress $ClientIp `
    -EndIpAddress $ClientIp |
    Select-Object FirewallRuleName, StartIpAddress, EndIpAddress |
    Format-List

# หมายเหตุ: Azure SQL ปิดการเข้าถึงทุก IP โดย default - ถ้าไม่เปิด rule จะเชื่อมต่อไม่ได้
# ใน production: ใช้ Private Link/VNet rules ไม่ใช่ public IP whitelist

# --- Task 6: สร้าง database ---
Write-Host "`n=== Task 6: New-AzSqlDatabase ===" -ForegroundColor Cyan

$db = New-AzSqlDatabase `
    -ResourceGroupName $ResourceGroup `
    -ServerName $script:ServerName `
    -DatabaseName $DatabaseName `
    -Edition Basic

$db | Select-Object DatabaseName, Edition, Status, CurrentServiceObjectiveName |
    Format-List

# --- Task 7: สรุปข้อมูลการเชื่อมต่อ ---
Write-Host "`n=== ข้อมูลสำหรับเชื่อมต่อ (เก็บไว้ใช้ใน 03_Invoke_Sqlcmd_Azure.ps1) ===" -ForegroundColor Cyan
Write-Host @"
ServerInstance : $script:ServerName.database.windows.net
Database       : $DatabaseName
Username       : $AdminLogin
ResourceGroup  : $ResourceGroup
"@ -ForegroundColor Yellow

Write-Host "`nใช้เสร็จอย่าลืมลบ: .\04_Cleanup_Az.ps1 -ResourceGroup $ResourceGroup" -ForegroundColor Red

# --- ทดลองเอง ---
# 1) สร้าง database ระดับ vCore: New-AzSqlDatabase -Edition GeneralPurpose -Vcore 2 -ComputeGeneration Gen5 (ราคาสูงกว่ามาก - ระวัง)
# 2) เพิ่ม Entra admin: New-AzSqlServer... -ExternalAdminName / Set-AzSqlServerActiveDirectoryAdministrator
# 3) ดูทุก database ใน server: Get-AzSqlDatabase -ResourceGroupName $ResourceGroup -ServerName $script:ServerName
