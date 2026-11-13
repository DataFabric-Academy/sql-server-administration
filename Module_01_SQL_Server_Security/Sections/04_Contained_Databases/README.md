# Section 4 — รู้จักกับ Partially Contained Databases

เมื่อฐานข้อมูลย้ายบ้านบ่อย (failover ใน Availability Groups, migration ระหว่าง server, ส่งมอบให้ฝ่ายพัฒนา) การพึ่งพา login ระดับ server ทำให้ทุกการย้ายต้องซิงก์ logins อีกชุดหนึ่ง — **Contained Databases** คือคำตอบสถาปัตยกรรมของ Microsoft: ให้ "ข้อมูลและกฎการพิสูจน์ตัวตน" อยู่รวมกันในฐานข้อมูลตัวเดียว

## 4.1 แนวคิด: Containment แบบใดเอาเท่าไร

| ชนิด | พฤติกรรม |
|:-----|:---------|
| **Fully contained** | ทุกอย่าง (metadata, temp tables, collation) อยู่ใน DB จริง ๆ — SQL Server ยังไม่มีรุ่นสมบูรณ์แบบ 100% |
| **Partially contained** (ที่ใช้จริง) | ฐานข้อมูลถือ **contained users** (พิสูจน์ตัวตนกับ DB โดยตรง) ได้ แต่ยังอนุญาต instance-level objects ข้ามได้บางส่วน |

สิ่งที่ "อยู่ในกรอบ" เมื่อเปิด partial containment:

- **Contained SQL users** — password เก็บในฐานข้อมูลเอง (`CREATE USER ... WITH PASSWORD`)
- **Windows/Entra users** แบบไม่มี login (`CREATE USER [MACHINE\student]` โดยไม่มี login)
- Metadata ต่าง ๆ: default collation ของ session, **temporary table collations**, `@@LANGUAGE`, timezone logic บางส่วน

## 4.2 ข้อควรคำนึงก่อนใช้

1. **ต้องเปิด option ระดับ server ก่อน**: `sp_configure 'contained database authentication', 1` + `RECONFIGURE`
2. **ความเสี่ยง**: ผู้ใช้ contained ที่เป็น member ของ `db_owner` สามารถสร้าง user ใหม่ใน DB ได้เอง — เท่ากับมีสิทธิ์ระดับ "admin ย่อย" ที่ผู้ดูแล server ไม่รู้ตัว → Microsoft แนะนำให้ตรวจสอบด้วย DMV `sys.dm_contained_authentication` และจัดการเรื่อง **`ALTER ANY USER`** อย่างเข้มงวด
3. **Deny การย้ายอัตโนมัติ**: ฐานข้อมูลที่เคยสร้าง user แบบ instance มาแล้วจะยังใช้ได้ปกติ แต่ถ้ามี SQL login ที่ชื่อซ้ำกับ contained user ระบบจะเลือก contained user ก่อน (auth order: contained → login)
4. ฐานข้อมูล system บางตัว (master) ไม่สามารถ contain ได้

## 4.3 การสาธิต: สร้าง Partially Contained Database

สคริปต์เดโม: [Scripts/01_ContainedDatabase.sql](Scripts/01_ContainedDatabase.sql)

```sql
-- STEP A: ดูสถานะ option ระดับ server
USE [master];
GO
SELECT value_in_use, description
FROM sys.configurations
WHERE name = 'contained database authentication';
GO

-- STEP B: เปิดใช้
EXEC sys.sp_configure N'contained database authentication', 1;
RECONFIGURE;
GO

-- STEP C: สร้างฐานข้อมูลแบบ partially contained
CREATE DATABASE [PartialData] CONTAINMENT = PARTIAL;
GO

-- STEP D: สร้าง contained users (รหัสผ่านอยู่ใน DB — ไม่มี login!)
USE [PartialData];
GO
CREATE USER [ClientUser1] WITH PASSWORD = N'Pa$$w0rd2025';
CREATE USER [ClientUser2] WITH PASSWORD = N'Pa$$w0rd2025';
GO
SELECT * FROM sys.database_principals
WHERE authentication_type_desc = 'DATABASE';
GO
```

เมื่อย้าย `PartialData` ไป server ใหม่ (backup/restore หรือ AG failover): ผู้ใช้ login ด้วย `ClientUser1` + รหัสผ่านได้ทันทีโดยไม่ต้องสร้าง login ใด ๆ บน server ปลายทาง

**ทดสอบแบบ backup → restore ไป server อื่น** (หรือ container ที่สอง `sql2025b`):

```sql
BACKUP DATABASE PartialData
    TO DISK = N'D:\SQLBackups\PartialData.bak' WITH CHECKSUM;
-- ... copy ไป server ปลายทาง แล้ว ...
RESTORE DATABASE PartialData FROM DISK = N'D:\SQLBackups\PartialData.bak'
    WITH MOVE 'PartialData' TO 'D:\SQLData\PartialData.mdf',
         MOVE 'PartialData_log' TO 'D:\SQLLog\PartialData_log.ldf';
-- เปิด contained authentication บน server ปลายทาง (ถ้ายังไม่เปิด) แล้ว login ด้วย ClientUser1 ได้ทันที
```

**Cleanup**:

```sql
USE [master];
GO
ALTER DATABASE [PartialData] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IF EXISTS [PartialData];
EXEC sys.sp_configure N'contained database authentication', 0;
RECONFIGURE;
GO
```

## 4.4 Contained Users vs Instance Users — เมื่อไรใช้อะไร

| เกณฑ์ | Contained user | Instance user |
|:------|:---------------|:--------------|
| ย้าย DB บ่อย / AG failover | ✅ เหมาะที่สุด | ❌ ต้องซิงก์ logins |
| ควบคุม access กลางจาก server ตัวเดียว | ❌ กระจาย | ✅ |
| สิทธิ์ db_owner ของผู้ใช้ปลายทาง | ⚠️ เสี่ยง (สร้าง user เองได้) | โอเคถ้าคุมดี |
| เชื่อมกับ Entra/Managed identity | ใช้ได้ (2022+) | ใช้ได้ |

## 🚀 SQL Server 2025 & Modern Notes

- Containment ยังเป็นแบบ **partial** เหมือนเดิม — Microsoft ใช้มันเป็นฐานของ **Availability Group failover ที่มือใหม่ทำได้** และรูปแบบ contained AG บน Linux (SQL Server 2025 CU1+) ที่ restore/create DB ผ่าน listener ได้
- **PBKDF2 password hashing (2025)** ใช้กับ contained users ด้วย — รหัสผ่านของ contained users แข็งแรงขึ้นโดย default
- ตรวจ contained users ทั้ง instance ได้จาก `sys.dm_contained_authentication` / หรือสแกน `sys.database_principals.authentication_type_desc = 'DATABASE'`
- ระวังทางกลับ: ฐานข้อมูลที่เคย enable แล้วมี contained users ถ้า disable option ระดับ server — user เหล่านั้นจะ login ไม่ได้ทันที (เป็นข้อพังงานหลัง upgrade ที่พบบ่อย)

> อ้างอิง: [Contained Databases](https://learn.microsoft.com/sql/relational-databases/databases/contained-databases?view=sql-server-ver17), [Enable Contained Database Authentication](https://learn.microsoft.com/sql/database-engine/configure-windows/enable-contained-database-authentication-server-configuration-option?view=sql-server-ver17), [Security best practices with contained databases](https://learn.microsoft.com/sql/relational-databases/databases/security-best-practices-with-contained-databases?view=sql-server-ver17)
