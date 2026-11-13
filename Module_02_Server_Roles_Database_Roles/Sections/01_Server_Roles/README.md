# Section 1 — การใช้งาน Server Roles

Server roles คือ "กลุ่มสิทธิ์ระดับ server" — การเพิ่ม login เข้า role เท่ากับให้สิทธิ์ของ role ทั้งชุดในครั้งเดียว Section นี้ครอบคลุม permission hierarchy ทั้งหมดของ server, fixed roles ที่มากับตัว, public role และการสร้าง role เองแบบ least-privilege

## 1.1 สิทธิ์ในระดับเซิร์ฟเวอร์ — ดูแผนที่ทั้งหมด

ทุก permission ใน SQL Server จัดลำดับซ้อนกัน (hierarchy) — สิทธิ์แม่ครอบสิทธิ์ลูก เช่น `CONTROL SERVER` ครอบเกือบทุกอย่าง ดูลำดับจริงด้วย recursive CTE:

สคริปต์เดโม: [Scripts/01_ServerPermissionHierarchy.sql](Scripts/01_ServerPermissionHierarchy.sql)

```sql
WITH recCTE AS (
    SELECT permission_name, covering_permission_name AS parent_permission, 1 AS lvl
    FROM sys.fn_builtin_permissions('SERVER')
    WHERE permission_name = 'CONTROL SERVER'
    UNION ALL
    SELECT bp.permission_name, bp.covering_permission_name, r.lvl + 1
    FROM recCTE AS r
    CROSS APPLY sys.fn_builtin_permissions('SERVER') AS bp
    WHERE bp.covering_permission_name = r.permission_name
)
SELECT * FROM recCTE ORDER BY lvl, permission_name;
```

สิ่งที่ควรสังเกต: `CONTROL SERVER` (ที่ sysadmin ใช้ได้) ครอบ `ALTER SERVER STATE`, `ALTER SETTINGS` ฯลฯ และ `VIEW SERVER STATE` (ใช้ดู DMVs) อยู่ลึกข้างใน — จึงเป็นสิทธิ์ที่ควรแยกให้ทีม monitoring โดยไม่ต้องเป็น sysadmin

## 1.2 Fixed Server Roles — ชุดที่มากับตัว

สคริปต์เดโม: [Scripts/02_FixedServerRoles_Demo.sql](Scripts/02_FixedServerRoles_Demo.sql)

| Role | ทำอะไรได้ | ควรให้ใคร |
|:-----|:----------|:----------|
| **sysadmin** | ทุกอย่างทั้ง server (แม้ DENY ก็ข้ามได้) | DBA หลักเท่านั้น |
| **serveradmin** | เปลี่ยน config, ปิด/เปิด server | ผู้ดูแลระบบระดับสูง |
| **securityadmin** | จัดการ logins และให้สิทธิ์ระดับ server | ผู้รับผิดชอบ identity |
| **processadmin** | จบ session/process (`KILL`) | on-call engineer |
| **setupadmin** | จัดการ linked servers | ผู้ดูแล integration |
| **bulkadmin** | รัน `BULK INSERT` / `ADMINISTER BULK OPERATIONS` | ETL operator |
| **diskadmin** | จัดการไฟล์/filegroups ระดับ server | DBA ฝ่ายโครงสร้าง |
| **dbcreator** | สร้าง/แก้/ลบฐานข้อมูล | ผู้ดูแล dev environments |
| **public** | ทุก login เป็นสมาชิกโดย default — สิทธิ์ที่ให้เป็น "ของทุกคน" | ระวังการ GRANT เพิ่มที่นี่ |

จัดการ membership:

```sql
USE [master];
GO
-- เพิ่ม/ถอนสมาชิก
ALTER SERVER ROLE [diskadmin] ADD MEMBER [LabLogin];
ALTER SERVER ROLE [diskadmin] DROP MEMBER [LabLogin];
GO

-- ตรวจดูสมาชิกทั้งหมด
SELECT spr.name AS role_name, spm.name AS member_name
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS spr ON spr.principal_id = rm.role_principal_id
JOIN sys.server_principals AS spm ON spm.principal_id = rm.member_principal_id
WHERE spm.name = N'LabLogin'
ORDER BY role_name;
GO
```

### Fixed Server Roles ชุดใหม่ (SQL Server 2022+) — แนวคิด least-privilege

SQL Server 2022 เพิ่ม fixed server roles ที่ให้ "สิทธิ์อ่าน/จัดการเฉพาะด้าน" เขียนด้วยรูป `##MS_...##`:

| Role | สิทธิ์หลัก | แทนการให้ |
|:-----|:-----------|:----------|
| `##MS_DatabaseConnector##` | `CONNECT ANY DATABASE` — เชื่อมทุกฐานข้อมูลได้ | การสร้าง user ทีละฐานข้อมูล |
| `##MS_LoginReader##` | ดู logins/roles | sysadmin เพื่อ audit logins |
| `##MS_DatabaseStateReader##` | ดูสถานะทุก DB | sysadmin เพื่อ inventory |
| `##MS_ServerStateReader##` | `VIEW SERVER STATE` + `VIEW ANY DEFINITION` | sysadmin เพื่อดู DMVs |
| `##MS_ServerStateManager##` | `ALTER SERVER STATE` (KILL, reload config) | sysadmin เพื่อ kill session |
| `##MS_ServerPerformanceStateReader##` | ดู perf-related DMVs | sysadmin เพื่อ monitoring |
| `##MS_ServerSecurityStateReader##` | ดู security state | sysadmin เพื่อ security audit |
| `##MS_PerformanceDefinitionReader##` | ดู definition เชิง perf | sysadmin เพื่อ tuning |
| `##MS_SecurityDefinitionReader##` | ดู definition เชิง security | sysadmin เพื่อ audit |
| `##MS_DefinitionReader##` | ดู definition ทุกด้าน | sysadmin เพื่อ inventory |

> **สำคัญ (SQL Server 2025)**: Microsoft ถอด **Purview access policies** ใน SQL Server 2025 และแนะนำให้แทนด้วย roles กลุ่มนี้โดยตรง — ถ้าคุณเคยใช้ Purview policies กับ SQL Server วางแผนย้ายตั้งแต่ตอนอัปเกรด

## 1.3 User-defined Server Roles

เมื่อไม่มี fixed role ที่พอดี สร้างเองได้:

```sql
USE [master];
GO
CREATE SERVER ROLE [MonitoringViewer] AUTHORIZATION sa;
GO
GRANT VIEW SERVER STATE TO [MonitoringViewer];
GRANT VIEW ANY DATABASE TO [MonitoringViewer];
GO
ALTER SERVER ROLE [MonitoringViewer] ADD MEMBER [LabLogin];
GO
```

หรือมองเป็นหลักการ: **role = container ของสิทธิ์** — ออกแบบ role ตามหน้าที่งาน (job function) ไม่ใช่ตามคน; คนเข้า/ออกแค่เปลี่ยน membership

ตรวจสิทธิ์ของ login จริงผ่าน `EXECUTE AS`:

```sql
EXECUTE AS LOGIN = N'LabLogin';
SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
REVERT;
```

## 🚀 SQL Server 2025 & Modern Notes

- `sp_srvrolepermission` (เดิมใช้รายงานสิทธิ์ของ role) **deprecated** — ใช้ `sys.fn_builtin_permissions('SERVER')` + `sys.server_role_members` แทน
- ใช้ `##MS_ServerPerformanceStateReader##`/`##MS_ServerSecurityStateReader##` เป็นมาตรฐานใหม่แทน Purview access policies (discontinued ใน 2025)
- สิทธิ์ระดับ server ที่ใช้บ่อยสมัยใหม่: `VIEW SERVER STATE` (DMVs), `VIEW ANY DEFINITION` (metadata), `ADMINISTER BULK OPERATIONS` (ETL), `ALTER ANY CONNECTION`
- Security cache improvements (2025): การเปลี่ยน membership กระทบเฉพาะ login ที่เกี่ยว ระบบที่จัด role ถี่ไม่โดนแรงรวม

> อ้างอิง: [Server-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17), [GRANT server permissions](https://learn.microsoft.com/sql/t-sql/statements/grant-server-principals-transact-sql?view=sql-server-ver17)
