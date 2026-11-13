/* =============================================================================
   04_SystemDatabases.sql
   Module 07 - Section 3: backup ของ master / model / msdb และข้อจำกัด
   tempdb + resource (จะ backup ไม่ได้) — พร้อม runbook กู้ master
   รันได้บน SQL Server 2025 — idempotent
   ============================================================================= */

USE master;
GO
EXEC sys.xp_create_subdir N'C:\SQLBackups';
GO

/* ---------------------------------------------------------------
   1) Backup system databases ที่จำเป็น — ทำทุกครั้งหลังเปลี่ยน server config
      (สร้าง login / linked server / endpoint / Agent job)
   --------------------------------------------------------------- */
BACKUP DATABASE [master] TO DISK = N'C:\SQLBackups\master.bak'
WITH FORMAT, INIT, CHECKSUM, COMPRESSION, NAME = N'master backup';
GO
BACKUP DATABASE [model] TO DISK = N'C:\SQLBackups\model.bak'
WITH FORMAT, INIT, CHECKSUM, COMPRESSION, NAME = N'model backup';
GO
BACKUP DATABASE [msdb] TO DISK = N'C:\SQLBackups\msdb.bak'
WITH FORMAT, INIT, CHECKSUM, COMPRESSION, NAME = N'msdb backup';
GO
/* Expected: สำเร็จทั้งสามตัว — ไฟล์เล็กมากเพราะเป็น metadata เป็นหลัก */

/* ---------------------------------------------------------------
   2) พิสูจน์ว่า tempdb จะ backup ไม่ได้
   --------------------------------------------------------------- */
BEGIN TRY
    BACKUP DATABASE [tempdb] TO DISK = N'C:\SQLBackups\tempdb_never.bak';
END TRY
BEGIN CATCH
    PRINT N'EXPECTED FAIL (tempdb ไม่ backup): ' + ERROR_MESSAGE();
END CATCH
GO
/* Expected: Msg 3007 — "The server principal ... cannot back up database
   tempdb because it is a temporary database" — tempdb ถูกสร้างใหม่ทุกครั้ง
   ที่ service เริ่ม การ backup ไม่มีความหมายและไม่มีทางทำได้
   resource database ก็เช่นกัน — เป็นไฟล์ executable ของ SQL Server เอง */

/* ---------------------------------------------------------------
   3) ข้อมูลที่อยู่ใน msdb (เหตุผลว่าทำไมต้อง backup สม่ำเสมอ)
   --------------------------------------------------------------- */
SELECT N'Jobs'            AS what, COUNT(*) AS items FROM msdb.dbo.sysjobs
UNION ALL
SELECT N'Schedules',        COUNT(*) FROM msdb.dbo.sysschedules
UNION ALL
SELECT N'Operators',        COUNT(*) FROM msdb.dbo.sysoperators
UNION ALL
SELECT N'Alerts',           COUNT(*) FROM msdb.dbo.sysalerts
UNION ALL
SELECT N'Backup history',   COUNT(*) FROM msdb.dbo.backupset;
GO
/* Expected: ตัวเลขงานจริงของ instance — msdb พัง = job schedule และ
   backup history หายทั้งหมดจนกว่าจะ restore msdb.bak กลับ */

/* ---------------------------------------------------------------
   4) RUNBOOK — กู้ master (เก็บไว้เป็นเอกสารทีม ห้ามรันบนเครื่องทดลองโดยไม่คิด)
   --------------------------------------------------------------- */
/* กรณี A — master เสียแต่ instance ยังขึ้นได้ (แก้ที่ไฟล์ log เล็กน้อย):
   1) หยุด service:        net stop MSSQLSERVER
   2) เริ่ม single-user:   net start MSSQLSERVER /m"SQLCMD"
   3) เชื่อม + restore:
        sqlcmd -S .
        RESTORE DATABASE master FROM DISK = N'C:\SQLBackups\master.bak' WITH REPLACE;
   4) restart ปกติ + เริ่ม SQL Agent ใหม่ (master restore พา SQL Agent ลงด้วย)

   กรณี B — master เสียจน restore ไม่ได้ → rebuild:
   Setup.exe /QUIET /ACTION=RebuildDatabase /INSTANCENAME=MSSQLSERVER
             /SQLSYSADMINACCOUNTS="<admin>" /SAPWD=Pa$$w0rd2025
   แล้ว restore master.bak กลับ (คืน logins/endpoints/linked servers)
   + ตรวจทวน server configuration ที่ rebuild ไม่คืน (sp_configure, AG, cert)

   กู้ model: ทำเหมือน master (ต้อง -m เพราะ connections ใช้ model ขณะสร้าง DB)
   กู้ msdb: หยุด SQL Agent ก่อน → RESTORE DATABASE msdb WITH REPLACE
   --------------------------------------------------------------- */

/* ---------------------------------------------------------------
   5) ตรวจลิสต์ system DB ที่ backup ล่าสุด — เพิ่มเป็น Agent job รายวัน
   --------------------------------------------------------------- */
SELECT d.name, d.create_date,
       MAX(s.backup_finish_date) AS last_backup
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS s
       ON s.database_name = d.name AND s.type = 'D'
WHERE d.database_id <= 4
GROUP BY d.name, d.create_date
ORDER BY d.name;
GO
/* Expected: master / model / msdb มี last_backup สด; tempdb = NULL (ถูกต้อง) */

/* ---------------------------------------------------------------
   Cleanup — เก็บไฟล์ system backup ไว้ได้ หรือลบ:
   --------------------------------------------------------------- */
-- Remove-Item C:\SQLBackups\master.bak, C:\SQLBackups\model.bak, C:\SQLBackups\msdb.bak
GO
