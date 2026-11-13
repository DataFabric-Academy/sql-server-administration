# Section 2 — การแมป Login ไปเป็น User ในฐานข้อมูล

Login ตอบคำถาม "ใครมาถึง server" แต่งานจริงเกิดในฐานข้อมูล — Section นี้ต่อสายจาก Section 1: แมป login เข้าเป็น **Database User** ด้วย `CREATE USER ... FOR LOGIN` รวมถึงตัวละครพิเศษสองตัวที่ทุกฐานข้อมูลมีโดย default: **dbo** และ **guest**

## 2.1 การอนุญาตให้เข้าถึงฐานข้อมูล (CREATE USER)

สคริปต์เดโม: [Scripts/01_CreateUsers.sql](Scripts/01_CreateUsers.sql)

```sql
USE [AdventureWorks2025];
GO

-- Windows login → Windows user
CREATE USER [Sales_Asia]
    FOR LOGIN [MACHINE\Sales_Asia]
    WITH DEFAULT_SCHEMA = [Sales];

-- SQL login → SQL user
CREATE USER [Superman] FOR LOGIN [Superman];

-- ตั้งชื่อ user ให้ต่างจาก login ได้ (แต่ไม่แนะนำ — ยากตอบรวย)
CREATE USER [ake] FOR LOGIN [MACHINE\phakkhaphong];
GO
```

ข้อควรรู้:

- **หนึ่ง login มี user ได้หนึ่งตัวต่อฐานข้อมูล** แต่มี user ได้ในหลายฐานข้อมูลพร้อมกัน
- `DEFAULT_SCHEMA` กำหนด schema ที่ใช้ตอน query ชื่อแบบไม่ระบุ schema (`SELECT * FROM Orders` → `Sales.Orders`) — ตั้งให้ตรง schema งานของผู้ใช้จะลดการค้นหา name resolution ที่ซ้ำซ้อน (เรื่องนี้ต่อใน Module 3)
- ตั้งแต่ SQL Server 2022 ถ้าต้องให้ user "แค่เชื่อมต่อฐานข้อมูลอื่น ๆ ทั่วทั้ง server" โดยไม่ต้องสร้าง user ทีละฐาน มีทางเลือกสะดวกกว่าคือ fixed server role **`##MS_DatabaseConnector##`** (ดู Module 2)

## 2.2 dbo และ guest — ตัวละครพิเศษในทุกฐานข้อมูล

| User | คืออะไร | กฎ |
|:-----|:--------|:---|
| **dbo** | ผู้ใช้ default ของเจ้าของฐานข้อมูล (db_owner) — login ที่สร้างฐานข้อมูล หรือที่ถูก `ALTER AUTHORIZATION ON DATABASE::` ให้เป็นเจ้าของ จะผูกเป็น dbo โดยอัตโนมัติ | ลบ/เปลี่ยนชื่อไม่ได้; objects ที่สร้างโดย member ของ db_owner จะเข้า schema dbo เสมอ |
| **guest** | user สำหรับ "login ที่ไม่มี user ในฐานข้อมูลนี้" — ปิดอยู่เป็น default ในฐานข้อมูลผู้ใช้ และเปิดใน master/msdb | **อย่าเปิดบนฐานข้อมูล production** เพราะทำให้ login ทุกตัวบน server เข้าถึงฐานข้อมูลได้ |

```sql
-- เปิดใช้ guest (สำหรับสาธิต/ห้องเรียนเท่านั้น!)
USE AdventureWorks2025;
GO
GRANT CONNECT TO guest;
GO

-- ทดสอบ: login ที่ไม่มี user ในฐานข้อมูลนี้ จะเข้าได้เป็น guest
-- (รันจาก session ใหม่ด้วย login ที่ไม่มี user)
EXECUTE AS LOGIN = N'NoUserLogin';
SELECT USER_NAME();   -- จะได้ 'guest'
REVERT;
GO

-- ปิด guest กลับ (แนะนำหลังจบการสาธิต)
REVOKE CONNECT FROM guest;
GO
```

> ตรวจว่าใครเป็น dbo อยู่: `SELECT p.name, suser_sname(owner_sid) AS owner_login FROM sys.databases` หรือ `SELECT SUSER_SNAME() FROM sys.databases WHERE name = '...';`

## 2.3 เบื้องลึกเกี่ยวกับ Users — sys.database_principals

```sql
USE AdventureWorks2025;
GO
SELECT name, sid, type, type_desc, default_schema_name,
       authentication_type_desc, create_date, modify_date
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G', 'W')   -- SQL user, Windows user/group, Entra user
ORDER BY create_date DESC;
```

คอลัมน์ที่ควรสนใจ:

- `sid` — คู่กับ `sid` ของ login; ถ้าไม่ตรงกัน = **orphaned user** (Section 3 หัวข้อ 4)
- `authentication_type_desc` — `INSTANCE` (ผูก login), `DATABASE` (contained user — Section 4), `WINDOWS`, `NONE`

## 2.4 สิทธิ์ของ Logins และ User Tokens — ทำงานจริงอย่างไร

เมื่อ query เกิดขึ้น engine ตรวจสิทธิ์จาก **user token** (ไม่ใช่ login token) ภายในฐานข้อมูลปัจจุบัน โดยรวมสิทธิ์จากทุก identity ใน token:

สคริปต์เดโม: [Scripts/02_UserToken_PermissionTest.sql](Scripts/02_UserToken_PermissionTest.sql)

```sql
USE AdventureWorks2025;
GO
-- โจทย์: Superman ไม่มีสิทธิ์อ่านยกเว้นตารางที่ระบุ
GRANT CONNECT TO [Superman];                      -- user ต้องเชื่อมต่อได้ก่อน
GRANT SELECT ON SCHEMA::[Sales] TO [Superman];
DENY SELECT ON OBJECT::[Sales].[CreditCard] TO [Superman];   -- DENY ชนะ GRANT เสมอ
GO

EXECUTE AS USER = N'Superman';
SELECT TOP 3 * FROM Sales.SalesOrderHeader;      -- ✅ ผ่าน
SELECT TOP 3 * FROM Sales.CreditCard;            -- ❌ DENY ทำงาน
REVERT;
GO

-- Cleanup
REVOKE SELECT ON SCHEMA::[Sales] FROM [Superman];
REVOKE SELECT ON OBJECT::[Sales].[CreditCard] FROM [Superman];
REVOKE CONNECT FROM [Superman];
GO
```

✅ **สังเกต**: ลำดับความสำคัญของสิทธิ์คือ `DENY` > `GRANT` > ไม่มี — รายละเอียดครบถ้วนใน Module 3

## 2.5 Checklist ปัญหา "เชื่อมต่อได้ แต่ดูข้อมูลไม่ได้"

1. login เชื่อมต่อได้ → แปลว่า authentication ผ่านแล้ว
2. เช็คว่ามี user ในฐานข้อมูลนั้นไหม: `SELECT * FROM sys.database_principals WHERE sid = SUSER_SID('login')` หรือด้วยชื่อ
3. เช็ค `authentication_type_desc` ว่าเป็น `INSTANCE` จริง
4. เช็คสิทธิ์ที่ระดับ `CONNECT`: `GRANT CONNECT TO user;` ถ้าขาดจะเข้าฐานข้อมูลไม่ได้ (error 916)
5. เช็คสิทธิ์ระดับ object/schema — เพิ่ม GRANT ตามความจำเป็น (Module 3)

## 🚀 SQL Server 2025 & Modern Notes

- **Fixed server role `##MS_DatabaseConnector##`** (SQL Server 2022+) — ให้เชื่อมต่อทุกฐานข้อมูลโดยไม่ต้องสร้าง user เป็นทางเลือกใหม่ของรูปแบบ "connecting user" เดิม ([Server-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles-introduced-in-sql-server-2022))
- **Entra users** (`FROM EXTERNAL PROVIDER`, 2022+) และ `WITH OBJECT_ID` (2025) ใช้ได้ทั้งระดับ login และ user
- **Contained users** (`DATABASE` authentication) — แตกย่อยใน Section 4
- ตั้งแต่ SQL Server 2025 มี **security cache improvements** — การสร้าง/แก้ user ทำให้ cache ของ login อื่น invalidate น้อยลง ระบบใหญ่ ๆ ที่จัดการ user บ่อยจะเร็วขึ้น ([Security cache](https://learn.microsoft.com/sql/relational-databases/security-cache?view=sql-server-ver17))

> อ้างอิง: [CREATE USER (T-SQL)](https://learn.microsoft.com/sql/t-sql/statements/create-user-transact-sql?view=sql-server-ver17), [Create a Database User](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/create-a-database-user?view=sql-server-ver17), [sys.database_principals](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-principals-transact-sql?view=sql-server-ver17)
