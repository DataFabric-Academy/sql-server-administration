# =============================================================================
# 03_Invoke_Sqlcmd_Azure.ps1 - ใช้ SqlServer module เดิมกับ Azure SQL Database
# ประเด็น: cmdlet/SMO ชุดเดียวกับ on-premises ใช้ได้กับ *.database.windows.net
#          ของที่ไม่มี: BACKUP/RESTORE DATABASE, instance-level sp_configure
# รันหลังจาก 02_New_AzSqlServer_Db.ps1 สร้าง server แล้ว (แก้ค่าพารามิเตอร์ให้ตรง)
# =============================================================================

param(
    [string]$ServerFqdn   = 'sqladm-xxxxx.database.windows.net',  # แก้จาก output ของ Task 7 สคริปต์ 02
    [string]$DatabaseName = 'sqladm11db',
    [string]$AdminLogin   = 'sqladmin2025',
    [string]$AdminPassword = 'Pa$$w0rd2025'     # รหัสผ่านห้องเรียนเท่านั้น
)

Clear-Host

# --- Task 1: เชื่อมต่อและตรวจเวอร์ชัน ---
Write-Host "=== Task 1: SELECT @@VERSION ผ่าน Invoke-Sqlcmd ===" -ForegroundColor Cyan

$common = @{
    ServerInstance = $ServerFqdn
    Database       = $DatabaseName
    Username       = $AdminLogin
    Password       = $AdminPassword
    TrustServerCertificate = $true   # Azure SQL มี cert trust ได้อยู่แล้วจริง - คงไว้เพื่อความเข้ากัน
}

Invoke-Sqlcmd @common `
    -Query "SELECT @@SERVERNAME AS ServerName,
                   @@VERSION AS Version,
                   DATABASEPROPERTYEX(DB_NAME(), 'Edition') AS Edition;"

# สังเกต: การเชื่อมต่อเหมือน on-premises ทุกอย่าง (port 1433 ผ่าน FQDN)

# --- Task 2: สร้างตารางทดลอง (DDL ปกติทำงานเหมือน on-prem) ---
Write-Host "`n=== Task 2: สร้างตาราง + insert ===" -ForegroundColor Cyan

Invoke-Sqlcmd @common `
    -Query "IF OBJECT_ID('dbo.DemoAzure', 'U') IS NULL
            BEGIN
                CREATE TABLE dbo.DemoAzure
                (
                    Id   int           NOT NULL CONSTRAINT PK_DemoAzure PRIMARY KEY,
                    Note nvarchar(100) NOT NULL,
                    CreatedAt datetime2 NOT NULL CONSTRAINT DF_DemoAzure_Created DEFAULT SYSDATETIME()
                );
            END
            INSERT dbo.DemoAzure (Id, Note) VALUES (1, N'สร้างจาก PowerShell บน Azure');
            SELECT Id, Note, CreatedAt FROM dbo.DemoAzure;"

# --- Task 3: DMV ที่ใช้บน on-prem ยังใช้ได้ (แต่ scoped ต่อ database) ---
Write-Host "`n=== Task 3: DMV ระดับ database ===" -ForegroundColor Cyan

Invoke-Sqlcmd @common `
    -Query "SELECT name, size * 8 / 1024 AS SizeMB, state_desc
            FROM sys.database_files;" |
    Format-Table -AutoSize

# ต่างจาก on-prem: sys.master_files (ระดับ instance) ไม่มีใน Azure SQL DB

# --- Task 4: ความต่างที่สำคัญ - ลองแล้วจะเห็น error ---
Write-Host "`n=== Task 4: ของที่ Azure SQL DB ไม่มี ===" -ForegroundColor Cyan

try {
    Invoke-Sqlcmd @common -Query "BACKUP DATABASE [sqladm11db] TO DISK = 'D:\x.bak';" -ErrorAction Stop
}
catch {
    Write-Warning "BACKUP DATABASE ไม่มีใน Azure SQL DB - Azure ทำ automatic backup ให้เอง"
}

try {
    Invoke-Sqlcmd @common -Query "EXEC sp_configure 'max server memory (MB)';" -ErrorAction Stop
}
catch {
    Write-Warning "sp_configure ระดับ instance ไม่มี - ตั้งต่อ database ด้วย ALTER DATABASE SCOPED CONFIGURATION"
}

# รูปแบบที่ใช้แทน (ตัวอย่าง database-scoped configuration):
#   ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;

# --- Task 5: จัดการผ่าน cmdlet ฝั่ง Azure (เทียบ Get-SqlDatabase ของ on-prem) ---
Write-Host "`n=== Task 5: cmdlet ฝั่ง Az.Sql ===" -ForegroundColor Cyan

Get-AzSqlDatabase -ResourceGroupName 'rg-sqladm-11' -ServerName ($ServerFqdn.Split('.')[0]) |
    Select-Object DatabaseName, Edition, Status, CurrentServiceObjectiveName, CollationName |
    Format-Table -AutoSize

# ข้อมูล backup retention (automatic backups)
Get-AzSqlDatabase -ResourceGroupName 'rg-sqladm-11' -ServerName ($ServerFqdn.Split('.')[0]) `
    -DatabaseName $DatabaseName |
    Select-Object DatabaseName,
                   @{N = 'BackupRetentionDays'; E = { $_.BackupStorageRedundancy } } |
    Format-List

# --- Clean-up ---
Write-Host "`nใช้เสร็จรัน .\04_Cleanup_Az.ps1 -ResourceGroup 'rg-sqladm-11'" -ForegroundColor Red

# --- ทดลองเอง ---
# 1) เชื่อมต่อด้วย Entra auth แทน SQL auth: ใช้ -AccessToken หรือเครื่องมือ SSMS ที่รองรับ Entra
# 2) เทียบ sys.databases กับ Get-AzSqlDatabase - เห็นภาพ "logical server ครอบหลาย database"
# 3) restore จาก automatic backup: Restore-AzSqlDatabase -PointInTime (มีค่าใช้จ่าย - optional)
