# Section 3 — Operators และ Alerts

ประกอบทุกชิ้นจาก Section ก่อนหน้ามาเป็นระบบแจ้งเตือนจริง: **Operator** คือ "ผู้รับ" (บุคคล/ทีมที่มีที่อยู่อีเมล) และ **Alert** คือ "กติกา" ที่บอกว่าเหตุการณ์แบบไหน (error number, severity, performance counter, WMI event) ต้องเริ่มอะไร — รัน job หรือส่งอีเมลถึง operator

Agent เป็นผู้ทำหน้าที่ "เฝ้า" ทั้งหมด: มันดู Windows Application Log และ performance counters ของ Windows เป็นระยะ เมื่อเหตุการณ์ตรงกับ alert ที่เปิดใช้ก็เริ่ม response ตามที่ตั้ง — ทำงานต่อเนื่องแม้ไม่มีใครเปิด SSMS

## 3.1 Operators — ผู้รับข้อความ

สคริปต์เดโมฉบับเต็ม: [Scripts/01_Operators_Alerts.sql](Scripts/01_Operators_Alerts.sql)

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'Fabrikam DBA Team')
    EXEC dbo.sp_delete_operator @name = N'Fabrikam DBA Team';

EXEC dbo.sp_add_operator
    @name          = N'Fabrikam DBA Team',
    @enabled       = 1,
    @email_address = N'dba-team@fabrikam.example';   -- อีเมลเดี่ยวหรือ distribution list
GO
```

ข้อควรรู้เกี่ยวกับ operator:

- **ใช้อีเมลเท่านั้นในงานใหม่** — พารามิเตอร์ pager (`@pager_address`, `@pager_days`, `@weekday_pager_start_time` ฯลฯ) และ net send (`@netsend_address`) มีอยู่ใน syntax แต่เป็นกลไกที่ **จะถูกลบออกจาก SQL Server Agent ในเวอร์ชันอนาคต** (เอกสาร sp_add_alert/sp_add_operator ระบุข้อความเตือนนี้ชัด) — ใช้ `@email_address` หรือ `@email_address_in_day/night` แบบหมุนตามช่วงเวลาได้
- Operator คือ **ที่อยู่ตรรกะ ไม่ใช่ user ของ SQL Server** — ไม่มีสิทธิ์ในระบบเลย แนะนำใช้อีเมลของ **ทีม/distribution list** มากกว่าบุคคล เพื่อไม่ต้องแก้ config เวลาคนย้ายทีม
- ทดสอบส่งถึง operator ได้ทันทีด้วย `sp_notify_operator` (ใช้ใน Module 8 Section 3 แล้ว)
- ตัวเลือกสำคัญอีกตัว: **fail-safe operator** — operator ฉุกเฉินที่ Agent จะส่งหาเองเมื่อ notification หลัก fail หรือเมื่อ alert ที่ไม่ได้กำหนด operator เกิดขึ้น; ตั้งผ่านหน้าจอ Agent Properties → Alert System หรือ `master.dbo.sp_MSsetalertinfo @failsafeoperator = N'Fabrikam DBA Team', @notificationmethod = 1`

```sql
-- ผูก notification ของ job ให้เรียบร้อยก่อนเล่นกับ alert (เตรียมจาก Module 8):
IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'Daily Backup')
    PRINT N'ยังไม่มี job Daily Backup — รันแล็บ Module 8 ก่อนถ้าจะทดสอบ job notification';
```

## 3.2 Alerts — สามชนิดและการเลือก

Alert มีสามชนิดตามตัวทริกเกอร์ (หน้าจอ SSMS: New Alert → Type):

| ชนิด | ทริกเกอร์ | ใช้เมื่อ |
|:-----|:----------|:--------|
| **SQL Server event alert** | error number หรือ severity ใด ๆ ที่ถึง Windows Application Log | เหตุการณ์ที่ engine ยิงเอง เช่น severity 17/19, deadlock 1205, log เต็ม 9002 |
| **SQL Server performance condition alert** | counter ของ Windows เช่น `SQLServer:Databases \| Percent Log Used \| <db> \| > 90` | สถานะที่ "ใกล้จะเกิดปัญหา" ยังไม่เกิด error |
| **WMI event alert** | เหตุการณ์ของ WMI Provider ผ่าน WQL | เหตุการณ์ที่จับผ่าน event notification ได้ เช่น DEADLOCK_GRAPH |

### Event alert — ผูกกับ error number หรือ severity

```sql
USE msdb;
GO
-- (A) Alert กับ severity 17 (resource/software errors เช่น 9002 log full)
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Severity 17')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Severity 17';

EXEC dbo.sp_add_alert
    @name                        = N'Fabrikam - Severity 17',
    @severity                    = 17,     -- หรือ @message_id = 9002 เพื่อเจาะเฉพาะ log full
    @enabled                     = 1,
    @delay_between_responses     = 120,    -- วินาที — กันเมลล้นเมื่อ error ซ้ำถี่
    @notification_message        = N'Fabrikam: severity 17 error เกิดขึ้น — ตรวจ error log ทันที',
    @include_event_description_in = 1;     -- 1 = ใส่ description ในอีเมล (email only)
GO
```

หลักสำคัญของ event alert:

- **`@message_id` หรือ `@severity` เลือกอย่างใดอย่างหนึ่ง** — ถ้าใช้ severity, `@message_id = 0`; ถ้าใช้ message_id, `@severity = 0`
- อย่าลืมข้อจำกัดจาก Section 1: จับได้เฉพาะข้อความ **ที่ถึง Windows Application Log** — severity ต่ำจะไม่ยิง alert เว้นแต่ข้อความถูกตั้ง `WITH LOG`
- `@delay_between_responses` วินาที — ตั้งเสมอกับ alert ที่อาจซ้ำถี่ (เช่น deadlock ที่โหด) เพื่อกันเมลล้น
- `@database_name` จำกัดเฉพาะฐานข้อมูล (ว่าง = ทุก database); `@event_description_keyword` กรองคำในข้อความเพิ่มได้

### Performance condition alert — จับ "ก่อนพัง"

รูปแบบ `@performance_condition` คือ `Object|Counter|Instance|Comparator Value`:

```sql
USE msdb;
GO
-- เตือนเมื่อ transaction log ของ AdventureWorks2025 เตือน 90% (ก่อน error 9002 จริง)
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - AW2025 Log Used > 90%')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - AW2025 Log Used > 90%';

EXEC dbo.sp_add_alert
    @name = N'Fabrikam - AW2025 Log Used > 90%',
    @enabled = 1,
    @delay_between_responses = 300,
    @performance_condition = N'SQLServer:Databases|Percent Log Used|AdventureWorks2025|> 90';
GO
```

> บน **named instance** ชื่อ object ขึ้นต้นต่างไป: `MSSQL$<InstanceName>:Databases` — ดูชื่อจริงใน Windows Performance Monitor (SQLServer:Databases object) แล้ว copy ให้ตรง

### WMI alert — คร่าว ๆ (กรณี deadlock graph)

WMI alert ให้จับเหตุการณ์แบบเดียวกับ event notification ผ่าน WQL — ตัวอย่างทางการของ Microsoft คือจับ XML deadlock graph:

```sql
USE msdb;
GO
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Fabrikam - Deadlock graph (WMI)')
    EXEC dbo.sp_delete_alert @name = N'Fabrikam - Deadlock graph (WMI)';

EXEC dbo.sp_add_alert
    @name          = N'Fabrikam - Deadlock graph (WMI)',
    @enabled       = 1,
    @delay_between_responses = 60,
    @wmi_namespace = N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER',
    @wmi_query     = N'SELECT * FROM DEADLOCK_GRAPH';
GO
```

เงื่อนไขใช้จริง: Agent service account ต้องมีสิทธิ์ WMI ของ namespace นั้นและ msdb ต้องเปิด Service Broker (Database Mail ใช้อยู่แล้ว) — ใช้เมื่อต้องการข้อมูล event ดิบเป็น input ของ job (เช่นเก็บ deadlock graph ลงตาราง)

## 3.3 Response ของ Alert — Job หรือ Notification

แต่ละ alert ตอบสนองได้สองแบบพร้อมกัน:

**(1) รัน job ทันที** — ระบุตอนสร้างหรือ update:

```sql
USE msdb;
GO
EXEC dbo.sp_update_alert
    @name     = N'Fabrikam - AW2025 Log Used > 90%',
    @job_name = N'Daily Backup';        -- รัน job นี้เป็นการตอบสนอง (เช่น backup ระบุชิ้น)
GO
```

**(2) แจ้ง operator** — ด้วย `sp_add_notification` (หรือหน้าจอ Response tab):

```sql
USE msdb;
GO
-- ให้ alert ส่งอีเมลถึง operator เมื่อยิง
EXEC dbo.sp_add_notification
    @alert_name           = N'Fabrikam - Severity 17',
    @operator_name        = N'Fabrikam DBA Team',
    @notification_method  = 1;   -- 1 = email (ค่าเดียวที่ควรใช้ — pager/netsend กำลังถูกถอด)
GO

-- ตรวจระบบทั้งหมดในครั้งเดียว: alert + ผูก notification + operator อีเมล
SELECT a.name AS alert_name, a.enabled, a.delay_between_responses,
       a.performance_condition, a.wmi_query,
       o.name AS notified_operator, o.email_address
FROM dbo.sysalerts AS a
LEFT JOIN dbo.sysnotifications AS n ON n.alert_id = a.id
LEFT JOIN dbo.sysoperators AS o ON o.id = n.operator_id;
-- Expected: แถว alert ทั้งหมด + ช่อง operator ที่ผูกไว้
```

> **`sp_add_notification` ต้องมี alert + operator ทั้งคู่ก่อนเสมอ** — และ alert จะมีเมลส่งออกได้เมื่อ Database Mail พร้อม (Section 2) + Agent ตั้ง mail profile แล้ว

## 3.4 ทดสอบให้ยิงจริง

วิธีที่ปลอดภัยที่สุดเพื่อพิสูจน์ทั้งสาย: raise error severity 17 แบบ `WITH LOG`:

```sql
RAISERROR (N'Fabrikam: test severity 17 for alert.', 17, 1) WITH LOG;
-- ภายในไม่กี่วินาที Agent จะจับจาก Application Log → ส่งอีเมลถึง operator
```

ตรวจผลสามจุด: (1) อีเมลใน smtp4dev/กล่องจริง, (2) `sysmail_event_log` ฝั่ง Database Mail, (3) Agent log — `EXEC xp_readerrorlog 0, 2` (Agent log บันทึกการจับ alert ทุกครั้ง)

## 3.5 แก้ปัญหา "Alert ไม่ยิง" — ลำดับตรวจที่ถูกต้อง

จากเอกสาร [sp_add_alert](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-alert-transact-sql?view=sql-server-ver17) ระบบมีเงื่อนไขซ่อนอยู่ 5 จุดที่ทำให้ alert เงียบ:

1. **SQL Server Agent รันอยู่หรือไม่** — alert ทำงานโดย Agent ไม่ใช่ engine; Agent หยุด = alert ทั้ง instance หยุดเฝ้า
2. **ข้อความถึง Windows Application Log จริงไหม** — error severity 11–18 ไม่ถูกเขียน default; ต้องมาด้วย `WITH LOG`, ข้อความ custom `@with_log='TRUE'` หรือ severity 19+; ตรวจด้วย `xp_readerrorlog`/Event Viewer ก่อนด่า alert
3. **Alert เปิดหรือไม่** — `@enabled = 0` หรือปิดจากหน้าจอ; และ `@delay_between_responses` ตั้งยาวมาก ทำให้การเกิดซ้ำในช่วง delay **ไม่ถูกส่งซ้ำ** (จำนวน occurrence ยังเพิ่มแต่ไม่ notify)
4. **Mail profile ของ Agent ตั้งหรือยัง** — alert ยิงแต่เมลไม่ถึงเมื่อ Agent Properties → Alert System ยังว่าง หรือ Database Mail หยุด (`sysmail_help_status_sp`)
5. **เหตุการณ์จาก `xp_logevent` เกิดใน master** — alert ที่ระบุ `@database_name` เป็น database อื่นจะ **ไม่จับ** คำสั่ง xp_logevent ที่ยิงจาก master (ข้อควรระวังที่เอกสารระบุตรง ๆ)

ลำดับสายงานคือ: **error → Windows Application Log → Agent (alert engine) → response (job / Database Mail) → operator** — ตรวจจากต้นสายไปปลายสายเสมอ ไม่เริ่มจากการรื้อตั้ง alert ใหม่

## 3.6 ค่าสถิติของ Alert และการตรวจงานย้อนหลัง

ทุก alert นับสถิติการทำงานของตัวเองใน `msdb.dbo.sysalerts` — มีประโยชน์ตอน "ผู้บริหารถามว่าเดือนที่แล้วระบบเตือนกี่ครั้ง":

```sql
SELECT name, enabled, severity, message_id, performance_condition,
       occurrence_count,                        -- จำนวนครั้งที่ alert ยิงเลยตั้งแต่สร้าง/รีเซ็ต
       count_reset_date, count_reset_time,      -- เวลาที่นับรีเซ็ตครั้งล่าสุด
       last_response_date, last_response_time,  -- ครั้งล่าสุดที่ยิง
       last_notification_date                   -- ครั้งล่าสุดที่ส่ง notification จริง
FROM msdb.dbo.sysalerts
ORDER BY name;
```

สามคอลัมน์ที่ตีความต่างกัน: `occurrence_count` นับ **เหตุการณ์** (เกิดกี่ครั้ง), `last_response_date/time` คือครั้งที่ alert "ทำงาน" (ยิง response ล่าสุด), `last_notification_date` คือครั้งที่ **ส่งถึง operator จริง** — ถ้า occurrence โตแต่ notification นิ่ง แสดงว่า `@delay_between_responses` รีดการแจ้งซ้ำไว้ (ทำงานตามดีไซน์) หรือ notification fail ต้องย้อนไปดู Database Mail

อีกสองตัวเลือกที่ควรรู้จักเมื่อ alert ตั้งครบแล้ว:

- **Event forwarding ของ Agent** — ให้ instance ย่อย ๆ ส่ง event รวมขึ้น "ศูนย์รับ" เดียว (ตั้งที่ Agent Properties → Advanced) — เหมาะฟลีตจำนวนมากที่ยังคุมด้วยเครื่องมือ SQL Server ล้วน; เกี่ยวข้องกับ MSX/TSX ของ Module 8 Section 4
- **ปิด alert ชั่วคราวแบบตรวจสอบย้อนหลังได้** — `sp_update_alert @enabled = 0` แทนการลบ; ประวัติ occurrence ยังอยู่ เวลาเปิดกลับคือเห็นเส้นเวลาต่อเนื่อง (แต่ช่วงที่ปิดนั้นระบบไม่เฝ้าจริง ๆ — จดไว้ใน change log เสมอ)

### 🚀 SQL Server 2025 & Modern Notes

- **Pager / net send กำลังถูกถอด** — เอกสาร [sp_add_alert](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-alert-transact-sql?view=sql-server-ver17) มีข้อความ "Important" ระบุชัดว่าตัวเลือก Pager และ net send จะถูกลบจาก SQL Server Agent; ใหม่ ๆ ใช้ `@include_event_description_in = 1` (email) และ `@notification_method = 1` เท่านั้น
- **TLS 1.3 / TDS 8.0 (2025)** — Agent (ผู้เฝ้า alert) เชื่อม engine ด้วยการเข้ารหัสรุ่นใหม่แบบ strict ได้ ร่วมกับ Database Mail ที่ใช้ SMTP ขององค์กร
- **Azure SQL Database ไม่มี alert ของ Agent** — ทางเลือกเท่าเทียมคือ Azure Monitor metric alerts + action groups (Section 4); Azure SQL Managed Instance มี Agent alerts เหมือน on-prem
- **แนวทางเสริมยุคใหม่** — จับ deadlock/granular error ด้วย Extended Events (Module 13) แล้วปล่อยให้ alert severity สูง ๆ ของ Agent รับเหตุการณ์ระดับ server — ลดภาระ alert จำนวนมากที่ไม่ต้องเป็นเมล

> อ้างอิง: [SQL Server Agent alerts](https://learn.microsoft.com/sql/ssms/agent/alerts), [sp_add_alert](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-alert-transact-sql?view=sql-server-ver17), [sp_add_operator](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-operator-transact-sql?view=sql-server-ver17), [sp_add_notification](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-notification-transact-sql?view=sql-server-ver17), [Create a WMI event alert](https://learn.microsoft.com/sql/ssms/agent/create-a-wmi-event-alert)
