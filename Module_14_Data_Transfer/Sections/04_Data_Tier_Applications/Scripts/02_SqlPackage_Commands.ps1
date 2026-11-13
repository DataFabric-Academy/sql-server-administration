<#
.SYNOPSIS
    Module 14 - Section 4 - Script 02: คำสั่ง SqlPackage สำหรับ dacpac/bacpac
    (ปรับจากแนวทาง Mod15 เดิม ที่ใช้ SSMS wizard ล้วน มาเป็น CLI สมัยใหม่)

.DESCRIPTION
    ทำงานเป็น 4 ขั้น:
      1) Extract  schema จาก database FixedAssets  -> fixedassets_1.0.0.dacpac
      2) Publish  dacpac ไปสร้าง database ใหม่     -> FixedAssets_Deployed
      3) Export   database เป็น bacpac (schema+ข้อมูล)
      4) Import   bacpac กลับเป็น database ใหม่    -> FixedAssets_FromBacpac
    Cleanup: ลบ database ปลายทาง (uncomment ส่วนท้าย)

.NOTES
    ต้องมี SqlPackage — ดาวน์โหลด: https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage
    หรือมากับ SSMS (โฟลเดอร์ Common7\IDE\Extensions\Microsoft\SQLDB\DAC ของ Visual Studio)
    แนะนำติดตั้งเป็น dotnet tool: dotnet tool install -g microsoft.sqlpackage
#>
param(
    [string]$Server   = "localhost",
    [string]$DacDir   = "D:\dac"     # โฟลเดอร์เก็บไฟล์ dacpac/bacpac (ต้องมีอยู่แล้ว)
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Step 0: ตรวจ SqlPackage
# ----------------------------------------------------------------------------
if (-not (Get-Command sqlpackage -ErrorAction SilentlyContinue)) {
    Write-Error "หา sqlpackage ไม่เจอ — ติดตั้งด้วย: dotnet tool install -g microsoft.sqlpackage"
}
sqlpackage /Version

New-Item -ItemType Directory -Force -Path $DacDir | Out-Null

# ----------------------------------------------------------------------------
# Step 1: Extract — ดึง schema จาก database FixedAssets เป็น dacpac เวอร์ชัน 1.0.0
# ----------------------------------------------------------------------------
Write-Host "== Extract dacpac =="
sqlpackage /Action:Extract `
    /SourceServerName:$Server `
    /SourceDatabaseName:FixedAssets `
    /TargetFile:"$DacDir\fixedassets_1.0.0.dacpac" `
    /p:DacApplicationName=FixedAssets `
    /p:DacVersion=1.0.0

Get-Item "$DacDir\fixedassets_1.0.0.dacpac" | Format-List Name, Length, LastWriteTime

# ----------------------------------------------------------------------------
# Step 2: Publish — deploy dacpac ไปสร้าง database ใหม่
# หมายเหตุ: /p:BlockOnPossibleDataLoss=true เป็นเกราะกันการ deploy ที่อาจเสียข้อมูล
#           /p:CreateNewDatabase=true บังคับสร้างใหม่เสมอ (เอาออกถ้าต้องการ incremental)
# ----------------------------------------------------------------------------
Write-Host "== Publish ไป database ใหม่ =="
sqlpackage /Action:Publish `
    /SourceFile:"$DacDir\fixedassets_1.0.0.dacpac" `
    /TargetServerName:$Server `
    /TargetDatabaseName:FixedAssets_Deployed `
    /p:CreateNewDatabase=true `
    /p:BlockOnPossibleDataLoss=true

# ตรวจผลด้วย Invoke-Sqlcmd (SqlServer module)
Invoke-Sqlcmd -ServerInstance $Server -Database FixedAssets_Deployed -Query "
    SELECT t.name AS TableName, SUM(p.rows) AS RowCount_
    FROM sys.tables AS t
    JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0,1)
    GROUP BY t.name ORDER BY t.name;" | Format-Table

# ----------------------------------------------------------------------------
# Step 3: Export — bacpac (schema + ข้อมูล) สำหรับย้ายทั้ง database
# ----------------------------------------------------------------------------
Write-Host "== Export bacpac =="
sqlpackage /Action:Export `
    /SourceServerName:$Server `
    /SourceDatabaseName:FixedAssets `
    /TargetFile:"$DacDir\fixedassets.bacpac"

# ----------------------------------------------------------------------------
# Step 4: Import — กู้ bacpac เป็น database ใหม่
# ----------------------------------------------------------------------------
Write-Host "== Import bacpac =="
sqlpackage /Action:Import `
    /SourceFile:"$DacDir\fixedassets.bacpac" `
    /TargetServerName:$Server `
    /TargetDatabaseName:FixedAssets_FromBacpac

# ----------------------------------------------------------------------------
# (Optional) Upgrade in-place — หลังแก้ schema ของ FixedAssets (เพิ่มคอลัมน์)
# 1) แก้ schema: รัน T-SQL เพิ่มคอลัมน์ Asset.FixedAsset.SerialNumber
# 2) Extract เวอร์ชันใหม่ 1.1.0
# 3) Publish เวอร์ชันใหม่ทับ database เดิม (incremental update)
# ----------------------------------------------------------------------------
# ALTER TABLE Asset.FixedAsset ADD SerialNumber nvarchar(60) NULL;
#
# sqlpackage /Action:Extract /SourceServerName:$Server /SourceDatabaseName:FixedAssets `
#     /TargetFile:"$DacDir\fixedassets_1.1.0.dacpac" /p:DacApplicationName=FixedAssets /p:DacVersion=1.1.0
#
# sqlpackage /Action:Publish /SourceFile:"$DacDir\fixedassets_1.1.0.dacpac" `
#     /TargetServerName:$Server /TargetDatabaseName:FixedAssets_Deployed
#
# -- ตรวจเวอร์ชันที่ register ไว้ (ถ้า register ผ่าน SSMS wizard):
# SELECT instance_name, type_version, date_created FROM msdb.dbo.sysdac_instances;

# ----------------------------------------------------------------------------
# Cleanup — ลบ database ปลายทางเมื่อจบการทดลอง (เอา comment ออกเมื่อต้องการ)
# ----------------------------------------------------------------------------
# Invoke-Sqlcmd -ServerInstance $Server -Query "
#     IF DB_ID('FixedAssets_Deployed')   IS NOT NULL DROP DATABASE FixedAssets_Deployed;
#     IF DB_ID('FixedAssets_FromBacpac') IS NOT NULL DROP DATABASE FixedAssets_FromBacpac;"
# Remove-Item "$DacDir\fixedassets_1.0.0.dacpac", "$DacDir\fixedassets.bacpac" -ErrorAction SilentlyContinue
