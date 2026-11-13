# Module 13 — ติดตามค่าประสิทธิภาพ SQL Server (Performance Monitoring)

DBA ที่ดีไม่ได้ "รอให้ระบบล่มแล้วค่อยแก้" แต่ทำให้ระบบไม่ล่มตั้งแต่แรกด้วยการ**ติดตามและวัดค่าประสิทธิภาพอย่างเป็นระบบ** โมดูลนี้สอนการใช้ชุดเครื่องมือมาตรฐานของ SQL Server ในการมองเห็นสิ่งที่เกิดขึ้นข้างใน engine แบบเรียลไทม์ (DMVs, Activity Monitor, Windows Performance Monitor) ตลอดจนวิธีจับ blocking ที่เกิดขึ้นจริงและหาตัวการได้ภายในไม่กี่นาที

เนื่องจาก Module 12 คุณเรียนการ audit และดูเหตุการณ์ย้อนหลัง (Extended Events) แล้ว โมดูลนี้จะเน้น **ภาพสด (live view)** ของ instance: ใครกำลังรันอะไร ใคร block ใคร resource ไหนตึงมือ และจะเก็บค่าเหล่านี้เป็น **baseline** ไว้เทียบวันเกิดเหตุได้อย่างไร — หัวใจของการบริหาร capacity และ performance troubleshooting ระยะยาว

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – มองเห็นกิจกรรมปัจจุบัน**: ใช้ `sys.dm_exec_requests` / `sys.dm_exec_sessions` / `sys.dm_exec_connections` และ Activity Monitor เห็นว่าขณะนี้มี session ใดรันคำสั่งใดอยู่
- **ระดับ 2 – วินิจฉัยปัญหาเรียลไทม์**: จับ blocking จาก `blocking_session_id` อ่าน wait types จาก `sys.dm_os_wait_stats` และเทียบ SQL Server counters ผ่าน Performance Monitor ได้
- **ระดับ 3 – เก็บ baseline เชิงปฏิบัติ**: สร้างตาราง snapshot DMV + `sys.dm_os_performance_counters` ใน database แยก (`DBA_Baseline`) พร้อมตีความผลต่างระหว่างช่วงเวลา
- **ระดับ 4 – ออกแบบระบบติดตามระยะยาว**: ประเมิน Data Collector/Management Data Warehouse ในฐานะ legacy tool เลือกทางสมัยใหม่ (Query Store, DMV baseline script, Azure Arc assessments + Power BI) ให้เหมาะกับองค์กร

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [ติดตามกิจกรรม SQL Server (DMVs, Activity Monitor, PerfMon, Blocking)](Sections/01_Monitoring_Activity/README.md) |
| 2 | [การเก็บข้อมูลและสร้าง Baseline (Data Collector + วิธีสมัยใหม่)](Sections/02_Data_Collection_Baseline/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. ความแตกต่างระหว่าง sys.dm_exec_requests กับ sys.dm_exec_sessions คืออะไร และคอลัมน์ใช้กรอง "ผู้ใช้จริง" อย่างไร?</b></summary>

`sys.dm_exec_sessions` มอง **ทุก session ที่เชื่อมต่อ** (รวม session ภายในของระบบ) ส่วน `sys.dm_exec_requests` มองเฉพาะ **request ที่กำลังรันอยู่ ณ ขณะนั้น** จึง join กันด้วย `session_id` เพื่อได้ทั้งบริบทผู้ใช้ (login, program) และสถานะการรัน (command, wait_type) ในครั้งเดียว ใช้คอลัมน์ `is_user_process = 1` กรอง session ของระบบออก:

```sql
SELECT s.original_login_name, s.program_name, r.command,
       r.wait_type, r.wait_time, r.blocking_session_id
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
WHERE s.is_user_process = 1;
```
— อ่านละเอียด: [Section 1](Sections/01_Monitoring_Activity/README.md)
</details>

<details>
<summary><b>2. เห็น sys.dm_exec_requests แถวหนึ่งมี blocking_session_id = 55 จะหา "ตัวการ" ต่ออย่างไร?</b></summary>

ดู session 55 ว่ากำลังรันคำสั่งใดและรออะไรอยู่ ด้วย `OUTER APPLY sys.dm_exec_sql_text(r.sql_handle)` ดึงข้อความ batch ของ session นั้นมาดู แล้วตัดสินใจว่าจะรอ (request มีเหตุผล) หรือแก้ต้นทาง (transaction ลืม COMMIT) การ KILL ใช้ได้เมื่อมีสิทธิ์ `sysadmin` หรือ `processadmin` เท่านั้น
— อ่านละเอียด: [Section 1](Sections/01_Monitoring_Activity/README.md)
</details>

<details>
<summary><b>3. ทำไมค่า Page Life Expectancy ต่ำกว่า 300 วินาทีอย่างเดียวไม่พอจะสรุปว่า "RAM ไม่พอ"?</b></summary>

PLE เป็นค่า point-in-time ที่แกว่งตาม nature ของ workload (เช่น scan ตารางใหญ่ครั้งเดียวก็ทำให้ PLE ดิ่ง) จึงต้องดูเป็น **แนวโน้มเทียบกับ baseline** ของระบบตัวเอง ไม่ใช่ค่า threshold เดียวกันทุกเซิร์ฟเวอร์ วิธีที่ดีกว่าคือเก็บ PLE ตาม NUMA node (`sys.dm_os_performance_counters` instance = node) ร่วมกับ Page Reads/sec และ Memory Grants Pending
— อ่านละเอียด: [Section 1](Sections/01_Monitoring_Activity/README.md)
</details>

<details>
<summary><b>4. SQL Server Data Collector ยังควรใช้เป็นทางเลือกหลักใน SQL Server 2025 หรือไม่? เพราะอะไร?</b></summary>

ไม่ควร — Data Collector/Management Data Warehouse ถือเป็น **legacy** ในโลกปัจจุบัน เครื่องมือสมัยใหม่ทดแทนได้ดีกว่า: **Query Store** (เก็บ plan/runtime stats ต่อ query ในตัวฐานข้อมูลเอง), **DMV baseline script** (สคริปต์ snapshot เข้าตารางของเรา ควบคุมได้เต็มที่) และ **Azure Arc-enabled SQL Server + SQL assessments/Power BI** สำหรับติดตามหลายเซิร์ฟเวอร์ แต่ถ้าองค์กรยังรัน Data Collector อยู่ก็ยังทำงานได้ ควรเข้าใจโครงสร้าง (collection sets, dc_* roles, MDW) เพื่อดูแลระบบเดิม
— อ่านละเอียด: [Section 2](Sections/02_Data_Collection_Baseline/README.md)
</details>

<details>
<summary><b>5. DBA ปกติ (ไม่ใช่ sysadmin) ต้องได้สิทธิ์แบบไหนจึงจะอ่าน DMVs เพื่อ monitoring ได้อย่าง least privilege?</b></summary>

ตั้งแต่ SQL Server 2022 ใช้ fixed server roles ใหม่แทนการให้ sysadmin: `##MS_ServerPerformanceStateReader##` (อ่าน DMV ด้าน performance ผ่าน `VIEW SERVER PERFORMANCE STATE`) หรือ `##MS_ServerStateReader##` (อ่าน DMV ทั้งหมดผ่าน `VIEW SERVER STATE`) ทั้งสอง role ยังให้สิทธิ์ `VIEW DATABASE PERFORMANCE/STATE` ใน database ที่ user มีบัญชีด้วย
— อ่านละเอียด: [Section 1](Sections/01_Monitoring_Activity/README.md)
</details>

<details>
<summary><b>6. ตัวชี้วัด Log Growths ควรอยู่ที่ค่าเท่าไร และถ้าเกิดบ่อยแปลว่าอะไร?</b></summary>

ในระบบที่จัดการขนาด log ถูกต้อง การเติบโตอัตโนมัติของ log ระหว่างวันควรเป็น **ศูนย์หรือเกือบศูนย์** — เพราะการ grow log ทำให้ transactions ค้างรอ (instant file initialization ไม่ช่วย log file) และ VLF กระจัดกระจาย ถ้า Log Growths เกิดบ่อย แปลว่าขนาด/การเติบโตของ log ตั้งไว้เล็กเกินไปเมื่อเทียบกับ workload — ควรขยาย log ล่วงหน้าแบบ manual ในเวลา maintenance
— อ่านละเอียด: [Section 1](Sections/01_Monitoring_Activity/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **SQL Trace + SQL Server Profiler deprecated** — ติดตามเหตุการณ์ให้ใช้ Extended Events (XEvent Profiler ใน SSMS) เป็นทางการ
- **Query Store for readable secondaries** มาถึง SQL Server 2025 (ก่อนหน้า preview ใน 2022 ผ่าน trace flag) — เห็นสถิติ query ที่รันบน secondary replica ด้วย; SSMS 21 Query Store reports มี dropdown เลือก Replica
- **Fixed server roles แบบ least-privilege** (SQL Server 2022+) เช่น `##MS_ServerPerformanceStateReader##`, `##MS_ServerStateReader##` แทนการให้ sysadmin เพื่ออ่าน DMV
- **tempdb space resource governance** (2025) — จำกัด tempdb ต่อ resource group ได้ ช่วยหน่วง query ที่กิน tempdb มากเกิน
- **Optimized Locking** (2025) ลด blocking/lock memory (LAQ) — blocking ยังต้องวินิจฉัยด้วย DMV เหมือนเดิมแต่เบาลง
- **Time-bound Extended Events sessions** (2025) — session XE หยุดเองตามเวลา กัน session ทิ้งไว้กิน resource

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Performance monitoring and tuning tools](https://learn.microsoft.com/sql/relational-databases/performance/performance-monitoring-and-tuning-tools?view=sql-server-ver17), [Query Store for secondary replicas](https://learn.microsoft.com/sql/relational-databases/performance/query-store-for-secondary-replicas?view=sql-server-ver17), [Server-level roles](https://learn.microsoft.com/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17)
