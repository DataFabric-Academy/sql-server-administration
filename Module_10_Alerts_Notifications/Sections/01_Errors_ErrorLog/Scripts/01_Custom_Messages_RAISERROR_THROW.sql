-- ============================================================================
-- Module 10, Section 1 — Custom error messages, RAISERROR vs THROW
-- ต้องมี: sysadmin (sp_addmessage/sp_dropmessage + RAISERROR WITH LOG)
-- idempotent — ลบของเดิมก่อนสร้างใหม่; ท้ายสคริปต์ให้ทาง clean-up
-- ============================================================================

USE master;
GO

/* ----------------------------------------------------------------------------
   1) ดูข้อความระบบที่ใช้บ่อยในงาน DBA (sys.messages)
   ---------------------------------------------------------------------------- */
SELECT message_id, severity, language_id, LEFT(text, 80) AS text_head
FROM sys.messages
WHERE language_id = 1033                       -- us_english
  AND message_id IN (1205, 9002, 911, 823, 596, 9524)
ORDER BY message_id;
-- 1205 = deadlock victim, 9002 = transaction log full, 911 = database does not exist,
-- 823 = I/O error, 596 = cannot continue execution, 9524 = XML/well-formed error
-- Expected: 6 แถว — สังเกต severity ของแต่ละข้อความ (9002 = 17, 823 = 24)

/* ----------------------------------------------------------------------------
   2) สร้างข้อความ custom — severity 16 + @with_log = 'TRUE'
      (with_log = TRUE ทำให้ทุกครั้งที่ raise ข้อความนี้ ถูกเขียนลง
       Windows Application Log → alert ของ Module นี้จะจับได้)
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50001)
    EXEC dbo.sp_dropmessage @msgnum = 50001;

EXEC dbo.sp_addmessage
    @msgnum   = 50001,
    @severity = 16,
    @msgtext  = N'Fabrikam inventory alert: product %s fell below threshold %d.',
    @lang     = 'us_english',
    @with_log = 'TRUE';
GO

-- ใช้ RAISERROR อ้างเลขข้อความ + เติม placeholder
RAISERROR (50001, 16, 1, N'AW-1000', 5);
-- Expected: "Fabrikam inventory alert: product AW-1000 fell below threshold 5."
-- และถูกเขียนลง Application Log — ยืนยันด้วย xp_readerrorlog:
EXEC xp_readerrorlog 0, 1, N'Fabrikam inventory alert';
-- Expected: บรรทัดที่เพิ่ง raise ปรากฏใน log

/* ----------------------------------------------------------------------------
   3) RAISERROR vs THROW — เทียบพฤติกรรมใน TRY...CATCH
   ---------------------------------------------------------------------------- */
/* 3a) THROW แบบระบุข้อความ — severity คงที่ 16 */
BEGIN TRY
    THROW 50001, N'Batch stopped: invalid parameter.', 1;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()   AS error_number,     -- 50001
           ERROR_SEVERITY() AS error_severity,   -- 16 (THROW คงที่)
           ERROR_MESSAGE()  AS error_message;
END CATCH;
GO

/* 3b) THROW แบบ re-throw ใน CATCH — โยน error เดิมทั้งก้อน */
BEGIN TRY
    SELECT 1 / 0;                                  -- error 8134, severity 16
END TRY
BEGIN CATCH
    THROW;                                         -- re-throw ของเดิม
END CATCH;
GO
-- Expected: error 8134 (Divide by zero) หลุดออกจาก TRY/CATCH อีกที

/* 3c) RAISERROR severity ที่กำหนดเอง + WITH LOG */
BEGIN TRY
    RAISERROR (N'Simulated resource error for alert testing.', 17, 1) WITH LOG;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number,
           ERROR_SEVERITY() AS error_severity;    -- 17 — severity ที่เราตั้ง
END CATCH;
GO
-- Expected: severity 17 (ต่างจาก THROW ที่ 16) + ข้อความถึง Application Log
EXEC xp_readerrorlog 0, 1, N'Simulated resource error';

/* 3d) RAISERROR severity สูง (19+) เฉพาะ sysadmin — WITH LOG
      หมายเหตุ: sp_altermessage เปลี่ยนได้แค่ WITH_LOG (จะเปิด/ปิดการเขียน log)
      เปลี่ยน severity ของข้อความ custom ต้อง drop/add ใหม่เท่านั้น
      severity >= 19 ยิงด้วย RAISERROR ได้เฉพาะ sysadmin WITH LOG:
RAISERROR (N'Fatal simulation by sysadmin.', 19, 1) WITH LOG;
-- Expected (sysadmin): error severity 19 — บันทึกลง Application Log ทันที
*/

/* ----------------------------------------------------------------------------
   4) สร้างข้อความ custom อีกตัวสำหรับแล็บ (alert จับ severity 17 แบบ general)
      ใช้ข้อความทดสอบ severity 17 โดยไม่ผูกเลขข้อความ — RAISERROR ตรง ๆ
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50002)
    EXEC dbo.sp_dropmessage @msgnum = 50002;

EXEC dbo.sp_addmessage
    @msgnum   = 50002,
    @severity = 17,          -- จับได้ด้วย alert severity 17
    @msgtext  = N'Fabrikam: %s on server %s needs attention.',
    @lang     = 'us_english',
    @with_log = 'TRUE';
GO

RAISERROR (50002, 17, 1, N'index maintenance', @@SERVERNAME);
-- Expected: ข้อความเข้า log — ในแล็บ Lab 10 จะสร้าง alert severity 17
--           ที่จับข้อความเหล่านี้ได้ (รวมทั้ง RAISERROR 17 อื่น ๆ ด้วย)

/* ----------------------------------------------------------------------------
   5) xp_logevent — เขียน "เหตุการณ์" ลง log โดยไม่เป็น exception
      ต้อง sysadmin; ข้อความนับว่าเกิดใน master (alert @database_name อื่นไม่จับ)
      เหมาะเป็นตัวทดสอบ alert ที่สะอาดที่สุด
   ---------------------------------------------------------------------------- */
EXEC master.dbo.xp_logevent 60001, N'Fabrikam: test event via xp_logevent.', 'WARNING';
-- Expected: บรรทัด WARNING ลง SQL Server Error Log + Windows Application Log
EXEC xp_readerrorlog 0, 1, N'Fabrikam: test event';
-- Expected: เห็นบรรทัดที่เพิ่งเขียน

/* ----------------------------------------------------------------------------
   Clean-up — รันเมื่อจบเดโม/แล็บ
   ----------------------------------------------------------------------------
   IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50001)
       EXEC dbo.sp_dropmessage @msgnum = 50001;
   IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50002)
       EXEC dbo.sp_dropmessage @msgnum = 50002;
   GO
*/
