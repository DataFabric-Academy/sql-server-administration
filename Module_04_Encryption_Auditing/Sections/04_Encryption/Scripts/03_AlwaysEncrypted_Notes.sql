-- ============================================================================
-- Section 04 — Demo 03: Always Encrypted — ขั้นตอนที่ทำได้ด้วย T-SQL จริง
-- ฐานข้อมูล: AdventureWorks2025
-- ความจริงเรื่องเครื่องมือ (ต้องรู้ก่อนลอง):
--   - CMK (Column Master Key) จริงเก็บฝั่ง client (cert store / Azure Key Vault)
--   - การ "สร้าง key + เข้ารหัส CEK" ต้องทำผ่าน SSMS Always Encrypted wizard,
--     PowerShell (SqlServer module), หรือ client SDK — ไม่ใช่ T-SQL ล้วน
--   - T-SQL ทำได้คือ: ลงทะเบียน metadata (CMK definition), อ่าน DMV, สร้างตาราง
--     ที่มีคอลัมน์ ENCRYPTED WITH เมื่อ CMK/CEK พร้อมแล้ว
-- สคริปต์นี้จึงแบ่งเป็น: (A) ขั้นที่ทำด้วย T-SQL รันได้ (B) checklist ผ่าน wizard
-- ============================================================================
USE AdventureWorks2025;
GO

-- ============================================================
-- (A) ขั้นที่ T-SQL ทำได้จริง
-- ============================================================

-- ---------- A1: ดู CMK/CEK ที่มีอยู่ (จะว่างจนกว่า wizard สร้าง) ----------
SELECT * FROM sys.column_master_keys;
SELECT * FROM sys.column_encryption_keys;
SELECT * FROM sys.column_encryption_key_values;
GO

-- ---------- A2: ลงทะเบียน CMK definition (metadata เท่านั้น) ----------
-- แก้ THUMBPRINT เป็น certificate จริงใน cert store ของเครื่อง (Current User\My)
-- ที่คุณจะใช้ถือ master key — สร้าง self-signed cert ได้ด้วย PowerShell:
--   New-SelfSignedCertificate -Subject "CN=AW CMK" -CertStoreLocation "Cert:\CurrentUser\My"
--   -KeyExportPolicy Exportable -KeySpec KeyExchange -KeyLength 2048 -HashAlgorithm SHA256
IF NOT EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name = 'CMK_AW_Demo')
BEGIN
    CREATE COLUMN MASTER KEY CMK_AW_Demo
    WITH
    (
        KEY_STORE_PROVIDER_NAME = N'MSSQL_CERTIFICATE_STORE',
        KEY_PATH = N'CurrentUser/My/PUT-THUMBPRINT-HERE'
    );
END
GO

-- ---------- A3: โครงตารางที่จะใส่คอลัมน์เข้ารหัส (สร้างหลังมี CEK) ----------
-- รูปแบบคอลัมน์เข้ารหัส (รันได้ "หลัง" CEK_AW_Demo ถูกสร้างด้วย wizard):
-- CREATE TABLE Lab.CreditCardsDemo
-- (
--     Id int NOT NULL PRIMARY KEY,
--     CardNumber nvarchar(50) COLLATE Latin1_General_BIN2 ENCRYPTED WITH
--     (
--         ENCRYPTION_TYPE = DETERMINISTIC,
--         ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256',
--         COLUMN_ENCRYPTION_KEY = CEK_AW_Demo
--     ),
--     CardHolder nvarchar(100)
-- );
-- หมายเหตุ: คอลัมน์เข้ารหัสต้องใช้ collation ตระกูล BIN2

-- ---------- A4: (ทางเลือก) secure enclaves ----------
-- Always Encrypted with secure enclaves (2019+) ให้ query บนข้อมูลเข้ารหัสได้มากขึ้น
-- (comparison, pattern matching; 2022 เพิ่ม JOIN/GROUP BY/ORDER BY)
-- database scoped configuration ที่เกี่ยว: ALLOW_ENCLAVE_QUERIES (ค่าคงค้างเมื่อ wizard
-- หรือ PowerShell ตั้งไว้แล้วเท่านั้น — จะว่างจนกว่าจะได้ตั้ง)
SELECT name, value, value_for_secondary
FROM sys.database_scoped_configurations
WHERE name = 'ALLOW_ENCLAVE_QUERIES';
GO
-- การตั้งค่า enclave จริง (enclave-enabled CMK + ALLOW_ENCLAVE_QUERIES) ทำผ่าน
-- wizard/PowerShell คู่กับการเชื่อมต่อที่มี Attestation URL ตาม HGS/host attestation

-- ============================================================
-- (B) Checklist ทำผ่านเครื่องมือ (ทำตามลำดับนี้นอก T-SQL)
-- ============================================================
-- B1. สร้าง self-signed certificate ใน cert store ฝั่ง client (PowerShell ด้านบน)
-- B2. SSMS: ขวาเมาส์บน database → Tasks → Encrypt Columns (Always Encrypted wizard)
--     - เลือกคอลัมน์ (เช่น CardNumber)
--     - สร้าง CEK ใหม่ โดยชี้ CMK ไปที่ certificate ใน B1
--     - เลือก DETERMINISTIC (join/equality ได้) หรือ RANDOMIZED (ปลอดภัยสุด)
-- B3. ใน connection ที่ใช้ query: เปิด Column Encryption Setting = Enabled
--     (SSMS: Options → Additional Connection Parameters หรือใน app.config)
-- B4. ทดสอบ:
--     - DBA (connection ปกติ) SELECT → เห็น ciphertext
--     - client driver ที่เปิด CE setting → เห็น plaintext และ INSERT ได้ปกติ
-- B5. ตรวจหลังใช้งาน:
SELECT OBJECT_NAME(c.object_id) AS table_name, c.name AS column_name,
       c.encryption_type_desc, c.encryption_algorithm_desc, c.column_encryption_key_id
FROM sys.columns c
WHERE c.encryption_type IS NOT NULL;
GO

-- ---------- Cleanup (เฉพาะ metadata ที่ A2 สร้าง — ถ้าไม่ต้องการเก็บ) ----------
-- DROP COLUMN MASTER KEY CMK_AW_Demo;   -- ลบได้เมื่อไม่มี CEK ผูกอยู่
-- จบสคริปต์
