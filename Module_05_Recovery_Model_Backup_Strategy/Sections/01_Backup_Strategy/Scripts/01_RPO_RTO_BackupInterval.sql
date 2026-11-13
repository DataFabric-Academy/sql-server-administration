/* =============================================================================
   01_RPO_RTO_BackupInterval.sql
   Module 05 - Section 1: คำนวณ RPO/RTO โดยประมาณจาก backup history ใน msdb
   รันได้บน SQL Server 2025 (และ 2016+) — idempotent, ใช้ AdventureWorks2025
   ============================================================================= */

USE master;
GO

-- โฟลเดอร์เก็บ backup (สร้างถ้ายังไม่มี — เปลี่ยน drive ได้ตามเครื่องคุณ)
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) เตรียมชุด backup สั้น ๆ ให้ msdb มีข้อมูลประวัติให้วัด
   --------------------------------------------------------------- */
USE [master];
GO
IF DB_ID(N'AdventureWorks2025') IS NOT NULL
BEGIN
    -- ให้ FULL เพื่อทำ log chain สั้น ๆ ได้ (จะคืนค่าเดิมตอนท้าย)
    ALTER DATABASE [AdventureWorks2025] SET RECOVERY FULL;
END
GO

-- full backup แล้ว log backup สองรอบ (ห่างกันเล็กน้อยเพื่อให้เห็น interval)
BACKUP DATABASE [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_RPO_Full.bak'
WITH FORMAT, INIT, NAME = N'RPO demo - full', CHECKSUM, COMPRESSION;
GO

WAITFOR DELAY '00:00:05';

BACKUP LOG [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_RPO_Log1.trn'
WITH FORMAT, INIT, NAME = N'RPO demo - log 1', CHECKSUM;
GO

WAITFOR DELAY '00:00:05';

BACKUP LOG [AdventureWorks2025]
TO DISK = N'C:\SQLBackups\AW_RPO_Log2.trn'
WITH FORMAT, INIT, NAME = N'RPO demo - log 2', CHECKSUM;
GO

/* ---------------------------------------------------------------
   2) วัด RPO โดยประมาณ = ช่วงเวลาเฉลี่ยระหว่าง log backup ล่าสุด
      ของแต่ละ database ใน FULL/BULK_LOGGED recovery
   --------------------------------------------------------------- */
SELECT
    database_name,
    MAX(backup_finish_date) AS last_log_backup,
    -- ช่วงระหว่าง log backup สองอันล่าสุด ≈ RPO ปัจจุบัน
    DATEDIFF(SECOND,
             (SELECT TOP 1 b2.backup_finish_date
              FROM msdb.dbo.backupset AS b2
              WHERE b2.database_name = b.database_name
                AND b2.type = 'L'
              ORDER BY b2.backup_finish_date DESC OFFSET 1 ROWS),
             MAX(b.backup_finish_date)) AS log_backup_interval_sec,
    CAST(DATEDIFF(SECOND,
             (SELECT TOP 1 b2.backup_finish_date
              FROM msdb.dbo.backupset AS b2
              WHERE b2.database_name = b.database_name
                AND b2.type = 'L'
              ORDER BY b2.backup_finish_date DESC OFFSET 1 ROWS),
             MAX(b.backup_finish_date)) / 60.0 AS DECIMAL(10,1)) AS approx_RPO_minutes
FROM msdb.dbo.backupset AS b
WHERE b.type = 'L'
  AND DB_NAME(DB_ID(b.database_name)) IS NOT NULL   -- DB ยังอยู่บน instance นี้
GROUP BY b.database_name
ORDER BY b.database_name;
GO

/* ---------------------------------------------------------------
   3) วัด RTO โดยประมาณ = ขนาดที่ต้อง restore ของ chain ล่าสุด
      (full ล่าสุด + log ทุกอันหลัง full นั้น) — ใช้ backup_size
      เป็น proxy ของเวลา restore (ยิ่งเล็กยิ่ง restore เร็วโดยเฉลี่ย)
   --------------------------------------------------------------- */
WITH last_full AS (
    SELECT TOP 1 database_name, media_set_id, backup_finish_date,
           backup_size, compressed_backup_size
    FROM msdb.dbo.backupset
    WHERE database_name = N'AdventureWorks2025'
      AND type = 'D'
    ORDER BY backup_finish_date DESC
)
SELECT
    lf.database_name,
    lf.backup_finish_date        AS chain_base_full,
    COUNT(l.type)                AS logs_to_apply,          -- ยิ่งน้อย RTO ยิ่งสั้น
    SUM(l.backup_size) / 1048576.0 AS log_MB_to_apply,
    lf.compressed_backup_size / 1048576.0 AS full_MB
FROM last_full AS lf
OUTER APPLY (
    SELECT bs.backup_size, bs.type
    FROM msdb.dbo.backupset AS bs
    WHERE bs.database_name = lf.database_name
      AND bs.type = 'L'
      AND bs.backup_finish_date > lf.backup_finish_date
) AS l
GROUP BY lf.database_name, lf.backup_finish_date, lf.compressed_backup_size;
GO

/* Expected: แถว per-database แสดง log_backup_interval_sec ≈ 5 วินาทีจากเดโม
   ในระบบจริงตัวเลขนี้คือ RPO ปัจจุบันของคุณ;  logs_to_apply คือสิ่งที่ restore
   ต้องวิ่งตามลำดับ — ถ้าเกิน 100 อัน พิจารณาเพิ่ม differential backup */
GO

/* ---------------------------------------------------------------
   4) Cleanup — ลบไฟล์ .bak/.trn ของเดโมด้วยตนเอง (T-SQL ลบไฟล์ OS โดยตรงไม่ได้)
   --------------------------------------------------------------- */
-- ลบไฟล์ที่ C:\SQLBackups\AW_RPO_*.bak / *.trn ทีหลังได้
-- (ใช้ PowerShell: Remove-Item C:\SQLBackups\AW_RPO_* )
GO
