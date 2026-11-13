# =============================================================================
# 04_sp_configure_InvokeSqlcmd.ps1 - จัดการ instance settings ด้วย sp_configure ผ่าน Invoke-Sqlcmd
# รูปแบบ T-SQL-first: เหมาะกับ config ที่ไม่มี SMO property / วนหลาย server / มีรายชื่อจากตาราง
# เดโมด้วย 'cost threshold for parallelism' (แล็บใช้ 'max server memory (MB)')
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [int]   $NewCostThreshold = 40        # default ของ SQL Server คือ 5 (ล้าสมัย)
)

Clear-Host

# --- Task 1: เปิด advanced options (จำเป็นกับ config บางตัว) ---
Write-Host "=== Task 1: show advanced options ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;"

# --- Task 2: อ่านค่าปัจจุบัน (สองวิธี) ---
Write-Host "`n=== Task 2: อ่านค่า cost threshold for parallelism ===" -ForegroundColor Cyan

# วิธี (ก) sp_configure ไม่ใส่ค่า = รายงานค่าเดิม
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "EXEC sp_configure 'cost threshold for parallelism';" |
    Format-Table name, config_value, run_value -AutoSize

# วิธี (ข) sys.configurations (แนะนำ - อ่านเป็น result set ตารางได้ตรง)
$row = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT value_in_use AS CurrentValue FROM sys.configurations
            WHERE name = 'cost threshold for parallelism';"
$original = [int]$row.CurrentValue
Write-Host "ค่าเดิม: $original" -ForegroundColor Green

# --- Task 3: เปลี่ยนค่า + RECONFIGURE ---
Write-Host "`n=== Task 3: เปลี่ยนเป็น $NewCostThreshold ===" -ForegroundColor Cyan

# จุดสังเกต: ใช้ -Variable (sqlcmd substitution $(ชื่อ)) แทนการแปะ string ลง query
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query 'EXEC sp_configure ''cost threshold for parallelism'', $(NewCostThreshold); RECONFIGURE;' `
    -Variable "NewCostThreshold=$NewCostThreshold"

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations
            WHERE name = 'cost threshold for parallelism';" |
    Format-Table -AutoSize

# --- Task 4: วนแก้หลาย config จากรายการ (pattern ที่ใช้ได้กับหลาย instance) ---
Write-Host "`n=== Task 4: ปรับ config ชุดตามรายการ (ไม่ย้อนอัตโนมัติ - ตั้งใจใช้กับ baseline) ===" -ForegroundColor Cyan

# ค่า baseline ที่แนะนำโดยทั่วไป (ปรับตามองค์กร/รุ่นเซิร์ฟเวอร์ของคุณ)
$baseline = [ordered]@{
    'cost threshold for parallelism' = 40
    'max degree of parallelism'      = 8      # ปรับตามจำนวน core / workload
    'optimize for ad hoc workloads'  = 1      # ลด plan cache bloat (SQL Server 2008+)
}

foreach ($name in $baseline.Keys) {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
        -Query 'EXEC sp_configure ''$(CfgName)'', $(Val); RECONFIGURE;' `
        -Variable "CfgName=$name", "Val=$($baseline[$name])"
    Write-Host ("  ตั้ง {0} = {1}" -f $name, $baseline[$name]) -ForegroundColor Green
}

# --- Task 5: ย้อนกลับ cost threshold (ให้เครื่องทดลองกลับเท่าเดิม) ---
Write-Host "`n=== Task 5: ย้อน cost threshold กลับ $original ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query 'EXEC sp_configure ''cost threshold for parallelism'', $(Original); RECONFIGURE;' `
    -Variable "Original=$original"

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, value_in_use FROM sys.configurations
            WHERE name = 'cost threshold for parallelism';" |
    Format-Table -AutoSize

# --- ข้อควรระวัง ---
# - sp_configure ที่จำเป็นต้อง restart เช่น 'max server memory (MB)' กับบาง config
#   จะแสดง run_value ยังเก่า (คำเตือน "Run the RECONFIGURE statement" หรือ restart notice)
# - RECONFIGURE บางตัวต้อง RECONFIGURE WITH OVERRIDE (เช่น common criteria compliance enabled)
# - config สำคัญระดับ production ให้เก็บค่าเดิมลง CMDB/ไฟล์ log ก่อนเปลี่ยนเสมอ

# --- ทดลองเอง ---
# 1) รายงาน config ที่ต่างจากค่า default: ใช้หัวข้อ documentation 'Setting Server Configuration Options'
# 2) ทำ script รับชื่อ server หลายตัว (foreach) แล้วปรับ baseline ทั้งชุดเทียบกัน
