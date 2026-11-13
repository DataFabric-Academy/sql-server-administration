# Module 03 — อนุญาตให้ผู้ใช้เข้าใช้งานทรัพยากร (Authorizing Users to Access Resources)

โมดูลก่อนหน้าครอบคลุมการสร้าง Login/User และบทบาท (Roles) ระดับ server และ database แล้ว แต่การเป็น "ผู้ใช้ในระบบ" ไม่ได้แปลว่าผู้ใช้ทำอะไรได้เลย — ตามหลักการ SQL Server ทุกอย่างเริ่มจาก "ไม่มีสิทธิ์อะไรเลย" แล้ว DBA เป็นคนมอบสิทธิ์ทีละชิ้นด้วย `GRANT` โมดูลนี้จึงเจาะลึกฝั่ง **Authorization**: การมอบสิทธิ์บนทรัพยากรประเภทต่าง ๆ ทั้ง **Object** (ตาราง, คอลัมน์, แถว), **Code** (stored procedure, function) และ **Schema** (ทั้งกลุ่ม object ในครั้งเดียว)

สิ่งที่ทำให้โมดูลนี้สำคัญคือ DBA ส่วนใหญ่ทำผิดในทางเดียวกันคือยัดใส่ role ใหญ่ ๆ เช่น `db_owner` ให้ทุกคนเพราะง่าย แต่หลัก **Principle of Least Privilege** ต้องการสิทธิ์แค่เท่าที่จำเป็น — ซึ่ง SQL Server มีเครื่องมือรองรับครบ ตั้งแต่ column-level permissions ไปจนถึง Row-Level Security (RLS) ที่กรองข้อมูลที่ระดับแถวโดยแอปไม่ต้องรู้ตัวด้วยซ้ำ

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)

- **ระดับ 1 – GRANT/DENY/REVOKE**: สามารถมอบ ปฏิเสธ และเรียกคืนสิทธิ์บน table/view ได้ และเข้าใจลำดับการประเมินว่า DENY ชนะเมื่อไหร่
- **ระดับ 2 – Fine-grained permissions**: สามารถกำหนดสิทธิ์ระดับคอลัมน์ และคุมการเข้าถึงระดับแถวด้วย Row-Level Security ได้
- **ระดับ 3 – Code security**: สามารถมอบสิทธิ์ `EXECUTE` บน stored procedure/function และควบคุม execution context ด้วย `EXECUTE AS` และ ownership chaining ได้
- **ระดับ 4 – Schema-level administration**: สามารถออกแบบ permission model ทั้ง schema ด้วย role-based grants ได้โดยไม่ต้อง GRANT ทีละ object

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [Object Permissions — สิทธิ์บนตาราง คอลัมน์ และแถว](Sections/01_Object_Permissions/README.md) |
| 2 | [Code Permissions — สิทธิ์บน Stored Procedure, Function และ Execution Context](Sections/02_Code_Permissions/README.md) |
| 3 | [Schema Permissions — กำหนดสิทธิ์ระดับ Schema](Sections/03_Schema_Permissions/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. User A มี GRANT SELECT ที่ระดับ table แต่โดน DENY SELECT บนคอลัมน์เดียว แล้ว SELECT * ได้ไหม?</b></summary>
ไม่ได้ เพราะ DENY มีลำดับความสำคัญสูงกว่า GRANT เสมอ (DENY wins) ข้อยกเว้นเดียวคือขอบเขตที่แคบกว่า: ถ้า DENY ที่ระดับ table แต่ GRANT ระดับ column แบบไม่เปิด Common Criteria Compliance แล้ว SELECT เฉพาะคอลัมน์ที่ได้ GRANT จะยังทำได้ — อ่านละเอียด: [Section 1](Sections/01_Object_Permissions/README.md)
</details>

<details>
<summary><b>2. RLS (Row-Level Security) ทำงานอย่างไร และประกอบด้วยอะไรบ้าง?</b></summary>
ประกอบด้วย 3 ชิ้น: (1) inline table-valued function ที่คืน 1 เมื่อแถวนั้นใช้ได้ (มักเทียบกับ <code>USER_NAME()</code> หรือ <code>SESSION_CONTEXT</code>) (2) <code>CREATE SECURITY POLICY</code> ที่ผูก function เป็น FILTER PREDICATE (กรองตอนอ่าน) หรือ BLOCK PREDICATE (กันเขียนผิดเงื่อนไข) บนตาราง และ (3) การเปิดด้วย <code>WITH (STATE = ON)</code> โค้ดครบ: [Section 1](Sections/01_Object_Permissions/README.md)
</details>

<details>
<summary><b>3. ทำไมการ GRANT EXECUTE บน stored procedure ถึงปลอดภัยกว่าการ GRANT SELECT บนตารางที่ proc อ้างถึง?</b></summary>
เพราะทันทีที่ proc และตารางอยู่ภายใต้เจ้าของ (owner) เดียวกัน กลไก **Ownership Chaining** จะข้ามการตรวจสิทธิ์ของ statement ภายใน proc — user ที่เรียก proc ไม่ต้องมีสิทธิ์บนตารางเลย และยังไม่สามารถ query ตารางโดยตรงได้ ผลคือฝั่ง client เข้าถึงข้อมูลได้เฉพาะช่องทางที่ proc อนุญาต — อ่านละเอียด: [Section 2](Sections/02_Code_Permissions/README.md)
</details>

<details>
<summary><b>4. Ownership chaining เจอ dynamic SQL แล้วเกิดอะไรขึ้น จะแก้อย่างไร?</b></summary>
Dynamic SQL ไม่ผูกเข้ากับโครงสร้าง proc ตอน compile ทำให้ ownership chaining ไม่ทำงาน — SQL Server ประเมินสิทธิ์ใหม่ทั้งหมดใน context ของผู้เรียก วิธีแก้มี 2 ทางหลักคือ <code>EXECUTE AS</code> (สวมสิทธิ์) และ certificate signing (ADD SIGNATURE) ซึ่งเป็น best practice เพราะควบคุมสิทธิ์ได้เฉพาะ object ไม่กระทบ session ทั้งหมด — อ่านละเอียด: [Section 2](Sections/02_Code_Permissions/README.md)
</details>

<details>
<summary><b>5. การ GRANT ที่ระดับ SCHEMA:: ต่างจาก GRANT ทีละ object อย่างไร และ user เกิดมี DEFAULT_SCHEMA ทำไม?</b></summary>
GRANT ที่ระดับ schema ครอบคลุม **ทุก object ปัจจุบันและอนาคต** ใน schema นั้นในคำสั่งเดียว ต่างจาก object-level grant ที่ต้องรันใหม่ทุกครั้งที่สร้าง object ใหม่ ส่วน DEFAULT_SCHEMA คือ schema ที่ SQL Server จะหยิบมาเติมให้อัตโนมัติเมื่อ user อ้างชื่อแบบ 1-part name (เช่น <code>SELECT * FROM Employees</code>) ช่วยลดปัญหาตารางหลุดไปคนละ schema ตามตัวอักษรของชื่อ user — อ่านละเอียด: [Section 3](Sections/03_Schema_Permissions/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)

- **Security cache improvements**: เมื่อ permission เปลี่ยน (GRANT/DENY/REVOKE) SQL Server 2025 invalidate security cache เฉพาะของ **login ที่ได้รับผลกระทบ** เท่านั้น ทำให้การอนุญาต/เรียกคืนสิทธิ์รายใหญ่ ๆ กระทบ performance ของ user คนอื่นน้อยลงมาก ([Security cache](https://learn.microsoft.com/sql/relational-databases/security-cache?view=sql-server-ver17))
- **RLS + Dynamic Data Masking** ยังเป็นมาตรฐานเหมือนเดิม ทำงานได้ปกติบน SQL Server 2025 ทั้งคู่
- **Ledger (SQL Server 2022+)** เป็นตัวเลือก tamper-evident เสริม เก็บหลักฐานเข้ารหัสว่าข้อมูลถูกแก้อย่างไร — คนละงานกับ permission แต่เสริมความน่าเชื่อถือเรื่อง audit ([Ledger overview](https://learn.microsoft.com/sql/relational-databases/security/ledger/ledger-overview?view=sql-server-ver17))
- Permission system โดยรวมไม่เปลี่ยนโครงสร้างจากรุ่น 2019 — สคริปต์ GRANT/DENY เดิมยังรันได้ แต่อาจได้ performance ที่ดีขึ้นจาก security cache ใหม่

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Row-Level Security](https://learn.microsoft.com/sql/relational-databases/security/row-level-security?view=sql-server-ver17), [Ownership chains](https://learn.microsoft.com/sql/relational-databases/security/ownership-chains?view=sql-server-ver17)
