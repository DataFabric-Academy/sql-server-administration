# Module 08 — การจัดการ SQL Server โดยอัตโนมัติ (Automating SQL Server Management)

โมดูลก่อนหน้า (Module 6–7) คุณได้ทำงาน DBA ด้วยมือ — backup, restore, ตรวจ integrity, จัดการ index ซึ่งครั้งเดียวไม่เป็นไร แต่ทำซ้ำทุกวันทุกคืนแบบพิมพ์เองคือสูตรของ "ลืมทำวันหนึ่ง" และความผิดพลาดจากมนุษย์ โมดูลนี้จะสอนให้ SQL Server ทำงานหน้าที่พวกนั้แทนคุณด้วย **SQL Server Agent** — บริการ scheduler ในตัวที่รัน Jobs ตามเวลา ตอบสนองเหตุการณ์ และรายงานผลการทำงาน

หัวใจของโมดูลคือการเขียน Jobs ด้วย T-SQL ล้วน ๆ (`sp_add_job`, `sp_add_jobstep`, `sp_add_jobschedule`) แทนการคลิกใน SSMS เพราะสคริปต์เก็บใน source control ได้ deploy ซ้ำได้ และแก้ไขได้แบบ batch — เป็นวิธีที่ผู้เชี่ยวชาญใช้จริง ตัวอย่างงานจริงที่จะสร้างคือ backup job, DBCC CHECKDB job และ index maintenance ตามแพตเทิร์นของ Ola Hallengren สุดท้ายเราจะขยายสเกลไปถึง **Multiserver Administration (MSX/TSX)** ที่กระจาย jobs จาก server แม่ไปยัง server ลูกได้ในครั้งเดียว

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)

- **ระดับ 1 – เข้าใจภูมิทัศน์ของ automation**: เลือกเครื่องมือให้ถูกงานได้ (SQL Server Agent / Maintenance Plans / Task Scheduler + PowerShell / เครื่องมือภายนอก) และจัดการ Agent service กับตัวเลือก `Agent XPs` ได้
- **ระดับ 2 – สร้าง Jobs ด้วย T-SQL**: สร้าง job หลาย step หลาย subsystem (T-SQL, CmdExec, PowerShell, SSIS) พร้อม schedule แบบ recurring และ one-off ได้ และแปลง job ที่มีอยู่เป็นสคริปต์ CREATE ได้
- **ระดับ 3 – ดูแลและแก้ปัญหา**: อ่าน job history จาก `msdb.dbo.sysjobhistory`, ปรับ history retention, หาสาเหตุ job ล้ม และตั้ง notification ราย job ให้ operator ได้
- **ระดับ 4 – บริหารหลายเซิร์ฟเวอร์**: อธิบายและสร้างสภาพแวดล้อม Master/Target Server (MSX/TSX) ได้ พร้อมเทียบเคียงกับทางเลือกยุคใหม่ (dbatools, Ansible, Azure Arc)

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [ภาพรวม Automation และ SQL Server Agent](Sections/01_Automation_Overview/README.md) |
| 2 | [Agent Jobs — Steps, Subsystems และ Schedules](Sections/02_Agent_Jobs/README.md) |
| 3 | [การจัดการ Jobs — History, Retention และ Notification](Sections/03_Job_Management/README.md) |
| 4 | [Multiserver Jobs — MSX/TSX และทางเลือกยุคใหม่](Sections/04_Multiserver_Jobs/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. SQL Server Agent, Maintenance Plans และ Windows Task Scheduler ควรใช้ตัวไหนเมื่อไหร่?</b></summary>
SQL Server Agent คือหัวใจหลัก — รัน jobs ได้ทุก subsystem มี history, notification และ multiserver ในตัว Maintenance Plans คือห่อหุ้มของ Agent สำหรับงานง่าย ๆ (backup, shrink, CHECKDB, rebuild) แต่ปรับละเอียดได้จำกัด Task Scheduler + PowerShell เหมาะเมื่องานต้องแตะ OS นอก SQL Server หรือผูกกับสคริปต์ .ps1 อยู่แล้ว งาน maintenance จริงจังผู้เชี่ยวชาญส่วนใหญ่เลือก T-SQL jobs หรือ Ola Hallengren's Maintenance Solution — อ่านละเอียด: [Section 1](Sections/01_Automation_Overview/README.md)
</details>

<details>
<summary><b>2. เปิด SSMS แล้วไม่เห็น SQL Server Agent node หรือ error "SQL Server Agent XPs component is turned off" — แก้อย่างไร?</b></summary>
สองสาเหตุ: (1) บริการ SQL Server Agent ไม่ได้รัน — เปิดผ่าน SQL Server Configuration Manager หรือ `services.msc` และตั้ง start mode เป็น Automatic (2) เมื่อ Agent หยุด engine จะปิด `Agent XPs` อัตโนมัติ ต้องเปิดใหม่ด้วย <code>EXEC sp_configure 'Agent XPs', 1; RECONFIGURE;</code> — อ่านละเอียด: [Section 1](Sections/01_Automation_Overview/README.md)
</details>

<details>
<summary><b>3. ความต่างของ @on_success_action ค่า 1, 2, 3, 4 ใน sp_add_jobstep คืออะไร?</b></summary>
<code>1</code> = จบ job ด้วยสถานะ success, <code>2</code> = จบ job ด้วยสถานะ failure, <code>3</code> = ไป step ถัดไป, <code>4</code> = กระโดดไป step ที่ระบุใน <code>@on_success_step_id</code> — คู่ failure (<code>@on_fail_action</code>) ใช้ค่าชุดเดียวกัน และค่าทั้งสองควรตั้งชัดเจนเสมอเพราะการเข้าใจ flow ผิดเป็นสาเหตุบ่อยที่สุดของ job ที่รันผ่านแต่ไม่ได้ทำงานครบ — อ่านละเอียด: [Section 2](Sections/02_Agent_Jobs/README.md)
</details>

<details>
<summary><b>4. Job รันล้มแต่ View History ดูข้อมูลไม่ครบ / ประวัติหาย — เพราะอะไร?</b></summary>
SQL Server Agent เก็บ job history ใน <code>msdb.dbo.sysjobhistory</code> แบบวนลบของเก่า ค่า default คือ 1,000 แถวรวมทั้ง instance และ 100 แถวต่อ job — job ที่รันถี่ (เช่น log backup ทุก 15 นาที) จะกินโควตาเร็วจน history ของ job อื่นถูกลบ แก้ด้วย <code>msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows = ..., @jobhistory_max_rows_per_job = ...</code> (หรือหน้า Agent Properties → History) — อ่านละเอียด: [Section 3](Sections/03_Job_Management/README.md)
</details>

<details>
<summary><b>5. MSX/TSX ทำงานอย่างไร และเมื่อไหร่ควรเลือกใช้ dbatools/Ansible แทน?</b></summary>
Master Server (MSX) เก็บนิยาม job แล้ว "โพสต์" คำสั่งลงคิว <code>msdb.dbo.sysdownloadlist</code> — Target Server (TSX) poll คิวนี้เป็นระยะ ดึง job มารันและอัปโหลดสถานะกลับ เหมาะกับจำนวน server ไม่มากและ job ชุดเดียวกัน ส่วนเฟลตใหญ่/DevOps pipeline มักเลือก dbatools, Ansible หรือ Azure Arc เพราะทำงานผ่าน source control และ idempotent ได้ดีกว่า — อ่านละเอียด: [Section 4](Sections/04_Multiserver_Jobs/README.md)
</details>

<details>
<summary><b>6. SQL Server 2025 มีอะไรเกี่ยวกับ Agent ที่ต้องรู้บ้าง?</b></summary>
การเชื่อมต่อของ Agent (รวมถึงระหว่าง MSX/TSX) รองรับ TLS 1.3 + TDS 8.0 แบบ strict encryption และตัวเลือก notification แบบ Pager กับ net send กำลังถูกถอดออก — ระบบใหม่ควรใช้ email เท่านั้น (ดู Module 10) — อ่านละเอียด: กล่อง SQL Server 2025 ในแต่ละ Section
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)

- **TLS 1.3 + TDS 8.0** — SQL Server Agent และการเชื่อมต่อ MSX↔TSX รองรับการเข้ารหัสแบบ strict (handshake เข้ารหัสทั้งหมด) ร่วมกับ sqlcmd, bcp, SQL Writer, linked servers
- **Pager / net send notifications กำลังถูกถอด** — ตัวเลือก `@notify_level_netsend` / `@notify_level_page` และหน้าจอที่เกี่ยวข้องจะถูกลบในเวอร์ชันอนาคต ระบบใหม่ใช้ **email เท่านั้น**
- **Maintenance Plans ยังอยู่แต่ไม่ใช่คำตอบสำหรับงานจริงจัง** — แนวปฏิบัติปัจจุบันคือ T-SQL jobs หรือ [Ola Hallengren's Maintenance Solution](https://ola.hallengren.com) (DatabaseBackup / DatabaseIntegrityCheck / IndexOptimize)
- **Multiserver Administration ไม่รองรับบน Azure SQL Managed Instance** — ระบบกระจายงานบน cloud ให้พิจารณา elastic jobs (Azure SQL Database) หรือ automation ภายนอกแทน
- สิ่งแวดล้อมยุคใหม่ (container/Linux) ใช้ Agent ได้ แต่ CmdExec รันผ่าน shell ของ OS และ job history retention ปรับด้วย `mssql-conf` แทนหน้าจอ SSMS

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [SQL Server Agent overview](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent), [Automate management across multiple instances (multiserver administration)](https://learn.microsoft.com/sql/ssms/agent/create-a-multiserver-environment), [Ola Hallengren's Maintenance Solution](https://ola.hallengren.com)
