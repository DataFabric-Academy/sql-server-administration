# Section 03 — Schema Permissions: กำหนดสิทธิ์ระดับ Schema

ทั้ง Section 1 และ 2 เรา GRANT ทีละ object — ตารางนี้ proc นั้น ซึ่งทำงานได้จนกระทั่งระบบโตขึ้น: schema `Sales` มี 40 ตาราง และทุกทีที่ทีม dev เพิ่มตารางใหม่ DBA ต้องนั่ง GRANT ให้ role ทุกกลุ่มใหม่อีกรอบ วิธีแก้ใน SQL Server คือ GRANT ที่ **ระดับ schema** — ครอบคลุมทุก object ใน schema **ทั้งที่มีอยู่แล้วและที่จะถูกสร้างใหม่ในอนาคต**

ก่อนเข้า GRANT ระดับ schema เราต้องจับสองแนวคิดที่ผูกกันตั้งแต่ SQL Server 2005: **user-schema separation** และการ **อ้างชื่อ object**

## User–Schema Separation

ใน SQL Server 2000 สมัยเก่า user คนหนึ่ง "ครอบ" schema ที่มีชื่อเหมือนตัวเอง (user `somchai` มี schema `somchai` ที่ตารางของเขาอยู่) — ลบ user ไม่ได้ถ้ายังมีตาราง, โยกความเป็นเจ้าของลำบาก ตั้งแต่ SQL Server 2005 สถาปัตยกรรมแยกออกจากกัน:

| Entity | คืออะไร | เป็นเจ้าของได้โดย |
|:-------|:--------|:-----------------|
| **User** | ตัวตนระดับ database | — |
| **Schema** | namespace ของ object (`Sales`, `Production`, `dbo`) | user, role, application role หรือ server principal ใด ๆ |
| **Object** | ตาราง, proc, view ที่อยู่ใน schema | ตาม schema ที่ตัวเองอยู่ (via AUTHORIZATION) |

ผลในทางปฏิบัติที่ DBA ได้ประโยชน์จริง:

- **ลบ/โยก user ได้** โดยไม่ลาก object ติดไป เพราะ object ผูกกับ schema ไม่ใช่ user
- **เปลี่ยนเจ้าของทั้งกลุ่ม** ด้วยคำสั่งเดียว: `ALTER AUTHORIZATION ON SCHEMA::Sales TO newOwner;`
- **GRANT ทีเดียวทั้งกลุ่ม** (หัวใจของ Section นี้)
- object ไม่กระจายตามชื่อคน ช่วยเรื่อง deployment และ dacpac ด้วย

```sql
-- สร้าง schema และกำหนดเจ้าของ
CREATE SCHEMA Sales AUTHORIZATION dbo;

-- เปลี่ยนเจ้าของ schema ทีเดียวทั้งก้อน
ALTER AUTHORIZATION ON SCHEMA::Sales TO DemoTableOwner;
```

> **Best practice ยุคใหม่**: ให้ **role เป็นเจ้าของ schema** แทน user ที่เป็นตัวคน เช่น `ALTER AUTHORIZATION ON SCHEMA::Sales TO [Sales_OwnerRole];` เพราะ role ไม่มีวันลาออก ไม่ต้องรื้นสิทธิ์เวลาคนเปลี่ยนทีม

## การอ้างชื่อ Object และ DEFAULT_SCHEMA

SQL Server อ้างชื่อ object ได้ 4 รูปแบบ:

| รูปแบบ | ตัวอย่าง | SQL Server หาจาก |
|:-------|:---------|:-----------------|
| 4-part | `Server01.AdventureWorks2025.Sales.Orders` | ตรงชัดทุกชั้น (linked server) |
| 3-part | `AdventureWorks2025.Sales.Orders` | database + schema + object |
| **2-part** | `Sales.Orders` | schema + object — **แนะนำเสมอ** |
| 1-part | `Orders` | เดา: user's DEFAULT_SCHEMA → ถ้าไม่เจอจะรื้อหาใน `dbo` |

การอ้าง 1-part ช่างเขียนโค้ดสะดวก แต่เป็นจุดเปราะ: ทั้งความหมายของ query และ **performance ของ plan cache** ขึ้นกับคนรันคือใคร (ถ้า user A มี DEFAULT_SCHEMA `Sales` และ user B มี `HR` โค้ด `SELECT * FROM Orders` คนละตารางกันได้!)

`DEFAULT_SCHEMA` กำหนดตอนสร้าง user หรือเปลี่ยนทีหลัง:

```sql
CREATE USER DemoRep FOR LOGIN DemoRep
    WITH DEFAULT_SCHEMA = Sales;        -- อ้าง 1-part จะเจอของใน Sales ก่อน

ALTER USER DemoRep WITH DEFAULT_SCHEMA = Sales;   -- เปลี่ยนภายหลัง
```

กติกา default ถ้าไม่กำหนด: SQL Server จะพยายามใช้ schema ชื่อเดียวกับ user ถ้ามีจริง ไม่งั้นตกไปที่ `dbo` ทำให้ code เก่าที่เขียน `CREATE TABLE Employees` จาก admin session มากองอยู่ใน `dbo` แล้ว query จาก user ที่อ้าง 1-part มองไม่เห็น — ปัญหาคลาสสิกที่ 2-part naming ตัดรอกไปได้เลย

## GRANT ที่ระดับ SCHEMA::

syntax ใช้ `SCHEMA::` ตรง ๆ เหมือนคำสั่ง GRANT ทุกอย่างที่ผ่านมา:

```sql
-- สิทธิ์ DML ทั้ง schema
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Sales TO SalesAppRole;

-- สิทธิ์รันโค้ดทั้ง schema (ครอบทุก proc/function ปัจจุบันและอนาคต)
GRANT EXECUTE ON SCHEMA::dbo TO AppRole;

-- มองดูโครงสร้างทั้ง schema โดยไม่อ่านข้อมูล
GRANT VIEW DEFINITION ON SCHEMA::HumanResources TO AuditorRole;

-- ควบคุมเต็มรูปแบบ
GRANT CONTROL ON SCHEMA::Sales TO DataSteward;
```

จุดแข็งที่ต่างจาก object-level:

| ประเด็น | Object-level GRANT | Schema-level GRANT |
|:--------|:-------------------|:-------------------|
| object ที่สร้างใหม่ใน schema | ต้อง GRANT ใหม่ | ครอบอัตโนมัติ |
| จำนวนคำสั่ง deployment | โตตามจำนวนตาราง | คงที่ (1 คำสั่ง) |
| ความเสี่ยงลืม GRANT ใหม่ | สูง (มือปราบ) | ต่ำ |
| ขอบเขตละเอียดแค่ไหน | เฉพาะตาราง/คอลัมน์ | ทั้ง namespace |

### ลำดับการประเมินเมื่อมีทั้ง schema grant และ object deny

สิทธิ์ที่ **ระดับลึกกว่าและชัดเจนกว่า** มีน้ำหนัก: schema-level `GRANT` + object-level `DENY` → **DENY ชนะ** เพราะกฎ "DENY ชนะ" ยังใช้เหมือนเดิมทุก scope:

```sql
GRANT EXECUTE ON SCHEMA::dbo TO DemoSchemaUser;   -- ให้ทุก proc ใน dbo
DENY  EXECUTE ON dbo.uspGetManagerEmployees TO DemoSchemaUser;  -- แต่ปิดตัวนี้
-- ผล: รัน proc อื่นใน dbo ได้ รัน uspGetManagerEmployees ไม่ได้
```

## ตรวจเจ้าของ schema และย้าย object ระหว่าง schema

ตรวจว่า schema ไหนเป็นของใครทั้ง database (จุดแรกที่ดูเวลาไล่เรื่อง ownership chaining จาก Section 2):

```sql
SELECT s.name AS schema_name, p.name AS owner_name, p.type_desc
FROM sys.schemas s
JOIN sys.database_principals p ON p.principal_id = s.principal_id
ORDER BY s.name;
GO
```

ย้าย object ข้าม schema ด้วย `ALTER SCHEMA ... TRANSFER` (object คงข้อมูลเดิม ข้ามแบบ metadata-only เร็วมาก):

```sql
-- ย้ายตาราง dbo.TempOrders ไปอยู่ใน schema Sales
ALTER SCHEMA Sales TRANSFER dbo.TempOrders;
GO
```

ข้อควรรู้: (1) `TRANSFER` ล้างสิทธิ์ที่เคยกำหนดบน object เดิม (ต้อง GRANT ใหม่) (2) object ที่มี schema-bound dependency (เช่น indexed view) อาจย้ายไม่ได้ (3) เวลาย้าย proc ที่อ้างชื่อ 2-part แล้ว schema เดิมหายไป โค้ดที่อ้าง `dbo.TempOrders` จะพัง — ย้ายพร้อม update references เสมอ

## Role สำเร็จรูป vs Role ผูกกับ schema — เทียบให้เห็นทางเลือก

| กลไก | ขอบเขต | เหมาะกับ | ข้อจำกัด |
|:-----|:-------|:---------|:---------|
| `db_datareader` / `db_datawriter` | **ทุก schema ใน database** | เครื่องมือภายในที่ต้องอ่านทุกอย่าง | กว้างเกินจำเป็นสำหรับแอปธุรกิจ — ขัด least privilege |
| `db_ddladmin` | DDL ทั้ง database | เครื่องมือ deploy | ไม่ควรให้ user ธุรกิจ |
| **Role ผู้ใช้สร้าง + GRANT ON SCHEMA::** | เฉพาะ schema ที่ระบุ | แอปธุรกิจ, ทีมงานตามสายงาน | ต้องวาง role/schema ให้สอดคล้องกันตั้งแต่ออกแบบ |

วิธีอ่านสมาชิก role และสิทธิ์ของ role:

```sql
-- สมาชิกทั้งหมดของ role
SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
ORDER BY r.name;
GO

-- สิทธิ์ระดับ schema ทั้งหมดที่มีใน database (class = 3)
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       SCHEMA_NAME(pe.major_id) AS schema_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 3
ORDER BY schema_name, grantee;
GO
```

## fn_builtin_permissions — สิทธิ์ใด "ครอบ" สิทธิ์ใด

เมื่อสงสัยว่า "GRANT CONTROL ที่ schema ให้ผลอะไรบ้าง" ระบบมี function รายการ hierarchy ของสิทธิ์ทั้งหมด (`covering_permission_name` = สิทธิ์ระดับบนที่ครอบมัน):

```sql
-- สิทธิ์ทั้งหมดที่ระดับ schema กำหนดได้ + สิทธิ์ที่ครอบมัน
SELECT permission_name, covering_permission_name, parent_class_desc
FROM sys.fn_builtin_permissions('SCHEMA')
ORDER BY permission_name;
GO

-- เทียบกับระดับ object
SELECT permission_name, covering_permission_name
FROM sys.fn_builtin_permissions('OBJECT')
WHERE permission_name IN ('SELECT', 'EXECUTE', 'CONTROL');
GO
```

การสำรวจด้วยคำสั่งนี้ช่วยตอบคำถามเชิงออกแบบ เช่น "ให้ role รันโค้ดทั้ง schema ต้อง GRANT อะไร" (`EXECUTE` ที่ schema) หรือ "GRANT ที่ database ไหนครอบ SELECT บนตาราง" (`SELECT` ที่ระดับ database ครอบทุกตาราง — ซึ่งเป็นเหตุผลที่ `db_datareader` กว้างมาก)

## ผลต่อการ Deploy และความเสถียร

โมเดล "schema แบ่งตามสายงาน + role ต่อ schema" ได้ประโยชน์พิเศษเวลา deploy:

- DACPAC/SqlPackage จัดการ schema และสิทธิ์ของ role อย่างเป็นระเบียบ (สิทธิ์ที่ GRANT ผ่าน script อยู่ใน database project ได้)
- ตารางใหม่ลง schema เดิมแล้วสิทธิ์ "เสร็จตอน deploy" ทันที — ไม่มีขั้นตอน "แก้ permission หลัง deploy" ที่มักลืม
- ตอนย้าย environment (dev → prod) โครงสร้างสิทธิ์คงรูปเดิมเพราะผูกกับ schema/role ไม่ผูกกับชื่อคน

## แบบฝึกหัดจากสไลด์: Role + สิทธิ์ 4 อย่างบน HumanResources

โจทย์มาตรฐานของหลักสูตร: สร้าง role กลุ่ม HR แล้ว GRANT 4 สิทธิ์ (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) ให้ทั้ง schema `HumanResources` ด้วยคำสั่ง **รวมสิทธิ์ในครั้งเดียว**:

```sql
USE AdventureWorks2025;
GO

CREATE ROLE HumanResources_Users;

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HumanResources
    TO HumanResources_Users;

ALTER ROLE HumanResources_Users ADD MEMBER DemoHRUser;
```

สคริปต์แบบฝึกหัดฉบับรันได้เต็ม (สร้าง user ทดสอบ, ทดสอบจริงด้วย EXECUTE AS, cleanup) อยู่ที่ [`Scripts/02_HR_Role_Practice.sql`](Scripts/02_HR_Role_Practice.sql) และ demo พื้นฐานเทียบ object vs schema grant อยู่ที่ [`Scripts/01_SchemaLevelPermissions.sql`](Scripts/01_SchemaLevelPermissions.sql)

ผลที่ควรเห็นหลังใส่ role:

- `SELECT * FROM HumanResources.Employee` ผ่าน
- `INSERT` / `UPDATE` / `DELETE` บนตารางใน schema นั้นผ่าน
- ตารางใน schema อื่น (เช่น `Production.Product`) ยังไม่ได้ — ขอบเขต schema ตัดตรงนั้น
- ตาราง **ใหม่** ที่เพิ่งสร้างใน `HumanResources` user ใช้ได้ **ทันที** โดยไม่แตะ GRANT ใหม่ — ลองในสคริปต์

## แบบฝึกหัดขยาย: แยก Reader/Writer role ต่อ schema

รูปแบบจริงมักไม่ใช่ role เดียวได้ทุกสิทธิ์ — แยกออกเป็นสอง role ต่อ schema เพื่อคุมเข้มขึ้น:

```sql
CREATE ROLE HR_Reader;         -- อ่านอย่างเดียว (สำหรับเครื่องมือรายงาน)
CREATE ROLE HR_Writer;         -- แก้ไขข้อมูล (สำหรับทีม HR จริง)

GRANT SELECT ON SCHEMA::HumanResources TO HR_Reader;

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HumanResources TO HR_Writer;
GO
```

แล้วเพิ่มสมาชิกตามบทบาทจริง — ประเด็นที่ต้องคิดก่อนตั้ง:

- อย่าให้ `HR_Reader` ได้ `EXECUTE ON SCHEMA::HumanResources` โดยปริยาย ถ้ามี proc ที่เปลี่ยนข้อมูลอยู่ใน schema เดียวกัน — ถ้าต้องแยกจริง ให้ย้าย proc "เขียน" ไป schema ของตัวเอง (เช่น `HR_Ops`)
- `DENY` ระดับ object ใช้เป็น "ปลั๊ก" ข้อยกเว้น เช่น `DENY SELECT ON OBJECT::HumanResources.EmployeePayHistory (Rate) TO HR_Reader;`
- ตรวจผลสุดท้ายด้วย `fn_my_permissions('HumanResources', 'SCHEMA')` ในบริบท user ทดสอบเสมอ (รูปแบบอยู่ใน Section 1)

## จุดเชื่อมกับโมดูลก่อนหน้าและถัดไป

- **Module 1–2** (login/user/role): schema-based model คือชั้นบนสุดของสิทธิ์ — role ที่สร้างไว้แล้วใช้ที่นี่ได้ทันที
- **Module 3 Section 1–2**: column/row และ code permissions ซ้อนกับ schema grant ได้ (DENY ระดับลึกยังชนะ)
- **Module 4**: audit specification จะอ้าง `BY <role>` ตอนจับเหตุการณ์ — โครง role ที่วางดีตอนนี้ทำให้ audit log อ่านง่ายขึ้นทันที

## DEFAULT_SCHEMA — ตรวจและแก้ย้อนหลัง

ปัญหาคลาสสิกที่ตามมาจากโค้ด 1-part name — ตรวจว่า user แต่ละคนใช้ default schema อะไร:

```sql
SELECT name, default_schema_name
FROM sys.database_principals
WHERE type IN ('S', 'U')   -- SQL user / Windows user
ORDER BY name;
GO
```

อาการที่บอกว่าต้องแก้ตรงนี้:

- `SELECT * FROM Employees` รันได้เมื่อรันจาก admin session แต่ล้มเหลวจากแอป (หรือดึงคนละตาราง!)
- แอปแจ้ง error "Invalid object name" กับตารางที่มีอยู่จริง — เพราะ 1-part name เดาจาก default_schema แล้วไม่เจอ
- Query plan cache มี plan ซ้ำสองชุดสำหรับ query ข้อความเดียวกัน (default schema ต่างกันทำให้ cache key ต่างกัน)

วิธีแก้ทั้งปลายเปิดและปลายปิด: ตั้ง `DEFAULT_SCHEMA = 'dbo'` (หรือ schema หลักของแอป) ให้ user เวลาสร้าง และแก้ของเดิมด้วย `ALTER USER ... WITH DEFAULT_SCHEMA = ...` ส่วนโค้ดใหม่ทุกบรรทัดใช้ 2-part name จบเรื่องถาวร

## Inventory ก่อนเปลี่ยนโครงสร้าง schema ในระบบจริง

ก่อนเปลี่ยนเจ้าของ schema หรือย้าย object ใหญ่ รวมข้อมูลสามชุดนี้ให้จบก่อน (เพราะ chain และสิทธิ์ขึ้นกับเจ้าของตรง ๆ):

```sql
-- 1) เจ้าของปัจจุบันของทุก schema
SELECT s.name AS schema_name, p.name AS owner_name
FROM sys.schemas s JOIN sys.database_principals p
     ON p.principal_id = s.principal_id;

-- 2) สิทธิ์ระดับ schema ทั้งหมด (ใครได้อะไรบน schema ไหน)
SELECT pr.name AS grantee, pe.permission_name, pe.state_desc,
       SCHEMA_NAME(pe.major_id) AS schema_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.class = 3;

-- 3) object นับตาม schema (มองภาพขนาดของการย้าย)
SELECT s.name AS schema_name, COUNT(*) AS objects
FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.type IN ('U', 'P', 'V')
GROUP BY s.name ORDER BY objects DESC;
GO
```

## สรุป

- แยก user จาก schema ตั้งแต่ออกแบบฐานข้อมูล — role เป็นเจ้าของ schema ที่ดีที่สุด
- เขียนโค้ดเป็น 2-part name เสมอ ตั้ง DEFAULT_SCHEMA เผื่อโค้ดเก่า
- GRANT ที่ระดับ schema คือเครื่องมือบริหารสิทธิ์แบบ "เปิดกลุ่ม" คู่กับ role ทำ deployment ไม่ต้องกลัวลืม
- DENY ที่ object ยังชนะ GRANT ที่ schema — ใช้เป็นปลั๊กข้อยกเว้น

จบโมดูล 3 ที่นี่ ไปที่ **Labs/README.md** เพื่อรวมทุกทักษะในแล็บเดียว

---

### 🚀 SQL Server 2025 & Modern Notes

- **Security cache improvements (2025)**: GRANT ระดับ schema กระทบหลาย object ในรุ่นเก่าอาจสั่น cache หนัก ใน SQL Server 2025 invalidate เฉพาะ login ที่เกี่ยว ([Security cache](https://learn.microsoft.com/sql/relational-databases/security-cache?view=sql-server-ver17))
- **Contained availability groups (SQL Server 2022+)** เก็บ user/permission ทั้ง database และ **role ใน contained system database** ทำให้ schema-based permission model ย้าย AG ได้สมบูรณ์ ([Contained AGs](https://learn.microsoft.com/sql/database-engine/availability-groups/windows/contained-availability-groups-overview?view=sql-server-ver17))
- ยังแนะนำให้ใช้ role + schema grant แทนการยัด `db_datareader`/`db_owner` ให้ user รายคน — หลัก least privilege ไม่เปลี่ยน

> อ้างอิง: [GRANT (Transact-SQL)](https://learn.microsoft.com/sql/t-sql/statements/grant-transact-sql?view=sql-server-ver17), [Ownership and user-schema separation](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/ownership-and-user-schema-separation-sql-server?view=sql-server-ver17), [CREATE USER](https://learn.microsoft.com/sql/t-sql/statements/create-user-transact-sql?view=sql-server-ver17)
