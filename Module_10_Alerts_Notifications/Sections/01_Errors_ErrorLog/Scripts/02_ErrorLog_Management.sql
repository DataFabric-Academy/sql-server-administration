-- ============================================================================
-- Module 10, Section 1 — อ่านและจัดการ SQL Server Error Log
-- read-only เกือบทั้งหมด ยกเว้นขั้นที่ 4-5 (cycle + NumErrorLogs) ให้รันเมื่อต้องการ
-- ต้องมี: sysadmin สำหรับขั้น 4-5 (xp_readerrorlog ทำได้กับสิทธิ์ที่เหมาะสม)
-- ============================================================================

USE master;
GO

/* ----------------------------------------------------------------------------
   1) อ่าน error log ปัจจุบันทั้งไฟล์ (ผ่าน T-SQL ไม่ต้องเปิด SSMS)
      xp_readerrorlog พารามิเตอร์:
        [0]  = archive number: 0 = ไฟล์ปัจจุบัน, 1 = ERRORLOG.1, 2 = ERRORLOG.2 ...
        [1]  = log type: 1 = SQL Server log, 2 = SQL Server Agent log
        [2]  = ข้อความ filter 1 (ค้นในบรรทัด)
        [3]  = ข้อความ filter 2 (ต้องมีทั้งสอง)
        [4-5]= ช่วงเวลา (datetime)
   ---------------------------------------------------------------------------- */
EXEC xp_readerrorlog 0, 1;
-- Expected: บรรทัดทั้งหมดของ ERRORLOG ปัจจุบัน — startup ล่าสุด, recovery,
--           backup ที่เสร็จ, alert ที่ยิง (ถ้ามี)

/* ----------------------------------------------------------------------------
   2) ค้นหาด้วย filter — เป็นเทคนิคที่ใช้ทุกวัน
   ---------------------------------------------------------------------------- */
-- 2a) หาตอน engine restart ล่าสุด
EXEC xp_readerrorlog 0, 1, N'SQL Server is now ready for client connections';
-- Expected: บรรทัดบอกเวลาที่ engine พร้อมรับ connection หลัง startup ล่าสุด

-- 2b) หาเหตุการณ์ backup ที่ถูกบันทึกลง log
EXEC xp_readerrorlog 0, 1, N'Backup completed successfully';
-- Expected: บรรทัด backup ล่าสุด (ถ้าเคย backup บน instance นี้)

-- 2c) หาเหตุการณ์ความผิดปกติระดับ high severity
EXEC xp_readerrorlog 0, 1, N'Error', N'21';   -- ต้องมีทั้ง 'Error' และ '21'
-- Expected: มักว่างในระบบปกติ — ว่าง = ข่าวดี

/* ----------------------------------------------------------------------------
   3) อ่าน log ของ SQL Server Agent (ไฟล์แยก ต่างจาก engine log)
   ---------------------------------------------------------------------------- */
EXEC xp_readerrorlog 0, 2;
-- Expected: ประวัติการทำงานของ Agent — jobs ที่เริ่ม/จบ, alert ที่จับได้
-- (สมมูลหน้าจอ SSMS: SQL Server Agent -> Error Logs)

/* ----------------------------------------------------------------------------
   4) หมุนไฟล์ error log ด้วยมือ (sp_cycle_errorlog)
      ไฟล์ปัจจุบันถูกเลื่อนเป็น ERRORLOG.1, เปิดไฟล์ใหม่ — ไม่ต้อง restart
      ให้ uncomment เมื่อต้องการทำจริง
   ---------------------------------------------------------------------------- */
-- EXEC msdb.dbo.sp_cycle_errorlog;
-- SELECT TOP 5 * FROM sys.dm_os_sys_info;   -- ทำอะไรเบา ๆ ให้ log ใหม่มีอย่างน้อยหนึ่งบรรทัด
-- EXEC xp_readerrorlog 0, 1;
-- Expected: ไฟล์ใหม่เริ่มด้วยบรรทัด "Starting up database ..." / นาฬิกาใหม่

-- ของ SQL Server Agent ก็มีให้หมุนเช่นกัน:
-- EXEC msdb.dbo.sp_cycle_agent_errorlog;

/* ----------------------------------------------------------------------------
   5) ปรับจำนวนไฟล์ error log ที่เก็บ (default 7 ไฟล์ = ปัจจุบัน + 6 archives)
      ค่านี้เก็บใน registry ของ instance — เขียนผ่าน xp_instance_regwrite
      ซึ่งแก้ได้ทั้ง default instance และ named instance โดยไม่ต้องรู้ path เอง
      เข้าค่าใหม่ครั้งถัดไปที่ log ถูก cycle/restart
   ---------------------------------------------------------------------------- */
-- EXEC xp_instance_regwrite
--     N'HKEY_LOCAL_MACHINE',
--     N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer',
--     N'NumErrorLogs',
--     REG_DWORD,
--     30;   -- เก็บย้อนหลัง 30 ไฟล์
-- (สมมูลหน้าจอ SSMS: คลิกขวา SQL Server Logs -> Configure)

/* ----------------------------------------------------------------------------
   6) ที่อยู่จริงของไฟล์ error log (เอาไป tail/ส่งต่อให้ log analytics)
   ---------------------------------------------------------------------------- */
SELECT SERVERPROPERTY('ErrorLogFileName') AS current_errorlog_path;
-- SQL Server 2019+ มี property นี้ — คืน path ของ ERRORLOG ปัจจุบัน
-- Expected: เช่น C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Log\ERRORLOG
--           หรือ /var/opt/mssql/log/errorlog บน Linux/container
