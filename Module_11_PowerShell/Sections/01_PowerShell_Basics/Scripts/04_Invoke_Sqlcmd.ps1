# =============================================================================
# 04_Invoke_Sqlcmd.ps1 - พื้นฐาน Invoke-Sqlcmd
# รัน T-SQL จาก PowerShell, ส่งค่าเข้า T-SQL อย่างปลอดภัย, เก็บผลออกไฟล์
# ต้องมี SqlServer module (Install-Module SqlServer)
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$Database       = 'AdventureWorks2025'
)

Clear-Host

# --- Task 1: query พื้นฐาน ---
Write-Host "=== Task 1: query เดี่ยว ===" -ForegroundColor Cyan

Invoke-Sqlcmd `
    -ServerInstance $ServerInstance `
    -Database       $Database `
    -TrustServerCertificate `
    -Query "SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version;"

# หมายเหตุ: -TrustServerCertificate จำเป็นเมื่อ instance ใช้ self-signed certificate
# (SqlServer module v22+ เปิด encryption โดย default) บน production ที่จริงให้
# ติดตั้ง certificate ที่ client trust แล้วใช้ encryption จริง

# --- Task 2: เก็บผลในตัวแปรแล้วใช้ต่อ ---
Write-Host "`n=== Task 2: เก็บผลเป็น object ===" -ForegroundColor Cyan

$result = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, compatibility_level, recovery_model_desc FROM sys.databases WHERE database_id > 4;"

Write-Host "จำนวนแถว: $($result.Count)"
Write-Host "แถวแรก: $($result[0].name) (compat level $($result[0].compatibility_level))"
$result | Format-Table name, recovery_model_desc -AutoSize

# --- Task 3: -Variable ส่งค่าเข้า T-SQL (แทนการแปะ string ด้วย PowerShell interpolation) ---
Write-Host "`n=== Task 3: ส่งพารามิเตอร์เข้า query ===" -ForegroundColor Cyan

$pattern = 'S%'                       # ลองเปลี่ยนเป็นค่าอื่น
# ใช้ single-quoted PowerShell string เพื่อให้ $(pattern) ไม่ถูก PowerShell แทรกก่อน
# (single quote คู่ '' ใน PowerShell string แปลเป็น ' หนึ่งตัวของ T-SQL)
$query = 'SELECT name FROM sys.databases WHERE name LIKE ''$(pattern)'';'
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query $query `
    -Variable "pattern=$pattern" |
    Format-Table -AutoSize

# สังเกต: -Variable ทำ sqlcmd-style substitution - ใน query อ้างด้วย $(ชื่อตัวแปร)
# ต้องใส่ single-quote รอบค่า string เองตามปกติของ T-SQL
# ค่าที่มาจาก user จริงควร validate/escape ก่อน หรือใช้ sp_executesql แบบมี parameter จริง

# --- Task 4: รันคำสั่ง DML/DDL (ไม่คืน result set) ---
Write-Host "`n=== Task 4: สร้าง-ลบตารางทดลอง (idempotent) ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "
    IF OBJECT_ID('dbo.InvokeSqlcmdDemo', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.InvokeSqlcmdDemo (Id int PRIMARY KEY, Note nvarchar(50));
        INSERT dbo.InvokeSqlcmdDemo (Id, Note) VALUES (1, N'สร้างจาก PowerShell');
    END
    SELECT Id, Note FROM dbo.InvokeSqlcmdDemo;"

# --- Task 5: รันสคริปต์ .sql ทั้งไฟล์ด้วย -InputFile (รองรับ GO / :r ฯลฯ) ---
Write-Host "`n=== Task 5: -InputFile ===" -ForegroundColor Cyan

$tempSql = Join-Path $env:TEMP 'sqladm_demo.sql'
@'
-- ไฟล์นี้รองรับ GO และ sqlcmd variables
SELECT DB_NAME() AS CurrentDb;
GO
SELECT COUNT(*) AS OrderHeaderRows FROM Sales.SalesOrderHeader;
'@ | Out-File $tempSql -Encoding UTF8

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Database $Database -InputFile $tempSql |
    Format-Table -AutoSize

Remove-Item $tempSql -ErrorAction SilentlyContinue

# --- Task 6: เก็บผลออกไฟล์ ---
Write-Host "`n=== Task 6: export เป็น CSV ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT TOP (5) name, size * 8 / 1024 AS SizeMB FROM sys.master_files
            WHERE type = 0 AND database_id > 4 ORDER BY size DESC" |
    Export-Csv "$env:TEMP\InvokeSqlcmdTop5.csv" -NoTypeInformation -Encoding UTF8
Get-Content "$env:TEMP\InvokeSqlcmdTop5.csv"

# --- Task 7: error handling แบบ script จริง ---
Write-Host "`n=== Task 7: จัดการ error ===" -ForegroundColor Cyan

try {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
        -Query "SELECT * FROM dbo.TableThatDoesNotExist;" -ErrorAction Stop
}
catch {
    Write-Warning "query ล้ม: $($_.Exception.Message.Split([char]10)[0])"
    # ในสคริปต์จริงอาจ log ลงไฟล์ / ส่ง notification / ตัดสินใจ retry
}

# --- ทดลองเอง ---
# 1) ใช้ -Variable รับชื่อ schema จาก user แล้วรายงานตารางใน schema นั้น
# 2) เขียน loop foreach ($db in $result) { Invoke-Sqlcmd ... -Query "..." } รายงานต่อ database
# 3) เทียบกับ sqlcmd.exe: sqlcmd -S localhost -E -Q "SELECT @@VERSION" (ต้องมี mssql-tools)
