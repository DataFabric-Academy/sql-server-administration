ในบทที่ 1 ผู้เรียนจัดการ identity รายบุคคล ในบทนี้จะเปลี่ยนมุมมองเป็น **กลุ่ม (Roles)** — เครื่องมือจริงที่ใช้บริหารสิทธิ์ในองค์กร เพราะการให้สิทธิ์ทีละคนทำให้ระบบพังในเชิงบริหารเร็วที่สุด

หลักการ: SQL Server มี roles สองระดับ — ระดับ server (จัดการ instance ทั้งหมด) และระดับ database (จัดการข้อมูลในฐานข้อมูล) โดยมีทั้งชุดที่สร้างมาให้ (fixed) และชุดที่ออกแบบเองได้ (user-defined) และตั้งแต่ SQL Server 2022 มีชุด fixed server roles แบบ least-privilege (`##MS_*##`) ที่กลายเป็นมาตรฐานใหม่เมื่อ Purview access policies ถูกถอดใน SQL Server 2025

### 2.1 Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – รู้จักแผนที่สิทธิ์**: อธิบาย permission hierarchy ของ server และ database ผ่าน `sys.fn_builtin_permissions` ได้
- **ระดับ 2 – ใช้ fixed roles ได้ถูกตัว**: เลือกใช้ fixed server roles / fixed database roles / `##MS_*##` roles ให้ตรงกับหน้าที่ โดยไม่ให้ sysadmin ฟรี ๆ
- **ระดับ 3 – ออกแบบ role model**: สร้าง user-defined roles พร้อมสิทธิ์ที่ schema เหมาะกับองค์กร และจัดการ membership อย่างมีวินัย
- **ระดับ 4 – ควบคุมขอบเขตแอป**: ใช้ application roles เพื่อแยกสิทธิ์ของแอปพลิเคชันออกจากสิทธิ์ของคน

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [การใช้งาน Server Roles](Sections/01_Server_Roles/README.md) |
| 2 | [การใช้งาน Fixed Database Roles](Sections/02_Fixed_Database_Roles/README.md) |
| 3 | [User-defined Database Roles และ Application Roles](Sections/03_User_Defined_Roles/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. Login ใหม่ทุกตัวเป็นสมาชิก role ใดโดยอัตโนมัติ และได้สิทธิ์อะไรมา?</b></summary>
เป็นสมาชิก **public** server role — สิทธิ์ที่ได้เริ่มต้นดูได้จาก `EXECUTE AS LOGIN = 'x'; SELECT * FROM sys.fn_my_permissions(NULL,'SERVER'); REVERT;` — ส่วนใหญ่คือ VIEW SERVER STATE บางส่วนและ CONNECT SQL — อ่านละเอียด: [Section 1](Sections/01_Server_Roles/README.md)
</details>

<details>
<summary><b>2. db_datareader กับ db_ddladmin ต่างกันอย่างไร?</b></summary>
`db_datareader` อ่านได้ทุกตาราง/ทุก view; `db_ddladmin` สร้าง/แก้/ลบ objects (CREATE, ALTER, DROP) แต่ไม่ได้อ่านข้อมูลโดยอัตโนมัติ — ต้องคู่กันถ้าต้องการ "developer ที่เขียน schema และดูข้อมูลได้" — อ่านละเอียด: [Section 2](Sections/02_Fixed_Database_Roles/README.md)
</details>

<details>
<summary><b>3. เมื่อไรควรใช้ user-defined server role แทนการให้ sysadmin?</b></summary>
เมื่อทีมต้องการสิทธิ์เฉพาะกลุ่ม เช่น "ดู DMV/performance" หรือ "เรียก BULK OPERATIONS" — ใช้ `CREATE SERVER ROLE` + `GRANT <permission> TO role` แทนการเลื่อนเป็น sysadmin; SQL Server 2022+ มี `##MS_*##` roles สำเร็จรูปหลายกรณี — อ่านละเอียด: [Section 1](Sections/01_Server_Roles/README.md)
</details>

<details>
<summary><b>4. Application role เปิดใช้แล้ว session เกิดอะไรขึ้น?</b></summary>
Session สลับเป็น user token ของ app role ทันที สิทธิ์ของผู้ใช้จริง "หายไป" (รวมถึงการเข้าถึง database อื่น) จนกว่าจะ `sp_unsetapprole` ด้วย cookie — อ่านละเอียด: [Section 3](Sections/03_User_Defined_Roles/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **Fixed server roles ชุดใหม่ (2022+)** — `##MS_DatabaseConnector##`, `##MS_LoginReader##`, `##MS_ServerStateReader##`, `##MS_ServerPerformanceStateReader##` ฯลฯ ใช้แทนการให้ sysadmin เพื่อดู monitoring/security
- **Purview access policies discontinued ใน SQL Server 2025** — Microsoft แนะนำให้ย้ายมาใช้ fixed server roles ชุดนี้แทน (SQL Performance Monitoring → `##MS_ServerPerformanceStateReader##`; SQL Security Auditing → `##MS_ServerSecurityStateReader##`)
- **PBKDF2 password hash (2025)** — ใช้กับ application roles ด้วย รหัสผ่านของ app role ปลอดภัยขึ้นโดย default
- **Security cache improvements (2025)** — การเปลี่ยน membership ของ roles กระทบ cache เฉพาะ login ที่เกี่ยวข้อง
- `sp_srvrolepermission` **deprecated** — ดูสิทธิ์ของ role ด้วย `sys.fn_builtin_permissions` และ `sys.server_role_members` แทน

> อ้างอิง: [Server-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17), [Database-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/database-level-roles?view=sql-server-ver17), [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17)
