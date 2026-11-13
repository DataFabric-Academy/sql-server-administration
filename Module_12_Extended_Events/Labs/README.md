# Lab 12: ติดตามเหตุการณ์ SQL Server ด้วย Extended Events (บทที่ 12)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab12** (Monitoring SQL Server with Extended Events) + [Microsoft Learn — Extended Events](https://learn.microsoft.com/sql/relational-databases/extended-events/extended-events?view=sql-server-ver17), [system_health session](https://learn.microsoft.com/sql/relational-databases/extended-events/use-the-system-health-session?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว

## Prerequisites
- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้ ยกเว้น Step time-bound ใน Exercise 1 เป็นฟีเจอร์ 2025), database **AdventureWorks2025** restore เรียบร้อย
- SSMS เปิดได้ **2 หน้าต่าง query พร้อมกัน** (สำหรับจำลอง deadlock ใน Exercise 3)
- สิทธิ์ `CREATE ANY EVENT SESSION` / `ALTER ANY EVENT SESSION` (sysadmin บน instance ทดลองผ่านหมด)
- โฟลเดอร์เก็บไฟล์ .xel ให้ SQL Server service เขียนได้:
  ```powershell
  New-Item -Path C:\SQLBackups\XE -ItemType Directory -Force
  ```
- ตรวจ path ก่อนเริ่ม: สคริปต์ในแล็บใช้ `C:\SQLBackups\XE\` — ถ้าแก้ path ให้แก้ให้ครบในทุกไฟล์

## Scenario
ระบบขายหน้าร้านบน AdventureWorks2025 มีอาการสองแบบที่คุณยังหาสาเหตุไม่ได้: (1) ทุกเช้ามี deadlock กระโดดขึ้นมาใน error log แต่ทีม dev บอกว่า "โค้ดเราทำ deadlock ไม่ได้" (2) บางคืนมี query กินเวลาหลายวินาทีโดยที่ Activity Monitor ก็ไม่จำอะไรไว้ คุณจึงออกแบบระบบเก็บ **หลักฐานระดับเหตุการณ์** ด้วย Extended Events — เริ่มจาก session จับ query ช้า, ทำ wait analysis ต่อ session ระหว่าง workload, ดึง deadlock ย้อนหลังจาก system_health และตาม page splits ที่ index สร้างใหม่ของทีม dev อาจทำขึ้น

## Objectives
1. สร้าง session จับ long-running queries ด้วย event_file + ring_buffer แล้ว parse ผลจากทั้งสอง target
2. รัน workload จำลอง + ตาม waits ต่อ session ด้วย event `sqlserver.wait_info`
3. ดึง deadlock graph ย้อนหลังจาก session `system_health` (จำลอง deadlock จริงด้วยสอง session)
4. สร้าง session ตาม page splits ด้วย `transaction_log` + histogram target แล้วรายงานต่อ index
5. ทำ Clean-up: DROP EVENT SESSION ทุกตัวในตอนจบ

---

## Exercise 1: จับ Long-running Queries (event_file + ring_buffer)

### Step 1 — สร้างและเริ่ม session

รันไฟล์ [`../Sections/02_XE_Sessions/Scripts/01_Long_Query_Session.sql`](../Sections/02_XE_Sessions/Scripts/01_Long_Query_Session.sql) ถึง **Task 3** (หลัง `STATE = START`) — session จับ `sql_batch_completed`/`rpc_completed` ที่ `duration > 5000000` (5 วินาที หน่วยไมโครวินาที) เก็บลง event_file + ring_buffer

> **ต้องรู้ก่อน**: `duration` เป็น **ไมโครวินาที** — 5 วินาที = 5,000,000 กรองที่ predicate ก่อนเก็บคือหลักทำให้ session เบา รายละเอียดทุกองค์ประกอบ: [Section 2](../Sections/02_XE_Sessions/README.md)

✅ **สังเกต**: หลัง CREATE — session อยู่ใน `sys.server_event_sessions` (metadata) แต่ยังไม่อยู่ใน `sys.dm_xe_sessions` จนกว่าจะ START

### Step 2 — ยิง workload ที่ช้าเกินเกณฑ์

สคริปต์ Task 4 ยิงให้แล้ว (batch มี `WAITFOR DELAY '00:00:06'` + proc `dbo.uspLongQueryDemo` ที่ช้า 6 วินาที) — รันต่อถ้ายังไม่ได้รัน

### Step 3 — อ่านผลจาก ring_buffer (สด)

รัน **Task 5** ของสคริปต์เดิม — shred XML ผ่าน `sys.dm_xe_session_targets`:

```sql
WITH xe AS (
    SELECT CAST(st.target_data AS XML) AS xe_data
    FROM sys.dm_xe_session_targets AS st
    JOIN sys.dm_xe_sessions AS s ON st.event_session_address = s.address
    WHERE s.name = N'LongQueries' AND st.target_name = 'ring_buffer'
)
SELECT TOP (20)
       x.xe_xml.value('(@name)[1]', 'nvarchar(60)')                AS event_name,
       x.xe_xml.value('(data[@name="duration"]/value)[1]', 'bigint') / 1000.0 AS duration_ms,
       x.xe_xml.value('(action[@name="session_id"]/value)[1]', 'int') AS session_id,
       x.xe_xml.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM xe
CROSS APPLY xe_data.nodes('RingBufferTarget/event') AS x(xe_xml)
ORDER BY event_time;
```

**Expected:** เห็น event อย่างน้อย 2 แถว (batch + RPC) duration_ms ≈ 6,000 พร้อมข้อความ T-SQL — ถ้ายังว่าง ให้รอ `MAX_DISPATCH_LATENCY` (10 วินาที) แล้วรันซ้ำ

### Step 4 — อ่านผลจาก event_file (ถาวร)

รันไฟล์ [`../Sections/02_XE_Sessions/Scripts/02_Parse_File_Target.sql`](../Sections/02_XE_Sessions/Scripts/02_Parse_File_Target.sql) ทีละ Task — อ่าน `LongQueries*.xel` ด้วย `sys.fn_xe_file_target_read_file` แล้ว shred เป็นรายงาน top statement (Task 2-3)

**Expected:** ข้อมูลชุดเดียวกับ ring_buffer แต่อยู่ในไฟล์ .xel — เก็บไว้วิเคราะห์ย้อนหลังได้เสมอ

### Step 5 — (SQL Server 2025) ทดลอง time-bound session

รันไฟล์ [`../Sections/02_XE_Sessions/Scripts/06_Time_Bound_Session.sql`](../Sections/02_XE_Sessions/Scripts/06_Time_Bound_Session.sql) ทีละ Task — สร้าง session พร้อม `WITH (MAX_DURATION = 5 MINUTES)` เริ่มรัน ยิง query ช้า แล้วรอให้ session **หยุดเองเมื่อครบเวลา** (Task 4 มี `WAITFOR DELAY '00:05:10'` คอมเมนต์ไว้ — รันแล้วรอ) จากนั้นยืนยันว่า session หายจาก `sys.dm_xe_sessions` แต่ยังอยู่ใน `sys.server_event_sessions` พร้อม `max_duration = 300`

**Expected:** session หยุดเองโดยไม่มีใครสั่ง — นี่คือวินัยแบบอัตโนมัติที่มาใน SQL Server 2025

### Step 6 — หยุด/ลบ session ทดลอง

สคริปต์ Task 7 ของ 01 ลบให้แล้ว (STOP + DROP + ลบ proc ทดลอง) — ตรวจว่าไม่เหลือ:

```sql
SELECT name FROM sys.dm_xe_sessions;
SELECT name FROM sys.server_event_sessions
WHERE name IN (N'LongQueries', N'LongQueriesTimeBound');
```

---

## Exercise 2: จำลอง Workload + ตาม Waits ต่อ Session

### Step 1 — เริ่ม session WaitsBySession

รัน [`../Sections/02_XE_Sessions/Scripts/03_Track_Waits_By_Session.sql`](../Sections/02_XE_Sessions/Scripts/03_Track_Waits_By_Session.sql) ถึง **Task 2** (หลัง START) — session จับ `sqlserver.wait_info` เฉพาะ wait นานกว่า 10 ms เก็บลง event_file

> **ต้องรู้ก่อน**: `wait_info` เกิด "ต่อการรอหนึ่งครั้งเมื่อจบ" มี field `duration`, `signal_duration` และ `wait_type` (map type — อ่านค่าผ่าน node `/text`) ต่างจาก `sys.dm_os_wait_stats` ที่เป็นค่าสะสมทั้ง instance

### Step 2 — เปิด workload ไปพร้อมกัน

รัน [`../Sections/02_XE_Sessions/Scripts/07_Workload_Generator.sql`](../Sections/02_XE_Sessions/Scripts/07_Workload_Generator.sql) จาก**หน้าต่างที่ 2** — วน query รายงานหนัก + insert key สุ่มทุกวินาที (หยุดภายหลังด้วย `CREATE TABLE ##stopload (id int);` จากหน้าต่างใหม่)

### Step 3 — เก็บ waits 1-2 นาที แล้วสรุปต่อ session

ในหน้าต่างแรก รัน **Task 4** ของสคริปต์ 03 (aggregate ต่อ `session_id` + `wait_type`) — ควรเห็น workload ของหน้าต่างที่ 2 รายงาน wait เช่น `SOS_SCHEDULER_YIELD` (รอ CPU) / `PAGEIOLATCH_SH` (อ่าน disk) โดยมี session_id ของ workload เอง

**Expected:** รายงานแบบ "session ไหน รออะไร รวมกี่มิลลิวินาที" แทนค่าสะสมของ DMV — เทียบกับ Module 13 ให้เห็นภาพว่า XE ตอบคำถาม "ช่วงเวลานี้ใครกินรอ" ได้ตรงกว่า

### Step 4 — หยุด workload และ session

```sql
CREATE TABLE ##stopload (id int);          -- จากหน้าต่างอื่น: หยุด workload
-- แล้วรัน Task 6 ของสคริปต์ 03: STOP + DROP EVENT SESSION WaitsBySession
```

---

## Exercise 3: system_health — ดึง Deadlock เก่า

### Step 1 — ตรวจ system_health และอ่านย้อน

รัน [`../Sections/02_XE_Sessions/Scripts/04_System_Health_Deadlocks.sql`](../Sections/02_XE_Sessions/Scripts/04_System_Health_Deadlocks.sql) **Task 1-2** — ยืนยัน session กำลังรันและอ่าน event ล่าสุดจาก `system_health*.xel` (relative path resolve ที่โฟลเดอร์ LOG ของ instance)

> **ต้องรู้ก่อน**: `system_health` เปิดอัตโนมัติ (STARTUP_STATE=ON) เก็บ error severity ≥ 20, deadlock graph, latch wait > 15 วินาที ฯลฯ — เป็น "กล่องดำ" ที่ไปหาก่อนเสมอเวลาเกิดเหตุ

### Step 2 — จำลอง deadlock จริงด้วยสองหน้าต่าง

เตรียมตาราง (รันจากหน้าต่างใดก็ได้):

```sql
USE AdventureWorks2025;
GO
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
GO
IF OBJECT_ID('Lab.DeadlockA', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.DeadlockA (Id int PRIMARY KEY, Val int NOT NULL);
    INSERT Lab.DeadlockA VALUES (1, 0);
END
IF OBJECT_ID('Lab.DeadlockB', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.DeadlockB (Id int PRIMARY KEY, Val int NOT NULL);
    INSERT Lab.DeadlockB VALUES (1, 0);
END
GO
```

**หน้าต่าง A:**

```sql
BEGIN TRAN;
UPDATE Lab.DeadlockA SET Val = 1 WHERE Id = 1;
-- อย่า COMMIT ยัง — ไปทำหน้าต่าง B ก่อน
```

**หน้าต่าง B:**

```sql
BEGIN TRAN;
UPDATE Lab.DeadlockB SET Val = 1 WHERE Id = 1;
UPDATE Lab.DeadlockA SET Val = 2 WHERE Id = 1;   -- รอ lock ของ A
```

**กลับหน้าต่าง A:**

```sql
UPDATE Lab.DeadlockB SET Val = 2 WHERE Id = 1;   -- วงจรปิด -> DEADLOCK
```

**Expected:** หน้าต่างใดหน้าต่างหนึ่งได้ error หมายเลข 1205 ("Transaction (Process ID ...) was deadlocked ... Rerun the transaction") — SQL Server เลือก victim แล้ว rollback ให้เอง

✅ **สังเกต**: session ที่รอดชีวิตให้ `COMMIT;` ปิด transaction ทิ้งให้เรียบร้อย

### Step 3 — ดึง deadlock graph ที่เกิดขึ้นเมื่อกี้

รัน **Task 3-4** ของสคริปต์ 04 — กรอง `xml_deadlock_report` เรียงเวลา แล้วแยก victim/process-list/resource-list:

```sql
SELECT x.c.value('(@timestamp)[1]', 'datetime2(3)') AS event_time,
       x.c.query('.') AS deadlock_graph
FROM (
    SELECT CAST(event_data AS XML) AS xe_xml
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
) AS raw
CROSS APPLY raw.xe_xml.nodes('/event') AS x(c)
WHERE x.c.value('(@name)[1]', 'varchar(100)') = 'xml_deadlock_report'
ORDER BY event_time;
```

**Expected:** มี event ใหม่เมื่อไม่กี่นาทีที่ผ่านมา คลิก XML อ่านว่า process ไหนถือ lock อะไร ใครเป็น victim และ resource ชนกันที่ key ไหน — นี่คือหลักฐานที่คุณจะยื่นให้ทีม dev พร้อมชื่อ statement ของทั้งสองฝั่ง

### Step 4 — เคลียร์ตารางทดลอง (จะทำรวมใน Clean-up)

---

## Exercise 4: ตาม Page Splits ด้วย Histogram

### Step 1 — สร้าง session TrackPageSplits

รัน [`../Sections/02_XE_Sessions/Scripts/05_Page_Splits_Histogram.sql`](../Sections/02_XE_Sessions/Scripts/05_Page_Splits_Histogram.sql) **Task 1** — session จับ `sqlserver.transaction_log` กรอง `operation = N'LOP_DELETE_SPLIT'` (mid-page split) ของ database AdventureWorks2025 นับผ่าน **histogram** ต่อ `alloc_unit_id`

> **ต้องรู้ก่อน**: ไม่มี event ชื่อ "page_splits" ใน XE — split แบบกลางหน้าปรากฏใน transaction log เป็น operation `LOP_DELETE_SPLIT` (แถวถูกย้ายออกจาก page เดิมไปหน้าใหม่ที่ครึ่งกลางของ index) split ท้าย page (append) ไม่ก่อ fragmentation จึงไม่สน

### Step 2 — เริ่ม session แล้วยิง workload (แทรก key สุ่ม)

สคริปต์ **Task 2-3** เตรียมตาราง `Lab.SplitDemo` (index `IX_SplitDemo_RandomKey`) และแทรก key สุ่ม ~10,000 แถว 2 ชุด — รันต่อจนจบ (หรือใช้ workload ต่อเนื่องจาก Exercise 2 ร่วมกันได้)

### Step 3 — อ่าน histogram แล้วตบแต่งเป็นรายงานต่อ index

รัน **Task 4-6** ของสคริปต์ 05 — Task 6 join `sys.allocation_units`/`sys.partitions`/`sys.indexes`:

**Expected:** `IX_SplitDemo_RandomKey` อยู่อันดับหนึ่งด้วยจำนวน splits หลายพัน — รูปแบบเดียวกันนี้ใช้กับ index จริงบน production เพื่อหา "index ไหนถูก split บ่อย" แล้วแก้ด้วย FILLFACTOR/key design

### Step 4 — หยุด/ลบ session

สคริปต์ **Task 7** ทำ STOP + DROP และลบ `Lab.SplitDemo` ให้แล้ว

---

## 🧹 Clean-up

รันทั้งหมดเมื่อจบแล็บ (อย่าปล่อย session ค้างบน instance ที่ใช้ร่วมกัน):

```sql
-- 1) XE sessions ที่แล็บสร้าง (idempotent)
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'LongQueries')
    DROP EVENT SESSION [LongQueries] ON SERVER;
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'LongQueriesTimeBound')
    DROP EVENT SESSION [LongQueriesTimeBound] ON SERVER;
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'WaitsBySession')
    DROP EVENT SESSION [WaitsBySession] ON SERVER;
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'TrackPageSplits')
    DROP EVENT SESSION [TrackPageSplits] ON SERVER;
GO

-- 2) proc + ตารางทดลองใน AdventureWorks2025
USE AdventureWorks2025;
GO
DROP PROCEDURE IF EXISTS dbo.uspLongQueryDemo;
DROP TABLE IF EXISTS Lab.SplitDemo;
DROP TABLE IF EXISTS Lab.DeadlockA;
DROP TABLE IF EXISTS Lab.DeadlockB;
GO

-- 3) สัญญาณหยุด workload (ถ้ายังค้าง)
CREATE TABLE ##stopload (id int);   -- ลูปจะเห็นและจบเอง
-- รอ 2 วินาทีแล้วลบสัญญาณทิ้ง
DROP TABLE IF EXISTS ##stopload;

-- 4) ไฟล์ .xel (ตัดสินใจเก็บเป็นหลักฐานหรือไม่)
-- PowerShell: Remove-Item C:\SQLBackups\XE\*.xel
```

> ตรวจสุดท้าย: `SELECT name FROM sys.dm_xe_sessions;` ควรเหลือเฉพาะ session ระบบ (`system_health` ฯลฯ) — **อย่า DROP system_health**

## Quiz ท้ายแล็บ

1. เหตุใดจึงตั้งเกณฑ์ `duration > 5000000` แล้วไม่ `> 5` — หน่วยของ duration ใน XE คืออะไร?
2. จาก Exercise 1: ring_buffer กับ event_file ให้ข้อมูลต่างกันอย่างไร และถ้า STOP session ตอนนี้ของใน target ใดจะหาย?
3. จาก Exercise 3: จาก deadlock graph ที่ได้ — process ไหนเป็น victim และเหตุผลเชิงเทคนิคที่ SQL Server เลือกตัวนั้นมักเป็นเพราะอะไร?
4. จาก Exercise 4: เหตุใดจึงกรอง `operation = N'LOP_DELETE_SPLIT'` แทนการจับ `lock_acquired` ทั้งหมด?
5. หลังเกิดเหตุ production จริง คุณจะเลือกกลยุทธ์ session อย่างไรระหว่าง (ก) STARTUP_STATE=ON ตลอดไป (ข) session เฉพาะกิจแบบ time-bound (2025) — ข้อดีข้อเสียแต่ละทาง?
