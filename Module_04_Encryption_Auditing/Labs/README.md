# Lab 4: Auditing Activity and Encrypting Data (บทที่ 4)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab04** (Exercise 1: Audit activity / Exercise 3: TDE + move DB) + [Microsoft Learn — SQL Server Audit](https://learn.microsoft.com/sql/relational-databases/security/auditing/sql-server-audit-database-engine?view=sql-server-ver17), [TDE](https://learn.microsoft.com/sql/relational-databases/security/encryption/transparent-data-encryption?view=sql-server-ver17), [Dynamic Data Masking](https://learn.microsoft.com/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> **สิ่งที่ปรับจากแล็บเดิม**: แล็บเดิมใช้ฐานข้อมูล `salesapp1` + instance ที่สอง (MIA-SQL\SQL2) และโฟลเดอร์ `D:\Labfiles\` — เราใช้ **AdventureWorks2025**, instance เดียว และเช็ค "ย้าย DB ที่เข้ารหัส" ด้วยสคริปต์ย้ายภายใน instance เดียวแทน

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025**
- โฟลเดอร์ที่ SQL Server **service account** เขียนได้ สองโฟลเดอร์ (audit log + backup): ตัวอย่างใช้ `C:\AuditLogs\` และ `C:\Backups\` — สร้างเองและแก้ path ในสคริปต์ให้ตรงเครื่องของคุณ
- รันด้วย login ที่มีสิทธิ์ `sysadmin` (สคริปต์แตะ server config, TDE และ backup)
- ⚠️ รันบน VM/instance ทดลองเท่านั้น — Exercise 2 เปิด TDE ซึ่งเข้ารหัส `tempdb` ของทั้ง instance

## Scenario

Fabrikam Retail กำลังรับ audit จากผู้ตรวจสอบความปลอดภัยของธนาคารพันธมิตร ผู้ตรวจขอสามอย่าง:

1. **หลักฐานว่าใครอ่าน/เพิ่มข้อมูลคำสั่งขาย** — ต้องมี audit log ที่แก้ไขไม่ได้
2. **การป้องกันไฟล์ฐานข้อมูลระดับ at-rest** — ต้องเปิด TDE พร้อมแผนย้าย/DR ที่ไม่พังเพราะ certificate
3. **การปกปิดข้อมูลบุคคลในตาราง HR** — user ธรรมดาไม่ควรเห็นเงินเดือน/อีเมลเต็ม

คุณเป็น DBA ต้องทำทั้งสามให้จบภายในสิบนาทีและทิ้งหลักฐานที่สะอาด

## Objectives

1. สร้าง Server Audit + Database Audit Specification จับ SELECT/INSERT และอ่านผลด้วย `sys.fn_get_audit_file`
2. เปิด TDE บน AdventureWorks2025 ตรวจ `encryption_state = 3` และสรุปขั้นตอนย้ายฐานข้อมูลที่เข้ารหัส
3. ใช้ Dynamic Data Masking บนตารางข้อมูลบุคคล HR พร้อมผู้ใช้ทดสอบ

---

## Setup — เตรียมพาธและฐาน

```sql
-- สร้างโฟลเดอร์ C:\AuditLogs\ และ C:\Backups\ ก่อน (หรือแก้ path ทั้งแล็บ)
-- ตรวจว่า SQL Server service account เขียนได้:
EXEC xp_fixeddrives;   -- ดูพื้นที่ (เป็นแค่จุดเริ่มตรวจ)
```

> **ต้องรู้ก่อน**: SQL Server เขียนไฟล์ด้วย **service account** เสมอ (เช่น `NT Service\MSSQLSERVER`) ไม่ใช่ user ของคุณ — folder permission ผิดคือสาเหตุอันดับหนึ่งที่ audit/TDE demo ล้ม

---

## Exercise 1: Audit Activity — Server Audit + Database Audit Specification

### Step 1 — สร้าง Server Audit (ปลายทางไฟล์) และเปิดใช้

> **ต้องรู้ก่อน**: Server Audit = ปลายทาง + ตัวรวม; `QUEUE_DELAY = 5000` รอ flush ทุก 5 วินาที (0 = ทันที); `ON_FAILURE = CONTINUE` คือเครื่องยังใช้ได้แม้เขียน log ไม่สำเร็จ ([CREATE SERVER AUDIT](https://learn.microsoft.com/sql/t-sql/statements/create-server-audit-transact-sql?view=sql-server-ver17))

```sql
USE master;
GO

CREATE SERVER AUDIT Lab04Audit
TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 50 MB, MAX_ROLLOVER_FILES = 10)
WITH (QUEUE_DELAY = 5000, ON_FAILURE = CONTINUE);
GO

ALTER SERVER AUDIT Lab04Audit WITH (STATE = ON);
GO
```

✅ **สังเกต**: ไฟล์ `.sqlaudit` ตัวแรกเกิดใน `C:\AuditLogs\` ทันที — ชื่อไฟล์จะเป็น `Lab04Audit_<GUID>_0.sqlaudit`

### Step 2 — Database Audit Specification จับ SELECT/INSERT

> **ต้องรู้ก่อน**: Database Audit Specification ระบุ action เจาะจงต่อ securable รูปแบบ `ADD (<action> ON <securable> BY <principal>)` — `BY public` = จับทุกคน ([CREATE DATABASE AUDIT SPECIFICATION](https://learn.microsoft.com/sql/t-sql/statements/create-database-audit-specification-transact-sql?view=sql-server-ver17)) เราใช้ตารางทดลอง `Lab.AuditDemoOrders` สำหรับ INSERT เพื่อไม่ยุ่งข้อมูลจริงของ AdventureWorks

```sql
USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Lab')
    CREATE SCHEMA Lab;
GO

IF OBJECT_ID('Lab.AuditDemoOrders', 'U') IS NOT NULL
    DROP TABLE Lab.AuditDemoOrders;
GO
CREATE TABLE Lab.AuditDemoOrders (OrderId int IDENTITY PRIMARY KEY, Note nvarchar(50));
GO

CREATE DATABASE AUDIT SPECIFICATION Lab04DbSpec
FOR SERVER AUDIT Lab04Audit
ADD (SELECT ON OBJECT::Sales.SalesOrderHeader BY public),
ADD (SELECT ON OBJECT::Sales.SalesOrderDetail BY public),
ADD (SELECT, INSERT ON OBJECT::Lab.AuditDemoOrders BY public)
WITH (STATE = ON);
GO
```

### Step 3 — สร้างกิจกรรมที่ถูกจับ

```sql
-- อ่าน (จับด้วย SELECT)
SELECT TOP 5 SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader ORDER BY SalesOrderID;

-- เพิ่ม (จับด้วย INSERT) — ตารางทดลอง
INSERT INTO Lab.AuditDemoOrders (Note) VALUES (N'Lab04 demo order');
DECLARE @id int = SCOPE_IDENTITY();
DELETE FROM Lab.AuditDemoOrders WHERE OrderId = @id;   -- DELETE ไม่ได้จับ (ไม่ใช่ที่ audit)
GO
```

✅ **สังเกต**: DELETE ผ่านและ *ไม่* ปรากฏใน audit เพราะเราไม่ได้ประกาศ DELETE — audit จับเฉพาะที่ประกาศเท่านั้น

### Step 4 — อ่านผลด้วย sys.fn_get_audit_file

```sql
SELECT event_time, action_id, server_principal_name, object_name,
       statement, succeeded
FROM sys.fn_get_audit_file('C:\AuditLogs\Lab04Audit*', default, default)
ORDER BY event_time DESC;
GO

-- กรองเฉพาะ SELECT/INSERT ที่เราเพิ่งทำ (action_id: SL = SELECT, IN = INSERT)
SELECT event_time, action_id, server_principal_name, statement
FROM sys.fn_get_audit_file('C:\AuditLogs\Lab04Audit*', default, default)
WHERE action_id IN ('SL', 'IN')
  AND object_name IN ('SalesOrderHeader', 'AuditDemoOrders')
ORDER BY event_time DESC;
GO
```

**Expected:** เห็นคำสั่ง SELECT ทั้งหมดและ INSERT ที่รันใน Step 3 — คอลัมน์ `statement` แสดงข้อความเดิม, `server_principal_name` ระบุใครรัน (ถ้า audit ยังไม่โชว์ รอ ~5 วินาที จาก QUEUE_DELAY แล้วรันใหม่)

### Step 5 — (ทางเลือก) เพิ่ม Server-level audit: FAILED_LOGIN_GROUP

```sql
USE master;
GO
CREATE SERVER AUDIT SPECIFICATION Lab04SrvSpec
FOR SERVER AUDIT Lab04Audit
ADD (FAILED_LOGIN_GROUP)
WITH (STATE = ON);
GO
-- จากนั้นลอง login ผิดพาสเวิร์ด (sqlcmd -S localhost -U NoSuchUser -P x)
-- แล้วอ่านไฟล์อีกครั้ง — จะเห็น event ล้มเหลว (succeeded = 0)
```

---

## Exercise 2: TDE — เข้ารหัสไฟล์ AdventureWorks2025 และแผนย้ายฐานข้อมูล

### Step 1 — DMK + certificate ใน master

> **ต้องรู้ก่อน**: ลำดับคีย์ TDE คือ SMK → DMK (master) → certificate → DEK (user DB) — cert คือชิ้นที่ต้อง "ยกไปด้วย" เมื่อย้ายเครื่อง ([TDE](https://learn.microsoft.com/sql/relational-databases/security/encryption/transparent-data-encryption?view=sql-server-ver17))

```sql
USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases
               WHERE name = 'master' AND is_master_key_encrypted_by_server = 1)
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025';
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Lab04_TDE_Cert')
    DROP CERTIFICATE Lab04_TDE_Cert;
GO
CREATE CERTIFICATE Lab04_TDE_Cert
    WITH SUBJECT = 'Lab04 TDE certificate';
GO
```

### Step 2 — Backup certificate + private key (หัวใจของแผนย้าย)

```sql
BACKUP CERTIFICATE Lab04_TDE_Cert
TO FILE = 'C:\Backups\Lab04_TDE_Cert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Backups\Lab04_TDE_Cert_pk.pvk',
    ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025'
);
GO
```

**Expected:** ได้ไฟล์สองตัว (.cer + .pvk) — SQL Server จะหยุด warn 33091 ที่เตือนเรื่อง backup cert ตั้งแต่บรรทัดนี้เป็นต้นไป

### Step 3 — สร้าง DEK และเปิด TDE

```sql
USE AdventureWorks2025;
GO
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE Lab04_TDE_Cert;
GO

ALTER DATABASE AdventureWorks2025 SET ENCRYPTION ON;
GO
```

### Step 4 — ตรวจสถานะ (รันซ้ำจนเสร็จ)

```sql
SELECT d.name, d.is_encrypted,
       ek.encryption_state,   -- 3 = เข้ารหัสเสร็จ
       ek.percent_complete,
       ek.key_algorithm
FROM sys.dm_database_encryption_keys ek
JOIN sys.databases d ON d.database_id = ek.database_id;
GO
```

**Expected:** `AdventureWorks2025` มี `encryption_state = 3` เมื่อ scan เสร็จ และ **`tempdb` กลายเป็น 3 ด้วยโดยอัตโนมัติ** — หาก percent_complete ค้างต่ำ อดใจไว้ (scan อ่านหน้าแล้วเขียนกลับทั้งไฟล์)

### Step 5 — Backup DB ที่เข้ารหัส (เข้ารหัสอัตโนมัติในไฟล์ .bak)

```sql
BACKUP DATABASE AdventureWorks2025
TO DISK = 'C:\Backups\AW2025_TDE.bak'
WITH COMPRESSION, CHECKSUM;   -- compression กับ TDE ทำงานร่วมกันตั้งแต่ 2019 CU5
GO
```

### Step 6 — พิสูจน์ว่า "ไม่มี cert = restore ไม่ได้" (จำลองย้ายใน instance เดียว)

> **ต้องรู้ก่อน**: แล็บเดิมทำขั้นนี้บน instance ที่สอง (MIA-SQL\SQL2) — เราจำลองใน instance เดียวโดยลบ cert ชั่วคราวแล้ว restore จาก backup จะ fail แบบเห็นกับตา **ทำบน VM ทดลองเท่านั้น**

```sql
-- (ก) ลบ cert จำลอง "เครื่องปลายทางที่ยังไม่มี cert"
-- (ต้องเขียนไฟล์ .bak ไว้ก่อนเพราะ restore จะต้องใช้)
USE master;
GO
DROP CERTIFICATE Lab04_TDE_Cert;
GO

-- (ข) พยายาม restore → คาดหวัง error 33111
RESTORE DATABASE AW2025_TDETest
FROM DISK = 'C:\Backups\AW2025_TDE.bak'
WITH MOVE 'AdventureWorks2025_Data' TO 'C:\Backups\AW2025TDETest.mdf',
     MOVE 'AdventureWorks2025_Log'  TO 'C:\Backups\AW2025TDETest.ldf',
     REPLACE;
GO
-- error: Cannot find server certificate with thumbprint ...

-- (ค) สร้าง cert กลับจากไฟล์ backup — เหมือนสิ่งที่ต้องทำบนเครื่องจริงตอนย้าย
CREATE CERTIFICATE Lab04_TDE_Cert
FROM FILE = 'C:\Backups\Lab04_TDE_Cert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Backups\Lab04_TDE_Cert_pk.pvk',
    DECRYPTION BY PASSWORD = 'Pa$$w0rd2025'
);
GO

-- (ง) restore ซ้ำ → ผ่าน
RESTORE DATABASE AW2025_TDETest
FROM DISK = 'C:\Backups\AW2025_TDE.bak'
WITH MOVE 'AdventureWorks2025_Data' TO 'C:\Backups\AW2025TDETest.mdf',
     MOVE 'AdventureWorks2025_Log'  TO 'C:\Backups\AW2025TDETest.ldf',
     REPLACE;
GO

SELECT TOP 5 CustomerID, AccountNumber FROM AW2025_TDETest.Sales.Customer;
GO
```

**Expected:** (ข) ล้มเหลวด้วย error 33111; (ง) สำเร็จ — นี่คือเหตุผลว่าทำไม cert backup ต้องอยู่ใน runbook ย้ายเครื่องเสมอ

### บทสรุป: ย้ายฐานข้อมูลที่เข้ารหัส (TDE) ต้องทำอะไรบ้าง

1. **เครื่องต้น**: `BACKUP CERTIFICATE` + private key เก็บในที่ปลอดภัย (สูญ cert = สูญ DB)
2. **เครื่องปลายทาง**: สร้าง DMK ใน `master` (ถ้ายังไม่มี) → `CREATE CERTIFICATE ... FROM FILE` + `WITH PRIVATE KEY (DECRYPTION BY PASSWORD)`
3. Restore/attach ฐานข้อมูล หรือเปิด Availability Group/Log Shipping ต่อตามปกติ
4. ถ้าใช้ EKM/AKV ต้องตั้งค่า provider ฝั่งใหม่ก่อนเหมือนกัน (SQL Server 2025 ใช้ managed identity ผ่าน Azure Arc ได้)
5. จำ: backup ที่เกิดหลังเปิด TDE เข้ารหัสแล้วเสมอ — กติกาเดียวกันทุกขั้นตอน

### Step 7 — Clean-up ของ Exercise 2 (ตามที่สัญญาไว้: ปิด TDE ตอนจบ)

```sql
USE master;
GO
DROP DATABASE IF EXISTS AW2025_TDETest;

ALTER DATABASE AdventureWorks2025 SET ENCRYPTION OFF;
GO
-- รอถอดรหัสเสร็จ (encryption_state = 1) แล้วรันต่อ:
USE AdventureWorks2025;
GO
DROP DATABASE ENCRYPTION KEY;
GO
USE master;
GO
DROP CERTIFICATE Lab04_TDE_Cert;
GO
-- ลบไฟล์ C:\Backups\*.bak/*.cer/*.pvk ด้วย OS เมื่อไม่ต้องใช้
```

---

## Exercise 3: Dynamic Data Masking — ปกปิดข้อมูลบุคคลตาราง HR

### Step 1 — สร้าง schema Lab + ตาราง HR ที่มี mask

> **ต้องรู้ก่อน**: DDM ปกปิดเฉพาะ "หน้าตา" — ข้อมูลบน disk เป็น plaintext จึงไม่แทนการเข้ารหัส ใช้กัน user ทั่วไปเผลอเห็นข้อมูล ([DDM](https://learn.microsoft.com/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17))

```sql
USE AdventureWorks2025;
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Lab')
    CREATE SCHEMA Lab;
GO

IF OBJECT_ID('Lab.EmployeePersonalData', 'U') IS NOT NULL
    DROP TABLE Lab.EmployeePersonalData;
GO
CREATE TABLE Lab.EmployeePersonalData
(
    empid int NOT NULL PRIMARY KEY,
    salary int MASKED WITH (FUNCTION = 'default()') NOT NULL,
    email_address varchar(255) MASKED WITH (FUNCTION = 'email()') NULL,
    company_credit_card_number varchar(30)
        MASKED WITH (FUNCTION = 'partial(0,"XXXX-",4)') NULL
);
GO

INSERT INTO Lab.EmployeePersonalData
    (empid, salary, email_address, company_credit_card_number)
VALUES
    (1, 25000, 'emp1@adventure-works.net', '9999-5656-4433-2211'),
    (2, 35000, 'qx3e@adventure-works.org', '9999-7676-5566-3141');
GO
```

### Step 2 — สร้างผู้ใช้ทดสอบ (ไม่มี UNMASK) และเทียบผล

```sql
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Lab04MaskTest')
    DROP USER Lab04MaskTest;
GO
CREATE USER Lab04MaskTest WITHOUT LOGIN;
GRANT SELECT ON Lab.EmployeePersonalData TO Lab04MaskTest;
GO

-- admin เห็นของจริง
SELECT * FROM Lab.EmployeePersonalData;

-- user ธรรมดาเห็น mask
EXECUTE AS USER = 'Lab04MaskTest';
SELECT * FROM Lab.EmployeePersonalData;
REVERT;
GO
```

**Expected:** admin เห็น `25000 / emp1@adventure-works.net / 9999-5656-4433-2211`; user ทดสอบเห็น `0 / eXXX@XXXX.com / XXXX-2211`

### Step 3 — GRANT UNMASK แล้วเทียบผล

```sql
GRANT UNMASK TO Lab04MaskTest;
GO

EXECUTE AS USER = 'Lab04MaskTest';
SELECT * FROM Lab.EmployeePersonalData;   -- เห็นของจริงทั้งหมด
REVERT;
GO

REVOKE UNMASK FROM Lab04MaskTest;
GO

-- (SQL Server 2022+) เปิดเฉพาะคอลัมน์อีเมล:
GRANT UNMASK ON OBJECT::Lab.EmployeePersonalData (email_address) TO Lab04MaskTest;
GO
```

### Step 4 — ตรวจ metadata ของ mask

```sql
SELECT t.name AS table_name, c.name AS column_name, c.masking_function
FROM sys.masked_columns mc
JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
JOIN sys.tables t ON t.object_id = mc.object_id;
GO
```

**Expected:** แถว salary/email/card พร้อม function ที่กำหนดไว้

---

## 🧹 Clean-up (รวมทั้งแล็บ)

```sql
USE AdventureWorks2025;
GO
ALTER DATABASE AUDIT SPECIFICATION Lab04DbSpec WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION Lab04DbSpec;
DROP TABLE IF EXISTS Lab.AuditDemoOrders;
DROP TABLE IF EXISTS Lab.EmployeePersonalData;
DROP USER IF EXISTS Lab04MaskTest;
GO

USE master;
GO
ALTER SERVER AUDIT SPECIFICATION Lab04SrvSpec WITH (STATE = OFF);
DROP SERVER AUDIT SPECIFICATION Lab04SrvSpec;
ALTER SERVER AUDIT Lab04Audit WITH (STATE = OFF);
DROP SERVER AUDIT Lab04Audit;
GO
-- ไฟล์ .sqlaudit และ .bak/.cer/.pvk อยู่ใน C:\AuditLogs\ / C:\Backups\
-- ลบด้วยระบบไฟล์เมื่อไม่ต้องใช้ (ถ้า Exercise 2 ยังไม่ cleanup ให้ทำ Step 7 ก่อน)
```

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม DELETE ใน Exercise 1 ไม่ถูกจับ?</b></summary>
เพราะ Database Audit Specification จับเฉพาะ action ที่ประกาศ (SELECT/INSERT) — อยากจับ DELETE ต้องเพิ่ม <code>ADD (DELETE ON ... BY public)</code> แล้วปิด-เปิด spec
</details>

<details>
<summary><b>2. อาการ restore ติด error 33111 ตอนย้ายเครื่องแก้อย่างไร?</b></summary>
สร้าง certificate ที่เครื่องปลายทางจากไฟล์ backup ก่อน (<code>CREATE CERTIFICATE ... FROM FILE</code> + private key) — ต้องทำก่อน restore ทุกครั้งถ้า DB เปิด TDE
</details>

<details>
<summary><b>3. DDM ทำให้ "ข้อมูลรั่วจากไฟล์ที่ถูกขโมย" น้อยลงหรือไม่?</b></summary>
ไม่ — DDM ปกปิดแค่ผล query ต่อ user ที่ไม่มี UNMASK ข้อมูลบน disk เป็น plaintext งานกันไฟล์หลุดคือ TDE (ทั้งไฟล์) หรือ Always Encrypted (ระดับคอลัมน์)
</details>
