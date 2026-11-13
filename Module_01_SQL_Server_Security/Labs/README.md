# Lab 1: Logins, Users และ Contained Databases (บทที่ 1)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab01** (Authenticating and Authorizing Users) + [Microsoft Learn — Create a Login](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/create-a-login?view=sql-server-ver17) + [Troubleshoot orphaned users](https://learn.microsoft.com/sql/sql-server/database-engine/configure-windows/troubleshoot-orphaned-users-sql-server?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว
> ต้นฉบับ Lab01 ออกแบบให้ใช้ Active Domain (ADVENTUREWORKS\Student) — เวอร์ชันนี้ปรับให้ทำได้บน **เครื่องที่ไม่มี domain** โดยใช้ SQL Authentication + local Windows account และระบุจุดที่ทำกับ domain จริงได้แยกไว้

## Prerequisites

- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** restore เรียบร้อย (ดู [Module 00](../../Module_00_Getting_Started/README.md))
- Mixed Mode authentication เปิดอยู่ (SSMS → Server Properties → Security → SQL Server and Windows Authentication mode)
- บัญชีผู้ใช้ที่มีสิทธิ์ sysadmin บน instance นั้น
- อ่านคู่: [Section 1](../Sections/01_Authentication_Logins/README.md), [Section 3](../Sections/03_Cross_Server_Security/README.md), [Section 4](../Sections/04_Contained_Databases/README.md), [Glossary](../../Glossary.md)

## Scenario

บริษัท Adventure Works จะเปิดระบบ Sales ให้ทีมขายเอเชีย (Sales_Asia) คุณต้องสร้าง identity ให้ทีม แมปเข้าฐานข้อมูลให้ถูกสิทธิ์ และเตรียมฐานข้อมูลให้ย้ายไป server สำรองได้โดยไม่ต้องซิงก์ logins

## Objectives

1. สร้าง SQL Authentication login + แมปเป็น user แล้วทดสอบพฤติกรรมสิทธิ์
2. จำลอง orphaned user จาก restore ข้ามเครื่อง แล้วแก้ด้วย `ALTER USER ... WITH LOGIN` และ `CREATE LOGIN ... WITH SID`
3. สร้าง partially contained database ที่มี contained users พร้อมทดสอบย้าย

---

## Exercise 1: สร้าง Login และแมป User (Section 1–2)

### Step 1 — สร้าง SQL login สำหรับทีมขาย

> **ต้องรู้ก่อน**: `CREATE LOGIN ... WITH PASSWORD` สร้างตัวตนระดับ server; `CHECK_POLICY=ON` บังคับผ่านกฎรหัสผ่านของ Windows; `DEFAULT_DATABASE` คือ DB ที่ต่อเข้ามาทันที — อ่านเพิ่มที่ [Glossary — Login](../../Glossary.md)

```sql
USE [master];
GO
CREATE LOGIN [Sales_Asia] WITH PASSWORD = N'Pa$$w0rd2025',
    DEFAULT_DATABASE = [AdventureWorks2025],
    CHECK_POLICY = ON;
GO
```

*(หากมี domain จริง: `CREATE LOGIN [ADVENTUREWORKS\Sales_Asia] FROM WINDOWS WITH DEFAULT_DATABASE=[AdventureWorks2025];`)*

### Step 2 — แมปเป็น user ในฐานข้อมูล พร้อม default schema

```sql
USE [AdventureWorks2025];
GO
CREATE USER [Sales_Asia] FOR LOGIN [Sales_Asia]
    WITH DEFAULT_SCHEMA = [Sales];
GO
```

### Step 3 — ทดสอบ: เชื่อมต่อด้วย login ใหม่

เปิด SSMS ใหม่ (หรือ sqlcmd) เชื่อมด้วย SQL auth `Sales_Asia` / `Pa$$w0rd2025` แล้วรัน:

```sql
-- รันใน session ของ Sales_Asia
SELECT SUSER_SNAME() AS server_login, USER_NAME() AS db_user;
SELECT TOP 3 SalesOrderID, OrderDate FROM Sales.SalesOrderHeader;   -- ❌ ยังไม่มีสิทธิ์อ่าน
```

✅ **สังเกต**: เชื่อมต่อผ่าน (authentication ใช้ได้) แต่ query fail (authorization ยังไม่ให้) — ตรงตามโมเดล Login → User → Permission

### Step 4 — ให้สิทธิ์อ่าน schema Sales แล้วทดสอบซ้ำ

```sql
-- รันด้วย sysadmin
USE [AdventureWorks2025];
GO
GRANT CONNECT TO [Sales_Asia];
GRANT SELECT ON SCHEMA::[Sales] TO [Sales_Asia];
GO
```

กลับ session ของ Sales_Asia รัน query ข้อ 3 อีกครั้ง — ✅ ผ่านแล้ว

**Expected:** การอนุญาตทำงาน 3 ชั้นเป็นลำดับ: server login → database user → object/schema permission

---

## Exercise 2: Orphaned User — จำลองและแก้ (Section 3)

### Step 1 — จำลอง restore จากเครื่องอื่น: สร้าง DB + user ด้วย SID ของมันเอง

> **ต้องรู้ก่อน**: `sid` คือรหัสเฉพาะที่ผูก login↔user; restore ข้ามเครื่องพา user (พร้อม SID เดิม) ไปแต่ login ปลายทางมี SID ใหม่ → ไม่ตรงกัน = orphaned — อ่านเพิ่มที่ [Glossary — SID](../../Glossary.md)

```sql
USE [master];
GO
CREATE DATABASE LabOrphan;
GO
USE [LabOrphan];
GO
CREATE USER [reportuser] WITH PASSWORD = N'Pa$$w0rd2025';  -- contained user ชั่วคราว
GO
-- สกัด SID ของ user ออกมาเพื่อ "restore ไปอีกเครื่อง"
SELECT sid FROM sys.database_principals WHERE name = N'reportuser';
```

จดค่า `sid` (เช่น `0x0100A5...`)

### Step 2 — สร้าง login ชื่อเดียวกันบน "เครื่องปลายทาง" (SID ใหม่)

```sql
USE [master];
GO
CREATE LOGIN [reportuser] WITH PASSWORD = N'Pa$$w0rd2025',
    CHECK_POLICY = OFF;   -- SID ใหม่แน่นอน เพราะสร้างสด
GO
```

### Step 3 — ผูก user เข้า login จริง (แปลงเป็น instance user) แล้วเจอปัญหา

```sql
USE [LabOrphan];
GO
ALTER USER [reportuser] WITH LOGIN = [reportuser];  -- เชื่อมให้ (อยู่ใน same server จึงผ่าน)
GO
-- ตรวจ: ในกรณี restore จริงข้ามเครื่อง ชื่อตรงแต่ SID ไม่ตรง = orphaned
SELECT dp.name, dp.sid, SUSER_SNAME(dp.sid) AS matching_login
FROM sys.database_principals dp
WHERE dp.type = 'S' AND dp.sid <> 0x0;
```

✅ **สังเกต**: แถวที่ `matching_login` เป็น NULL คือ orphaned user

### Step 4 — แก้ด้วยสองวิธี

```sql
-- วิธี A (แนะนำ): ผูก user ที่มีอยู่ไปยัง login ที่ถูกต้อง
ALTER USER [reportuser] WITH LOGIN = [reportuser];
GO

-- วิธี B: สร้าง login ใหม่ที่ SID เดียวกับ user (รักษา SID เดิมสำหรับ AG/replica)
USE [master];
GO
DECLARE @sid varbinary(85) =
    (SELECT sid FROM LabOrphan.sys.database_principals WHERE name = N'reportuser');
-- (ถ้าต้องการซ้อม: DROP LOGIN reportuser ก่อนแล้วสร้างใหม่ด้วย SID=@sid)
```

**Expected:** หลังแก้ `SUSER_SNAME(dp.sid)` ต้องรายงานชื่อ login ตรงกัน

> หมายเหตุ: `sp_change_users_login 'Report'` เดิมใช้หาปัญหานี้ — **deprecated แล้ว** ใช้ query ใน Step 3 แทน

### Step 5 — Cleanup

```sql
USE [master];
GO
DROP LOGIN IF EXISTS [reportuser];
ALTER DATABASE LabOrphan SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS LabOrphan;
GO
```

---

## Exercise 3: Partially Contained Database (Section 4)

### Step 1 — เปิด containment ระดับ server และสร้างฐานข้อมูล

> **ต้องรู้ก่อน**: `contained database authentication` เป็น server config option; ฐานข้อมูลที่ `CONTAINMENT = PARTIAL` เก็บ user+password ของตัวเองได้ — อ่านเพิ่มที่ [Glossary — Contained](../../Glossary.md)

```sql
USE [master];
GO
EXEC sys.sp_configure N'contained database authentication', 1;
RECONFIGURE;
GO
CREATE DATABASE [PartialData] CONTAINMENT = PARTIAL;
GO
```

### Step 2 — สร้าง contained users และให้สิทธิ์

```sql
USE [PartialData];
GO
CREATE USER [ClientUser1] WITH PASSWORD = N'Pa$$w0rd2025';
GRANT SELECT ON SCHEMA::[dbo] TO [ClientUser1];
GO
CREATE TABLE dbo.Demo (id int identity, note nvarchar(50));
INSERT INTO dbo.Demo (note) VALUES (N'ย้ายได้เลย'), (N'ไม่ต้องซิงก์ login');
GO
```

### Step 3 — ทดสอบย้าย: backup → restore ไป "เครื่องปลายทาง"

```sql
BACKUP DATABASE [PartialData] TO DISK = N'D:\SQLBackups\PartialData.bak' WITH CHECKSUM;
```

ถ้ามี container ที่สอง (`sql2025b`, port 1434): copy ไฟล์ .bak ไป แล้ว restore บนนั้น — **ไม่ต้องสร้าง login ใด ๆ** แล้ว login ด้วย `ClientUser1` / `Pa$$w0rd2025` (เลือก default DB = PartialData) ได้ทันที

บน instance เดียว: ทดสอบ login ด้วย `ClientUser1` ได้ทันทีเหมือนกัน (ตั้ง SSMS database ตอน connect = PartialData)

✅ **สังเกต**: การพิสูจน์ตัวตนเกิดที่ฐานข้อมูล — server-level login ไม่มีบทบาท

### Step 4 — ข้อพึงระวัง: db_owner ของ contained user

```sql
USE [PartialData];
GO
ALTER ROLE [db_owner] ADD MEMBER [ClientUser1];
-- ตอนนี้ ClientUser1 สร้าง contained user เพิ่มเองได้ และ DB นี้พร้อม grant สิทธิ์ใหม่โดยไม่ผ่าน DBA
```

**Expected:** เข้าใจว่า containment เพิ่มความเสี่ยงของ ownership — ควบคุมด้วยการตรวจ `sys.database_principals` เป็นระยะ

### Step 5 — Cleanup

```sql
USE [master];
GO
ALTER DATABASE [PartialData] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [PartialData];
EXEC sys.sp_configure N'contained database authentication', 0;
RECONFIGURE;
GO
-- ลบ login/user ของ Exercise 1 ด้วยถ้าไม่ต้องการเก็บ
DROP LOGIN IF EXISTS [Sales_Asia];
```

---

## สรุปผลที่ต้องเห็นก่อนจบแล็บ

- [ ] login เชื่อมต่อได้แต่ query ไม่ผ่านเมื่อยังไม่ให้สิทธิ์ (authentication ≠ authorization)
- [ ] หา orphaned user จาก `SUSER_SNAME(dp.sid) = NULL` และแก้ได้ด้วย `ALTER USER ... WITH LOGIN`
- [ ] contained user login ผ่านฐานข้อมูลโดยตรง และเข้าใจความเสี่ยง db_owner
