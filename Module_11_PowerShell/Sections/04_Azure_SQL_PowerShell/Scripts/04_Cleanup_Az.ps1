# =============================================================================
# 04_Cleanup_Az.ps1 - ลบทรัพยากร Azure ที่สร้างไว้ใน Section นี้ (ลบ resource group ทีเดียวจบ)
# สำคัญ: Azure SQL Database เก็บเงินรายชั่วโมง - ใช้เสร็จลบทันที
# =============================================================================

param(
    [string]$ResourceGroup = 'rg-sqladm-11'
)

Clear-Host

# --- Task 1: ตรวจว่า resource group มีอะไรอยู่ในนั้นก่อนลบ ---
Write-Host "=== Task 1: ทรัพยากรที่จะถูกลบ ===" -ForegroundColor Cyan

$resources = Get-AzResource -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if (-not $resources) {
    Write-Host "ไม่พบ resource group $ResourceGroup (อาจลบไปแล้ว) - จบการทำงาน"
    return
}

$resources | Select-Object Name, ResourceType, Location | Format-Table -AutoSize

# --- Task 2: ยืนยันก่อนลบ (ป้องกันพิมพ์ชื่อผิดแล้วลบของอื่น) ---
Write-Host "`nจะลบ resource group '$ResourceGroup' พร้อมทุกทรัพยากรข้างใน" -ForegroundColor Red

$answer = Read-Host "พิมพ์ YES เพื่อยืนยันลบ"
if ($answer -ne 'YES') {
    Write-Host "ยกเลิก - ไม่ลบอะไร"
    return
}

# --- Task 3: ลบ ---
Write-Host "`n=== Task 3: Remove-AzResourceGroup ===" -ForegroundColor Cyan

Remove-AzResourceGroup -Name $ResourceGroup -Force
Write-Host "ส่งคำสั่งลบแล้ว (การลบจริงใช้เวลา 1-5 นาที)" -ForegroundColor Green

# --- Task 4: ตรวจว่าหายแล้ว ---
Write-Host "`n=== Task 4: ตรวจผล ===" -ForegroundColor Cyan

Start-Sleep -Seconds 20
$left = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if ($left -and $left.ProvisioningState -ne 'Deleting') {
    Write-Warning "ยังเห็น resource group อยู่ (ProvisioningState: $($left.ProvisioningState)) - ตรวจใน portal.azure.com"
}
else {
    Write-Host "ลบเรียบร้อย - ไม่มีค่าใช้จ่ายต่อจากนี้" -ForegroundColor Green
}

# --- ทดลองเอง ---
# 1) ลบเฉพาะ database เดียวโดยเก็บ server: Remove-AzSqlDatabase -ResourceGroupName ... -ServerName ... -DatabaseName ...
# 2) ตั้ง resource group lock กันลบ (production): New-AzResourceLock -LockName DoNotDelete -LockLevel CanNotDelete
