# Section 3 — User-defined Database Roles และ Application Roles

เมื่อ fixed roles ไม่ตรงกับโครงสร้างองค์กร ให้สร้าง role เองตาม "หน้าที่งาน" และเมื่อสิทธิ์ต้องผูกกับ **แอปพลิเคชัน** ไม่ใช่คน มีกลไกพิเศษชื่อ Application Role ที่ทำงานต่างจาก role ทุกตัวที่เหลือ

## 3.1 จัดการกับ User-Defined Database Roles

สคริปต์เดโม: [Scripts/01_UserDefinedRoles_Demo.sql](Scripts/01_UserDefinedRoles_Demo.sql)

```sql
USE [AdventureWorks2025];
GO

-- สร้าง role ตามหน้าที่
CREATE ROLE [human_resources_reader];
GO

-- ให้สิทธิ์ที่ role (ที่ระดับ schema จะครอบคลุมทุกตารางใน schema — ดู Module 3)
GRANT SELECT ON SCHEMA::[HumanResources] TO [human_resources_reader];
GO

-- เพิ่ม users เข้า role
ALTER ROLE [human_resources_reader] ADD MEMBER [hr_01];
ALTER ROLE [human_resources_reader] ADD MEMBER [hr_02];
GO
```

ตรวจสิทธิ์ที่ role มี:

```sql
SELECT dpr.name AS principal_name, dpe.permission_name, dpe.class_desc, sch.name AS schema_name
FROM sys.database_permissions AS dpe
JOIN sys.database_principals AS dpr ON dpr.principal_id = dpe.grantee_principal_id
LEFT JOIN sys.schemas AS sch ON sch.schema_id = dpe.major_id AND dpe.class = 3
WHERE dpr.name = N'human_resources_reader';
```

### การใช้ Roles ในสถานการณ์ทั่วไป — แบบแผนที่แนะนำ

1. **หนึ่ง role ต่อหน้าที่** — `hr_reader`, `finance_writer`, `dev_ddl` (ชื่อสื่อหน้าที่ ไม่ใช่ชื่อคน)
2. **ให้สิทธิ์ที่ role เท่านั้น** — ห้าม GRANT ตรงให้ user ส่วนตัว เพราะตรวจย้อนไม่ได้เมื่อคนเปลี่ยนหน้าที่
3. **ทดสอบด้วย `EXECUTE AS USER`** — หลังแก้สิทธิ์ทุกครั้งให้สวม user ทดลอง query จริง
4. **ถอนสิทธิ์เมื่อย้ายหน้าที่** — `ALTER ROLE ... DROP MEMBER`; อย่าลืมว่า public + deny roles ยังถืออยู่

## 3.2 รู้จักกับ Application Roles

**Application Role** ต่างจาก database role ตรงที่มัน "ไม่มี member" — แอปเปิดใช้เองด้วยรหัสผ่าน แล้ว session ทั้งหมดสลับเป็นสิทธิ์ของ role นั้นทันที

สคริปต์เดโม: [Scripts/02_ApplicationRoles_Demo.sql](Scripts/02_ApplicationRoles_Demo.sql)

```sql
USE [AdventureWorks2025];
GO
CREATE APPLICATION ROLE [purchase_order] WITH PASSWORD = N'Pa$$w0rd2025';
GO
GRANT SELECT ON SCHEMA::[Purchasing] TO [purchase_order];
GO

-- เปิดใช้ (cookie เก็บไว้เพื่อปิดทีหลัง)
DECLARE @cookie varbinary(8000);
EXEC sp_setapprole
    @rolename  = N'purchase_order',
    @password  = N'Pa$$w0rd2025',
    @fCreateCookie = true,
    @cookie    = @cookie OUTPUT;
GO

-- ณ จุดนี้: session สลับเป็น purchase_order แล้ว
SELECT USER_NAME() AS current_user;      -- 'purchase_order'
SELECT SUSER_SNAME() AS login_name;      -- login จริงยังดูได้

SELECT TOP 5 * FROM Purchasing.ShipMethod;   -- ✅ ผ่าน (role มีสิทธิ์)
-- SELECT TOP 5 * FROM Sales.Customer;       -- ❌ ถูกปฏิเสธ (สิทธิ์ user จริงหายไป)
```

ปิดการใช้:

```sql
DECLARE @cookie varbinary(8000) = ...;   -- cookie จากตอนเปิด
EXEC sp_unsetapprole @cookie;
GO
```

ข้อเข้าใจสำคัญเกี่ยวกับ Application Roles:

- **หลังเปิด ผู้ใช้สิทธิ์อื่นหายไปหมด** — ไม่มี "ผสมสิทธิ์ของ user + role"
- ไม่สามารถเข้าถึงฐานข้อมูลอื่นได้เลยในโหมด app role (context ของ app role อยู่ใน DB เดียว)
- รหัสผ่าน app role ต้องฝังใน connection string/แอป — จัดการเป็น secret (key vault) ไม่ใช่ hardcode
- SQL Server 2025 ใช้ **PBKDF2** hash รหัสผ่านของ application role โดย default — ปลอดภัยขึ้นโดยไม่แก้อะไร

## 🚀 SQL Server 2025 & Modern Notes

- Application role ยังใช้ได้ดีกับ legacy/ERP แต่แอปสมัยใหม่นิยมใช้ SQL auth login เฉพาะแอป + minimal permissions หรือ **Managed Identity** (2025, Arc) เมื่อแอปอยู่บน Azure
- หากใช้ app role กับ **contained database** สังเกตว่า app role ทำงานได้ปกติ แต่ควรระวังการจับคู่รหัสผ่านซ้ำระหว่าง DB
- ยังไม่มี feature ทดแทน `sp_setapprole` แบบ official ใหม่ — ใช้ต่อได้เต็มที่ใน SQL Server 2025

> อ้างอิง: [Application Roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/application-roles?view=sql-server-ver17), [sp_setapprole](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-setapprole-transact-sql?view=sql-server-ver17), [CREATE ROLE](https://learn.microsoft.com/sql/t-sql/statements/create-role-transact-sql?view=sql-server-ver17)
