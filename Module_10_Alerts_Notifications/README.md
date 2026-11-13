# Module 10 — ตอบสนองด้วย Alerts และ Notifications (Responding to Alerts and Notifications)

Automation ใน Module 8–9 ทำให้ SQL Server "ทำงานแทนคุณ" — แต่งานจริงสำเร็จหรือล้ม คุณจะรู้ได้ยังไง? หัวใจของโมดูลนี้คือการปิดวงจร: **error เกิด → ถูกบันทึก → ระบบตรวจจับ → แจ้งคนที่ต้องรู้ โดยไม่ต้องมีใครนั่งเฝ้า** SQL Server จัดการเรื่องนี้ด้วยองค์ประกอบสี่ชิ้นที่ซ้อนกัน: **Error Log** (ข้อความของระบบเอง), **Database Mail** (ช่องทางส่งอีเมลผ่าน SMTP), **Operators** (ผู้รับข้อความ) และ **Alerts** (กติกาว่าเหตุการณ์แบบไหนต้องตอบสนองอย่างไร)

โมดูลนี้คู่กับ Module 8 โดยตรง — job ที่คุณสร้างในแล็บ Lab 8 จะถูกผูก notification เมื่อล้มได้จริงในแล็บ Lab 10 นี้ และเราจะแนะแนวเทียบกับ Azure: บน Azure SQL Database ไม่มี Agent/Alert ของ SQL Server แต่มี **Azure Monitor metric alerts + action groups** รับหน้าที่นี้แทน

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)

- **ระดับ 1 – เข้าใจ Error และ Error Log**: อธิบาย severity levels 0–25, อ่าน SQL Server Error Log ด้วย T-SQL และจัดการการหมุนไฟล์ log ได้
- **ระดับ 2 – Database Mail**: สร้าง Mail Account + Profile + ควบคุมสิทธิ์/retention แล้วส่งอีเมลทดสอบจาก SQL Server ได้
- **ระดับ 3 – Operators & Alerts**: สร้าง operator รับอีเมล, สร้าง alert จาก error number/severity/performance counter และผูก response เป็น job หรือ notification ได้
- **ระดับ 4 – วินิจฉัยและเทียบเคียงระบบ**: แก้ปัญหา "alert ไม่ยิง" ด้วยลำดับตรวจสอบที่ถูกต้อง และออกแบบระบบแจ้งเตือนเทียบเคียงบน Azure SQL Database ด้วย Azure Monitor ได้

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [Errors และ SQL Server Error Log](Sections/01_Errors_ErrorLog/README.md) |
| 2 | [Database Mail — ช่องทางอีเมลของ SQL Server](Sections/02_Database_Mail/README.md) |
| 3 | [Operators และ Alerts](Sections/03_Operators_Alerts/README.md) |
| 4 | [Alerts บน Azure SQL Database — Azure Monitor](Sections/04_Azure_Alerts/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. Alert จะยิงได้ต้องมีเงื่อนไขอะไรเกี่ยวกับ error message บ้าง?</b></summary>
Alert ทำงานโดยดัก error ที่ถูกเขียนลง <b>Windows Application Log</b> — ข้อความจะเข้า log ที่ตรงนั้นเมื่อ: severity 19 ขึ้นไป (จาก sys.messages), <code>RAISERROR ... WITH LOG</code>, ข้อความ custom ที่สร้างด้วย <code>sp_addmessage ... @with_log='TRUE'</code>, หรือ <code>xp_logevent</code> — error severity ต่ำ ๆ ทั่วไปไม่เข้า Application Log จึงไม่ trigger alert เอง — อ่านละเอียด: [Section 1](Sections/01_Errors_ErrorLog/README.md) และ [Section 3](Sections/03_Operators_Alerts/README.md)
</details>

<details>
<summary><b>2. Severity level ไหน "พังหนัก" แค่ไหน — 19, 20, 21 ต่างกันอย่างไร?</b></summary>
<b>19</b> = ความรุนแรงระดับสูง (RAISERROR ได้เฉพาะ sysadmin WITH LOG) <b>20–25</b> = fatal — ยุติ connection ที่เกิดขึ้นทันที; 20–22 เกี่ยวกับ process/connection เดียว, 23–25 กระทบทั้งฐานข้อมูล/เครื่อง และเมื่อใช้ alert ด้วย severity 19–25 มีผลเฉพาะข้อความที่ sysadmin ประกาศ — อ่านละเอียด: [Section 1](Sections/01_Errors_ErrorLog/README.md)
</details>

<details>
<summary><b>3. Database Mail ใช้องค์ประกอบใดบ้าง และ account/profile ต่างกันยังไง?</b></summary>
<b>Account</b> = ข้อมูล SMTP จริง (mail server, ที่อยู่ผู้ส่ง, port, ข้อมูลล็อกอิน) — <b>Profile</b> = กลุ่มของ account ที่จะลองใช้เรียงตามลำดับ failover — user เรียกใช้ผ่าน profile ไม่ผ่าน account โดยตรง โดย profile เป็นได้ทั้งแบบ public (ใช้ได้ทุก user ใน DatabaseMailUserRole) และ private — อ่านละเอียด: [Section 2](Sections/02_Database_Mail/README.md)
</details>

<details>
<summary><b>4. สร้าง alert แล้วมัน "ไม่ยิง" — ตรวจอะไรบ้าง เรียงตามลำดับ?</b></summary>
(1) SQL Server Agent รันอยู่หรือไม่ (alert ทำงานโดย Agent) (2) ข้อความถึง Windows Application Log จริงไหม (WITH LOG / severity 19+ / @with_log) (3) mail profile ของ Agent ตั้งหรือยัง (Agent Properties → Alert System) (4) alert เปิด (@enabled=1) และ @delay_between_responses ไม่ได้รีดยาวเกิน (5) xp_logevent เกิดใน master — alert ที่ระบุ @database_name อื่นจะไม่จับ — อ่านละเอียด: [Section 3](Sections/03_Operators_Alerts/README.md)
</details>

<details>
<summary><b>5. บน Azure SQL Database ทำ Agent alerts ไม่ได้ แล้วทำแจ้งเตือนยังไง?</b></summary>
ใช้ <b>Azure Monitor metric alerts</b> (เฝ้า DTU/CPU/storage/percent log used ฯลฯ) + <b>action groups</b> (ส่งอีเมล/SMS/เรียก webhook/Logic App) — คู่นี้ทำหน้าที่แทน alert+operator ของ SQL Server และตั้งใน Portal หรือ az CLI ได้ไม่กี่บรรทัด — อ่านละเอียด: [Section 4](Sections/04_Azure_Alerts/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)

- **Pager / net send notifications กำลังถูกถอด** — ตัวเลือก pager ของ operator (`@pager_address`, `@netsend_address`) และ `@include_event_description_in` ค่า pager/net send จะถูกลบในเวอร์ชันอนาคต ระบบใหม่ใช้ **email เท่านั้น**
- **TLS 1.3 + TDS 8.0** — SQL Server Agent (ผู้รัน alert engine และส่ง notification) รองรับการเข้ารหัสรุ่นใหม่แบบ strict
- **Database Mail เป็นกลไกเดียวทางการสำหรับอีเมล** — SMTP-based ยังใช้เหมือนเดิมทั้งโครงสร้าง (account/profile/principal) บน SQL Server 2025
- **Azure SQL Database ไม่มี Agent alerts** — ระบบแจ้งเตือนในรุ่น cloud คือ Azure Monitor + action groups (Section 4); Azure SQL Managed Instance มี Agent และ alert แบบ SQL Server เต็มรูป
- **แนวทาง monitoring ยุคใหม่** — error monitoring ในระดับ query/lock ใช้ Extended Events (Module 13) ร่วมกับ alert severity สูง ๆ ของ Agent เป็นเสาหลัก

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [SQL Server Agent alerts](https://learn.microsoft.com/sql/ssms/agent/alerts), [Database Mail](https://learn.microsoft.com/sql/relational-databases/database-mail/database-mail?view=sql-server-ver17), [Azure Monitor alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview)
