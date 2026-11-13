ในบทเรียนแรกนี้ ผู้เรียนจะได้วางรากฐานความปลอดภัยของ SQL Server ซึ่งเป็นหัวใจของงาน Database Administration ทุกหัวข้อถัดไปในคอร์สนี้ (Roles, Permissions, Audit, Automation) ล้วนซ้อนอยู่บนโมเดลความปลอดภัยที่จะได้เรียนในโมดูลนี้

หลักการทำงาน: SQL Server ใช้โมเดล **Authentication → Authorization** — พิสูจน์ตัวตนระดับ server ด้วย Login ก่อน จากนั้นแมปเป็น User ระดับฐานข้อมูลเพื่อรับสิทธิ์ โดยทั้งหมดต้องผ่านกลไก **Security Token** ที่ engine ประกอบขึ้นทุกครั้งที่ login เข้ามา

### 1.1 Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – เข้าใจโมเดลความปลอดภัย**: อธิบาย Securable / Principal / Permission และความสัมพันธ์ Windows ↔ SQL Server ↔ Database ได้
- **ระดับ 2 – จัดการ Logins และ Users**: สร้าง/แก้ไข/ลบ login ด้วย SSMS และ T-SQL และแมป login เป็น user อย่างถูกหลัก least-privilege
- **ระดับ 3 – วิเคราะห์ปัญหาจริง**: อ่าน security token ของ session, อธิบาย double-hop และแก้ orphaned users (SID mismatch) ได้
- **ระดับ 4 – ออกแบบสถาปัตยกรรม**: เลือกใช้ contained databases, Microsoft Entra logins และ managed identity (SQL Server 2025) ให้เหมาะกับแต่ละสถานการณ์

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [Authentication และ Logins](Sections/01_Authentication_Logins/README.md) |
| 2 | [การแมป Login เป็น User ในฐานข้อมูล](Sections/02_Login_to_User_Mapping/README.md) |
| 3 | [สิทธิ์ข้ามเครื่อง — Linked Servers, Double-Hop และ SID](Sections/03_Cross_Server_Security/README.md) |
| 4 | [Partially Contained Databases](Sections/04_Contained_Databases/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. Login กับ User ต่างกันอย่างไร?</b></summary>
**Login** คือตัวตนระดับ server ใช้พิสูจน์ตัวตนตอนเชื่อมต่อ; **User** คือแมปของ login ภายในฐานข้อมูลหนึ่ง ๆ ใช้รับสิทธิ์กับ objects ใน database — login หนึ่งสามารถมี user ได้หลายตัวในหลายฐานข้อมูล แต่ 1 user ต่อ 1 database — อ่านละเอียด: [Section 2](Sections/02_Login_to_User_Mapping/README.md)
</details>

<details>
<summary><b>2. เจอ error "Login failed for user 'Superman'" ทั้งที่สร้าง login แล้ว — สาเหตุอะไรบ้าง?</b></summary>
สาเหตุที่พบบ่อย: (1) login ถูก disable (`ALTER LOGIN ... DISABLE`), (2) password ผิดหรือ policy block, (3) user ไม่ถูกสร้างในฐานข้อมูลเป้าหมาย หรือ SID ไม่ตรง (orphaned), (4) Windows account ไม่อยู่ในกลุ่มที่อนุญาต, (5) Mixed Mode ยังไม่เปิด — อ่านละเอียด: [Section 1](Sections/01_Authentication_Logins/README.md) และ [Section 3](Sections/03_Cross_Server_Security/README.md)
</details>

<details>
<summary><b>3. Orphaned user เกิดจากอะไร และแก้อย่างไรใน SQL Server ปัจจุบัน?</b></summary>
เกิดเมื่อ SID ของ user ในฐานข้อมูลไม่ตรงกับ SID ของ login ระดับ server (เช่น restore จาก server อื่น) — แก้ด้วย `ALTER USER [user] WITH LOGIN = [login]` (sp_change_users_login เดิม deprecated) — อ่านละเอียด: [Section 3 หัวข้อ 4](Sections/03_Cross_Server_Security/README.md)
</details>

<details>
<summary><b>4. Contained database user ต่างจาก SQL login อย่างไร เมื่อไรควรใช้?</b></summary>
Contained user พิสูจน์ตัวตนกับฐานข้อมูลโดยตรง ไม่ผูกกับ login ระดับ server — ย้ายฐานข้อมูลไป server ใหม่ได้ไม่ต้องแก้ mapping เลย เหมาะกับสภาพแวดล้อมที่ย้าย DB บ่อย (AG, cloud migration) แต่ต้องเปิด `contained database authentication` และระวังเรื่องการทำ failover — อ่านละเอียด: [Section 4](Sections/04_Contained_Databases/README.md)
</details>

<details>
<summary><b>5. SQL Server 2025 เปลี่ยนวิธีเก็บรหัสผ่าน login อย่างไร?</b></summary>
ใช้ **PBKDF2 (PBKDF2 + SHA512)** เป็นค่า default ของ password hash ตามมาตรฐาน NIST SP 800-63b ทำให้การ brute-force hash แพงขึ้นมากโดยไม่ต้องตั้งค่าใด ๆ — อ่านละเอียด: [Section 1 หัวข้อ SQL Server 2025](Sections/01_Authentication_Logins/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **PBKDF2 password hashes เป็น default** — CREATE LOGIN / APPLICATION ROLE ใช้ PBKDF2+SHA512 ตาม NIST SP 800-63b
- **Security cache improvements** — การ invalidate cache ทำเฉพาะ login ที่ถูกกระทบ ผู้ใช้อื่นไม่โดนกระทบ (GRANT/DENY จำนวนมากกระทบ performance น้อยลง)
- **Managed identity** ผ่าน Azure Arc — SQL Server เรียก Azure resources และรับ inbound connections ด้วย identity ที่ Azure จัดการให้ โดยไม่ต้องเก็บ secret
- **TLS 1.3 + TDS 8.0** — การเชื่อมต่อแบบ strict encryption รองรับ sqlcmd, linked servers และบริการประกอบอีกหลายตัว
- **Custom password policy บน Linux** — กำหนดเกณฑ์รหัสผ่านเองสำหรับ SQL Authentication บน SQL Server 2025 on Linux
- Microsoft Entra ID logins (`CREATE LOGIN ... FROM EXTERNAL PROVIDER`) มาตั้งแต่ SQL Server 2022 และรองรับ `WITH OBJECT_ID` สำหรับชื่อที่ซ้ำกันตั้งแต่ 2025

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Security Center for SQL Server](https://learn.microsoft.com/sql/relational-databases/security/security-center-for-sql-server-database-engine-and-azure-sql-database?view=sql-server-ver17), [SQL Server Authentication](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/choose-authentication-mode?view=sql-server-ver17)
