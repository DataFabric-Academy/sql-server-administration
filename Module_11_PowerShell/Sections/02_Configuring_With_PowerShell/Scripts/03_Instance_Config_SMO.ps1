# =============================================================================
# 03_Instance_Config_SMO.ps1 - เปลี่ยน instance configuration ด้วย SMO Configuration object
# ปรับปรุงจาก Old/Labfiles/Lab11/Starter/ChangeServerSettings.ps1.txt (คอร์ส 20764D)
#   เดิม: แก้ $server.Settings.LoginMode และ $server.UserOptions (AnsiNulls/AnsiPadding/...)
#   ใหม่: SqlServer module; เน้น Configuration (max/min server memory ฯลฯ) พร้อมย้อนกลับ
#         LoginMode ต้อง restart instance จึงเห็นผล - ตรวจสอบอย่างเดียวโดยไม่เปลี่ยน (อยู่ท้ายไฟล์)
# =============================================================================

param(
    [string]$ServerInstance = 'localhost'
)

Clear-Host
Import-Module SqlServer

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance

# --- Task 1: ดู Configuration object ทั้งก้อน ---
Write-Host "=== Task 1: Configuration properties ที่ใช้บ่อย ===" -ForegroundColor Cyan

$cfg = $srv.Configuration
$cfg |
    Select-Object MinServerMemory, MaxServerMemory,
                  MaxDegreeOfParallelism, CostThresholdForParallelism,
                  FillFactor, DefaultTraceEnabled |
    Format-List

# สังเกต: ConfigValue = ค่าที่ตั้งไว้ (ยังไม่ RECONFIGURE), RunValue = ค่าที่ engine ใช้จริง

# --- Task 2: เปลี่ยน max server memory -> ตรวจ -> ย้อนกลับ ---
Write-Host "`n=== Task 2: max server memory (บันทึกค่าเดิม เปลี่ยน ย้อน) ===" -ForegroundColor Cyan

$originalMax = $cfg.MaxServerMemory.ConfigValue
Write-Host "ค่าเดิม: $originalMax MB"

# เปลี่ยนเป็น 4096 MB (แนะนำให้เหลือ RAM 4-8 GB สำหรับ OS ในที่จริง)
$cfg.MaxServerMemory.ConfigValue = 4096
$cfg.Alter()
Write-Host "Alter() แล้ว - เทียบเท่า: EXEC sp_configure 'max server memory (MB)', 4096; RECONFIGURE;"

# ยืนยันผลด้วย T-SQL (อ่านจาก sys.configurations)
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations
            WHERE name = 'max server memory (MB)';" |
    Format-Table -AutoSize

# ย้อนกลับค่าเดิม
$cfg.MaxServerMemory.ConfigValue = $originalMax
$cfg.Alter()
Write-Host ("ย้อนกลับเป็น {0} MB แล้ว" -f $cfg.MaxServerMemory.ConfigValue) -ForegroundColor Green

# --- Task 3: เปลี่ยน min server memory (เหมาะกับ instance จำนวนมากต่อเครื่อง) ---
Write-Host "`n=== Task 3: min server memory (ลองตั้ง 0 = default) ===" -ForegroundColor Cyan

$originalMin = $cfg.MinServerMemory.ConfigValue
Write-Host "ค่าเดิม: $originalMin MB  (0 = engine จัดการเอง - ค่าปกติของระบบเดี่ยว)"

# --- Task 4: UserOptions - ค่า SET ต่อ connection ที่จะสืบทอดให้ทุก session ใหม่ ---
Write-Host "`n=== Task 4: UserOptions (จาก ChangeServerSettings.ps1 เดิม) ===" -ForegroundColor Cyan

$uo = $srv.UserOptions
$uo |
    Select-Object AnsiNulls, AnsiPadding, AnsiWarnings, QuotedIdentifier,
                  AbortOnArithmeticErrors, NoCount |
    Format-List

# เดิมคอร์ส 20764D เปิด AnsiNulls/AnsiPadding/AnsiWarnings/QuotedIdentifier แล้ว Alter()
# ในระบบปัจจุบันค่าเหล่านี้ปกติเป็น ON อยู่แล้วตาม default ของ model database
# จึงแสดงการตรวจแทนการเปลี่ยน - เปลี่ยนได้ด้วยรูปแบบเดียวกับ Configuration:
#   $uo.AnsiWarnings = $true; $uo.Alter()

# --- Task 5: LoginMode - อ่านอย่างเดียว (เปลี่ยนแล้วต้อง restart จึงมีผล) ---
Write-Host "`n=== Task 5: โหมด authentication (อ่านอย่างเดียว) ===" -ForegroundColor Cyan

Write-Host ("LoginMode = {0} (Integrated=Windows เท่านั้น, Mixed=รองรับ SQL auth)" -f $srv.Settings.LoginMode)

# เทียบเท่า T-SQL:
#   SELECT CASE WHEN SERVERPROPERTY('IsIntegratedSecurityOnly') = 1 THEN 'Integrated' ELSE 'Mixed' END;
# เปลี่ยนได้ด้วย (ต้อง restart SQL Server service ทันทีหลัง Alter จึงใช้ได้):
#   $srv.Settings.LoginMode = [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed
#   $srv.Settings.Alter()
# หรือใช้ cmdlet พร้อมใช้: Set-SqlAuthenticationMode -Credential ... -Mode Mixed -ForceServiceRestart

# --- ทดลองเอง ---
# 1) เขียนฟังก์ชัน Set-SqlConfig -Name -Value ที่ห่อ sp_configure ผ่าน Invoke-Sqlcmd แล้วคืนค่าเดิม
# 2) เปลี่ยน CostThresholdForParallelism จาก 5 เป็น 40 (แนวทางปัจจุบัน) แล้วเก็บ log ลงไฟล์ก่อน-หลัง
