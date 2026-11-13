# =============================================================================
# 03_Backup_Restore.ps1 - Backup / Restore ด้วย Backup-SqlDatabase / Restore-SqlDatabase
# แล็บนี้ทำ full backup -> VERIFYONLY -> restore เป็น database copy -> ตรวจข้อมูล -> ลบ copy
# (เป็น pattern ตรวจ backup ที่แนะนำ: backup ที่ restore ไม่ได้ไม่ใช่ backup)
# =============================================================================

param(
    [string]$ServerInstance   = 'localhost',
    [string]$Database         = 'AdventureWorks2025',
    [string]$DatabaseCopy     = 'AdventureWorks2025_Copy',
    [string]$BackupDir        = 'C:\SQLBackups',
    [string]$BackupFile       = 'C:\SQLBackups\AdventureWorks2025_Full.bak'
)

Clear-Host
Import-Module SqlServer

# --- Task 1: เตรียมโฟลเดอร์ backup ---
Write-Host "=== Task 1: เตรียม $BackupDir ===" -ForegroundColor Cyan

if (-not (Test-Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
    Write-Host "สร้างโฟลเดอร์แล้ว: $BackupDir"
    # หมายเหตุ: SQL Server service account ต้องเขียนไฟล์ได้ - ถ้าใช้โฟลเดอร์อื่นให้ตั้ง ACL เอง
}

# --- Task 2: Full backup + Compression + Checksum ---
Write-Host "`n=== Task 2: Backup-SqlDatabase (full, compression, checksum) ===" -ForegroundColor Cyan

Backup-SqlDatabase -ServerInstance $ServerInstance `
    -Database $Database `
    -BackupFile $BackupFile `
    -CompressionOption On `
    -Checksum `
    -Initialize `
    -BackupSetName "Module 11 full backup"

# ตรวจไฟล์
Get-Item $BackupFile |
    Select-Object FullName, @{N = 'SizeMB'; E = { [math]::Round($_.Length / 1MB, 2) } } |
    Format-List

# หมายเหตุ SQL Server 2025: ต้องการ ZSTD compression ให้รัน BACKUP T-SQL ผ่าน Invoke-Sqlcmd:
#   BACKUP DATABASE [AdventureWorks2025] TO DISK = N'...\AW2025_ZSTD.bak'
#   WITH COMPRESSION, ALGORITHM = ZSTD, CHECKSUM;

# --- Task 3: ตรวจความสมบูรณ์ไฟล์ backup ---
Write-Host "`n=== Task 3: RESTORE VERIFYONLY ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "RESTORE VERIFYONLY FROM DISK = N'$(BackupFile)' WITH CHECKSUM;"
Write-Host "VERIFYONLY ผ่าน - โครงไฟล์อ่านได้ครบ" -ForegroundColor Green
# ย้ำ: VERIFYONLY ไม่ใช่การ restore จริง - Task 5 คือการทดสอบที่แน่นอนกว่า

# --- Task 4: Differential + Log backup (แนะนำรูปแบบ) ---
Write-Host "`n=== Task 4: Differential และ Log backup ===" -ForegroundColor Cyan

# Differential: สำรอง extent ที่เปลี่ยนหลัง full ล่าสุด
Backup-SqlDatabase -ServerInstance $ServerInstance `
    -Database $Database `
    -BackupFile (Join-Path $BackupDir ($Database + '_Diff.bak')) `
    -BackupAction Database -Incremental -Checksum

# Log backup: ทำได้เมื่อ recovery model FULL (AdventureWorks2025 เดิม SIMPLE)
try {
    Backup-SqlDatabase -ServerInstance $ServerInstance `
        -Database $Database `
        -BackupFile (Join-Path $BackupDir ($Database + '_Log.trn')) `
        -BackupAction Log -Checksum -ErrorAction Stop
    Write-Host "log backup สำเร็จ (recovery model FULL)"
}
catch {
    Write-Warning "log backup ไม่สำเร็จ - $Database อยู่ SIMPLE recovery model (ปกติสำหรับ copy ของ sample)"
    Write-Host "เปลี่ยนเป็น FULL ก่อนถ้าต้องการ: ALTER DATABASE [$Database] SET RECOVERY FULL;"
}

# --- Task 5: Restore เป็น database copy ใหม่ (RelocateFile = WITH MOVE) ---
Write-Host "`n=== Task 5: restore เป็น $DatabaseCopy ===" -ForegroundColor Cyan

# 5.1 อ่าน logical file names จาก backup
$fileList = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "RESTORE FILELISTONLY FROM DISK = N'$(BackupFile)';"
$fileList | Select-Object LogicalName, PhysicalName, Type | Format-Table -AutoSize

# 5.2 หาโฟลเดอร์ default ของ instance (ที่ service account มีสิทธิ์เขียนแน่นอน)
$paths = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DataDir,
                   SERVERPROPERTY('InstanceDefaultLogPath') AS LogDir;"
$dataDir = $paths.DataDir
$logDir  = $paths.LogDir

# 5.3 สร้าง RelocateFile ทีละไฟล์ - map logical -> physical ใหม่
$relocate = foreach ($f in $fileList) {
    if ($f.Type -eq 'L') {
        $target = Join-Path $logDir  "$($f.LogicalName)_Copy.ldf"
    }
    else {
        $target = Join-Path $dataDir "$($f.LogicalName)_Copy.mdf"
    }
    Write-Host "  MOVE: $($f.LogicalName) -> $target"
    New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($f.LogicalName, $target)
}

# 5.4 Restore (ทำซ้ำได้เพราะ -ReplaceDatabase)
Restore-SqlDatabase -ServerInstance $ServerInstance `
    -Database $DatabaseCopy `
    -BackupFile $BackupFile `
    -RelocateFile $relocate `
    -ReplaceDatabase

# --- Task 6: ตรวจข้อมูลเทียบต้นฉบับกับ copy ---
Write-Host "`n=== Task 6: เทียบข้อมูล ===" -ForegroundColor Cyan

$query = 'SELECT ''$(DbOrig)'' AS Source, COUNT(*) AS Orders FROM [$(DbOrig)].Sales.SalesOrderHeader
          UNION ALL
          SELECT ''$(DbCopy)'', COUNT(*) FROM [$(DbCopy)].Sales.SalesOrderHeader;'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query $query `
    -Variable "DbOrig=$Database", "DbCopy=$DatabaseCopy" |
    Format-Table -AutoSize

# --- Clean-up: ลบ database copy ---
Write-Host "`n=== Clean-up ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database master `
    -Query 'IF DB_ID(N''$(DbCopy)'') IS NOT NULL
            BEGIN
                ALTER DATABASE [$(DbCopy)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [$(DbCopy)];
            END;' `
    -Variable "DbCopy=$DatabaseCopy"
Write-Host "ลบ $DatabaseCopy แล้ว (ไฟล์ .bak เก็บไว้ที่ $BackupDir เพื่อใช้ในแล็บ)" -ForegroundColor Green

# --- ทดลองเอง ---
# 1) ทำเป็น function Invoke-DbaVerifyRestore -Db -BakFile ที่ทำ Task 2-6 ทั้งหมด
# 2) เพิ่ม -CopyOnly ที่ Task 2 แล้วอธิบายความต่าง (ไม่กระทบ LSN chain - Module 5)
# 3) ทดลอง backup ตรงไป Azure Blob URL ด้วย T-SQL (TO URL - Module 5) แล้วเทียบระยะเวลา
