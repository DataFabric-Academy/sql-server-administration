# =============================================================================
# 02_Pipeline_Basics.ps1 - พื้นฐาน pipeline: objects ไม่ใช่ข้อความ
# Where-Object / Sort-Object / Select-Object / Measure-Object / การเก็บผลเป็นไฟล์
# รันบน PowerShell 7+ ที่ติดตั้ง SqlServer module แล้ว
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$Database       = 'AdventureWorks2025'
)

Clear-Host

# --- Task 1: ข้อมูลจาก SQL Server ท่องผ่าน pipeline ได้เหมือนข้อมูลอื่น ---
Write-Host "=== Task 1: DB ใดที่ไฟล์ข้อมูลใหญ่กว่า 100 MB (เรียงตามขนาด) ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT name AS FileName, size * 8 / 1024 AS SizeMB
            FROM sys.master_files
            WHERE type = 0 AND database_id > 4" |
    Where-Object { $_.SizeMB -gt 100 } |
    Sort-Object SizeMB -Descending |
    Format-Table -AutoSize

# --- Task 2: Measure-Object - สรุปตัวเลขจาก pipeline ---
Write-Host "=== Task 2: ผลรวมขนาดไฟล์ข้อมูลทั้ง instance ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, size * 8 / 1024 AS SizeMB FROM sys.master_files WHERE type = 0" |
    Measure-Object -Property SizeMB -Sum -Maximum |
    Select-Object Count, Sum, Maximum |
    Format-Table -AutoSize

# --- Task 3: Group-Object - จัดกลุ่มนับ ---
Write-Host "=== Task 3: นับ database ตาม compatibility level ===" -ForegroundColor Cyan

Get-ChildItem SQLSERVER:\SQL\$ServerInstance\DEFAULT\Databases |
    Group-Object CompatibilityLevel |
    Select-Object Name, Count |
    Format-Table -AutoSize

# --- Task 4: Select-Object - เลือกคอลัมน์/แถว ---
Write-Host "=== Task 4: 5 ตารางใหญ่สุดใน $Database ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT TOP (5) s.name + '.' + t.name AS TableName,
                   SUM(p.rows) AS RowCount,
                   SUM(a.total_pages) * 8 / 1024 AS SizeMB
            FROM sys.tables AS t
            JOIN sys.schemas AS s ON s.schema_id = t.schema_id
            JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
            JOIN sys.allocation_units AS a ON a.container_id = p.hobt_id
            GROUP BY s.name, t.name
            ORDER BY SizeMB DESC" |
    Select-Object -First 5 TableName, RowCount, SizeMB |
    Format-Table -AutoSize

# --- Task 5: เก็บผลเป็นไฟล์ (CSV / JSON) ---
Write-Host "=== Task 5: export รายงานเป็นไฟล์ ===" -ForegroundColor Cyan

$report = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT name, compatibility_level, recovery_model_desc, state_desc
            FROM sys.databases WHERE database_id > 4"

$report | Export-Csv  "$env:TEMP\DbReport.csv"  -NoTypeInformation -Encoding UTF8
$report | ConvertTo-Json -Depth 2 | Out-File "$env:TEMP\DbReport.json" -Encoding UTF8

Write-Host "เขียนไฟล์แล้ว:" -ForegroundColor Green
Get-Item "$env:TEMP\DbReport.csv", "$env:TEMP\DbReport.json" |
    Select-Object Name, Length |
    Format-Table -AutoSize

# ดูเนื้อหา CSV
Get-Content "$env:TEMP\DbReport.csv" -TotalCount 4

# --- Task 6: ข้อผิดพลาดที่พบบ่อย ---
# (ก) ท่องต่อหลัง Format-Table แล้ว filter ไม่ได้:
#     ... | Format-Table | Where-Object {...}        <-- ผิด: เหลือไม่มีอะไรให้กรอง
# (ข) ใช้ select แบบ property ไม่มีใน object:
#     $_.sized                                       <-- พิมพ์ผิด จะได้ $null เงียบ ๆ
#     ใช้ Set-StrictMode -Version Latest ทดลองจะช่วยตรวจ
# --- Task 7: ทดลองเอง ---
# 1) เปลี่ยนเงื่อนไข Task 1 เป็น "ไฟล์ log ใหญ่กว่า 50 MB" (type = 1)
# 2) export Task 4 เป็น CSV แล้วเปิดใน Excel
