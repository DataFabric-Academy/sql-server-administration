-- ============================================================================
-- Module 14 - Section 3 - Script 02: bcp export + import ผ่าน PowerShell
-- ปรับจาก: Microsoft 20764D Mod15 "bcp.txt" + Lab15 Exercise 2
-- รันได้บน: PowerShell 7 (pwsh) หรือ PowerShell 5.1, มี bcp จาก mssql-tools18
-- วิธีรัน:
--   pwsh .\02_bcp_Export_Import.ps1 -Server "localhost" -BcpDir "D:\bcp"
-- สิ่งที่ทำ:
--   1) เตรียมตาราง Lab.CurrencyImport (T-SQL ผ่าน Invoke-Sqlcmd)
--   2) bcp queryout  - export ผล query เป็น CSV
--   3) bcp format nul -x - สร้าง XML format file จากโครงตาราง
--   4) bcp in        - import กลับเข้าตารางด้วย format file
--   5) ตรวจผล + ลบไฟล์ชั่วคราว (Cleanup ในตัว)
-- ============================================================================
param(
    [string]$Server  = "localhost",
    [string]$Database = "AdventureWorks2025",
    [string]$BcpDir   = "D:\bcp"     # โฟลเดอร์เก็บไฟล์ชั่วคราว (ต้องมีอยู่แล้ว)
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Step 0: ตรวจ bcp และสร้างโฟลเดอร์ปลายทาง
# ----------------------------------------------------------------------------
if (-not (Get-Command bcp -ErrorAction SilentlyContinue)) {
    Write-Error "หา bcp ไม่เจอ — ติดตั้ง mssql-tools18 (SQL Server command line utilities) ก่อน"
}
New-Item -ItemType Directory -Force -Path $BcpDir | Out-Null

$ExportFile = Join-Path $BcpDir "currency_export.csv"
$FormatFile = Join-Path $BcpDir "currency_import_fmt.xml"

Write-Host "== bcp version =="
bcp -v

# ----------------------------------------------------------------------------
# Step 1: เตรียมตารางปลายทาง (idempotent)
# ----------------------------------------------------------------------------
Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query @"
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
IF OBJECT_ID('Lab.CurrencyImport','U') IS NULL
BEGIN
    CREATE TABLE Lab.CurrencyImport (
        CurrencyCode char(3)       NOT NULL PRIMARY KEY,
        CurrencyName nvarchar(100) NOT NULL,
        ModifiedDate datetime      NULL
    );
END
ELSE
    TRUNCATE TABLE Lab.CurrencyImport;
"@

# ----------------------------------------------------------------------------
# Step 2: bcp queryout — export ผล query (ไม่ต้องทั้งตาราง) เป็น CSV
# หมายเหตุ: -T = Windows integrated auth
#           ถ้าใช้ Entra ID ให้แทนด้วย -G (SQL Server 2022+ / Azure SQL)
#           ถ้าใช้ SQL auth ให้แทนด้วย -U sa -P 'Pa$$w0rd2025'
# ----------------------------------------------------------------------------
Write-Host "== bcp queryout (export) =="
bcp "SELECT CurrencyCode, Name FROM Production.Currency ORDER BY CurrencyCode" `
    queryout $ExportFile -t, -c -S $Server -d $Database -T

# ----------------------------------------------------------------------------
# Step 3: bcp format nul -x — สร้าง XML format file จากโครงตารางปลายทาง
# ----------------------------------------------------------------------------
Write-Host "== bcp format nul (XML format file) =="
bcp Lab.CurrencyImport format nul -f $FormatFile -x -c -t, -r \n -S $Server -d $Database -T

Write-Host "== เนื้อหา format file =="
Get-Content $FormatFile

# ----------------------------------------------------------------------------
# Step 4: bcp in — import ไฟล์เข้าตารางโดยอ้าง format file
# ----------------------------------------------------------------------------
Write-Host "== bcp in (import) =="
bcp Lab.CurrencyImport in $ExportFile -f $FormatFile -b 100 -S $Server -d $Database -T

# ----------------------------------------------------------------------------
# Step 5: ตรวจผล + เก็บแถวตัวอย่าง
# ----------------------------------------------------------------------------
Write-Host "== ตรวจผล import =="
Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query "
    SELECT COUNT(*) AS ImportedRows FROM Lab.CurrencyImport;
" | Format-List

# ----------------------------------------------------------------------------
# Cleanup: ลบไฟล์ชั่วคราว (comment ออกถ้าต้องการเก็บไว้ดู)
# ----------------------------------------------------------------------------
# Remove-Item $ExportFile, $FormatFile -ErrorAction SilentlyContinue
Write-Host "เสร็จสิ้น — ไฟล์อยู่ที่ $ExportFile และ $FormatFile"
