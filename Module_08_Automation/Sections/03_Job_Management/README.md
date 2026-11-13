# Section 3 — การจัดการ Jobs: History, Retention และ Notification

สร้าง job ได้ยังไม่พอ — จริง ๆ ต้อง "รู้ว่ามันรันแล้วเป็นยังไง" Job ที่ล้มเงียบ ๆ เป็นเวลาสามสัปดาห์โดยไม่มีใครเห็น คือหายนะคลาสสิกที่มาจากการลืมอ่าน job history ใน Section นี้คุณจะเรียนอ่านประวัติจาก `msdb.dbo.sysjobhistory` และ `sp_help_job`, รู้จักตาราง msdb สำคัญ ๆ, ปรับ history retention กันข้อมูลล้น, จัดการ notification ราย job ด้วย `sp_update_job` และส่งข้อความทดสอบถึง operator ด้วย `sp_notify_operator`

## 3.1 Job History — msdb.dbo.sysjobhistory

ทุกครั้งที่ Agent รัน job จะเขียนแถวลง `msdb.dbo.sysjobhistory` — หนึ่งแถว "ตัว job" (`step_id = 0`) + หนึ่งแถวต่อ step:

```sql
SELECT TOP 20
       h.instance_id,
       j.name AS job_name,
       s.step_name,
       h.run_date, h.run_time,
       h.run_duration,                  -- รูปแบบ HHMMSS เขียนติดกันเป็น int!
       CASE h.run_status                -- 0=Failed 1=Succeeded 2=Retry
            WHEN 0 THEN 'Failed'        -- 3=Canceled 4=In progress
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            WHEN 4 THEN 'In progress'
            ELSE '?' END AS run_status,
       h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs     AS j ON j.job_id = h.job_id
LEFT JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = h.job_id AND s.step_id = h.step_id
ORDER BY h.instance_id DESC;
```

✅ **สังเกต**: แถวที่ `step_id = 0` คือสรุปของ job ทั้งงาน (message เริ่มด้วย "The job succeeded...") — ตอนหา "job ครั้งล่าสุดล้มเมื่อไหร่" ให้กรองแถวนี้ก่อน

คอลัมน์ที่ต้องถอดรหัส:

| คอลัมน์ | รูปแบบ | วิธีอ่าน |
|:--------|:-------|:--------|
| `run_date` | int `20261112` | วันที่ YYYYMMDD |
| `run_time` | int `231530` | เวลา HHMMSS (ไม่มีโคลอน, ตี 1 = `10000` ไม่ใช่ `010000`) |
| `run_duration` | int `35` หรือ `10205` | วินาทีถ้า < 100; มิฉะนั้น HHMMSS (`10205` = 01:02:05) |
| `run_status` | 0–4 | 0=Failed, 1=Succeeded, 2=Retry, 3=Canceled, 4=In progress |
| `message` | nvarchar(max) | ข้อความ error ของ step ที่ล้ม — **จุดแรกที่ต้องอ่านเมื่อ troubleshoot** |

เวอร์ชันอ่านง่ายที่แปลงค่าให้ครบ อยู่ใน [Scripts/01_Job_History_Msdb_Tables.sql](Scripts/01_Job_History_Msdb_Tables.sql) — รวมถึงการแปลง `run_duration` เป็นจริง ๆ ด้วยแมธเมติกหาร 10000/100

### ทางลัดด้วย proc ในตัว

```sql
-- สรุปสถานะ job รายตัว (ใช้ได้ทุกคนที่มีสิทธิ์อ่าน Agent)
EXEC msdb.dbo.sp_help_job @job_name = N'Fabrikam - Demo Job';
-- คอลัมน์สำคัญ: last_run_date/last_run_time, last_run_outcome (1=สำเร็จ 0=ล้ม 3=ยังไม่รันเลย)

-- ประวัติการรัน (มี @mode = 'FULL' ให้ข้อมูลละเอียด)
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'Fabrikam - Demo Job', @mode = 'FULL';

-- หา job ที่ล้มเมื่อวานนี้ทั้ง instance
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = NULL,                    -- ทุก job
    @sql_message_severity = NULL;
-- หรือกรองเอง: WHERE run_status = 0 AND run_date = CONVERT(int, CONVERT(varchar(8), DATEADD(day,-1,GETDATE()), 112))
```

หน้าจอเทียบเท่าใน SSMS: คลิกขวา job → **View History** เปิด Log File Viewer ที่กรอง/ดูข้อความต่อ step ได้ — จริง ๆ คือกำลังอ่านตารางเดียวกันนี้

## 3.2 ตาราง msdb ที่ DBA ต้องรู้จัก

| ตาราง | เก็บอะไร | ใช้ตอนไหน |
|:------|:---------|:----------|
| `dbo.sysjobs` | นิยาม job ทุกตัว (ชื่อ, เจ้าขอน, enabled) | สำรวจงาน automation ทั้งหมด |
| `dbo.sysjobsteps` | step ของแต่ละ job: subsystem, command, กฎ on_success/on_fail, retry | อ่านว่า job ทำอะไรแน่ ๆ โดยไม่เปิด GUI |
| `dbo.sysjobschedules` / `dbo.sysschedules` | ผูก schedule เข้า job / นิยาม schedule | ตรวจว่างานตั้งเวลาตรงตาม policy ไหม |
| `dbo.sysjobhistory` | ผลการรันทุกครั้ง | troubleshoot (หัวข้อ 3.1) |
| `dbo.sysoperators` | ผู้รับ notification | Module 10 |
| `dbo.sysalerts` | alerts (severity/message/WMI/perf) | Module 10 |
| `dbo.sysproxies` | proxy accounts ของ Agent | Module 9 |
| `dbo.syscategories` | หมวดหมู่ job | จัดระเบียบ job จำนวนมาก |
| `dbo.sysdownloadlist` | คิวส่งงานไป TSX ในระบบ multiserver | Section 4 |
| `dbo.systargetservers` | รายชื่อ TSX ที่ MSX รู้จัก | Section 4 |
| `dbo.backupset` / `dbo.backupmediafamily` | ประวัติ backup (เขียนโดย BACKUP ไม่ใช่ Agent) | ตรวจว่า backup จริงเกิดขึ้นไหม — อย่ากลั้นแก้ด้วย job history อย่างเดียว |

> **ประโยคทองของการ audit**: "job สำเร็จ" ≠ "backup มีจริง" — ตรวจ `msdb.dbo.backupset` กับ age ของ backup ล่าสุดเสมอ ดีกว่าเชื่อสถานะของ job ล้วน ๆ

## 3.3 การแก้ปัญหา Job ล้ม — Checklist ลำดับที่ดี

เมื่อ `run_status = 0` อย่าเดา — เดินตามนี้:

1. **อ่าน `message` ของ step ที่ล้ม** ใน `sysjobhistory` (หรือ Log File Viewer) — 90% ของกรณีคำตอบอยู่ตรงนั้น (error number + คำอธิบาย)
2. **ดู output file ของ step** (ถ้าตั้ง `@output_file_name` ไว้) — ไฟล์มีข้อมูลมากกว่า history เพราะ history เก็บเฉพาะข้อความสรุป และถูกตัดตาม retention ได้
3. **จำนวน retry** — `run_status = 2` แปลว่า step กำลังลองใหม่ (`@retry_attempts`) — อย่ารีบด่า job ก่อน retry หมด
4. **หลังแก้ให้ทดสอบซ้ำแบบรู้ผล** — `sp_start_job` รันมือ, แล้วเทียบ `run_duration` ก่อน-หลัง ว่าการแก้ไม่ทำให้งานช้าลง

> ความแตกต่างที่หลายคนสับสน: history บันทึกผล **หลัง step จบ** เท่านั้น (ในกรณีทั่วไป) — step ที่กำลังรันนาน ๆ จะยังไม่มีแถว ให้ใช้ `sp_help_job` คอลัมน์ `current_execution_status` ดูว่ากำลังทำอะไรอยู่

## 3.4 History Retention — กันประวัติล้นและกันประวัติหาย

Agent ลบประวัติเก่าให้อัตโนมัติตามโควตาแถว ค่า default: **1,000 แถวรวม** และ **100 แถวต่อ job** — ปัญหาสองทิศทาง: log backup ทุก 15 นาที = 96 แถว/วัน/step จะกินโควตาอย่างรวดเร็ว ทำให้ประวัติ job อื่นถูกลบก่อนใครจะได้อ่าน

ตั้งใหม่ด้วย proc ที่ SSMS ใช้เขียนค่านี้เบื้องหลัง — `msdb.dbo.sp_set_sqlagent_properties`:

```sql
USE msdb;
GO
-- เพิ่มพื้นที่เก็บประวัติ: 10,000 แถวรวม, 1,000 แถวต่อ job
EXEC dbo.sp_set_sqlagent_properties
    @jobhistory_max_rows        = 10000,
    @jobhistory_max_rows_per_job = 1000;
GO
```

หมายเหตุที่ควรรู้:

- proc นี้คือสิ่งที่หน้าจอ **SQL Server Agent Properties → History** ("Limit size of job history log") เรียกใช้อยู่เบื้องหลัง — ตั้งผ่านหน้าจอก็ได้ผลเดียวกัน ([SQL Server Agent Properties (History Page)](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent-properties-history-page))
- บน **SQL Server on Linux/containers** ตั้งผ่าน `mssql-conf` เช่น `sudo /opt/mssql/bin/mssql-conf set sqlagent.jobhistorymaxrows 10000`
- ถ้าต้องการเก็บประวัติยาวกว่านั้นจริง ๆ (เช่นเพื่อ compliance) ให้เขียน job อีกตัวที่ copy แถวจาก `sysjobhistory` ไปตาราง archive ของตัวเองเป็นรายวัน แทนการเพิ่มโควตาไม่จำกัด

ล้างประวัติแบบ manual ได้ด้วย:

```sql
-- ลบประวัติของ job เดียว
EXEC msdb.dbo.sp_purge_jobhistory @job_name = N'Fabrikam - Demo Job';

-- ลบประวัติเก่ากว่า 90 วัน ทั้ง instance
EXEC msdb.dbo.sp_purge_jobhistory @oldest_date = DATEADD(day, -90, GETDATE());
```

## 3.5 Notification ราย Job — sp_update_job + sp_notify_operator

Job ที่สำคัญควรแจ้งเมื่อล้มโดยไม่ต้องให้คนเปิดหน้าจอดู ตั้งด้วย `sp_update_job` (หรือพารามิเตอร์เดียวกันตอน `sp_add_job`):

```sql
USE msdb;
GO
-- (1) ต้องมี operator ก่อน — ลึกใน Module 10; ตรงนี้สร้างแบบ minimal
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_add_operator
        @name          = N'Fabrikam DBA Team',
        @enabled       = 1,
        @email_address = N'dba-team@fabrikam.example';

-- (2) ผูก notification เข้ากับ job
EXEC dbo.sp_update_job
    @job_name                    = N'Fabrikam - Demo Job',
    @notify_level_email          = 2,     -- 1=สำเร็จ, 2=ล้ม, 3=ทั้งสอง
    @notify_email_operator_name  = N'Fabrikam DBA Team';
GO
```

พารามิเตอร์ `@notify_level_email` ใช้ชุดเดียวกับ `@notify_level_eventlog`: 0=ไม่แจ้ง, 1=เมื่อสำเร็จ, 2=เมื่อล้ม, 3=ทั้งสองกรณี — ค่า `@notify_level_netsend`/`@notify_level_page` มีใน syntax แต่เป็นกลไกที่ **กำลังถูกถอด** ไม่ใช้ในงานใหม่

`sp_update_job` ทำงานแบบ "แก้เฉพาะพารามิเตอร์ที่ส่งมา" — job อื่น ๆ ที่ตั้งไว้แล้วไม่ถูกกระทบ ส่วน `sp_add_jobserver @server_name = N'(local)'` คือคำสั่งที่ "ลงทะเบียน job ให้รันบน server นี้" — job ที่ขาดบรรทัดนี้จะมีนิยามแต่ Agent จะไม่รันให้ (error "job is not targeted at this server")

### ทดสอบช่องทางอีเมล — sp_notify_operator

ก่อนเชื่อกลไก notification จริง ให้พิสูจน์ว่า "จาก SQL Server → ถึงกล่องอีเมล" สำเร็จด้วยการส่งข้อความทดสอบตรง ๆ:

```sql
EXEC msdb.dbo.sp_notify_operator
    @profile_name        = N'',           -- NULL/ว่าง = ใช้ default profile ของ Agent
    @operator_name       = N'Fabrikam DBA Team',
    @notification_method = 1,             -- 1 = email (ค่าเดียวที่ยังใช้ได้จริง)
    @subject             = N'Test notification จาก SQL Server',
    @body                = N'ถ้าคุณเห็นอีเมลนี้ = ช่องทาง Agent → Database Mail ใช้งานได้';
```

**Expected:** อีเมลถึงกล่องของ operator ภายในไม่กี่วินาที; ถ้าไม่ถึง ให้ตรวจ (a) Database Mail เปิดและมี profile (Module 10), (b) Agent Properties → Alert System ตั้ง profile แล้ว, (c) log ของ Database Mail: `SELECT * FROM msdb.dbo.sysmail_event_log` — การตั้ง Database Mail ครบวงคือเนื้อหาหลักของ Module 10 จึงข้ามไปก่อนได้ สคริปต์ [Scripts/02_Job_Retention_Notification.sql](Scripts/02_Job_Retention_Notification.sql) มีทั้งหมดนี้แบบรันได้

## 3.6 ภาพรวมงานจัดการที่ควรมีในทุก instance

จากทั้งหมดข้างบน แพตเทิร์นที่ DBA ทำจริงเป็นชุด ๆ นี้:

1. Job ทำงานหลัก (backup/CHECKDB/index) — Module นี้ Section 2 + Labs
2. Notification เมื่อล้ม → operator ทางอีเมล — Section 3.5 + Module 10
3. Retention เหมาะกับความถี่ของ job — Section 3.4
4. Job ตรวจงานอื่น: สแกน `sysjobhistory` หา `run_status = 0` ของเมื่อวาน แล้วส่งรายงาน — ง่าย ๆ แต่ทรงพลัง

```sql
-- โครงของ "job คุม job": รายงานงานที่ล้มเมื่อวาน (ใส่เป็น step ของ job รายเช้า)
SELECT j.name AS failed_job, s.step_name, h.run_date, h.run_time, h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
LEFT JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = h.job_id AND s.step_id = h.step_id
WHERE h.run_status = 0
  AND h.run_date = CONVERT(int, CONVERT(varchar(8), DATEADD(day, -1, GETDATE()), 112))
  AND h.step_id > 0;    -- เอาแถวระดับ step (ไม่ใช่สรุป job)
```

### 🚀 SQL Server 2025 & Modern Notes

- **Job history defaults ยังเป็น 1,000/100** — เอกสาร Agent ของ SQL Server และ Azure SQL MI ระบุค่า default เดียวกัน ([View the SQL Server Agent job history](https://learn.microsoft.com/sql/ssms/agent/view-the-job-history)) ปรับได้ด้วย `sp_set_sqlagent_properties` (Windows) หรือ `mssql-conf` (Linux)
- **sysjobhistory บน Azure SQL Managed Instance** ใช้ได้เหมือนเดิม แต่ Agent properties บางตัว (รวม history retention) ปรับไม่ได้บน MI — ออกแบบ job บน MI ให้ตรวจ history บ่อยขึ้นแทน
- **แนวทางยุคใหม่**: หลายทีมย้ายการตรวจ job ไปที่ monitoring ภายนอก (dbatools `Get-DbaAgentJobHistory`, Grafana/Log analytics, Azure Arc assessments) แทนการอ่านประวัติผ่าน SSMS — ความรู้ตาราง msdb ยังจำเป็นเพราะเครื่องมือเหล่านั้นก็อ่านจากที่เดียวกัน
- **Pager / net send กำลังถูกถอด** — notification ใหม่ใช้ `@notify_level_email` และ `sp_notify_operator @notification_method = 1` เท่านั้น

> อ้างอิง: [dbo.sysjobhistory](https://learn.microsoft.com/sql/relational-databases/system-tables/dbo-sysjobhistory-transact-sql?view=sql-server-ver17), [View the SQL Server Agent job history](https://learn.microsoft.com/sql/ssms/agent/view-the-job-history), [SQL Server Agent Properties (History Page)](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent-properties-history-page), [sp_notify_operator](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-notify-operator-transact-sql?view=sql-server-ver17)
