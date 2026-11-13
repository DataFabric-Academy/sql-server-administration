-- ============================================================================
-- Module 09, Section 2 — สร้าง/จัดการ Credential
-- ปรับจาก Old/Demofiles/Mod09 (Demo 2 - credential.sql):
--   แทน domain account ADVENTUREWORKS\FileOps ด้วย local account MACHINE\FileOps
--   (ไม่ต้องมี Active Directory) + เพิ่มตัวอย่าง credential สำหรับ backup to S3
-- ต้องมี: สิทธิ์ sysadmin (หรือ ALTER ANY CREDENTIAL)
-- หมายเหตุ: บน Windows ให้แทน MACHINE ด้วยชื่อเครื่อง และสร้าง Windows local
--   account ชื่อ FileOps ด้วยรหัสผ่าน Pa$$w0rd2025 ก่อน (net user หรือ lusrmgr.msc)
--   บน Linux/container: ส่วน Windows credential จะสร้างได้แต่ใช้จริงไม่ได้ —
--   ใช้ตัวอย่าง S3 credential แทน
-- idempotent — ลบของเดิมก่อนสร้างใหม่
-- ============================================================================

USE master;
GO

/* ----------------------------------------------------------------------------
   1) สร้าง credential ที่ห่อ Windows account (สำหรับ proxy ใน Section 3)
      แทน MACHINE ด้วยชื่อเครื่องของคุณ เช่น LABPC1\FileOps
   ---------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'FileOperation')
    DROP CREDENTIAL FileOperation;

CREATE CREDENTIAL FileOperation
    WITH IDENTITY = N'MACHINE\FileOps',      -- Windows local account บนเครื่องนี้
         SECRET   = N'Pa$$w0rd2025';         -- รหัสผ่านของ account นั้น
GO

-- ตรวจว่าถูกเก็บแล้ว (SECRET ไม่เคยแสดงใน catalog — เข้ารหัสด้วย Service Master Key)
SELECT name, credential_id, identity_desc
FROM sys.credentials
WHERE name = N'FileOperation';
-- Expected: 1 แถว ชื่อ FileOperation และ identity_desc แสดง MACHINE\FileOps

/* ----------------------------------------------------------------------------
   2) เปลี่ยนค่า — ใช้เมื่อหมุนรหัสผ่านหรือเปลี่ยน account
      (job/proxy ที่อ้าง credential นี้จะใช้ค่าใหม่ทันที — ไม่ต้องแก้ proxy)
   ---------------------------------------------------------------------------- */
-- ALTER CREDENTIAL FileOperation
--     WITH IDENTITY = N'MACHINE\FileOps',
--          SECRET   = N'Pa$$w0rd';        -- รหัสผ่านใหม่หลังหมุน (ตัวอย่างห้องเรียน)

/* ----------------------------------------------------------------------------
   3) ตัวอย่างอื่น: credential สำหรับ backup to S3-compatible storage
      (cross-ref Module 6) — ชื่อ credential ต้องตรงกับ URL ที่ BACKUP TO URL ใช้
      ค่า key ด้านล่างคือตัวอย่างทางการของ AWS เท่านั้น — ห้ามใช้ของจริง
   ---------------------------------------------------------------------------- */
-- IF EXISTS (SELECT 1 FROM sys.credentials
--            WHERE name = N's3://s3.amazonaws.com:443/backups-fabrikam')
--     DROP CREDENTIAL [s3://s3.amazonaws.com:443/backups-fabrikam];
--
-- CREATE CREDENTIAL [s3://s3.amazonaws.com:443/backups-fabrikam]
--     WITH IDENTITY = N'S3 Access Key',
--          SECRET   = N'AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
--
-- -- แล้วใช้ได้เลย: (มี bucket จริงเท่านั้น)
-- BACKUP DATABASE [AdventureWorks2025]
-- TO URL = 's3://s3.amazonaws.com:443/backups-fabrikam/AW2025_full.bak'
-- WITH COMPRESSION, CHECKSUM;

/* ----------------------------------------------------------------------------
   4) ตรวจว่า credential ไหนถูก proxy ใช้อยู่ (มีแถว proxy เมื่อทำ Section 3)
      รันก่อน DROP credential อะไรก็ตามเพื่อไม่ทำ proxy พังเงียบ ๆ
   ---------------------------------------------------------------------------- */
SELECT c.name AS credential_name, c.identity_desc,
       p.name AS proxy_name, p.enabled AS proxy_enabled
FROM sys.credentials AS c
LEFT JOIN msdb.dbo.sysproxies AS p ON p.credential_id = c.credential_id
ORDER BY c.name;
-- Expected ก่อน Section 3: แถว FileOperation ที่ proxy_name = NULL (ยังไม่มีใครอ้าง)

/* ----------------------------------------------------------------------------
   Clean-up — ลบ credential เมื่อจบเดโม (ทำหลังลบ proxy ที่อ้างแล้ว)
   ----------------------------------------------------------------------------
   -- (ถ้าทำ Section 3 แล้ว: ลบ proxy ก่อน ดูสคริปต์ Clean-up ของ Section 3)
   USE master;
   IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'FileOperation')
       DROP CREDENTIAL FileOperation;
   GO
*/
