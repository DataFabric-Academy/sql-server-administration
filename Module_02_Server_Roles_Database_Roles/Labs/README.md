# Lab 2: Server Roles, Database Roles และ Application Roles (บทที่ 2)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab02** (Assigning Server and Database Roles) + [Microsoft Learn — Server-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> ต้นฉบับใช้ AD groups (HumanResources_Users) — เวอร์ชันนี้ปรับเป็น SQL logins บนเครื่องเดียว และหมายเหตุวิธีทำกับ domain จริงแยกไว้

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025**
- sysadmin บน instance
- อ่านคู่: [Section 1](../Sections/01_Server_Roles/README.md), [Section 2](../Sections/02_Fixed_Database_Roles/README.md), [Section 3](../Sections/03_User_Defined_Roles/README.md), [Glossary](../../Glossary.md)

## Scenario

Adventure Works ตั้งฝ่าย Database Managers ใหม่ คุณต้องออกแบบ role model ให้ครอบคลุมทั้งระดับ server และ database โดยห้ามให้ sysadmin กับทีมงานทั่วไป และต้องมีสิทธิ์เฉพาะแอป Purchasing สำหรับระบบออเดอร์

## Objectives

1. ออกแบบ server-level access ด้วย user-defined server role (ไม่ใช้ sysadmin)
2. สร้าง user-defined database roles พร้อมสิทธิ์ตาม schema และตรวจสอบพฤติกรรม
3. ใช้ application role คุมสิทธิ์ของระบบ purchasing

---

## Exercise 1: Server Roles (Section 1)

### Step 1 — สร้าง logins สำหรับทีม Database Managers

> **ต้องรู้ก่อน**: role คือ container ของสิทธิ์; membership ตรวจได้จาก `sys.server_role_members` — อ่านเพิ่มที่ [Glossary — Fixed Server Role](../../Glossary.md)

```sql
USE [master];
GO
CREATE LOGIN [db_manager_01] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
CREATE LOGIN [db_manager_02] WITH PASSWORD = N'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO
-- (มี domain: CREATE LOGIN [ADVENTUREWORKS\Database_Managers] FROM WINDOWS;)
```

### Step 2 — สร้าง user-defined server role และให้สิทธิ์แบบพอดีงาน

```sql
USE [master];
GO
CREATE SERVER ROLE [db_manager_role] AUTHORIZATION sa;
GO
GRANT VIEW SERVER STATE    TO [db_manager_role];   -- ดู DMVs
GRANT VIEW ANY DEFINITION  TO [db_manager_role];   -- ดู metadata
GRANT VIEW ANY DATABASE    TO [db_manager_role];
ALTER SERVER ROLE [db_manager_role] ADD MEMBER [db_manager_01];
ALTER SERVER ROLE [db_manager_role] ADD MEMBER [db_manager_02];
GO
```

### Step 3 — ทดสอบสิทธิ์และจำกัดที่ชัดเจน

```sql
EXECUTE AS LOGIN = N'db_manager_01'
SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
SELECT name FROM sys.databases;          -- ✅ มองเห็น
SELECT @@VERSION;                         -- ✅
-- SELECT * FROM sys.sql_logins;          -- ❌ ไม่มี VIEW ANY LOGIN
REVERT
GO
```

**Expected:** ทีมทำงาน monitoring/inventory ได้โดยไม่แตะ config หรือ logins

---

## Exercise 2: Database Roles (Section 2)

### Step 1 — สร้าง users ใน AdventureWorks2025

```sql
USE [AdventureWorks2025];
GO
CREATE USER [db_manager_01] FOR LOGIN [db_manager_01];
CREATE USER [db_manager_02] FOR LOGIN [db_manager_02];
GO
```

### Step 2 — สร้าง role ตามหน้าที่และให้สิทธิ์ที่ระดับ schema

```sql
CREATE ROLE [aw_reader];
GRANT SELECT ON SCHEMA::[Sales]   TO [aw_reader];
GRANT SELECT ON SCHEMA::[Purchasing] TO [aw_reader];
GO
ALTER ROLE [aw_reader] ADD MEMBER [db_manager_01];
GO
```

### Step 3 — ตรวจ membership + ทดสอบพฤติกรรม

```sql
EXECUTE AS USER = N'db_manager_01'
SELECT IS_MEMBER('aw_reader')   AS is_aw_reader,
       IS_MEMBER('db_datareader') AS is_datareader;  -- 0 เพราะไม่ได้ให้ทั้ง DB
SELECT TOP 3 SalesOrderID FROM Sales.SalesOrderHeader;  -- ✅
-- SELECT TOP 3 NationalIDNumber FROM HumanResources.Employee; -- ❌
REVERT
GO
```

**Expected:** สิทธิ์ที่ schema ครอบเฉพาะ schema นั้น — แตกต่างจาก db_datareader ที่ครอบทั้ง DB

---

## Exercise 3: Application Role (Section 3)

### Step 1 — สร้าง app role สำหรับระบบ purchasing

> **ต้องรู้ก่อน**: app role ไม่มี member — เปิดด้วยรหัสผ่านแล้ว session สลับ context ทันที ผู้ใช้เสียสิทธิ์เดิมจนกว่าจะ unset — อ่านเพิ่มที่ [Glossary — Application Role](../../Glossary.md)

```sql
USE [AdventureWorks2025];
GO
CREATE APPLICATION ROLE [purchasing_app] WITH PASSWORD = N'Pa$$w0rd2025';
GRANT SELECT ON SCHEMA::[Purchasing] TO [purchasing_app];
GO
```

### Step 2 — เปิดใช้ใน session ทดสอบ

```sql
-- เชื่อมต่อด้วย db_manager_01 ก่อน (หรือ user ตัวอย่างอื่น)
DECLARE @cookie varbinary(8000);
EXEC sp_setapprole @rolename = N'purchasing_app',
                   @password = N'Pa$$w0rd2025',
                   @fCreateCookie = true,
                   @cookie = @cookie OUTPUT;
GO
SELECT USER_NAME();   -- 'purchasing_app'
GO
-- จงใจเรียกตารางที่ไม่มีสิทธิ์
BEGIN TRY
    SELECT TOP 3 CustomerID FROM Sales.Customer;   -- ❌
END TRY
BEGIN CATCH
    PRINT N'ถูกปฏิเสธ: ' + ERROR_MESSAGE();
END CATCH
GO
```

### Step 3 — ปิด role และทดสอบกลับ

เนื่องจาก cookie อยู่คนละ batch ให้ใช้หลักการเดียวกับ demo: เก็บ cookie ใน `#cookie` ตั้งแต่ตอนเปิด แล้ว `EXEC sp_unsetapprole @cookie` ใน batch ถัดไป

### Step 4 — Cleanup ทั้งหมด

```sql
USE [AdventureWorks2025];
GO
DROP APPLICATION ROLE IF EXISTS [purchasing_app];
ALTER ROLE [aw_reader] DROP MEMBER [db_manager_01];
DROP ROLE IF EXISTS [aw_reader];
DROP USER IF EXISTS [db_manager_01];
DROP USER IF EXISTS [db_manager_02];
GO
USE [master];
GO
DROP SERVER ROLE IF EXISTS [db_manager_role];
DROP LOGIN IF EXISTS [db_manager_01];
DROP LOGIN IF EXISTS [db_manager_02];
GO
```

---

## สรุปผลที่ต้องเห็นก่อนจบแล็บ

- [ ] สร้าง server role + สิทธิ์เฉพาะด้านได้โดยไม่แตะ sysadmin
- [ ] user-defined database role คุมขอบเขตตาม schema
- [ ] เข้าใจว่า app role ตัดสิทธิ์เดิมของ session ทั้งหมด
