# Module 12 — ติดตามการเข้าถึง SQL Server ด้วย Extended Events

เวลาเกิดเหตุบน production — query ช้าลงฉับพลัน, deadlock ทุกเช้า, ผู้ใช้แจ้งว่า "ข้อมูลหาย" — DBA ต้องมี **หลักฐานระดับเหตุการณ์** ไม่ใช่แค่ค่าสะสมของ DMV Extended Events (XE) คือระบบจับเหตุการณ์ที่ฝังอยู่ใน engine ตั้งแต่ SQL Server 2008 เบาเกินกว่าจะกระทบระบบเมื่อตั้งค่าถูก และเป็นเครื่องมือที่ Microsoft รับรองให้ใช้ต่อ ในขณะที่ SQL Server Profiler และ SQL Trace ถูกประกาศ **deprecated** แล้ว — ทุก workflow "เปิด Profiler ดูสิ" ที่เคยใช้ในรุ่นก่อนจึงต้องแปลงเป็น XE session

โมดูลนี้ครอบคลุมทั้งแนวคิด (สถาปัตยกรรม events → predicates → actions → buffers → targets, packages, การแปลค่า map) และการลงมือเขียน `CREATE EVENT SESSION` จริงใน 5 สถานการณ์ที่ใช้บ่อยสุด: จับ query ช้า, wait analysis ต่อ session, ดึง deadlock ย้อนหลังจาก `system_health`, ตาม page splits ด้วย histogram และฟีเจอร์ **time-bound sessions ของ SQL Server 2025** ที่หยุดเองตามเวลาเพื่อกัน session รั่ว — เชื่อมโยงตรงกับงาน DMV baseline ของ Module 13 ที่จะตามมา

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – อ่านแผนที่ XE ได้**: สำรวจ packages/events/actions/targets ด้วย `sys.dm_xe_*` DMVs เลือก event ที่เหมาะกับโจทย์และรู้ว่า Profiler/SQL Trace เป็นของ deprecated
- **ระดับ 2 – เขียน session ได้**: เขียน `CREATE EVENT SESSION` ครบทั้ง predicate, actions, event_file/ring_buffer/histogram targets และตั้ง options (`MAX_MEMORY`, `MAX_DISPATCH_LATENCY`, `STARTUP_STATE`) ได้เอง
- **ระดับ 3 – วิเคราะห์ผลเป็นรายงาน**: shred XML จาก `sys.fn_xe_file_target_read_file` / `sys.dm_xe_session_targets` เป็นตารางวิเคราะห์ (waits ต่อ session, page splits ต่อ index) และดึง deadlock graph จาก `system_health`
- **ระดับ 4 – ใช้ XE ใน production อย่างมีวินัย**: ออกแบบ session ที่กระทบระบบน้อย (กรองที่ predicate), จัดการ lifecycle (START/STOP/DROP), ใช้ time-bound sessions (2025) และเก็บ evidence ย้อนหลังได้

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [แนวคิด Extended Events (XE vs Profiler/SQL Trace, สถาปัตยกรรม, Packages, Events, Targets, Maps)](Sections/01_XE_Concepts/README.md) |
| 2 | [สร้างและใช้งาน XE Sessions (CREATE EVENT SESSION, SSMS UI, system_health, time-bound 2025)](Sections/02_XE_Sessions/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. ทำไม Profiler/SQL Trace จึงไม่ควรใช้กับงานใหม่ และแทนด้วยอะไร?</b></summary>

**SQL Trace + SQL Server Profiler เป็น deprecated** — Microsoft ไม่พัฒนาต่อและจะเอาออกในรุ่นอนาคต; XE ให้ event มากกว่าหลายสิบเท่า กรองได้ลึกกว่า และเบากว่ามาก ตัวแทนที่ "หน้าตาเหมือน Profiler" คือ **XEvent Profiler** ใน SSMS (Management > XEvent Profiler > Launch) ส่วนไฟล์ .trc เก่าอ่านด้วย `fn_trace_gettable` ซึ่ง deprecated ตามไปด้วย — งานใหม่ใช้ .xel + `sys.fn_xe_file_target_read_file`
— อ่านละเอียด: [Section 1](Sections/01_XE_Concepts/README.md)
</details>

<details>
<summary><b>2. ลำดับ pipeline ของ XE คืออะไร และเพราะอะไร predicate จึง "ถูกที่สุด"?</b></summary>

ลำดับคือ **events → predicates → actions → buffers → targets** predicate ประเมินก่อน event ถูกจัดเก็บ ทำให้เหตุการณ์ที่ไม่ผ่านเงื่อนไข "แทบไม่มีค่าใช้จ่าย" ส่วน actions (เช่น `sql_text` ที่ดึงข้อความ batch) เกิดหลังกรองผ่านแล้วเท่านั้น — เขียน predicate ให้กรอง event ถี่ที่สุดออกก่อนคือหลักทำให้ XE เบาบน production
— อ่านละเอียด: [Section 1](Sections/01_XE_Concepts/README.md)
</details>

<details>
<summary><b>3. event_file กับ ring_buffer ควรเลือกเมื่อไร และหนึ่ง session ใช้ทั้งคู่ได้ไหม?</b></summary>

ใช้ทั้งคู่ได้ (target แต่ละชนิดใส่ได้ตัวเดียวต่อ session) `event_file` เก็บถาวรลง disk มี rollover — เหมาะกับการวิเคราะห์ย้อนหลัง/เก็บหลักฐาน; `ring_buffer` อยู่ใน memory หมุนวน — เหมาะมองของสดเร็ว ๆ จาก DMV โดยไม่แตะ disk แต่ข้อมูลเก่าหาย (และตั้ง `max_memory` ≤ 1024 KB ตามคำแนะนำ docs เพื่อกัน XML โต)
— อ่านละเอียด: [Section 1](Sections/01_XE_Concepts/README.md), [Section 2](Sections/02_XE_Sessions/README.md)
</details>

<details>
<summary><b>4. จะจับ query ที่รันเกิน 5 วินาที ต้องเขียน session แบบไหน และหน่วยของ duration คืออะไร?</b></summary>

ใช้ event `sqlserver.sql_batch_completed` + `sqlserver.rpc_completed` พร้อม predicate `WHERE duration > 5000000` — **duration เป็นไมโครวินาที** (5,000,000 µs = 5 วินาที) เก็บลง event_file แล้ว shred ด้วย `data[@name="duration"]/value`:

```sql
ADD EVENT sqlserver.sql_batch_completed (
    ACTION ( sqlserver.sql_text, sqlserver.session_id )
    WHERE duration > 5000000   -- 5 วินาที
)
```
— อ่านละเอียด: [Section 2](Sections/02_XE_Sessions/README.md)
</details>

<details>
<summary><b>5. จะหา "deadlock เกิดเมื่อวานนี้" ได้จากที่ไหนโดยไม่ต้องสร้าง session เอง?</b></summary>

จาก session **`system_health`** ที่เปิดอัตโนมัติและเก็บ `xml_deadlock_report` ทุกการเกิด (รวม error severity ≥ 20, latch wait > 15 วินาที) อ่านย้อนได้:

```sql
SELECT x.c.value('(@timestamp)[1]', 'datetime2(3)') AS event_time,
       x.c.query('.') AS deadlock_graph
FROM ( SELECT CAST(event_data AS XML) AS xe_xml
       FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) ) AS raw
CROSS APPLY raw.xe_xml.nodes('/event') AS x(c)
WHERE x.c.value('(@name)[1]', 'varchar(100)') = 'xml_deadlock_report'
ORDER BY event_time;
```
— อ่านละเอียด: [Section 2](Sections/02_XE_Sessions/README.md)
</details>

<details>
<summary><b>6. Time-bound event sessions คืออะไร ใช้ syntax อย่างไร และใช้ได้ตั้งแต่เวอร์ชันไหน?</b></summary>

ฟีเจอร์ **SQL Server 2025 (17.x)** (มีใน Azure SQL DB/MI มาก่อน) — ระบุ `MAX_DURATION` ใน `WITH(...)` แล้ว session หยุดเองเมื่อครบเวลา กัน session ลืมปิด:

```sql
WITH ( MAX_DURATION = 5 MINUTES, MAX_MEMORY = 4 MB, MAX_DISPATCH_LATENCY = 10 SECONDS )
```
ค่าเก็บเป็น "วินาที" ใน `sys.server_event_sessions.max_duration` (0 = UNLIMITED); หยุดก่อนเวลาได้ด้วย `STATE = STOP`, เริ่มใหม่นับเวลาใหม่ทั้งหมด และแก้ `MAX_DURATION` ได้เฉพาะตอน session หยุด; สูงสุด 24 วัน
— อ่านละเอียด: [Section 2](Sections/02_XE_Sessions/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **SQL Trace + SQL Server Profiler deprecated** — เครื่องมือเหตุการณ์ทางการคือ Extended Events; XEvent Profiler (SSMS 20/21) คือ UI ที่วิ่งบน XE ([Extended Events vs SQL Trace](https://learn.microsoft.com/sql/relational-databases/extended-events/extended-events-related-to-previously-supported-sql-trace-and-sql-server-profiler-classes?view=sql-server-ver17))
- **Time-bound event sessions (2025)** — `WITH (MAX_DURATION = <n> SECONDS|MINUTES|HOURS|DAYS|UNLIMITED)` ให้ session หยุดเอง อ่านย้อนจาก `sys.server_event_sessions.max_duration` ([Extended Events sessions](https://learn.microsoft.com/sql/relational-databases/extended-events/sql-server-extended-events-sessions?view=sql-server-ver17))
- **Permissions แบบ granular (2022+)** — `CREATE ANY EVENT SESSION` / `ALTER ANY EVENT SESSION` + อ่านผลผ่าน `VIEW SERVER PERFORMANCE STATE` แทนการแจก sysadmin ให้คน monitor ([CREATE EVENT SESSION](https://learn.microsoft.com/sql/t-sql/statements/create-event-session-transact-sql?view=sql-server-ver17))
- **`fn_trace_gettable` และ `sp_trace_*` deprecated** — workflow อ่านไฟล์ trace เก่าทั้งหมดเปลี่ยนเป็น .xel + `sys.fn_xe_file_target_read_file`
- **Azure SQL DB: session เป็น `ON DATABASE` เท่านั้น** — โครง metadata เปลี่ยนเป็น `sys.database_event_sessions*` ([Extended Events in Azure SQL](https://learn.microsoft.com/azure/azure-sql/database/xevent-db-diff-from-svr?view=azuresql))
- **`Read-SqlXEvent` ใน SqlServer module** — อ่าน .xel/live session จาก PowerShell โดยตรง เชื่อมกับ Module 11 ([Read-SqlXEvent](https://learn.microsoft.com/powershell/module/sqlserver/read-sqlxevent))

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Extended Events overview](https://learn.microsoft.com/sql/relational-databases/extended-events/extended-events?view=sql-server-ver17), [Extended Events sessions](https://learn.microsoft.com/sql/relational-databases/extended-events/sql-server-extended-events-sessions?view=sql-server-ver17), [system_health session](https://learn.microsoft.com/sql/relational-databases/extended-events/use-the-system-health-session?view=sql-server-ver17)
