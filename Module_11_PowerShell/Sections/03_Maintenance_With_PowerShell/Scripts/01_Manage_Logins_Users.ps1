# =============================================================================
# 01_Manage_Logins_Users.ps1 - จัดการ login/user/role ด้วย PowerShell
# แนวทาง: สร้างด้วย T-SQL มาตรฐานผ่าน Invoke-Sqlcmd (idempotent) ตรวจด้วย cmdlet
# หมายเหตุ: คอร์สเดิม (20764D) ใช้ AD domain account ADVENTUREWORKS\Student
#           ที่นี่ใช้ SQL authentication เพื่อไม่พึ่ง domain สามารถใช้
#           Windows local account แทนได้ (ดูคอมเมนต์ท้ายไฟล์)
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$Database       = 'AdventureWorks2025',
    [string]$LoginName      = 'SqlReader2025',
    [string]$Password       = 'Pa$$w0rd2025'   # รหัสผ่านตัวอย่างสำหรับห้องเรียนเท่านั้น
)

Clear-Host

# --- Task 1: สร้าง login (server-level) - เช็กก่อนสร้างเสมอ (idempotent) ---
Write-Host "=== Task 1: สร้าง login $LoginName ===" -ForegroundColor Cyan

# ใช้ single-quoted string + '' เพื่อไม่ให้ PowerShell ตีความ $$ ในรหัสผ่าน
$createLogin = 'IF SUSER_ID(N''$(LoginName)'') IS NULL
                BEGIN
                    CREATE LOGIN [$(LoginName)] WITH PASSWORD = N''$(Password)'',
                        CHECK_POLICY = ON,
                        DEFAULT_DATABASE = [$(DbName)];
                END
                SELECT name, type_desc, default_database_name
                FROM sys.sql_logins WHERE name = N''$(LoginName)'';'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database master `
    -Query $createLogin `
    -Variable "LoginName=$LoginName", "Password=$Password", "DbName=$Database" |
    Format-List

# --- Task 2: สร้าง user ใน database + เพิ่มเข้า role ---
Write-Host "`n=== Task 2: สร้าง user + เพิ่ม role db_datareader ===" -ForegroundColor Cyan

$createUser = 'IF DATABASE_PRINCIPAL_ID(N''$(LoginName)'') IS NULL
                   CREATE USER [$(LoginName)] FOR LOGIN [$(LoginName)];
               ALTER ROLE db_datareader ADD MEMBER [$(LoginName)];'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query $createUser -Variable "LoginName=$LoginName"

# ตรวจว่า user อยู่ role จริง
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query 'SELECT r.name AS RoleName, m.name AS MemberName
            FROM sys.database_role_members AS drm
            JOIN sys.database_principals AS r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals AS m ON m.principal_id = drm.member_principal_id
            WHERE m.name = N''$(LoginName)'';' `
    -Variable "LoginName=$LoginName" |
    Format-Table -AutoSize

# --- Task 3: ตรวจด้วย cmdlet ของ SqlServer module ---
Write-Host "`n=== Task 3: ตรวจด้วย Get-SqlLogin ===" -ForegroundColor Cyan

Get-SqlLogin -ServerInstance $ServerInstance |
    Where-Object Name -eq $LoginName |
    Select-Object Name, LoginType, CreateDate, DefaultDatabase |
    Format-List

# --- Task 4: ทดสอบสิทธิ์จริง (เชื่อมต่อด้วย login ใหม่) ---
Write-Host "`n=== Task 4: ทดสอบสิทธิ์ ===" -ForegroundColor Cyan

try {
    # อ่านได้ (db_datareader)
    $rows = Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
        -Database $Database -Username $LoginName -Password $Password `
        -Query 'SELECT COUNT(*) AS Cnt FROM Sales.SalesOrderHeader;' `
        -ErrorAction Stop
    Write-Host ("อ่านได้: SalesOrderHeader มี {0} แถว" -f $rows.Cnt) -ForegroundColor Green
}
catch {
    Write-Warning "อ่านไม่ได้: $($_.Exception.Message)"
}

try {
    # เขียนไม่ได้ (ไม่มี role เขียน) - ต้อง error 229 (permission denied)
    Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
        -Database $Database -Username $LoginName -Password $Password `
        -Query 'CREATE TABLE dbo.TestWrite (Id int);' -ErrorAction Stop
    Write-Host "เขียนได้?! (ควรไม่ได้ - ตรวจ role อีกครั้ง)" -ForegroundColor Red
}
catch {
    Write-Warning "เขียนถูกปฏิเสธ (คาดหวังไว้) - นี่คือ least privilege ทำงาน"
}

# --- Task 5: รายงาน login ทั้งหมดใน instance (รูปแบบรายงานที่ใช้ทำ audit) ---
Write-Host "`n=== Task 5: รายงาน SQL logins ===" -ForegroundColor Cyan

Get-SqlLogin -ServerInstance $ServerInstance |
    Where-Object LoginType -eq 'SqlLogin' |
    Select-Object Name, CreateDate, DefaultDatabase, IsLocked |
    Format-Table -AutoSize

# --- Clean-up: ลบของทดลอง ---
Write-Host "`n=== Clean-up: ลบ user/login ทดลอง ===" -ForegroundColor Cyan

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query 'IF DATABASE_PRINCIPAL_ID(N''$(LoginName)'') IS NOT NULL DROP USER [$(LoginName)];' `
    -Variable "LoginName=$LoginName"
Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database master `
    -Query 'IF SUSER_ID(N''$(LoginName)'') IS NOT NULL DROP LOGIN [$(LoginName)];' `
    -Variable "LoginName=$LoginName"
Write-Host "ลบแล้ว" -ForegroundColor Green

# --- ทดลองเอง ---
# 1) ใช้ Windows local account แทน SQL auth:
#    CREATE LOGIN [MACHINE-NAME\LocalUser] FROM WINDOWS;  (แทน Task 1)
# 2) ถ้ามี domain จริงใช้ CREATE LOGIN [DOMAIN\User] FROM WINDOWS;
# 3) ทำฟังก์ชัน New-SqlLoginAndUser -Server -Db -Login -Role ที่ทำ Task 1-3 ในบรรทัดเดียว
# 4) สร้าง user สำหรับ Entra ID บน SQL Server 2022+: CREATE LOGIN [user@tenant] FROM EXTERNAL PROVIDER;
