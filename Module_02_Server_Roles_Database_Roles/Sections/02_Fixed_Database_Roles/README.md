# Section 2 — การใช้งาน Fixed Database Roles

เมื่อลงมือที่ระดับฐานข้อมูล การให้สิทธิ์ทีละ object จะยุ่งมาก — fixed database roles คือชุดสำเร็จรูปที่ออกแบบมาครอบคลุมพฤติกรรมงานยอดนิยม Section นี้จัดระเบียบทั้งหมดและสอนการใช้จริง

## 2.1 สิทธิ์ในระดับฐานข้อมูล

โครงสิทธิ์ระดับ DB มีลำดับซ้อนเหมือนระดับ server ดูได้ด้วย pattern เดียวกัน:

สคริปต์เดโม: [Scripts/01_DatabasePermissionHierarchy.sql](Scripts/01_DatabasePermissionHierarchy.sql)

```sql
WITH recCTE AS
(
    SELECT permission_name, covering_permission_name AS parent_permission, 1 AS lvl
    FROM sys.fn_builtin_permissions('DATABASE')
    WHERE covering_permission_name = ''
    UNION ALL
    SELECT bp.permission_name, bp.covering_permission_name, r.lvl + 1
    FROM recCTE AS r
    CROSS APPLY sys.fn_builtin_permissions('DATABASE') AS bp
    WHERE bp.covering_permission_name = r.permission_name
)
SELECT * FROM recCTE ORDER BY lvl, permission_name;
```

สิ่งที่น่าจดจำ: `CONTROL` ระดับ database ≈ db_owner; `SELECT/INSERT/UPDATE/DELETE/EXECUTE` เป็นสิทธิ์ลูกที่ใช้ประจำ; `ALTER ANY USER` คือสิทธิ์ที่สำคัญมากเมื่อพูดถึง contained databases (Module 1)

## 2.2 Fixed Database Roles — ตารางอ้างอิงเต็ม

สคริปต์เดโม: [Scripts/02_FixedDatabaseRoles_Demo.sql](Scripts/02_FixedDatabaseRoles_Demo.sql)

| Role | ทำอะไรได้ | ใช้เมื่อไร |
|:-----|:----------|:----------|
| **db_owner** | ทุกอย่างในฐานข้อมูลนี้ (ยกเว้นเรื่อง server) | ผู้รับผิดชอบฐานข้อมูลนั้น |
| **db_securityadmin** | จัดการ roles/membership และสิทธิ์ใน DB | ผู้คุมสิทธิ์ย่อย |
| **db_accessadmin** | เพิ่ม/ถอน user (ACCESS) | onboarding users |
| **db_backupoperator** | `BACKUP DATABASE/LOG` | ทีม backup ระดับ DB |
| **db_datareader** | `SELECT` ทุกตาราง/view | นักวิเคราะห์, BI |
| **db_datawriter** | `INSERT/UPDATE/DELETE` ทุกตาราง | แอปเขียนข้อมูล |
| **db_ddladmin** | `CREATE/ALTER/DROP` objects | developer ฝั่ง schema |
| **db_denydatareader** | ห้ามอ่านทุกตาราง | กั้นขา (deny ชนะ grant) |
| **db_denydatawriter** | ห้ามเขียนทุกตาราง | กั้นขา |
| **dbm_monitor** | ดูสถานะ Database Mirroring (เมื่อใช้) | ops ดู health |

จัดการ membership:

```sql
USE [AdventureWorks2025];
GO
ALTER ROLE [db_datareader] ADD MEMBER [Sales_Asia];
ALTER ROLE [db_datareader] DROP MEMBER [Sales_Asia];
GO
```

## 2.3 Database Principals เข้า Roles — วิธีตรวจและจัดการ

```sql
-- ตรวจว่า user อยู่ role อะไร
SELECT rdp.name AS role_name, rdm.name AS member_name
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS rdp ON rdp.principal_id = rm.role_principal_id
JOIN sys.database_principals AS rdm ON rdm.principal_id = rm.member_principal_id
WHERE rdm.name = N'Sales_Asia'
ORDER BY role_name;

-- ตรวจจากฝั่งตัว user เอง (ระหว่าง session ของ user)
EXECUTE AS USER = N'Sales_Asia';
SELECT IS_MEMBER('db_datareader') AS is_datareader,
       IS_MEMBER('db_owner')      AS is_owner;
REVERT;
```

## 2.4 เจ้าของฐานข้อมูล (db_owner กับ ownership)

ข้อแตกต่างที่ทำให้ DBA พลาดบ่อย:

- **เจ้าของฐานข้อมูล** (database owner) — login ที่ถือ `principal_id = 1` (ตรวจด้วย `SELECT SUSER_SNAME(owner_sid) FROM sys.databases WHERE name='...'`) มีอำนาจเท่า db_owner **โดยไม่ต้องเป็นสมาชิก role** และเจ้าของเท่านั้นที่เข้าฐานข้อมูลได้แม้ DB จะอยู่โหมด `RESTRICTED_USER`
- เปลี่ยนเจ้าของ: `ALTER AUTHORIZATION ON DATABASE::[AdventureWorks2025] TO [new_login];`
- objects ที่สร้างโดย member ของ db_owner จะเป็นของ schema **dbo** เสมอ (สร้างชื่อ `dbo.x` โดย default)

> **แนวปฏิบัติ**: อย่าให้บุคคลตัวเป็น "เจ้าของ" ฐานข้อมูลของระบบงาน — ใช้ `sa` หรือ service account ถือ ownership และให้คนจริงเป็น db_owner ผ่าน role เพื่อความชัดเจนเวลาตรวจสอบ

## 🚀 SQL Server 2025 & Modern Notes

- `##MS_DatabaseConnector##` (2022+) เป็นทางเลือกใหม่เมื่อต้อง "เข้าถึงหลายฐานข้อมูล" โดยไม่ต้องสร้าง user ทีละตัว — ครอบคลุมบางกรณีที่เดิมใช้ db_accessadmin ซ้ำ ๆ
- การให้ `db_datareader` ครั้งเดียวเหมือนให้ SELECT ทุกตาราง **รวมตารางใหม่ที่สร้างภายหลัง** — ออกแบบโดยเข้าใจว่าเป็นสิทธิ์ "ทั้ง DB" ไม่ใช่ snapshot
- SQL Server 2025: การเปลี่ยน membership/สิทธิ์มี security cache ที่กระทบ user อื่นน้อยลง
- ในสถาปัตยกรรม AG / replication: db_owner บน secondary ทำงานเหมือน primary (สิทธิ์ถูก sync ทั้ง DB) — คุมทั้งสองข้าง

> อ้างอิง: [Database-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/database-level-roles?view=sql-server-ver17), [ALTER AUTHORIZATION](https://learn.microsoft.com/sql/t-sql/statements/alter-authorization-transact-sql?view=sql-server-ver17)
