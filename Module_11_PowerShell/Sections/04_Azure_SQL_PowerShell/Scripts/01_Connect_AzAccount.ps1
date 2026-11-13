# =============================================================================
# 01_Connect_AzAccount.ps1 - ติดตั้ง Az module เชื่อมต่อ Azure และตรวจ context
# ต้องมี Azure subscription (free tier ใช้ได้) - ตรวจสิทธิ์ด้วยแนวคิด least privilege
# =============================================================================

Clear-Host

# --- Task 1: ติดตั้ง Az module (ครั้งแรกครั้งเดียว - ข้ามได้ถ้าติดตั้งแล้ว) ---
# Az module ใหญ่ (ตัวอย่างจะติดตั้ง submodules หลายตัวรวม Az.Sql, Az.Resources)
# ถ้าต้องการเฉพาะ SQL ให้ติดตั้ง Az.Sql + Az.Accounts + Az.Resources พอ
if (-not (Get-Module Az.Accounts -ListAvailable)) {
    Write-Host "ยังไม่มี Az - ติดตั้ง Az module (อาจใช้เวลาสักครู่)" -ForegroundColor Yellow
    # Install-Module Az -Scope CurrentUser -Repository PSGallery -Force
    Write-Host "ยืนยันการติดตั้งด้วยตัวเองก่อน (คอมเมนต์บรรทัดข้างบน) หรือใช้ winget install Microsoft.Azure.PSModule"
}

# --- Task 2: เชื่อมต่อ Azure (เปิด browser ให้ล็อกอิน) ---
Write-Host "`n=== Task 2: Connect-AzAccount ===" -ForegroundColor Cyan

if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount            # interactive login
    # รูปแบบอื่นที่ควรรู้:
    #   Connect-AzAccount -Identity                  # managed identity (บน Azure VM)
    #   Connect-AzAccount -ServicePrincipal ...      # automation (เก็บ cert/secret ใน key vault)
}

# --- Task 3: ตรวจ context ปัจจุบัน ---
Write-Host "`n=== Task 3: Get-AzContext ===" -ForegroundColor Cyan

Get-AzContext |
    Select-Object Account, SubscriptionName, Subscription, Tenant, Environment |
    Format-List

# --- Task 4: เลือก subscription (ถ้ามีหลายตัว) ---
Write-Host "`n=== Task 4: รายการ subscription ที่เข้าถึงได้ ===" -ForegroundColor Cyan

Get-AzSubscription |
    Select-Object Name, Id, State |
    Format-Table -AutoSize

# ถ้าต้องเปลี่ยน: แก้ชื่อแล้วยกเลิกคอมเมนต์
# Set-AzContext -Subscription '<Subscription-Id>'

# --- Task 5: ทดสอบสิทธิ์ด้วยการอ่านทรัพยากร (least privilege check) ---
Write-Host "`n=== Task 5: ทดลองอ่านทรัพยากร ===" -ForegroundColor Cyan

try {
    $rgs = Get-AzResourceGroup -ErrorAction Stop
    Write-Host ("เข้าถึงได้ {0} resource group(s) ใน subscription นี้" -f $rgs.Count) -ForegroundColor Green
    $rgs | Select-Object ResourceGroupName, Location | Format-Table -AutoSize
}
catch {
    Write-Warning "อ่าน resource group ไม่ได้: $($_.Exception.Message)"
    Write-Host "ต้องมี role อย่างน้อย Reader ใน subscription (เรากำลังจะสร้างของ ต้องใช้ Contributor หรือ SQL Server Contributor)"
}

# --- ทดลองเอง ---
# 1) ดูรายการ region ทั้งหมด: Get-AzLocation | Select-Object Location | Sort-Object Location
# 2) ตรวจ quota/usage: Get-AzSqlUsage | Select-Object UsageName, CurrentValue, Limit
# 3) ลอง -Identity บน Azure VM ถ้ามี - สังเกตว่าไม่ต้องใส่ credential เลย
