# =============================================================================
# 05_Troubleshoot_Scenario.ps1 - สถานการณ์ troubleshoot สั้น: "DB ช้า" เช็กอะไรก่อน 10 นาทีแรก
# เป้าหมาย: สร้างความเคยชิน "รันสคริปต์ตัวเดิมเก็บภาพเดียวกันเสมอ" เวลาเกิดเหตุ
# โครง: สถานะ DB -> active requests -> wait stats -> file I/O -> backup ล่าสุด -> error log
# =============================================================================

param(
    [string]$ServerInstance = 'localhost',
    [string]$Database       = 'AdventureWorks2025',
    [string]$ReportFile     = ''    # ถ้าระบุ path เช่น C:\Temp\report.txt จะเก็บผลด้วย
)

Clear-Host
Import-Module SqlServer

function Write-Section ([string]$Title) {
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

# --- ชุด 1: สถานะ database ---
Write-Section '1. สถานะ database'

Get-SqlDatabase -ServerInstance $ServerInstance -Name $Database |
    Select-Object Name, Status, RecoveryModel, ReadOnly,
                  @{N = 'SizeMB'; E = { [math]::Round($_.Size / 1MB, 1) } } |
    Format-List
# ถ้า Status ไม่ใช่ Normal = หาต้นเหตุที่ database เอง (restoring? recovery pending?)
# ถ้าปกติ -> ไปดู workload ชุดถัดไป

# --- ชุด 2: ใครกำลังรันอะไร ใครรอใคร ---
Write-Section '2. Active requests / blocking'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT r.session_id, r.status, r.command,
                   r.wait_type, r.wait_time, r.blocking_session_id,
                   s.host_name, s.program_name,
                   LEFT(t.text, 120) AS CurrentSql
            FROM sys.dm_exec_requests AS r
            JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
            OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
            WHERE s.is_user_process = 1 AND r.session_id <> @@SPID;" |
    Format-Table -AutoSize -Wrap
# blocking_session_id <> 0 = มี blocking; wait_type PAGEIOLATCH_* = รอ disk; SOS_SCHEDULER_YIELD = CPU

# --- ชุด 3: wait statistics สะสม (TOP 10) ---
Write-Section '3. Wait stats (สะสมตั้งแต่ restart)'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT TOP (10) wait_type,
                   waiting_tasks_count,
                   wait_time_ms / 1000.0 AS wait_sec,
                   signal_wait_time_ms / 1000.0 AS signal_sec
            FROM sys.dm_os_wait_stats
            WHERE wait_time_ms > 0
              AND wait_type NOT IN ('SLEEP_TASK', 'BROKER_TASK_STOP', 'WAITFOR',
                    'XE_TIMER_EVENT', 'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
                    'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'XE_DISPATCHER_WAIT', 'LOGMGR_QUEUE')
            ORDER BY wait_time_ms DESC;" |
    Format-Table -AutoSize
# แปล wait type ดู Module 13 (PAGEIOLATCH=disk, LCK_M*=blocking, WRITELOG=log disk)

# --- ชุด 4: I/O latency ต่อ file ---
Write-Section '4. I/O latency ต่อ database file'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate -Database $Database `
    -Query "SELECT f.physical_name,
                   vfs.num_of_reads,
                   vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS AvgReadMs,
                   vfs.num_of_writes,
                   vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS AvgWriteMs
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
            JOIN sys.databases AS d ON d.database_id = vfs.database_id
            JOIN sys.master_files AS f ON f.database_id = vfs.database_id
                                      AND f.file_id = vfs.file_id
            WHERE d.name = N'$($Database)';" |
    Format-Table -AutoSize
# AvgRead/WriteMs > 20 ms ต่อเนื่อง = สงสัย disk หรือ RAM ไม่พอ (เทียบ PLE)

# --- ชุด 5: backup ล่าสุด (จะกู้ได้แค่ไหนถ้า DB พังตอนนี้) ---
Write-Section '5. Backup ล่าสุด'

Invoke-Sqlcmd -ServerInstance $ServerInstance -TrustServerCertificate `
    -Query "SELECT TOP (5) type_desc AS BackupType,
                   backup_start_date, backup_finish_date,
                   compressed_backup_size / 1048576.0 AS CompressedMB,
                   database_name
            FROM msdb.dbo.backupset
            WHERE database_name = N'$($Database)'
            ORDER BY backup_start_date DESC;" |
    Format-Table -AutoSize

# --- ชุด 6: SQL Server error log ล่าสุด (ผ่าน cmdlet) ---
Write-Section '6. Error log (ล่าสุด 15 รายการ)'

try {
    Get-SqlErrorLog -ServerInstance $ServerInstance -ErrorAction Stop |
        Sort-Object LogDate -Descending |
        Select-Object -First 15 LogDate, Source, Text |
        Format-Table -Wrap
}
catch {
    Write-Warning "Get-SqlErrorLog ใช้ไม่ได้ที่นี่: $($_.Exception.Message)"
}

# --- เก็บรายงานเป็นไฟล์ (ถ้าระบุ -ReportFile) ---
if ($ReportFile) {
    Start-Transcript -Path $ReportFile -Append | Out-Null
    # รันเนื้อหาซ้ำเพื่อบันทึก: วิธีใช้จริงคือเปิด transcript ก่อนรัน script นี้
    Stop-Transcript | Out-Null
    Write-Host "บันทึกรายงาน: $ReportFile" -ForegroundColor Green
}

# --- สรุปการตัดสินใจ ---
Write-Host @'
สรุปทิศทางจากชุดข้อมูลข้างบน (ดูละเอียด Module 13):
- blocking_session_id มีค่า          -> แก้ blocking (หา head blocker)
- PAGEIOLATCH / AvgReadMs สูง       -> disk/RAM เช็ก PLE + capacity
- SOS_SCHEDULER_YIELD / THREADPOOL  -> CPU หรือ worker ตึง
- WRITELOG สูง                      -> log disk latency
- ไม่มี backup ใน 24 ชม.            -> อันตราย - ทำ backup ก่อนทดลองแก้อะไรต่อ
'@ -ForegroundColor Yellow

# --- ทดลองเอง ---
# 1) เพิ่มชุดตรวจ "database file เต็มไหม" (sys.dm_db_file_space_usage / FILEPROPERTY('SpaceUsed'))
# 2) ทำ self-block demo: เปิด tran UPDATE ค้างไว้ (ดู Module 13 แล็บ) แล้วรันชุด 2 เพื่อเห็น blocking จริง
# 3) ตั้ง scheduled task รันสคริปต์นี้ทุก 15 นาที เก็บ transcript เป็น baseline คร่าว ๆ
