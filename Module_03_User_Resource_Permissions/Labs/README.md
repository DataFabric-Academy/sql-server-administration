# Lab 3: Authorizing Access to Objects, Code and Schemas (บทที่ 3)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab03** (Exercise 1–3: Object / Code / Schema permissions) + [Microsoft Learn — GRANT (Transact-SQL)](https://learn.microsoft.com/sql/t-sql/statements/grant-transact-sql?view=sql-server-ver17), [Row-Level Security](https://learn.microsoft.com/sql/relational-databases/security/row-level-security?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> **สิ่งที่ปรับจากแล็บเดิม**: แล็บเดิมใช้ฐานข้อมูล `InternetSales` + Windows domain group (`9EXPERT\...`) — เราใช้ **AdventureWorks2025** + SQL Authentication / `WITHOUT LOGIN` user แทน ไม่ต้องมี Active Directory

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** พร้อมใช้ (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- รันด้วย login ที่มีสิทธิ์ `sysadmin` หรือ `ALTER ANY LOGIN` + `ALTER ANY USER` + `ALTER ANY ROLE` บน AdventureWorks2025
- รันบน VM/instance ทดลองเท่านั้น — สคริปต์สร้าง/ลบ login และแก้ permissions

## Scenario

บริษัท "Fabrikam Retail" จะเปิดระบบรายงานภายในให้พนักงานสามกลุ่มใช้:

1. **เว็บแอปส่วนหน้า** (`Lab03WebApp`) — เห็นข้อมูลคำสั่งขายอย่างเดียว และต้อง **ไม่เห็นเงินเดือนพนักงาน**
2. **พนักงาน HR** (`Lab03HRUser`) — อ่านได้ทั้ง schema ข้อมูลบุคลากร แต่รัน proc ขายไม่ได้
3. **ผู้จัดการ** (`Lab03Manager`) — เข้าถึงเงินเดือนผ่าน stored procedure เท่านั้น (ไม่มีสิทธิ์อ่านตารางตรง ๆ)

คุณเป็น DBA ต้องออกแบบสิทธิ์ตาม Principle of Least Privilege แล้วพิสูจน์ด้วย `EXECUTE AS` ว่าแต่ละกลุ่มเห็นแค่ที่ควรเห็น

## Objectives

1. กำหนดสิทธิ์ระดับ object และ **คอลัมน์** (SELECT/DENY บนคอลัมน์เงินเดือน)
2. มอบสิทธิ์รันโค้ด (`GRANT EXECUTE`) ให้ผู้จัดการอ่านเงินเดือนผ่าน proc ที่รวม ownership chaining และ `EXECUTE AS OWNER`
3. กำหนดสิทธิ์ระดับ **schema** ด้วย role + `GRANT ... ON SCHEMA::HumanResources`

---

## Setup — เตรียม principals (รันก่อนทุก Exercise)

> **ต้องรู้ก่อน**: `CREATE USER ... WITHOUT LOGIN` สร้าง user ใน database ที่ไม่มี login ระดับ server รองรับ — ใช้สำหรับ role/service และทดสอบด้วย `EXECUTE AS` ได้เลย เหมาะกับแล็บที่ไม่มี domain ([CREATE USER](https://learn.microsoft.com/sql/t-sql/statements/create-user-transact-sql?view=sql-server-ver17))

```sql
USE AdventureWorks2025;
GO

-- (ถ้ารัน Setup ซ้ำ ให้ลบของเดิมก่อน — สคริปต์ Clean-up อยู่ท้ายแล็บ)
-- สร้าง roles
CREATE ROLE Lab03_WebAppRole;
CREATE ROLE Lab03_ManagerRole;
CREATE ROLE Lab03_HRRole;
GO

-- เว็บแอปใช้ SQL Authentication (สมมติเป็นแอปจริง)
CREATE LOGIN Lab03WebApp WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
CREATE USER Lab03WebApp FOR LOGIN Lab03WebApp;
ALTER ROLE Lab03_WebAppRole ADD MEMBER Lab03WebApp;

-- ผู้จัดการ + พนักงาน HR ใช้ WITHOUT LOGIN (ทดสอบด้วย EXECUTE AS ได้)
CREATE USER Lab03Manager WITHOUT LOGIN;
CREATE USER Lab03HRUser  WITHOUT LOGIN;
ALTER ROLE Lab03_ManagerRole ADD MEMBER Lab03Manager;
ALTER ROLE Lab03_HRRole      ADD MEMBER Lab03HRUser;
GO
```

✅ **สังเกต**: รัน `SELECT name, type_desc FROM sys.database_principals WHERE name LIKE 'Lab03%'` ตรวจว่า user ครบ 3 ตัว + role ครบ 3 ตัว

---

## Exercise 1: Object Permissions — SELECT/DENY บนคอลัมน์เงินเดือน

### Step 1 — ให้เว็บแอปอ่านคำสั่งขาย (ตาราง + view)

> **ต้องรู้ก่อน**: `GRANT SELECT ON <object> TO <principal>` — เรายึด 2-part name เสมอ และมอบให้ **role** ไม่ใช่ user รายคน เพื่อรองรับสมาชิกเปลี่ยนได้

```sql
GRANT SELECT ON Sales.SalesOrderHeader TO Lab03_WebAppRole;
GRANT SELECT ON Sales.SalesOrderDetail TO Lab03_WebAppRole;
GO
```

✅ **สังเกต**: ยังไม่แตะ schema อื่น — สิทธิ์เป็นศูนย์จนกว่าจะ GRANT

### Step 2 — เงินเดือน: ผู้จัดการเห็นได้, เว็บแอปโดน DENY ระดับคอลัมน์

> **ต้องรู้ก่อน**: `DENY SELECT ON OBJECT::schema.table (column)` ปิดคอลัมน์เดียว — ตามกฎ DENY ชนะ GRANT ทุกขอบเขต (มีข้อยกเว้นทางเทคนิค "column grant beats table deny" ถ้าไม่ได้เปิด Common Criteria — ดู [Section 1](../Sections/01_Object_Permissions/README.md))

```sql
-- ผู้จัดการอ่านได้ทั้งตารางค่าจ้าง
GRANT SELECT ON HumanResources.EmployeePayHistory TO Lab03_ManagerRole;

-- เว็บแอป: ปิดคอลัมน์ Rate (เงินเดือน) ชัดเจน — กันไม่ให้ role อื่นปล่อยทาง
DENY SELECT ON OBJECT::HumanResources.EmployeePayHistory (Rate)
    TO Lab03_WebAppRole;
GO
```

✅ **สังเกต**: `OBJECT::` ทำให้ชัดว่าอ้างระดับ object และวงเล็บ `(Rate)` ระบุคอลัมน์

### Step 3 — พิสูจน์ด้วย EXECUTE AS

```sql
-- เว็บแอปอ่านคำสั่งขายได้
EXECUTE AS USER = 'Lab03WebApp';
SELECT TOP 3 SalesOrderID, OrderDate, TotalDue FROM Sales.SalesOrderHeader;
REVERT;
GO

-- เว็บแอปอ่านเงินเดือนไม่ได้ (คอลัมน์ Rate ถูก DENY)
EXECUTE AS USER = 'Lab03WebApp';
SELECT BusinessEntityID, Rate FROM HumanResources.EmployeePayHistory;   -- error 229
REVERT;
GO

-- ผู้จัดการอ่านได้
EXECUTE AS USER = 'Lab03Manager';
SELECT TOP 3 BusinessEntityID, Rate FROM HumanResources.EmployeePayHistory;
REVERT;
GO
```

**Expected:** query แรกคืนแถวคำสั่งขาย; query ที่สอง error **229** ("The SELECT permission was denied on the column 'Rate'..."); query ที่สามคืนค่า Rate ปกติ

### Step 4 — เรียกคืน (REVOKE) แล้วเทียบผล

```sql
REVOKE SELECT ON Sales.SalesOrderHeader FROM Lab03_WebAppRole;

EXECUTE AS USER = 'Lab03WebApp';
SELECT TOP 1 SalesOrderID FROM Sales.SalesOrderHeader;   -- error 229 อีกครั้ง
REVERT;
GO

-- ให้คืนกลับมาใช้ต่อใน Exercise ถัดไป
GRANT SELECT ON Sales.SalesOrderHeader TO Lab03_WebAppRole;
GO
```

**Expected:** `REVOKE` กลับสถานะเป็น "ไม่ได้กำหนด" — user หยุดเข้าถึงทันทีโดยไม่ error ตอน revoke

---

## Exercise 2: Code Permissions — ผู้จัดการอ่านเงินเดือนผ่าน Proc

### Step 1 — สร้าง proc ใน schema ที่เจ้าของเดียวกับตาราง

> **ต้องรู้ก่อน**: proc และตารางอยู่ใน `HumanResources` (owner เดียวกัน) → **ownership chaining** ข้ามการตรวจสิทธิ์ statement ภายใน proc ผู้เรียกต้องมีแค่ `EXECUTE` ([Ownership chains](https://learn.microsoft.com/sql/relational-databases/security/ownership-chains?view=sql-server-ver17))

```sql
IF OBJECT_ID('HumanResources.uspGetPayInfo', 'P') IS NOT NULL
    DROP PROCEDURE HumanResources.uspGetPayInfo;
GO
CREATE PROCEDURE HumanResources.uspGetPayInfo
    @BusinessEntityID int
AS
    SET NOCOUNT ON;
    SELECT BusinessEntityID, Rate, PayFrequency
    FROM HumanResources.EmployeePayHistory
    WHERE BusinessEntityID = @BusinessEntityID;
GO

GRANT EXECUTE ON HumanResources.uspGetPayInfo TO Lab03_ManagerRole;
GO
```

✅ **สังเกต**: ยังไม่ได้ GRANT SELECT บนตารางให้ใครใน role ผู้จัดการเลย

### Step 2 — พิสูจน์ chaining: EXECUTE ได้ แต่อ่านตารางตรง ๆ ไม่ได้

```sql
EXECUTE AS USER = 'Lab03Manager';
EXEC HumanResources.uspGetPayInfo @BusinessEntityID = 2;     -- OK — chaining ทำงาน
SELECT Rate FROM HumanResources.EmployeePayHistory;          -- error 229 — ไม่มีสิทธิ์ตรง
REVERT;
GO
```

**Expected:** proc คืนแถวค่าจ้าง; SELECT ตรง error — นี่คือรูปแบบที่ออกแบบไว้: เข้าถึงข้อมูลได้เฉพาะทางที่ proc กำหนด

### Step 3 — EXECUTE AS OWNER กับ proc ที่มี dynamic SQL

> **ต้องรู้ก่อน**: dynamic SQL (`EXEC(...)`) หัก ownership chaining — สิทธิ์ถูกประเมินใหม่ในบริบทผู้เรียก วิธีแก้คือ `WITH EXECUTE AS OWNER` หรือ certificate signing ([Section 2](../Sections/02_Code_Permissions/README.md))

```sql
IF OBJECT_ID('HumanResources.uspGetPayInfoDyn', 'P') IS NOT NULL
    DROP PROCEDURE HumanResources.uspGetPayInfoDyn;
GO
CREATE PROCEDURE HumanResources.uspGetPayInfoDyn
    @BusinessEntityID int
WITH EXECUTE AS OWNER
AS
    SET NOCOUNT ON;
    EXEC ('SELECT BusinessEntityID, Rate FROM HumanResources.EmployeePayHistory
           WHERE BusinessEntityID = ' + @BusinessEntityID);
GO

GRANT EXECUTE ON HumanResources.uspGetPayInfoDyn TO Lab03_ManagerRole;
GO

-- ทดสอบเทียบสองรูปแบบ
EXECUTE AS USER = 'Lab03Manager';
EXEC HumanResources.uspGetPayInfoDyn @BusinessEntityID = 2;  -- OK — รันในบริบท OWNER
REVERT;
GO
```

**Expected:** proc dynamic ทำงานได้เพราะ `EXECUTE AS OWNER` ยกบริบทข้างในเป็นเจ้าของ proc — จุดต่างกับ Step 2 คือบริบทภายในเปลี่ยน (audit จะเห็นเป็น owner ไม่ใช่ผู้เรียก)

---

## Exercise 3: Schema Permissions — Role-based Grant ทั้ง Schema

### Step 1 — GRANT 4 สิทธิ์ทั้ง schema ให้ role HR

> **ต้องรู้ก่อน**: `GRANT ... ON SCHEMA::HumanResources` ครอบทุก object ใน schema **รวม object ที่จะถูกสร้างใหม่** — ต่างจาก object grant ที่ต้องรันใหม่ทุกครั้ง

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HumanResources
    TO Lab03_HRRole;
GO
```

### Step 2 — พิสูจน์สิทธิ์ 4 อย่างจริง

```sql
EXECUTE AS USER = 'Lab03HRUser';

-- SELECT
SELECT TOP 3 DepartmentID, Name FROM HumanResources.Department;

-- INSERT (รหัส 990 กันชน PK)
INSERT INTO HumanResources.Department (DepartmentID, Name, GroupName)
VALUES (990, N'Lab03-Temp', N'Executive General and Administration');

-- UPDATE
UPDATE HumanResources.Department SET Name = N'Lab03-Temp-Updated'
WHERE DepartmentID = 990;

-- DELETE
DELETE FROM HumanResources.Department WHERE DepartmentID = 990;

REVERT;
GO
```

**Expected:** ทั้งสี่ statement ผ่าน — และ schema อื่นยังปิด: `SELECT TOP 1 * FROM Production.Product` ภายใต้ `EXECUTE AS USER = 'Lab03HRUser'` ต้อง error 229 (ลองดู)

### Step 3 — ทดสอบ "ครอบตารางใหม่อัตโนมัติ"

```sql
CREATE TABLE HumanResources.Lab03NewTable (Id int, Note nvarchar(50));
GO

EXECUTE AS USER = 'Lab03HRUser';
INSERT INTO HumanResources.Lab03NewTable VALUES (1, N'ไม่ต้อง GRANT เพิ่ม');
SELECT * FROM HumanResources.Lab03NewTable;
REVERT;
GO
```

**Expected:** ทำงานได้ทันที — ขอบเขต schema grant ครอบ object ที่เกิดหลังจากมอบสิทธิ์

### Step 4 — ตรวจทุกอย่างที่แล็บนี้ให้ไว้

```sql
-- สิทธิ์ระดับ schema
SELECT pr.name AS grantee, pe.permission_name, SCHEMA_NAME(pe.major_id) AS schema_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 3 AND pr.name LIKE 'Lab03%';

-- สิทธิ์ระดับ object (เลือกเฉพาะของแล็บ)
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id) AS object_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 1
  AND OBJECT_NAME(pe.major_id) IN ('EmployeePayHistory', 'SalesOrderHeader',
                                   'uspGetPayInfo', 'uspGetPayInfoDyn');
GO
```

**Expected:** แถวทั้งหมดสอดคล้องกับที่ GRANT/DENY ไว้ — แถว `DENY` (state_desc = DENY) ต้องเห็น `EmployeePayHistory` ของ `Lab03_WebAppRole`

---

## 🧹 Clean-up

```sql
USE AdventureWorks2025;
GO
DROP PROCEDURE IF EXISTS HumanResources.uspGetPayInfo;
DROP PROCEDURE IF EXISTS HumanResources.uspGetPayInfoDyn;
DROP TABLE IF EXISTS HumanResources.Lab03NewTable;

REVOKE SELECT ON SCHEMA::HumanResources FROM Lab03_HRRole;

ALTER ROLE Lab03_WebAppRole DROP MEMBER Lab03WebApp;
ALTER ROLE Lab03_ManagerRole DROP MEMBER Lab03Manager;
ALTER ROLE Lab03_HRRole DROP MEMBER Lab03HRUser;
DROP ROLE Lab03_WebAppRole;
DROP ROLE Lab03_ManagerRole;
DROP ROLE Lab03_HRRole;

REVOKE SELECT ON Sales.SalesOrderHeader FROM Lab03_WebAppRole;
REVOKE SELECT ON Sales.SalesOrderDetail FROM Lab03_WebAppRole;
REVOKE SELECT ON HumanResources.EmployeePayHistory FROM Lab03_ManagerRole;
REVOKE SELECT ON OBJECT::HumanResources.EmployeePayHistory (Rate) FROM Lab03_WebAppRole;
REVOKE EXECUTE ON HumanResources.uspGetPayInfo FROM Lab03_ManagerRole;
REVOKE EXECUTE ON HumanResources.uspGetPayInfoDyn FROM Lab03_ManagerRole;

DROP USER Lab03WebApp;
DROP USER Lab03Manager;
DROP USER Lab03HRUser;
GO

USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'Lab03WebApp')
    DROP LOGIN Lab03WebApp;
GO
-- จบแล็บ — ตรวจว่าไม่เหลือจากแล็บ:
-- SELECT name FROM sys.database_principals WHERE name LIKE 'Lab03%';
```

> `DROP X IF EXISTS` syntax ใช้ได้ตั้งแต่ SQL Server 2016

## Quiz ท้ายแล็บ

<details>
<summary><b>1. ทำไม DENY คอลัมน์ Rate ให้เว็บแอปต้องเขียนเป็น OBJECT::... (Rate)?</b></summary>
เพราะ DENY ระดับ <strong>คอลัมน์</strong> ต้องระบุคอลัมน์ในวงเล็บหลังชื่อตาราง (หรือหลัง <code>OBJECT::</code>) — DENY แบบไม่มีวงเล็บจะไปปิดทั้งตาราง ซึ่งให้ผลต่างกันกับสถานการณ์ "GRANT คอลัมน์ที่ลึกกว่า"
</details>

<details>
<summary><b>2. ผู้จัดการ EXEC proc ได้ แต่ SELECT ตารางไม่ได้ — เกิดจากกลไกอะไร?</b></summary>
Ownership chaining: proc และตารางอยู่ใน schema <code>HumanResources</code> ที่มีเจ้าของเดียวกัน SQL Server จึงข้ามการตรวจสิทธิ์ statement ภายใน proc และตรวจเฉพาะสิทธิ์ EXECUTE จุดเริ่ม
</details>

<details>
<summary><b>3. ถ้า proc ใน Exercise 2 ใช้ dynamic SQL แบบไม่ใส่ EXECUTE AS OWNER จะเกิดอะไร?</b></summary>
error 229 จากข้างใน proc — เพราะ ownership chaining ไม่ทำงานกับ dynamic SQL สิทธิ์ถูกประเมินใหม่ในบริบทผู้เรียก แก้ได้ด้วย EXECUTE AS OWNER หรือ certificate signing
</details>
