# Module 04 — ปกป้องข้อมูลด้วยการเข้ารหัสและการ Audit (Protecting Data with Encryption and Auditing)

Module 3 จัดการเรื่อง "ใครทำอะไรได้" (Authorization) แล้ว — แต่มีสองคำถามที่ permission ไม่ตอบ: **"มีใครทำอะไรไปแล้วจริง ๆ?"** (Audit) และ **"ถ้าไฟล์/backup/คอลัมน์หลุดมือใคร ข้อมูลจะรั่วไหม?"** (Encryption) โมดูลนี้ตอบทั้งสองเรื่องซึ่งมักถูกใช้เป็นคู่กันในข้อกำหนด PDPA / ISO 27001 / PCI-DSS: audit หลักฐานว่าเกิดอะไรขึ้น, encryption กันข้อมูลรั่วแม้จะได้ไฟล์ไปครอบ

DBA ที่ทำงานจริงจะเจอทั้งสองเรื่องพร้อมกันเสมอ เช่นเมื่อ audit บอกว่า "user A อ่านคอลัมน์ราคา 500 ครั้ง" แต่ถ้าอยากคุมว่าแม้แต่ DBA เองยังไม่ควรเห็นข้อมูลลูกค้าแบบถอดรหัสได้ นั่นคืองานของ Always Encrypted ใน Section 4

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)

- **ระดับ 1 – เลือกกลไก audit ให้ถูกงาน**: เทียบข้อดีข้อเสียของ trigger, temporal tables, SQL Server Audit, Extended Events และอธิบายได้ว่า SQL Trace ทำอะไรไม่ได้แล้ว (deprecated)
- **ระดับ 2 – สร้างและสืบค้น SQL Server Audit**: สร้าง Server Audit + Specification ทั้งระดับ server และ database และอ่านไฟล์ .sqlaudit ด้วย `sys.fn_get_audit_file`
- **ระดับ 3 – ทำงานกับ TDE**: สร้าง hierarchy (DMK → certificate → DEK), เปิด TDE, ตรวจสถานะ และอธิบายขั้นตอนย้ายฐานข้อมูลที่เข้ารหัสไปเซิร์ฟเวอร์ใหม่
- **ระดับ 4 – เลือกเครื่องมือเข้ารหัสให้ตรงโจทย์**: ตัดสินใจได้ว่า TDE / Always Encrypted / Dynamic Data Masking ตอบโจทย์ความเสี่ยงไหน และรู้ข้อจำกัดสำคัญของแต่ละตัว

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [Audit Options — ทางเลือกกลไกตรวจสอบ](Sections/01_Audit_Options/README.md) |
| 2 | [SQL Server Audit — กลไก audit ทางการ](Sections/02_SQL_Server_Audit/README.md) |
| 3 | [Managing Audit — สืบค้นและแก้ปัญหา audit](Sections/03_Managing_Audit/README.md) |
| 4 | [Encryption — TDE, Always Encrypted, DDM, EKM](Sections/04_Encryption/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. อยากรู้ว่าตารางค่าจ้างถูกแก้โดยใครและแก้เป็นค่าอะไร จะใช้กลไกไหนดีที่สุด?</b></summary>
Temporal Table (system-versioned) เหมาะสุดถ้าโจทย์คือ "ดูข้อมูลเก่าก่อนแก้ + ประวัติทุกเวอร์ชัน" เพราะ history table เก็บแถวเก่าอัตโนมัติและแก้ไม่ได้ ส่วน AFTER trigger เขียน log เองเหมาะเมื่อต้องการรูปแบบ log เฉพาะ (เช่น log เฉพาะคอลัมน์/ผู้ใช้) — อ่านละเอียด: [Section 1](Sections/01_Audit_Options/README.md)
</details>

<details>
<summary><b>2. SQL Trace และ Profiler ยังใช้ได้ไหม?</b></summary>
<b>Deprecated แล้ว</b> — อย่าเริ่มงานใหม่ด้วย SQL Trace (sp_trace_*) ให้ใช้ Extended Events แทน (SSMS มี XEvent Profiler ให้ใช้งานง่าย ๆ) — อ่านละเอียด: [Section 1](Sections/01_Audit_Options/README.md)
</details>

<details>
<summary><b>3. Server Audit, Server Audit Specification และ Database Audit Specification ต่างกันอย่างไร?</b></summary>
<b>Server Audit</b> = ปลายทาง + ตัวรวม (เขียนไฟล์ / Windows log / Security log) ระดับ instance; <b>Server Audit Specification</b> = รายการเหตุการณ์ระดับ server (เช่น FAILED_LOGIN_GROUP) ที่ผูกกับ audit หนึ่ง; <b>Database Audit Specification</b> = รายการเหตุการณ์ระดับ database (เช่น SELECT บนตาราง) ผูกกับ audit เดียวกันได้ — อ่านละเอียด: [Section 2](Sections/02_SQL_Server_Audit/README.md)
</details>

<details>
<summary><b>4. TDE ป้องกันข้อมูลจากภัยแบบไหน และไม่ป้องกันแบบไหน?</b></summary>
ป้องกัน "ขโมยไฟล์" — คนได้ไฟล์ .mdf/.bak ไปแต่ถอดรหัสไม่ได้เพราะต้องมี certificate ใน master ของเครื่องเดิม ไม่ป้องกันผู้ใช้ที่ query ผ่าน SQL Server ได้ตามปกติ (ข้อมูลถอดรหัสแล้วใน memory) และไม่ป้องกัน DBA — อ่านละเอียด: [Section 4](Sections/04_Encryption/README.md)
</details>

<details>
<summary><b>5. ย้ายฐานข้อมูลที่เปิด TDE ไป server ใหม่ ทำอะไรบ้าง?</b></summary>
Backup certificate (พร้อม private key) จาก master ของเครื่องเดิม สร้าง DMK ใน master ใหม่ แล้ว CREATE CERTIFICATE FROM FILE ที่เครื่องใหม่ก่อน restore/attach DB — ไม่มี cert แล้ว restore ไม่ผ่านแน่นอน — อ่านละเอียด: [Section 4](Sections/04_Encryption/README.md) และ [Labs — Exercise 2 บทสรุป](Labs/README.md)
</details>

<details>
<summary><b>6. Dynamic Data Masking ต่างจากการเข้ารหัสจริงตรงไหน?</b></summary>
DDM ปกปิดเฉพาะ "หน้าตา" ข้อมูลต่อ user ที่ไม่มีสิทธิ์ UNMASK — ข้อมูลจริงยังเก็บบน disk เป็น plaintext ดังนั้นใครที่ได้ไฟล์ database โดยตรงยังอ่านได้หมด ถ้าต้องการคุมระดับ "ไฟล์หลุดก็ไม่รั่ว" ให้ใช้ TDE หรือ Always Encrypted — อ่านละเอียด: [Section 4](Sections/04_Encryption/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)

- **SQL Trace / SQL Server Profiler ถูกย้ำว่า deprecated** — งาน monitoring/audit ใช้ **Extended Events** และ XEvent Profiler ใน SSMS ([Deprecated features](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17))
- **EKM กับ Azure Key Vault/HSM ใช้ Managed Identity ได้ (2025)** ผ่าน SQL Server enabled by Azure Arc — ไม่ต้องเก็บ secret ใน SQL Server ([Managed Identity + EKM](https://learn.microsoft.com/sql/sql-server/azure-arc/managed-identity-extensible-key-management?view=sql-server-ver17))
- **OAEP padding สำหรับ RSA certificates/asymmetric keys (2025)** เพิ่มชั้นความปลอดภัยให้การเข้ารหัสด้วย key ([Encryption hierarchy](https://learn.microsoft.com/sql/relational-databases/security/encryption/encryption-hierarchy?view=sql-server-ver17))
- **Ledger (SQL Server 2022+)** เป็น audit แบบ tamper-evident เสริม — พิสูจน์ด้วย cryptographic digest ว่าข้อมูลไม่ถูกแก้ ([Ledger overview](https://learn.microsoft.com/sql/relational-databases/security/ledger/ledger-overview?view=sql-server-ver17))
- **Temporal tables ยังใช้ได้ดี** เป็นกลไก audit ข้อมูลเชิง business คู่กับ SQL Server Audit ที่คุม "เหตุการณ์"

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [SQL Server Audit](https://learn.microsoft.com/sql/relational-databases/security/auditing/sql-server-audit-database-engine?view=sql-server-ver17), [Transparent Data Encryption](https://learn.microsoft.com/sql/relational-databases/security/encryption/transparent-data-encryption?view=sql-server-ver17)
