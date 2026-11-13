# Lab 13: ติดตามประสิทธิภาพและสร้าง Baseline (บทที่ 13)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab13** (Monitoring SQL Server) + [Microsoft Learn — Activity Monitor](https://learn.microsoft.com/sql/relational-databases/performance-monitor/activity-monitor?view=sql-server-ver17), [sys.dm_os_performance_counters](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-os-performance-counters-transact-sql?view=sql-server-ver17), [Data Collection](https://learn.microsoft.com/sql/relational-databases/data-collection/data-collection?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว

## Prerequisites
- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025** restore เรียบร้อย
- SSMS เปิดได้ **3 หน้าต่าง query พร้อมกัน** (สำหรับ Exercise 1 — ทุกหน้าต่างเชื่อมต่อ instance เดียวกัน)
- สิทธิ์ sysadmin บน instance ทดลอง (Exercise 3 optional ต้องใช้)
- เครื่อง Windows สำหรับเปิด `perfmon` (Exercise 2 optional ส่วน UI)

## Scenario
คุณเป็น DBA ของบริษัทค้าปลีกที่มีแอปขายหน้าร้านวิ่งบน AdventureWorks2025 ช่วงโปรโมชันปลายปี workload หนาขึ้นและมีคำร้องเรื่อง "ระบบกระตุก" เข้ามา แต่ยังไม่มีใครพูดได้ว่าระบบ "ปกติ" เป็นอย่างไร ภารกิจของคุณในแล็บนี้: (1) จำลอง workload + blocking เพื่อฝึกวินิจฉัยแบบสด (2) เก็บ baseline ของ counters ด้วย T-SQL (3) ทดลองเครื่องมือเก็บข้อมูลแบบ legacy หนึ่งครั้งเพื่อให้เข้าใจระบบเก่าที่องค์กรอาจมีอยู่ และ (4) สร้างระบบ baseline สมัยใหม่ของตัวเองใน database `DBA_Baseline`

## Objectives
1. รัน workload จำลอง + blocking สอง session แล้ววิเคราะห์ด้วย `sys.dm_exec_requests`
2. รวบรวม SQL Server counters ผ่าน `sys.dm_os_performance_counters` และสร้าง baseline script
3. (Optional) เปิด Data Collector + ดูรายงานจาก Management Data Warehouse
4. สร้างตาราง DMV snapshot baseline ใน database แยก `DBA_Baseline`

---

## Exercise 1: Workload + การวิเคราะห์ Blocking ด้วย DMVs

### Step 1 — เตรียมตารางทดลอง

> **ต้องรู้ก่อน**: สคริปต์นี้สร้าง schema `Lab` และตาราง `Lab.BlockingDemo` (idempotent) เพื่อไม่ต้องไปล็อกตารางจริงของ AdventureWorks

รันใน **หน้าต่างที่ 1**:

```sql
USE AdventureWorks2025;
GO
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
GO
IF OBJECT_ID('Lab.BlockingDemo', 'U') IS NULL
BEGIN
    CREATE TABLE Lab.BlockingDemo
    (
        Id          int          NOT NULL CONSTRAINT PK_BlockingDemo PRIMARY KEY,
        ProductName nvarchar(50) NOT NULL,
        Balance     int          NOT NULL
    );
    INSERT Lab.BlockingDemo (Id, ProductName, Balance)
    VALUES (1, N'Widget A', 100), (2, N'Gadget B', 50);
END
GO
```

✅ **สังเกต**: รันซ้ำกี่ครั้งก็ไม่ซ้ำข้อมูล (ตรวจ `OBJECT_ID` ก่อน)

### Step 2 — เปิด transaction ค้างไว้ (ผู้ block)

ยังอยู่หน้าต่างที่ 1 รัน (อย่ารัน COMMIT/ROLLBACK ตอนนี้):

```sql
BEGIN TRANSACTION;
UPDATE Lab.BlockingDemo
SET Balance = Balance + 1
WHERE Id = 1;
```

✅ **สังเกต**: `@@SPID` ของหน้าต่างนี้ (ใช้ `SELECT @@SPID;`) — จำไว้เทียบกับภายหลัง

### Step 3 — ทำให้ session อื่นถูก block

รันใน **หน้าต่างที่ 2** — query จะค้าง:

```sql
USE AdventureWorks2025;
SELECT * FROM Lab.BlockingDemo WHERE Id = 1;
```

**Expected:** หน้าต่างที่ 2 ไม่คืนผล — กำลังรอ lock ของ session ที่ 1 (default lock timeout 120 วินาที)

### Step 4 — จับ blocking จากหน้าต่างที่ 3

รันใน **หน้าต่างที่ 3**:

```sql
SELECT r.session_id,
       r.blocking_session_id,
       r.wait_type,          -- LCK_M_S = รอ shared lock
       r.wait_time,          -- มิลลิวินาที
       r.wait_resource,
       s.program_name,
       t.text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;
```

✅ **สังเกต**: `blocking_session_id` = SPID ของหน้าต่างที่ 1

**Expected:** ได้แถวเดียวคือ session ที่ถูก block พร้อมข้อความ query ที่รันค้าง แล้วสอบถาม "ตัวการ" ต่อ (แก้ `55` เป็น blocking_session_id ที่ได้):

```sql
SELECT s.session_id, s.original_login_name, s.program_name,
       c.most_recent_sql_handle
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_exec_connections AS c ON c.session_id = s.session_id
WHERE s.session_id = 55;

-- แปลง handle เป็นข้อความ
SELECT * FROM sys.dm_exec_sql_text(
    (SELECT most_recent_sql_handle FROM sys.dm_exec_connections WHERE session_id = 55));
```

### Step 5 — เปิด Activity Monitor ดูภาพเดียวกันแบบ UI

Right-click ชื่อ server ใน Object Explorer > **Activity Monitor** > แท็บ **Processes** จัดเรียงตามคอลัมน์ **Blocked By** — จะเห็นหน้าต่างที่ 2 รออยู่หลังหน้าต่างที่ 1 (Right-click > Details ดู query ของ blocker)

### Step 6 — รัน workload จำลองเป็นพื้นหลัง (ปรับจาก workload1.sql เดิม)

รันในหน้าต่างใหม่ (จะวน query รายงานทุกวินาทีจนกว่าจะสั่งหยุด):

```sql
USE AdventureWorks2025;
GO
DROP TABLE IF EXISTS ##stopload;
GO
WHILE OBJECT_ID('tempdb..##stopload') IS NULL
BEGIN
    SELECT c.Name AS Category, SUM(d.OrderQty * d.UnitPrice) AS Revenue, COUNT_BIG(*) AS LineItems
    FROM Sales.SalesOrderHeader AS o
    JOIN Sales.SalesOrderDetail AS d ON d.SalesOrderID = o.SalesOrderID
    JOIN Production.Product AS p ON p.ProductID = d.ProductID
    JOIN Production.ProductSubcategory AS sc ON sc.ProductSubcategoryID = p.ProductSubcategoryID
    JOIN Production.ProductCategory AS c ON c.ProductCategoryID = sc.ProductCategoryID
    GROUP BY c.Name
    ORDER BY c.Name;
    WAITFOR DELAY '00:00:01';
END
```

แล้วกลับไปรัน query จับกิจกรรม (Step 4) ซ้ำ — จะเห็น workload วิ่งอยู่ใน `sys.dm_exec_requests`

**หยุด workload**: รัน `CREATE TABLE ##stopload (id int);` จากหน้าต่างอื่น — ลูปจะตรวจเจอและหยุดเอง

### Step 7 — ปลดล็อกและเคลียร์

กลับหน้าต่างที่ 1: `COMMIT;` — หน้าต่างที่ 2 คืนผลทันที

```sql
-- เมื่อจบ Exercise ทั้งหมดของแล็บ:
-- DROP TABLE IF EXISTS Lab.BlockingDemo;
```

---

## Exercise 2: รวบรวม Counters ผ่าน sys.dm_os_performance_counters สร้าง Baseline Script

### Step 1 — เก็บ snapshot ดิบ

> **ต้องรู้ก่อน**: `sys.dm_os_performance_counters` คือ counter ชุดเดียวกับ perfmon แต่อ่านด้วย T-SQL ได้ คอลัมน์ `cntr_type` บอกชนิดค่า (point-in-time / ต่อวินาที / fraction)

```sql
SELECT object_name, counter_name, instance_name, cntr_value, cntr_type
FROM sys.dm_os_performance_counters
ORDER BY object_name, counter_name, instance_name;
```

✅ **สังเกต**: มีมากกว่า 500 แถว — ในทางปฏิบัติคัดเฉพาะที่สนใจ

### Step 2 — วัด Batch Requests/sec จริงด้วยสอง snapshot

```sql
DECLARE @v1 bigint, @t1 datetime2(3) = SYSDATETIME();

SELECT @v1 = cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%SQL Statistics%'
  AND counter_name = N'Batch Requests/sec';

WAITFOR DELAY '00:00:10';

SELECT (c.cntr_value - @v1) / 10.0 AS BatchRequestsPerSec
FROM sys.dm_os_performance_counters AS c
WHERE c.object_name LIKE N'%SQL Statistics%'
  AND c.counter_name = N'Batch Requests/sec';
```

**Expected:** ตัวเลขหลักถึงหลักร้อย — ถ้าเพิ่งรัน workload จาก Exercise 1 ค่าจะสูงกว่าตอน idle ชัดเจน นี่แหละคือ "rate" ที่เราต้องการเก็บเป็น baseline

### Step 3 — อ่าน Buffer cache hit ratio ด้วย base counter

```sql
WITH Raw AS (
    SELECT counter_name, cntr_value
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Buffer Manager%'
      AND counter_name IN (N'Buffer cache hit ratio', N'Buffer cache hit ratio base')
)
SELECT CAST(MAX(CASE WHEN counter_name = N'Buffer cache hit ratio' THEN cntr_value END) AS float)
     / NULLIF(MAX(CASE WHEN counter_name = N'Buffer cache hit ratio base' THEN cntr_value END), 0)
       AS BufferCacheHitRatio
FROM Raw;
```

**Expected:** ค่าใกล้ 1.0 (OLTP ที่ RAM พอ) — ถ้าต่ำกว่า 0.9 ต่อเนื่องให้สงสัย memory pressure

### Step 4 — รัน baseline script ที่เตรียมไว้

รันไฟล์ [`../Sections/01_Monitoring_Activity/Scripts/04_Counters_DMV.sql`](../Sections/01_Monitoring_Activity/Scripts/04_Counters_DMV.sql) ทีละ Task — Task 2 คือชุด counters คัดแล้ว (PLE, Log Growths, Active Temp Tables, Batch Requests/sec ฯลฯ) พร้อมคำอธิบาย `cntr_type`

**Expected:** ได้ตาราง counters สำคัญแบบ point-in-time และแบบ rate — เก็บไว้เทียบวันเกิดเหตุ

### Step 5 — (Optional UI) เทียบกับ Performance Monitor

เปิด `perfmon` > Performance Monitor > ปุ่ม + > เลือก `SQLServer:SQL Statistics\Batch Requests/sec` และ `SQLServer:Buffer Manager\Page life expectancy` — กราฟสดควรแสดงค่าสอดคล้องกับที่ T-SQL ให้ (บน named instance จะเป็น `MSSQL$<INSTANCE>:...`)

---

## Exercise 3 (Optional): เปิด Data Collector + ดูรายงาน (ระบบ legacy)

> ⚠️ ทำบน instance ทดลองเท่านั้น Data Collector เป็น legacy tool ในโลกสมัยใหม่ใช้ Query Store + DMV baseline + Azure Arc แทน — Exercise นี้มีไว้เพื่อให้เข้าใจระบบเก่าที่อาจพบในที่ทำงาน

### Step 1 — สร้าง Management Data Warehouse

SSMS: right-click instance > **Tasks** > **Configure Management Data Warehouse** > สร้าง database ใหม่ชื่อ `MDW` (ตรวจว่า map user ปัจจุบันเป็น `mdw_admin`)

### Step 2 — เปิด Data Collection

SSMS: right-click instance > **Tasks** > **Configure Data Collection** > ชี้ไปที่ `MDW` ที่สร้างไว้

หรือแบบ T-SQL:

```sql
EXEC msdb.dbo.sp_syscollector_enable_collector;

SELECT name, collection_mode, is_running
FROM msdb.dbo.syscollector_collection_sets;
```

✅ **สังเกต**: standard sets 3 ชุด — **Disk Usage**, **Query Statistics**, **Server Activity** พร้อม Agent jobs ที่ถูกสร้างให้อัตโนมัติ

### Step 3 — รอแล้วดูรายงาน

รอ 15–30 นาที (หรือเริ่ม collection set เองด้วย `sp_syscollector_start_collection_set`) แล้ว right-click database ใด ๆ > **Reports** > **Standard Reports** > **Disk Usage** และ **Server Activity History** — รายงานอ่านจากตารางใน `MDW`

**Expected:** กราฟแนวโน้มขนาดไฟล์และ CPU/wait ของช่วงเวลาที่เก็บมาแล้ว

### Step 4 — เคลียร์ (ถ้าไม่ต้องการเก็บต่อ)

```sql
EXEC msdb.dbo.sp_syscollector_disable_collector;
```

---

## Exercise 4: DMV Snapshot Baseline ใน DBA_Baseline

### Step 1 — สร้างคลัง baseline

รันไฟล์ [`../Sections/02_Data_Collection_Baseline/Scripts/01_DBA_Baseline_Setup.sql`](../Sections/02_Data_Collection_Baseline/Scripts/01_DBA_Baseline_Setup.sql) ทั้งไฟล์

> **ต้องรู้ก่อน**: สคริปต์สร้าง database `DBA_Baseline` + ตาราง `BaselineRun/WaitStats/PerfCounters/FileStats` + proc `dbo.usp_CaptureBaseline` ที่เก็บ snapshot ครั้งแรกให้อัตโนมัติ

**Expected:** ได้ `NewRunId = 1` จากการเรียก proc ครั้งแรก

### Step 2 — รัน workload ระหว่างสอง snapshot

รัน workload จำลองจาก Exercise 1 Step 6 ประมาณ 3–5 นาที แล้ว:

```sql
USE DBA_Baseline;
EXEC dbo.usp_CaptureBaseline @Note = N'รอบสอง ระหว่างมี workload';
```

### Step 3 — อ่านผลต่างระหว่างสองรอบ

รันไฟล์ [`../Sections/02_Data_Collection_Baseline/Scripts/02_PerfCounters_Baseline.sql`](../Sections/02_Data_Collection_Baseline/Scripts/02_PerfCounters_Baseline.sql) ทีละ Task:

- Task 2: Batch Requests/sec, Compilations/sec ระหว่างรอบ (ค่าควรสูงกว่าตอน idle)
- Task 3: PLE / Active Temp Tables ณ รอบล่าสุด
- Task 5: I/O latency ต่อ file ในช่วงมี workload

**Expected:** มีรายงาน "ค่าต่อช่วงเวลา" จริง ๆ แล้ว — นี่คือรูปแบบ baseline ที่คุณจะตั้ง Agent job รันทุก 15 นาทีบน production (โครง job อยู่ Task 6 ของสคริปต์)

### Step 4 — ค้นหา query แพงจาก plan cache (เสริม)

```sql
SELECT TOP (10)
       qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
       qs.execution_count,
       SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                 ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                       ELSE qs.statement_end_offset END
                  - qs.statement_start_offset) / 2) + 1) AS StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY AvgLogicalReads DESC;
```

**Expected:** workload จำลองของเรา (GROUP BY หลายตาราง) ควรติดอันดับ — เชื่อมโยงกับ Query Store ใน Module 4 ว่าถ้าเปิด Query Store ไว้จะเห็นประวัติย้อนหลังได้โดยไม่ต้อง snapshot เอง

---

## 🧹 Clean-up

```sql
-- 1) ตารางทดลองใน AdventureWorks2025
USE AdventureWorks2025;
DROP TABLE IF EXISTS Lab.BlockingDemo;
DROP TABLE IF EXISTS ##stopload;

-- 2) คลัง baseline (ถ้าต้องการลบทิ้งทั้ง database)
-- USE master;
-- DROP DATABASE IF EXISTS DBA_Baseline;

-- 3) Data Collector (ถ้าเปิดใน Exercise 3)
-- EXEC msdb.dbo.sp_syscollector_disable_collector;
-- USE master;
-- DROP DATABASE IF EXISTS MDW;   -- ตรวจว่าไม่มี collection set ใช้อยู่ก่อน

-- 4) หยุด workload ที่ยังวนอยู่ (ถ้ามี)
-- CREATE TABLE ##stopload (id int);
```

> หาก schema `Lab` ไม่มีอย่างอื่นเหลืออยู่: `DROP SCHEMA IF EXISTS Lab;` — โปรดจำข้อจำกัดที่ว่า schema ที่จะลบต้องว่างเปล่า (ไม่มี object อยู่ข้างใน)

## Quiz ท้ายแล็บ

1. ทำไมต้อง snapshot `Batch Requests/sec` สองรอบแทนที่จะอ่าน `cntr_value` ตรง ๆ?
2. `blocking_session_id` ที่ไม่ใช่ 0 บอกอะไร และหา statement ของตัวการได้จาก DMV ตัวใดบ้าง?
3. ถ้า PLE ต่ำตอน 10:00 ทุกวัน แต่สูงตลอดวันอื่น สรุปว่า RAM ไม่พอได้เลยหรือไม่ เพราะอะไร?
4. ความแตกต่างสำคัญระหว่าง Data Collector (MDW) กับ Query Store ในเชิง "เก็บที่ไหน" และ "เก็บอะไร"?
