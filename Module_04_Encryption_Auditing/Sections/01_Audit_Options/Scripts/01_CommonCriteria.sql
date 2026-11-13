-- ============================================================================
-- Section 01 — Demo 01: Common Criteria Compliance
-- ตรวจค่าปัจจุบัน + ขั้นตอนเปิด/ปิด (ต้องรีสตาร์ท SQL Server service หลังเปลี่ยน)
-- ระวัง: มี performance overhead และรับรองเฉพาะ Enterprise edition — รันบน VM ทดลอง
-- ============================================================================
USE master;
GO

-- ---------- ขั้น 1: ดูค่าปัจจุบัน ----------
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

SELECT name, value_in_use, value, description
FROM sys.configurations
WHERE name = 'common criteria compliance enabled';
GO
-- value_in_use = 0 หมายถึงยังไม่เปิด

-- ---------- ขั้น 2: (ทางเลือก) เปิดใช้ Common Criteria Compliance ----------
-- ให้คอมเมนต์ไว้ — ต้องการรันจริงเมื่อทดสอบบน VM เท่านั้น (รีสตาร์ทหลังรัน!)
-- EXEC sp_configure 'common criteria compliance enabled', 1;
-- RECONFIGURE WITH OVERRIDE;
-- GO
-- หลังรัน: restart SQL Server service ใน SQL Server Configuration Manager
-- แล้ว query ซ้ำขั้น 1 — value_in_use จะเป็น 1

-- ---------- ขั้น 3: เมื่อเปิดแล้ว สิ่งที่เปลี่ยน ----------
-- 3a) Login statistics ต่อ session (ต้องเปิด CCC ก่อนจึงมีค่า)
SELECT session_id, login_name,
       last_successful_logon,      -- เวลาล็อกอินสำเร็จล่าสุด
       last_unsuccessful_logon,    -- เวลาล็อกอินล้มเหลวล่าสุด
       unsuccessful_logons_between_logons
FROM sys.dm_exec_sessions
WHERE is_user_process = 1;
GO

-- 3b) พฤติกรรม permission เปลี่ยน: เมื่อเปิด CCC
--     table-level DENY จะ "ชนะ" column-level GRANT (ต่างจาก default)
-- ทดสอบได้ด้วยชุดคำสั่งแบบ Module 03 Section 01 (column permissions)
-- หลังเปิด CCC แล้วลอง: DENY SELECT ทั้งตาราง + GRANT SELECT บนคอลัมน์เดียว
-- ผลเมื่อเปิด CCC: อ่านคอลัมน์ที่ GRANT ก็ยังโดนปฏิเสธ

-- ---------- ขั้น 4: (ทางเลือก) ปิดกลับ ----------
-- EXEC sp_configure 'common criteria compliance enabled', 0;
-- RECONFIGURE WITH OVERRIDE;
-- GO
-- แล้ว restart SQL Server service อีกครั้ง

-- จบสคริปต์ (ไม่มี object ค้าง — เปลี่ยนแค่ server config)
